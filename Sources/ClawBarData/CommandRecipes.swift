import Foundation
import ClawBarShared

/// How each of the engine's commands is carried out against a process, the network or disk, and what it answers.
/// One recipe per command, composed from the probes' spec/interpret pairs; `DataController` and `--diagnose` both
/// run them.
struct CommandRecipes: Sendable {
    /// The system boundaries, injectable so tests drive the data side with fakes and a hand clock.
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

    /// How a command answers.
    enum Recipe {
        /// On the spot, so the engine continues within the same event: a lookup on disk or a save.
        case now(DataEvent)
        /// Off the main actor, until its answer comes back as an event.
        case later(priority: TaskPriority? = nil, work: @Sendable () async -> DataEvent)
    }

    private let deps: Dependencies
    private let latchStore: LatchStore
    private let historyStore: UsageHistoryStore
    private let updateLog: URL
    /// Keeps each transcript's read position and the week's replies between scans.
    private let scanner = TranscriptScanner()

    /// The status page and the latest version; the changelog is a bigger file.
    static let httpTimeout: TimeInterval = 15
    static let changelogTimeout: TimeInterval = 30

    init(deps: Dependencies, paths: AppPaths) {
        self.deps = deps
        latchStore = LatchStore(url: paths.stateFile)
        historyStore = UsageHistoryStore(url: paths.historyFile)
        updateLog = paths.updateLog
    }

    /// What the engine starts from.
    func savedLatch() -> UsageLatch? { latchStore.load() }
    func savedHistory() -> [UsageSample] { historyStore.load(now: deps.clock()) }

    /// The recipe for one command; nil for the log line and the cancel, which are the adapter's own.
    func recipe(for command: DataCommand, now: Date) -> Recipe? {
        let runner = deps.runner, http = deps.http, home = deps.home, clock = deps.clock
        switch command {
        case .locate(let configPath, let login):
            let found = ClaudeLocator(home: home, candidates: deps.candidates).locate(configPath: configPath, login: login)
            return .now(.located(found, installHint: found.flatMap { UpdateRunner.installHint(claudePath: $0.path) }))
        case .readSessions(let directory):
            let sessions = SessionRegistry(directory: directory, table: deps.table, readFile: deps.readFile)
                .read(excluding: runner.childPIDs, now: now)
            return .now(.sessionsRead(sessions))
        case .runLoginShell:
            let capture = deps.loginShell, environment = deps.environment
            return .later { .loginShell(await capture(runner, environment, home)) }
        case .probeUsage(let claude, let environment):
            let spec = UsageProbe.spec(claude: claude, environment: environment, home: home), zone = deps.timeZone
            return .later { .usage(UsageProbe.interpret(await runner.run(spec), now: clock(), timeZone: zone)) }
        case .probeVersion(let claude, let environment, let configDirectory):
            let spec = VersionProbe.spec(claude: claude, environment: environment, home: home)
            let settings = URL(fileURLWithPath: configDirectory).appendingPathComponent("settings.json")
            return .later {
                let local = VersionProbe.local(await runner.run(spec))
                let channel = VersionProbe.channel(settings: try? Data(contentsOf: settings))
                let body = try? await http.get(VersionProbe.latestURL(channel: channel), timeout: Self.httpTimeout)
                let latest = body.flatMap { VersionProbe.latest(String(decoding: $0, as: UTF8.self)) }
                return .version(local: local, latest: latest, channel: channel)
            }
        case .probeAccount(let claude, let environment):
            let spec = AccountProbe.spec(claude: claude, environment: environment, home: home)
            return .later { .account(AccountProbe.interpret(await runner.run(spec))) }
        case .probeStatus:
            return .later { .status((try? await http.get(AppInfo.statusSummary, timeout: Self.httpTimeout)).flatMap(StatusProbe.parse)) }
        case .fetchChangelog:
            return .later {
                .changelog((try? await http.get(AppInfo.changelogRaw, timeout: Self.changelogTimeout)).map { String(decoding: $0, as: UTF8.self) })
            }
        case .runUpdate(let claude, let environment):
            let log = updateLog
            let spec = UpdateRunner.spec(claude: claude, environment: environment, home: home, log: log)
            return .later {
                let result = await runner.run(spec)
                let tail = UpdateRunner.tail(of: log, home: home)
                return .update(UpdateRunner.failure(result, tail: tail, home: home), logTail: tail)
            }
        case .saveLatch(let latch):
            return .now(.latchSaved(failure: Self.failure { try latchStore.save(latch) }))
        case .saveHistory(let samples):
            return .now(.historySaved(failure: Self.failure { try historyStore.save(samples) }))
        case .scanProjects(let root):
            let scanner = scanner
            // A first pass reads every transcript of the week, so it yields to everything else.
            return .later(priority: .utility) { .projects(await scanner.scan(root: root, now: clock())) }
        case .log, .cancelAll:
            return nil
        }
    }

    /// Runs the recipe at the clock to its answer, whichever way it answers; nil for a command without one.
    func answer(_ command: DataCommand) async -> DataEvent? {
        switch recipe(for: command, now: deps.clock()) {
        case .now(let event)?: event
        case .later(_, let work)?: await work()
        case nil: nil
        }
    }

    /// What `write` threw, described; nil when it went through.
    private static func failure(_ write: () throws -> Void) -> String? {
        do {
            try write()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
