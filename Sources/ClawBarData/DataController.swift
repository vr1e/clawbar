import Foundation
import ClawBarShared

/// Owns every probe and the session registry, and folds their results into one `DataSnapshot`.
@MainActor
public final class DataController {
    public private(set) var snapshot: DataSnapshot = .empty
    /// Called after an async probe completion changed `snapshot`; never from inside the methods below.
    public var onChange: (@MainActor () -> Void)?

    /// The system boundaries, injectable so tests drive the controller with fakes and a hand clock.
    struct Dependencies: Sendable {
        var runner: any ProcessRunning
        var http: any HTTPFetching
        var clock: @Sendable () -> Date
        /// For reset stamps without a zone of their own.
        var timeZone: TimeZone
        var environment: [String: String]
        var home: String
        var table: any ProcessTable
        /// Session files only.
        var readFile: @Sendable (URL) throws -> Data
        var loginShell: @Sendable (any ProcessRunning, [String: String], String) async -> LoginEnvironment?
        /// nil: the usual install locations.
        var candidates: [String]?

        static func live() -> Dependencies {
            Dependencies(
                runner: ProcessRunner(), http: URLSessionHTTP(), clock: { Date() }, timeZone: .autoupdatingCurrent,
                environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory(), table: LiveProcessTable(),
                readFile: { try Data(contentsOf: $0) },
                loginShell: { runner, env, home in
                    await LoginShell.capture(runner: runner, shell: LoginShell.shell(environment: env), environment: env, home: home)
                },
                candidates: nil
            )
        }
    }

    private enum Resolution { case pending, running, done }

    /// One probe's bookkeeping: cadence counts from the last attempt.
    private struct Slot {
        var lastTry: Date?
        var running = false

        func due(_ interval: Int, _ now: Date) -> Bool {
            !running && Cadence.due(last: lastTry, interval: TimeInterval(interval), now: now)
        }
    }

    private var config: Config
    private let paths: AppPaths
    private let deps: Dependencies
    private let log: ErrorLog
    private let latchStore: LatchStore
    private var latch: UsageLatch?
    private let weather: WeatherService

    private var resolution = Resolution.pending
    private var login: LoginEnvironment?
    private var claude: ClaudeLocator.Found?
    private var lastLocate: Date?

    private var usage = Slot()
    private var account = Slot()
    private var status = Slot()
    private var version = Slot()
    private var changelog = Slot()
    private var versionAgain = false
    /// After a clean `claude update`: the version it started from, for the next look to judge.
    private var pendingVerify: String?
    private var updating = false
    private var stopped = false
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var nextTask = 0
    /// The last logged failure per source, so a dead endpoint logs once, not every interval.
    private var failures: [String: String] = [:]

    static let changelogRetry: TimeInterval = 600

    public convenience init(config: Config, paths: AppPaths) {
        self.init(config: config, paths: paths, deps: .live())
    }

    init(config: Config, paths: AppPaths, deps: Dependencies) {
        self.config = config.clamped()
        self.paths = paths
        self.deps = deps
        log = ErrorLog(url: paths.errorLog)
        latchStore = LatchStore(url: paths.stateFile)
        latch = latchStore.load()
        weather = WeatherService(http: deps.http, clock: deps.clock, log: { _ in })
        weather.onUpdate = { [weak self] in self?.weatherChanged() }
        weather.log = { [weak self] in self?.fail("weather", $0) }
    }

    // MARK: - Public API

    /// A reloaded config: new intervals, coordinates, claudePath and show flags take effect.
    public func apply(config new: Config) {
        let old = config
        config = new.clamped()
        if config.claudePath != old.claudePath, resolution == .done { locate(now: deps.clock()) }
    }

    /// The data tick: collect finished probes, start those whose interval has passed since their last attempt.
    public func tick(now: Date) {
        guard !stopped else { return }
        if resolution == .pending { resolve() }
        weather.tick(now: now, config: config)
        snapshot.place = weather.place
        startDue(now: now)
    }

    /// Re-reads the session registry synchronously.
    public func pollSessions(now: Date) {
        guard !stopped, resolution == .done else { return }
        readSessions(now: now)
    }

    /// Refresh now: start the usage probe unless one is running or the probe is latched.
    public func refreshNow() {
        guard !stopped, resolution == .done else { return }
        let now = deps.clock()
        if claude == nil { locate(now: now) }
        guard latch == nil, !usage.running, claude != nil else { return }
        startUsage(now: now)
    }

    /// Runs a headless `claude update` that survives quitting.
    public func startClaudeUpdate() {
        guard !stopped, !updating, let claude else { return }
        updating = true
        snapshot.version.updating = true
        snapshot.version.updateFailure = nil
        pendingVerify = nil
        let from = snapshot.version.local, to = snapshot.version.latest
        let spec = UpdateRunner.spec(claude: claude.path, environment: childEnvironment, home: deps.home, log: paths.updateLog)
        let runner = deps.runner, logURL = paths.updateLog, home = deps.home
        spawn { me in
            var failure = UpdateRunner.failure(await runner.run(spec), log: logURL, home: home)
            failure?.from = from
            failure?.to = to
            me.completing {
                me.updating = false
                me.snapshot.version.updating = false
                me.snapshot.version.updateFailure = failure
                if let failure {
                    me.fail("update", "exit \(failure.exitCode.map(String.init) ?? "timeout"): \(failure.outputTail)")
                } else {
                    me.succeed("update")
                    me.pendingVerify = from
                }
                // The version may have changed either way: look again now.
                me.version.lastTry = nil
                if me.version.running { me.versionAgain = true } else { me.startVersion(now: me.deps.clock()) }
            }
        }
    }

    /// Stops every probe child except a running update.
    public func shutdown() {
        guard !stopped else { return }
        stopped = true
        weather.shutdown()
        for t in tasks.values { t.cancel() }
        deps.runner.shutdown()
    }

    // MARK: - Startup

    /// The login shell once, then claude's location; the claude probes wait for both.
    private func resolve() {
        resolution = .running
        let capture = deps.loginShell, runner = deps.runner, env = deps.environment, home = deps.home
        spawn { me in
            let login = await capture(runner, env, home)
            me.completing {
                me.login = login
                me.resolution = .done
                let now = me.deps.clock()
                me.locate(now: now)
                me.readSessions(now: now)
                me.startDue(now: now)
            }
        }
    }

    private func locate(now: Date) {
        lastLocate = now
        claude = ClaudeLocator(home: deps.home, candidates: deps.candidates).locate(configPath: config.claudePath, login: login)
        if let claude {
            snapshot.version.installHint = UpdateRunner.installHint(claudePath: claude.path)
            if snapshot.usageIssue == .claudeNotFound { snapshot.usageIssue = nil }
            succeed("locate")
        } else {
            snapshot.usageIssue = .claudeNotFound
            snapshot.usageProbeCompleted = true
            fail("locate", "claude not found")
        }
    }

    private func startDue(now: Date) {
        if config.showStatus, status.due(config.statusIntervalSeconds, now) { startStatus(now: now) }
        guard resolution == .done else { return }
        // Not found: look again every usage interval.
        if claude == nil, Cadence.due(last: lastLocate, interval: TimeInterval(config.usageIntervalSeconds), now: now) {
            locate(now: now)
        }
        guard claude != nil else { return }
        if version.due(config.versionIntervalSeconds, now) { startVersion(now: now) }
        if latch == nil, usage.due(config.usageIntervalSeconds, now) { startUsage(now: now) }
        if config.showAccount, account.due(config.accountIntervalSeconds, now) { startAccount(now: now) }
        startChangelogIfNeeded(now: now)
    }

    // MARK: - Probes

    private func startUsage(now: Date) {
        guard let claude else { return }
        usage.lastTry = now
        usage.running = true
        let spec = UsageProbe.spec(claude: claude.path, environment: childEnvironment, home: deps.home)
        let runner = deps.runner, clock = deps.clock, zone = deps.timeZone
        spawn { me in
            let report = UsageProbe.interpret(await runner.run(spec), now: clock(), timeZone: zone)
            var cliVersion: String?
            if case .issue(let issue) = report.outcome, issue.isLatched { cliVersion = await me.currentCLIVersion() }
            me.completing {
                me.usage.running = false
                me.snapshot.usageProbeCompleted = true
                switch report.outcome {
                case .usage(let u):
                    me.snapshot.usage = u
                    me.snapshot.usageAt = clock()
                    me.snapshot.usageIssue = nil
                    me.succeed("usage")
                case .issue(.noLimits):
                    // A login without a subscription: the old subscription's numbers no longer apply, its stats do.
                    me.snapshot.usage = report.stats ?? UsageSnapshot()
                    me.snapshot.usageAt = clock()
                    me.snapshot.usageIssue = .noLimits
                    me.succeed("usage")
                case .issue(let issue):
                    if issue == .claudeNotFound {
                        me.claude = nil
                        me.lastLocate = clock()
                    }
                    if let l = UsageLatch(version: cliVersion ?? "", issue: issue) {
                        // Without a known version the latch holds for this run and is keyed once one is known.
                        me.latch = l
                        if !l.version.isEmpty { me.latchStore.save(l) }
                    }
                    me.snapshot.usageIssue = issue
                    me.fail("usage", Self.describe(issue))
                }
            }
        }
    }

    /// The CLI version a latch is keyed by: the probed one, else a quick `claude --version`.
    private func currentCLIVersion() async -> String? {
        if let v = snapshot.version.local { return v }
        guard let claude else { return nil }
        let spec = VersionProbe.spec(claude: claude.path, environment: childEnvironment, home: deps.home)
        return VersionProbe.local(await deps.runner.run(spec))
    }

    private func startVersion(now: Date) {
        guard let claude else { return }
        version.lastTry = now
        version.running = true
        // Only a look started after a clean update may judge it; one already running saw the old version.
        let verifying = pendingVerify
        pendingVerify = nil
        let spec = VersionProbe.spec(claude: claude.path, environment: childEnvironment, home: deps.home)
        let settings = URL(fileURLWithPath: configDirectory).appendingPathComponent("settings.json")
        let runner = deps.runner, http = deps.http
        spawn { me in
            let local = VersionProbe.local(await runner.run(spec))
            let url = VersionProbe.latestURL(channel: VersionProbe.channel(settings: try? Data(contentsOf: settings)))
            let body = try? await http.get(url, timeout: 15)
            let latest = body.flatMap { VersionProbe.latest(String(decoding: $0, as: UTF8.self)) }
            me.completing {
                me.version.running = false
                if let local { me.snapshot.version.local = local }
                if let latest { me.snapshot.version.latest = latest }
                if local == nil || latest == nil {
                    me.fail("version", local == nil ? "claude --version failed" : "no latest version from \(url.host ?? "")")
                } else {
                    me.succeed("version")
                }
                me.judgeUpdate(probed: local, startedFrom: verifying)
                me.checkLatch()
                if me.versionAgain {
                    me.versionAgain = false
                    me.startVersion(now: me.deps.clock())
                }
                me.startChangelogIfNeeded(now: me.deps.clock())
            }
        }
    }

    /// A failed update lasts while the versions it started from hold, as upstream's failed=<ver> does; a clean exit
    /// that left the version where it was, with the update still out, is a failure too.
    private func judgeUpdate(probed local: String?, startedFrom: String?) {
        var v = snapshot.version
        if let f = v.updateFailure,
           !v.updateAvailable || (f.from != nil && v.local != f.from) || (f.to != nil && v.latest != f.to) {
            v.updateFailure = nil
        }
        if let startedFrom, let local, local == startedFrom, v.updateAvailable {
            v.updateFailure = UpdateFailure(
                exitCode: 0, outputTail: UpdateRunner.tail(of: paths.updateLog, home: deps.home), from: local, to: v.latest
            )
            fail("update", "exit 0, but Claude Code is still \(local)")
        }
        snapshot.version = v
    }

    /// Holds a latch for the version it was seen with; any other version re-arms the usage probe at once.
    private func checkLatch() {
        guard var l = latch else { return }
        if let v = snapshot.version.local, !l.holds(forVersion: v) {
            if l.version.isEmpty {
                l.version = v
                latch = l
                latchStore.save(l)
            } else {
                latch = nil
                latchStore.save(nil)
                if snapshot.usageIssue?.isLatched == true { snapshot.usageIssue = nil }
                usage.lastTry = nil
                if !usage.running, claude != nil { startUsage(now: deps.clock()) }
                return
            }
        }
        snapshot.usageIssue = l.issue
        snapshot.usageProbeCompleted = true
    }

    private func startChangelogIfNeeded(now: Date) {
        let v = snapshot.version
        guard !stopped, v.updateAvailable, let local = v.local, let latest = v.latest, !changelog.running else { return }
        if let c = v.changes, c.forVersion == latest, c.fromVersion == local { return }
        guard Cadence.due(last: changelog.lastTry, interval: Self.changelogRetry, now: now) else { return }
        changelog.lastTry = now
        changelog.running = true
        let http = deps.http
        spawn { me in
            let body = try? await http.get(AppInfo.changelogRaw, timeout: 30)
            me.completing {
                me.changelog.running = false
                guard let body, let local = me.snapshot.version.local, let latest = me.snapshot.version.latest else {
                    return me.fail("changelog", "download failed")
                }
                let items = ChangelogSlicer.slice(String(decoding: body, as: UTF8.self), after: local, upTo: latest)
                me.snapshot.version.changes = ChangesExcerpt(forVersion: latest, fromVersion: local, items: items)
                me.succeed("changelog")
            }
        }
    }

    private func startAccount(now: Date) {
        guard let claude else { return }
        account.lastTry = now
        account.running = true
        let spec = AccountProbe.spec(claude: claude.path, environment: childEnvironment, home: deps.home)
        let runner = deps.runner
        spawn { me in
            let info = AccountProbe.interpret(await runner.run(spec))
            me.completing {
                me.account.running = false
                if let info {
                    me.snapshot.account = info
                    me.succeed("account")
                } else {
                    me.fail("account", "claude auth status gave no answer")
                }
            }
        }
    }

    private func startStatus(now: Date) {
        status.lastTry = now
        status.running = true
        let http = deps.http, clock = deps.clock
        spawn { me in
            let body = try? await http.get(AppInfo.statusSummary, timeout: 15)
            me.completing {
                me.status.running = false
                if let s = body.flatMap(StatusProbe.parse) {
                    me.snapshot.status = s
                    me.snapshot.statusAt = clock()
                    me.succeed("status")
                } else {
                    me.fail("status", "no summary from \(AppInfo.statusSummary.host ?? "")")
                }
            }
        }
    }

    private func readSessions(now: Date) {
        guard config.showSessions || config.showMascot else { return }
        let dir = SessionRegistry.directory(configDir: configDirectory, home: deps.home)
        snapshot.sessions = SessionRegistry(directory: dir, table: deps.table, readFile: deps.readFile)
            .read(excluding: deps.runner.childPIDs, now: now)
        snapshot.sessionsRead = true
    }

    private func weatherChanged() {
        completing {
            snapshot.weather = weather.weather
            snapshot.place = weather.place
            succeed("weather")
        }
    }

    // MARK: - Plumbing

    private var configDirectory: String {
        ClaudeConfigDir.resolve(account: snapshot.account, login: login, environment: deps.environment, home: deps.home)
    }

    private var childEnvironment: [String: String] {
        ChildEnv.make(inherited: deps.environment, login: login, claude: claude?.path)
    }

    /// Runs `body` on the main actor and forgets the task when it ends.
    private func spawn(_ body: @escaping @MainActor (DataController) async -> Void) {
        let id = nextTask
        nextTask += 1
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            await body(self)
            self.tasks[id] = nil
        }
    }

    /// An async completion: applies `change` unless we stopped, and tells the app when the snapshot moved.
    private func completing(_ change: () -> Void) {
        guard !stopped else { return }
        let before = snapshot
        change()
        if snapshot != before { onChange?() }
    }

    private func fail(_ source: String, _ message: String) {
        guard failures[source] != message else { return }
        failures[source] = message
        log.append("\(source): \(message)", now: deps.clock(), timeZone: deps.timeZone)
    }

    private func succeed(_ source: String) { failures[source] = nil }

    nonisolated static func describe(_ issue: UsageIssue) -> String {
        switch issue {
        case .claudeNotFound: "claude not found"
        case .launchFailed(let s): s
        case .timedOut: "timed out after 60 s"
        case .probeFailed(let s): s
        case .noLimits: "no plan limits in /usage"
        case .flagRejected(let o): "claude rejected \(o); stopped until the CLI version changes"
        case .modelReached(let turns, let cost, let tokens):
            "/usage reached the model (\(turns) turns, $\(cost), \(tokens) tokens); stopped until the CLI version changes"
        }
    }
}
