import Foundation
import ClawBarShared

/// record-gif.ps1 with a seeded generator and a virtual clock: one scenario through an `AnimationEngine`, a frame
/// per tick. Scenario time is frames × 0.09 s whatever the tick interval; the clock advances by the cadence.
public final class ScenarioRun {
    let engine: AnimationEngine
    public let script: ScenarioScript
    /// The fake data as of the last frame.
    public private(set) var data: DataSnapshot
    private let player: ScenarioPlayer
    private let config: Config
    private let timeZone: TimeZone
    private var now: Date
    private var n = 0

    /// Update-Texts renders once before the first tick, with no data yet.
    public init(
        _ scenario: RecordScenario, seed: UInt64, config: Config, timeZone: TimeZone = Samples.timeZone, start: Date = Samples.now
    ) {
        script = Scenarios.script(scenario)
        player = ScenarioPlayer(script)
        self.config = config
        self.timeZone = timeZone
        now = start
        engine = AnimationEngine(random: SeededRandomSource(seed: seed), config: config, now: start)
        data = player.snapshot(now: start)
        engine.apply(data, config: config, now: start)
    }

    public var mascotVisible: Bool { engine.mascotVisible }
    public var skyVisible: Bool { engine.skyVisible }

    /// The mascot timer's own handler first, then record-gif.ps1's: the due steps, then Update-Widget. Nil once the
    /// last step is due, which ends the recording.
    public func next(numberWidth: Double) -> ScenarioFrame? {
        let at = now
        let animation = engine.step(AnimationInputs(now: at, timeZone: timeZone, numberWidth: numberWidth))
        let applied = player.advance(frame: n, now: at)
        for action in applied {
            switch action {
            case .click: engine.click(now: at)
            case .drain: engine.startDrain()
            case let .sky(phase, code):
                engine.perform(.skyPhase(phase))
                engine.perform(.skyWeather(code))
            case .usage, .sessions: break
            }
        }
        var fresh: DataSnapshot?
        if !applied.isEmpty {
            data = player.snapshot(now: at)
            engine.apply(data, config: config, now: at)
            fresh = data
        }
        if player.finished { return nil }
        // A hidden Clawd has no cadence; the recording keeps the original's 90 ms frame then.
        now = at.addingTimeInterval(Double(engine.tickMilliseconds ?? 90) / 1000)
        n += 1
        return ScenarioFrame(animation: animation, at: at, data: fresh)
    }
}
