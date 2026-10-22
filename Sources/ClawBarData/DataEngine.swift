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
    case weatherFailed(String)
    /// nil once the samples are on disk.
    case historySaved(failure: String?)
    /// nil once the latch is in state.json.
    case latchSaved(failure: String?)
    case projects(ProjectScan)
}

/// What the engine asks the controller to do. Each probe, lookup and save answers with its event.
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
    case scanProjects(root: String)
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

        mutating func start(_ now: Date) {
            lastTry = now
            running = true
        }
    }

    /// What continues once claude's location comes back as its own event.
    private enum AfterLocate {
        case refreshUsage, startDue
    }

    private let environment: [String: String]
    private let home: String
    private var latch: UsageLatch?
    private var login: LoginEnvironment?
    /// Login shell runs that finished; the claude probes wait for the first.
    private var loginRuns = 0
    private var claude: ClaudeLocator.Found?
    /// The login shell or the lookup that finds claude.
    private var locating = Slot()
    private var afterLocate: AfterLocate?

    private var usage = Slot()
    private var account = Slot()
    private var status = Slot()
    private var version = Slot()
    private var changelog = Slot()
    private var projects = Slot()
    /// After a clean `claude update`: the version it started from and the log's last lines, for the next look to judge.
    private var pendingVerify: (from: String, tail: String)?
    /// Taken from `pendingVerify` when a look starts: a look already running saw the old version.
    private var judging: (from: String, tail: String)?
    private var updateFrom: String?
    private var updateTo: String?
    private var stopped = false
    /// The last logged failure per source, so a dead endpoint logs once, not every interval.
    private var failures: [String: String] = [:]
    private var commands: [DataCommand] = []

    static let changelogRetry = 600
    /// Upstream's 15 minutes: the transcripts change by the minute, a week's shares do not.
    static let projectsInterval = 900
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
            if claude == nil { locate(then: .refreshUsage, now: now) } else { refreshUsage(now: now) }
        case .startUpdate:
            startUpdate()
        case .configChanged(let new):
            let old = config
            config = new.clamped()
            if config.claudePath != old.claudePath, resolved { locate(now: now) }
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
            locating.running = false
            loginRuns += 1
            self.login = login
            if login == nil { fail("login", "the login shell gave no answer") } else { succeed("login") }
            readSessions()
            locate(then: .startDue, now: now)
        case .usage(let report):
            usageAnswered(report, now: now)
        case .version(let local, let latest):
            versionAnswered(local: local, latest: latest, now: now)
        case .account(let info):
            account.running = false
            if let info {
                let root = projectsRoot
                snapshot.account = info
                // A scan that ran before the account named its config dir read the wrong transcripts.
                if projectsRoot != root { projects.lastTry = nil }
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
        case .weatherFailed(let message):
            fail("weather", message)
        case .historySaved(let failure):
            if let failure { fail("history", failure) } else { succeed("history") }
        case .latchSaved(let failure):
            if let failure { fail("latch", failure) } else { succeed("latch") }
        case .projects(let scan):
            projectsAnswered(scan, now: now)
        }
        return commands
    }

    // MARK: - The schedule

    private mutating func startDue(now: Date) {
        if config.showStatus, status.due(config.statusIntervalSeconds, now) { startStatus(now: now) }
        // Not found: look again every usage interval, through a login shell that gave no answer yet, since one slowed
        // down at login may be the only one that knows where.
        if claude == nil, locating.due(config.usageIntervalSeconds, now) {
            if login == nil, loginRuns < Self.loginRunLimit { runLoginShell(now: now) } else { locate(then: .startDue, now: now) }
        }
        // The transcripts need no claude, only the config dir the login shell may name.
        if resolved, config.showHistory, config.expanded, projects.due(Self.projectsInterval, now) { startProjects(now: now) }
        guard resolved, claude != nil else { return }
        if version.due(config.versionIntervalSeconds, now) { startVersion(now: now) }
        if latch == nil, usage.due(config.usageIntervalSeconds, now) { startUsage(now: now) }
        if config.showAccount, account.due(config.accountIntervalSeconds, now) { startAccount(now: now) }
        startChangelogIfNeeded(now: now)
    }

    private mutating func runLoginShell(now: Date) {
        locating.start(now)
        emit(.runLoginShell)
    }

    private mutating func locate(then next: AfterLocate? = nil, now: Date) {
        locating.start(now)
        afterLocate = next
        emit(.locate(configPath: config.claudePath, login: login))
    }

    /// Claude's location, then whatever asked for it continues.
    private mutating func located(_ found: ClaudeLocator.Found?, installHint: InstallHint?, now: Date) {
        locating.running = false
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
        let next = afterLocate
        afterLocate = nil
        switch next {
        case .refreshUsage?: refreshUsage(now: now)
        case .startDue?: startDue(now: now)
        case nil: break
        }
    }

    private mutating func readSessions() {
        guard config.showSessions || config.showMascot else { return }
        emit(.readSessions(directory: SessionRegistry.directory(configDir: configDirectory, home: home)))
    }

    private mutating func refreshUsage(now: Date) {
        guard latch == nil, !usage.running else { return }
        startUsage(now: now)
    }

    // MARK: - Probes

    private mutating func startUsage(now: Date) {
        guard let claude else { return }
        usage.start(now)
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
                locating.lastTry = now
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
        version.start(now)
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
        judgeUpdate(probed: local, verify: judging)
        judging = nil
        checkLatch(now: now)
        // An update that ended during this look cleared its cadence: look again now.
        if version.lastTry == nil { startVersion(now: now) }
        startChangelogIfNeeded(now: now)
    }

    /// A failed update lasts while the versions it started from hold, as upstream's failed=<ver> does; a clean exit
    /// that left the version where it was, with the update still out, is a failure too.
    private mutating func judgeUpdate(probed: String?, verify: (from: String, tail: String)?) {
        let v = snapshot.version
        if let f = v.updateFailure, !(v.updateAvailable && f.holds(local: v.local, latest: v.latest)) {
            snapshot.version.updateFailure = nil
        }
        if let verify, probed == verify.from, v.updateAvailable {
            snapshot.version.updateFailure = UpdateFailure(exitCode: 0, outputTail: verify.tail, from: verify.from, to: v.latest)
            fail("update", "exit 0, but Claude Code is still \(verify.from)")
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
                if !usage.running { startUsage(now: now) }
                return
            }
        }
        snapshot.usageIssue = l.issue
        snapshot.usageProbeCompleted = true
    }

    private mutating func startChangelogIfNeeded(now: Date) {
        let v = snapshot.version
        guard v.updateAvailable, let local = v.local, let latest = v.latest, changelog.due(Self.changelogRetry, now) else { return }
        if let c = v.changes, c.forVersion == latest, c.fromVersion == local { return }
        changelog.start(now)
        emit(.fetchChangelog)
    }

    private mutating func startAccount(now: Date) {
        guard let claude else { return }
        account.start(now)
        emit(.probeAccount(claude: claude.path, environment: childEnvironment))
    }

    private mutating func startStatus(now: Date) {
        status.start(now)
        emit(.probeStatus)
    }

    private mutating func startProjects(now: Date) {
        projects.start(now)
        emit(.scanProjects(root: projectsRoot))
    }

    /// Counts only: the log never names a project or quotes a transcript.
    private mutating func projectsAnswered(_ scan: ProjectScan, now: Date) {
        projects.running = false
        snapshot.projects = scan.usage
        snapshot.projectsAt = now
        if scan.unreadable > 0 { fail("projects", "unreadable transcripts: \(scan.unreadable)") } else { succeed("projects") }
        if scan.unpricedModels.isEmpty {
            succeed("projects-price")
        } else {
            fail("projects-price", "no list price for \(scan.unpricedModels.joined(separator: ", ")); priced as the nearest model")
        }
    }

    // MARK: - The update

    private mutating func startUpdate() {
        guard !snapshot.version.updating, let claude else { return }
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
        snapshot.version.updating = false
        snapshot.version.updateFailure = failure
        if let failure {
            fail("update", "exit \(failure.exitCode.map(String.init) ?? "timeout"): \(failure.outputTail)")
        } else {
            succeed("update")
            pendingVerify = updateFrom.map { (from: $0, tail: tail) }
        }
        // The version may have changed either way: look again now, or as soon as the running look answers.
        version.lastTry = nil
        if !version.running { startVersion(now: now) }
    }

    // MARK: - Plumbing

    private var resolved: Bool { loginRuns > 0 }

    private var configDirectory: String {
        ClaudeConfigDir.resolve(account: snapshot.account, login: login, environment: environment, home: home)
    }

    private var projectsRoot: String { configDirectory + "/projects" }

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
