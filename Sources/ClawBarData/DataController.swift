import Foundation
import ClawBarShared

/// Owns every probe and the session registry, and folds their results into one `DataSnapshot`. `DataEngine` decides;
/// this runs its commands against processes, the network and disk, and feeds each answer back as an event.
@MainActor
public final class DataController {
    public var snapshot: DataSnapshot { engine.snapshot }
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

    private var engine: DataEngine
    private let paths: AppPaths
    private let deps: Dependencies
    private let log: ErrorLog
    private let latchStore: LatchStore
    private let historyStore: UsageHistoryStore
    private let weather: WeatherService
    /// Keeps each transcript's read position and the week's replies between scans.
    private let scanner = TranscriptScanner()
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var nextTask = 0

    public convenience init(config: Config, paths: AppPaths) {
        self.init(config: config, paths: paths, deps: .live())
    }

    init(config: Config, paths: AppPaths, deps: Dependencies) {
        self.paths = paths
        self.deps = deps
        log = ErrorLog(url: paths.errorLog)
        latchStore = LatchStore(url: paths.stateFile)
        historyStore = UsageHistoryStore(url: paths.historyFile)
        engine = DataEngine(
            config: config, environment: deps.environment, home: deps.home,
            latch: latchStore.load(), history: historyStore.load(now: deps.clock())
        )
        weather = WeatherService(http: deps.http, clock: deps.clock, log: { _ in })
        weather.onUpdate = { [weak self] in self?.weatherChanged() }
        weather.log = { [weak self] in self?.complete(.weatherFailed($0)) }
    }

    // MARK: - Public API

    /// A reloaded config: new intervals, coordinates, claudePath and show flags take effect.
    public func apply(config new: Config) {
        perform(.configChanged(new), now: deps.clock())
    }

    /// The data tick: collect finished probes, start those whose interval has passed since their last attempt.
    public func tick(now: Date) {
        weather.tick(now: now, config: engine.config)
        perform(.place(weather.place), now: now)
        perform(.tick, now: now)
    }

    /// Re-reads the session registry synchronously.
    public func pollSessions(now: Date) {
        perform(.pollSessions, now: now)
    }

    /// Refresh now: start the usage probe unless one is running or the probe is latched.
    public func refreshNow() {
        perform(.refresh, now: deps.clock())
    }

    /// Runs a headless `claude update` that survives quitting.
    public func startClaudeUpdate() {
        perform(.startUpdate, now: deps.clock())
    }

    /// Stops every probe child except a running update.
    public func shutdown() {
        perform(.shutdown, now: deps.clock())
    }

    // MARK: - Running the engine

    /// Runs the engine's commands for one event; a command answered at once goes straight back in. Nothing here fires
    /// `onChange`.
    private func perform(_ event: DataEvent, now: Date) {
        for command in engine.handle(event, now: now) {
            if let answer = execute(command, now: now) { perform(answer, now: now) }
        }
    }

    /// An async completion: as `perform`, then `onChange` when the snapshot moved.
    private func complete(_ event: DataEvent) {
        let before = engine.snapshot
        perform(event, now: deps.clock())
        if engine.snapshot != before { onChange?() }
    }

    /// Runs one command. A lookup or save answers at once with its event; the rest answer through `complete`.
    private func execute(_ command: DataCommand, now: Date) -> DataEvent? {
        let runner = deps.runner, http = deps.http, home = deps.home
        switch command {
        case .locate(let configPath, let login):
            let found = ClaudeLocator(home: home, candidates: deps.candidates).locate(configPath: configPath, login: login)
            return .located(found, installHint: found.flatMap { UpdateRunner.installHint(claudePath: $0.path) })
        case .readSessions(let directory):
            let sessions = SessionRegistry(directory: directory, table: deps.table, readFile: deps.readFile)
                .read(excluding: runner.childPIDs, now: now)
            return .sessionsRead(sessions)
        case .runLoginShell:
            let capture = deps.loginShell, environment = deps.environment
            spawn { .loginShell(await capture(runner, environment, home)) }
        case .probeUsage(let claude, let environment):
            let spec = UsageProbe.spec(claude: claude, environment: environment, home: home)
            let clock = deps.clock, zone = deps.timeZone
            spawn { .usage(UsageProbe.interpret(await runner.run(spec), now: clock(), timeZone: zone)) }
        case .probeVersion(let claude, let environment, let configDirectory):
            let spec = VersionProbe.spec(claude: claude, environment: environment, home: home)
            let settings = URL(fileURLWithPath: configDirectory).appendingPathComponent("settings.json")
            spawn {
                let local = VersionProbe.local(await runner.run(spec))
                let url = VersionProbe.latestURL(channel: VersionProbe.channel(settings: try? Data(contentsOf: settings)))
                let body = try? await http.get(url, timeout: 15)
                return .version(local: local, latest: body.flatMap { VersionProbe.latest(String(decoding: $0, as: UTF8.self)) })
            }
        case .probeAccount(let claude, let environment):
            let spec = AccountProbe.spec(claude: claude, environment: environment, home: home)
            spawn { .account(AccountProbe.interpret(await runner.run(spec))) }
        case .probeStatus:
            spawn { .status((try? await http.get(AppInfo.statusSummary, timeout: 15)).flatMap(StatusProbe.parse)) }
        case .fetchChangelog:
            spawn { .changelog((try? await http.get(AppInfo.changelogRaw, timeout: 30)).map { String(decoding: $0, as: UTF8.self) }) }
        case .runUpdate(let claude, let environment):
            let logURL = paths.updateLog
            let spec = UpdateRunner.spec(claude: claude, environment: environment, home: home, log: logURL)
            spawn {
                let result = await runner.run(spec)
                let tail = UpdateRunner.tail(of: logURL, home: home)
                return .update(UpdateRunner.failure(result, tail: tail, home: home), logTail: tail)
            }
        case .saveLatch(let latch):
            return .latchSaved(failure: Self.failure { try latchStore.save(latch) })
        case .saveHistory(let samples):
            return .historySaved(failure: Self.failure { try historyStore.save(samples) })
        case .scanProjects(let root):
            let scanner = scanner, clock = deps.clock
            // A first pass reads every transcript of the week, so it yields to everything else.
            spawn(priority: .utility) { .projects(await scanner.scan(root: root, now: clock())) }
        case .log(let line):
            log.append(line, now: deps.clock(), timeZone: deps.timeZone)
        case .cancelAll:
            weather.shutdown()
            for t in tasks.values { t.cancel() }
            runner.shutdown()
        }
        return nil
    }

    private func weatherChanged() {
        complete(.weather(weather.weather, weather.place))
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

    /// Runs `work` off the main actor, feeds its event back on it, and forgets the task when it ends.
    private func spawn(priority: TaskPriority? = nil, _ work: @escaping @Sendable () async -> DataEvent) {
        let id = nextTask
        nextTask += 1
        tasks[id] = Task(priority: priority) { [weak self] in
            let event = await work()
            guard let self else { return }
            self.complete(event)
            self.tasks[id] = nil
        }
    }
}
