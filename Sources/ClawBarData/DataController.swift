import Foundation
import ClawBarShared

/// The data engine's live run. `DataEngine` decides; each command goes through `CommandRecipes`, an answer that
/// takes a Task comes back on the main actor as an event, the engine's log lines reach error.log, and `onChange`
/// fires when an answer moved the snapshot.
@MainActor
public final class DataController {
    public var snapshot: DataSnapshot { engine.snapshot }
    /// Called after an async probe completion changed `snapshot`; never from inside the methods below.
    public var onChange: (@MainActor () -> Void)?

    private var engine: DataEngine
    private let deps: CommandRecipes.Dependencies
    private let recipes: CommandRecipes
    private let log: ErrorLog
    private let weather: WeatherService
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var nextTask = 0

    public convenience init(config: Config, paths: AppPaths) {
        self.init(config: config, paths: paths, deps: .live())
    }

    init(config: Config, paths: AppPaths, deps: CommandRecipes.Dependencies) {
        self.deps = deps
        recipes = CommandRecipes(deps: deps, paths: paths)
        log = ErrorLog(url: paths.errorLog)
        engine = DataEngine(
            config: config, environment: deps.environment, home: deps.home,
            latch: recipes.savedLatch(), history: recipes.savedHistory()
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

    /// Runs one command. The log line and the cancel are the controller's own; the rest have a recipe, answered at
    /// once or through a Task that answers through `complete`.
    private func execute(_ command: DataCommand, now: Date) -> DataEvent? {
        switch command {
        case .log(let line):
            log.append(line, now: deps.clock(), timeZone: deps.timeZone)
        case .cancelAll:
            weather.shutdown()
            for t in tasks.values { t.cancel() }
            deps.runner.shutdown()
        default:
            switch recipes.recipe(for: command, now: now) {
            case .now(let event)?: return event
            case .later(let priority, let work)?: spawn(priority: priority, work)
            case nil: break
            }
        }
        return nil
    }

    private func weatherChanged() {
        complete(.weather(weather.weather, weather.place))
    }

    /// Runs `work` off the main actor, feeds its event back on it, and forgets the task when it ends.
    private func spawn(priority: TaskPriority?, _ work: @escaping @Sendable () async -> DataEvent) {
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
