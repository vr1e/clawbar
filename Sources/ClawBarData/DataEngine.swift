import Foundation
import ClawBarShared

/// What reaches the engine: the controller's entry points, and the answer to each command it asked for.
enum DataEvent: Sendable {
    case tick
    case pollSessions
    case refresh
    case startUpdate
    case configChanged(Config)
    case shutdown
    /// The weather service's place on a tick; configured coordinates need no fetch.
    case place(Place?)

    case located(ClaudeLocator.Found?, installHint: InstallHint?)
    case sessionsRead([SessionInfo])
    case loginShell(LoginEnvironment?)
    case usage(UsageProbe.Report)
    case version(local: String?, latest: String?)
    case account(AccountInfo?)
    case status(ServiceStatus?)
    case changelog(String?)
    case update(UpdateFailure?, logTail: String)
    case weather(WeatherSnapshot?, Place?)
    /// How work without an answer of its own went: a save, or the weather service.
    case succeeded(source: String)
    case failed(source: String, message: String)
}

/// What the engine asks the controller to do. The probes, the lookups and the login shell answer with their event;
/// a save answers `succeeded` or `failed`, or not at all.
enum DataCommand: Sendable, Hashable {
    case locate(configPath: String?, login: LoginEnvironment?)
    case readSessions(directory: URL)
    case runLoginShell
    case probeUsage(claude: String, environment: [String: String])
    case probeVersion(claude: String, environment: [String: String], configDirectory: String)
    case probeAccount(claude: String, environment: [String: String])
    case probeStatus
    case fetchChangelog
    case runUpdate(claude: String, environment: [String: String])
    case saveLatch(UsageLatch?)
    case saveHistory([UsageSample])
    case log(String)
    case cancelAll
}

/// The data side's decisions: which probe runs when, and what each answer does to the snapshot. Pure: time arrives
/// with every event, and whatever touches a process, the network or disk is a command the controller runs.
struct DataEngine: Sendable {
    private(set) var snapshot: DataSnapshot = .empty
    private(set) var config: Config

    /// One probe's bookkeeping: cadence counts from the last attempt.
    private struct Slot {
        var lastTry: Date?
        var running = false

        func due(_ interval: Int, _ now: Date) -> Bool {
            !running && Cadence.due(last: lastTry, interval: TimeInterval(interval), now: now)
        }
    }

    /// What asked for claude's location, since the answer comes back as its own event.
    private enum LocateReason {
        case config, refresh, schedule, login
    }

    private let environment: [String: String]
    private let home: String
    private var latch: UsageLatch?
    private var login: LoginEnvironment?
    /// Login shell runs that finished; the claude probes wait for the first.
    private var loginRuns = 0
    private var loginRunning = false
    private var claude: ClaudeLocator.Found?
    private var lastLocate: Date?
    private var locateReason: LocateReason?

    private var usage = Slot()
    private var account = Slot()
    private var status = Slot()
    private var version = Slot()
    private var changelog = Slot()
    private var versionAgain = false
    /// After a clean `claude update`: the version it started from, for the next look to judge.
    private var pendingVerify: String?
    /// Taken from `pendingVerify` when a look starts: a look already running saw the old version.
    private var judging: String?
    private var updating = false
    private var updateFrom: String?
    private var updateTo: String?
    /// The update log's last lines, for a clean exit that left the version where it was.
    private var updateTail = ""
    private var stopped = false
    /// The last logged failure per source, so a dead endpoint logs once, not every interval.
    private var failures: [String: String] = [:]
    private var commands: [DataCommand] = []

    static let changelogRetry: TimeInterval = 600
    /// Each run sources the user's rc files again, so a shell that never answers is not asked forever.
    static let loginRunLimit = 4

    init(config: Config, environment: [String: String], home: String, latch: UsageLatch?, history: [UsageSample]) {
        self.config = config.clamped()
        self.environment = environment
        self.home = home
        self.latch = latch
        snapshot.history = history
    }

    /// Applies one event and returns the work it calls for, in order. After `shutdown` every event is ignored.
    mutating func handle(_ event: DataEvent, now: Date) -> [DataCommand] {
        guard !stopped else { return [] }
        commands = []
        switch event {
        case .tick:
            startDue(now: now)
        case .pollSessions:
            if resolved { readSessions() }
        case .refresh:
            guard resolved else { break }
            if claude == nil { locate(.refresh, now: now) } else { refreshUsage(now: now) }
        case .startUpdate:
            startUpdate()
        case .configChanged(let new):
            let old = config
            config = new.clamped()
            if config.claudePath != old.claudePath, resolved { locate(.config, now: now) }
        case .shutdown:
            stopped = true
            emit(.cancelAll)
        case .place(let place):
            snapshot.place = place
        case .located(let found, let hint):
            located(found, installHint: hint, now: now)
        case .sessionsRead(let sessions):
            snapshot.sessions = sessions
            snapshot.sessionsRead = true
        case .loginShell(let login):
            loginRunning = false
            loginRuns += 1
            self.login = login
            if login == nil { fail("login", "the login shell gave no answer") } else { succeed("login") }
            locate(.login, now: now)
        case .usage(let report):
            usageAnswered(report, now: now)
        case .version(let local, let latest):
            versionAnswered(local: local, latest: latest, now: now)
        case .account(let info):
            account.running = false
            if let info {
                snapshot.account = info
                succeed("account")
            } else {
                fail("account", "claude auth status gave no answer")
            }
        case .status(let status):
            self.status.running = false
            if let status {
                snapshot.status = status
                snapshot.statusAt = now
                succeed("status")
            } else {
                fail("status", "no summary from \(AppInfo.statusSummary.host ?? "")")
            }
        case .changelog(let body):
            changelog.running = false
            guard let body, let local = snapshot.version.local, let latest = snapshot.version.latest else {
                fail("changelog", "download failed")
                break
            }
            let items = ChangelogSlicer.slice(body, after: local, upTo: latest)
            snapshot.version.changes = ChangesExcerpt(forVersion: latest, fromVersion: local, items: items)
            succeed("changelog")
        case .update(let failure, let tail):
            updateFinished(failure, tail: tail, now: now)
        case .weather(let weather, let place):
            snapshot.weather = weather
            snapshot.place = place
            succeed("weather")
        case .succeeded(let source):
            succeed(source)
        case .failed(let source, let message):
            fail(source, message)
        }
        defer { commands = [] }
        return commands
    }

    // MARK: - The schedule

    private mutating func startDue(now: Date) {
        if config.showStatus, status.due(config.statusIntervalSeconds, now) { startStatus(now: now) }
        // Not found: look again every usage interval, through a login shell that gave no answer yet, since one slowed
        // down at login may be the only one that knows where.
        if claude == nil, !loginRunning, Cadence.due(last: lastLocate, interval: TimeInterval(config.usageIntervalSeconds), now: now) {
            if login == nil, loginRuns < Self.loginRunLimit { runLoginShell(now: now) } else { locate(.schedule, now: now) }
        }
        guard resolved, claude != nil else { return }
        if version.due(config.versionIntervalSeconds, now) { startVersion(now: now) }
        if latch == nil, usage.due(config.usageIntervalSeconds, now) { startUsage(now: now) }
        if config.showAccount, account.due(config.accountIntervalSeconds, now) { startAccount(now: now) }
        startChangelogIfNeeded(now: now)
    }

    private mutating func runLoginShell(now: Date) {
        lastLocate = now
        loginRunning = true
        emit(.runLoginShell)
    }

    private mutating func locate(_ reason: LocateReason, now: Date) {
        lastLocate = now
        locateReason = reason
        emit(.locate(configPath: config.claudePath, login: login))
    }

    /// Claude's location, then whatever asked for it continues.
    private mutating func located(_ found: ClaudeLocator.Found?, installHint: InstallHint?, now: Date) {
        claude = found
        if found != nil {
            snapshot.version.installHint = installHint
            if snapshot.usageIssue == .claudeNotFound { snapshot.usageIssue = nil }
            succeed("locate")
        } else {
            snapshot.usageIssue = .claudeNotFound
            snapshot.usageProbeCompleted = true
            fail("locate", "claude not found")
        }
        let reason = locateReason
        locateReason = nil
        switch reason {
        case .config, nil:
            break
        case .refresh:
            refreshUsage(now: now)
        case .schedule:
            startDue(now: now)
        case .login:
            readSessions()
            startDue(now: now)
        }
    }

    private mutating func readSessions() {
        guard config.showSessions || config.showMascot else { return }
        emit(.readSessions(directory: SessionRegistry.directory(configDir: configDirectory, home: home)))
    }

    /// Refresh now: the usage probe unless one is running or the probe is latched.
    private mutating func refreshUsage(now: Date) {
        guard latch == nil, !usage.running, claude != nil else { return }
        startUsage(now: now)
    }

    // MARK: - Probes

    private mutating func startUsage(now: Date) {
        guard let claude else { return }
        usage.lastTry = now
        usage.running = true
        emit(.probeUsage(claude: claude.path, environment: childEnvironment))
    }

    private mutating func usageAnswered(_ report: UsageProbe.Report, now: Date) {
        usage.running = false
        snapshot.usageProbeCompleted = true
        switch report.outcome {
        case .usage(let u):
            snapshot.usage = u
            snapshot.usageAt = now
            snapshot.usageIssue = nil
            succeed("usage")
            logUnread(report.unreadStamps)
            recordHistory(u, at: now)
        case .issue(.noLimits):
            // A login without a subscription: the old subscription's numbers no longer apply, its stats do.
            snapshot.usage = report.stats ?? UsageSnapshot()
            snapshot.usageAt = now
            snapshot.usageIssue = .noLimits
            succeed("usage")
        case .issue(let issue):
            if issue == .claudeNotFound {
                claude = nil
                lastLocate = now
            }
            if let l = UsageLatch(version: snapshot.version.local ?? "", issue: issue) {
                // Without a known version the latch holds for this run and is keyed by the next version answer.
                latch = l
                if !l.version.isEmpty {
                    emit(.saveLatch(l))
                } else if !version.running {
                    startVersion(now: now)
                }
            }
            snapshot.usageIssue = issue
            fail("usage", Self.describe(issue))
        }
    }

    /// Reset stamps in a format the parser does not know, by shape; the next CLI change shows up here.
    private mutating func logUnread(_ stamps: [String]) {
        var shapes: [String] = []
        for s in stamps.map(UsageParser.shape) where !shapes.contains(s) { shapes.append(s) }
        if shapes.isEmpty {
            succeed("usage-stamp")
        } else {
            fail("usage-stamp", "no date in " + shapes.map { "\"\($0)\"" }.joined(separator: ", "))
        }
    }

    /// Every good answer is a sample, whether or not the chart is shown, since nothing can fill in a missed day later.
    private mutating func recordHistory(_ u: UsageSnapshot, at now: Date) {
        guard UsageHistoryStore.record(u, at: now, into: &snapshot.history) else { return }
        emit(.saveHistory(snapshot.history))
    }

    private mutating func startVersion(now: Date) {
        guard let claude else { return }
        version.lastTry = now
        version.running = true
        // Only a look started after a clean update may judge it.
        judging = pendingVerify
        pendingVerify = nil
        emit(.probeVersion(claude: claude.path, environment: childEnvironment, configDirectory: configDirectory))
    }

    private mutating func versionAnswered(local: String?, latest: String?, now: Date) {
        version.running = false
        if let local { snapshot.version.local = local }
        if let latest { snapshot.version.latest = latest }
        if local == nil || latest == nil {
            fail("version", local == nil ? "claude --version failed" : "no latest version from \(AppInfo.releasesBase.host ?? "")")
        } else {
            succeed("version")
        }
        judgeUpdate(probed: local, startedFrom: judging)
        judging = nil
        checkLatch(now: now)
        if versionAgain {
            versionAgain = false
            startVersion(now: now)
        }
        startChangelogIfNeeded(now: now)
    }

    /// A failed update lasts while the versions it started from hold, as upstream's failed=<ver> does; a clean exit
    /// that left the version where it was, with the update still out, is a failure too.
    private mutating func judgeUpdate(probed: String?, startedFrom: String?) {
        let v = snapshot.version
        if let f = v.updateFailure, !(v.updateAvailable && f.holds(local: v.local, latest: v.latest)) {
            snapshot.version.updateFailure = nil
        }
        if let startedFrom, probed == startedFrom, v.updateAvailable {
            snapshot.version.updateFailure = UpdateFailure(exitCode: 0, outputTail: updateTail, from: startedFrom, to: v.latest)
            fail("update", "exit 0, but Claude Code is still \(startedFrom)")
        }
    }

    /// Holds a latch for the version it was seen with; any other version re-arms the usage probe at once.
    private mutating func checkLatch(now: Date) {
        guard var l = latch else { return }
        if let v = snapshot.version.local, !l.holds(forVersion: v) {
            if l.version.isEmpty {
                l.version = v
                latch = l
                emit(.saveLatch(l))
            } else {
                latch = nil
                emit(.saveLatch(nil))
                if snapshot.usageIssue?.isLatched == true { snapshot.usageIssue = nil }
                usage.lastTry = nil
                if !usage.running, claude != nil { startUsage(now: now) }
                return
            }
        }
        snapshot.usageIssue = l.issue
        snapshot.usageProbeCompleted = true
    }

    private mutating func startChangelogIfNeeded(now: Date) {
        let v = snapshot.version
        guard v.updateAvailable, let local = v.local, let latest = v.latest, !changelog.running else { return }
        if let c = v.changes, c.forVersion == latest, c.fromVersion == local { return }
        guard Cadence.due(last: changelog.lastTry, interval: Self.changelogRetry, now: now) else { return }
        changelog.lastTry = now
        changelog.running = true
        emit(.fetchChangelog)
    }

    private mutating func startAccount(now: Date) {
        guard let claude else { return }
        account.lastTry = now
        account.running = true
        emit(.probeAccount(claude: claude.path, environment: childEnvironment))
    }

    private mutating func startStatus(now: Date) {
        status.lastTry = now
        status.running = true
        emit(.probeStatus)
    }

    // MARK: - The update

    private mutating func startUpdate() {
        guard !updating, let claude else { return }
        updating = true
        snapshot.version.updating = true
        snapshot.version.updateFailure = nil
        pendingVerify = nil
        updateFrom = snapshot.version.local
        updateTo = snapshot.version.latest
        emit(.runUpdate(claude: claude.path, environment: childEnvironment))
    }

    private mutating func updateFinished(_ result: UpdateFailure?, tail: String, now: Date) {
        var failure = result
        failure?.from = updateFrom
        failure?.to = updateTo
        updating = false
        updateTail = tail
        snapshot.version.updating = false
        snapshot.version.updateFailure = failure
        if let failure {
            fail("update", "exit \(failure.exitCode.map(String.init) ?? "timeout"): \(failure.outputTail)")
        } else {
            succeed("update")
            pendingVerify = updateFrom
        }
        // The version may have changed either way: look again now.
        version.lastTry = nil
        if version.running { versionAgain = true } else { startVersion(now: now) }
    }

    // MARK: - Plumbing

    private var resolved: Bool { loginRuns > 0 }

    private var configDirectory: String {
        ClaudeConfigDir.resolve(account: snapshot.account, login: login, environment: environment, home: home)
    }

    private var childEnvironment: [String: String] {
        ChildEnv.make(inherited: environment, login: login, claude: claude?.path)
    }

    private mutating func emit(_ command: DataCommand) { commands.append(command) }

    private mutating func fail(_ source: String, _ message: String) {
        guard failures[source] != message else { return }
        failures[source] = message
        emit(.log("\(source): \(message)"))
    }

    private mutating func succeed(_ source: String) { failures[source] = nil }

    static func describe(_ issue: UsageIssue) -> String {
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
