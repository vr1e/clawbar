import Foundation
import ClawBarShared

/// record-gif.ps1 with a seeded generator and a virtual clock: one scenario through an `AnimationEngine` on
/// record-gif.ps1's config.json, a frame per tick. The steps set the fake data; the clock advances by the cadence.
public final class ScenarioRun {
    /// record-gif.ps1's config.json, for the presenter too.
    public let config = Scenarios.config
    /// The fake data as of the last frame.
    public private(set) var data = DataSnapshot.empty
    let engine: AnimationEngine
    let script: ScenarioScript
    private var now = Samples.now
    private var n = 0
    private var due = 0
    private var pct: Int?
    private var sessionReset: Date?
    private var weekReset: Date?
    private var usageAt: Date?
    private var sessions: [FakeSession] = []

    /// Update-Texts renders once before the first tick, with no data yet.
    public init(_ scenario: RecordScenario, seed: UInt64) {
        script = Scenarios.script(scenario)
        engine = AnimationEngine(random: SeededRandomSource(seed: seed), config: config, now: now)
        data = fakeData(now: now)
        engine.apply(data, config: config, now: now)
    }

    /// Crop below the reset line, as every scenario but the tour does.
    public var crop: Bool { script.crop }
    /// The engine's visibility rule, so the recorder draws what the app would.
    public var mascotVisible: Bool { engine.mascotVisible }
    public var skyVisible: Bool { engine.skyVisible }

    /// The mascot timer's own handler first, then record-gif.ps1's: the due steps, then Update-Widget. Nil once the
    /// last step is due, which ends the recording.
    public func next(numberWidth: Double) -> ScenarioFrame? {
        let at = now
        let animation = engine.step(AnimationInputs(now: at, timeZone: Samples.timeZone, numberWidth: numberWidth))
        var applied = 0
        while due < script.steps.count, script.steps[due].at <= Scenarios.time(frame: n) {
            for action in script.steps[due].actions { apply(action, now: at) }
            applied += script.steps[due].actions.count
            due += 1
        }
        var fresh: DataSnapshot?
        if applied > 0 {
            data = fakeData(now: at)
            engine.apply(data, config: config, now: at)
            fresh = data
        }
        if due >= script.steps.count { return nil }
        // record-gif.ps1's config shows Clawd, so a tick always has a cadence.
        now = at.addingTimeInterval(Double(engine.tickMilliseconds!) / 1000)
        n += 1
        return ScenarioFrame(animation: animation, at: at, data: fresh)
    }

    /// Set-Sky, Set-Usage and the session list as record-gif.ps1 applies them: the overrides, the click and the drain
    /// go to the engine, the data waits for Update-Widget.
    private func apply(_ action: ScenarioAction, now: Date) {
        switch action {
        case let .sky(phase, code):
            engine.perform(.skyPhase(phase))
            engine.perform(.skyWeather(code))
        case let .usage(p, minutes):
            pct = p
            sessionReset = now.addingTimeInterval(minutes * 60)
            weekReset = now.addingTimeInterval(2.4 * 86400)
            usageAt = now
        case let .sessions(s): sessions = s
        case .click: engine.click(now: now)
        case .drain: engine.startDrain()
        }
    }

    /// The fake data, with a fresh status so the line never says loading.
    private func fakeData(now: Date) -> DataSnapshot {
        let usage = pct.map { p in
            UsageSnapshot(
                sessionPercent: p, weekPercent: 41, sessionReset: sessionReset, weekReset: weekReset,
                modelWeeks: [ModelWeek(name: "Fable", percent: 18, reset: weekReset)]
            )
        }
        return DataSnapshot(
            usage: usage, usageAt: usageAt, usageProbeCompleted: true,
            sessions: sessions.enumerated().map { i, s in
                SessionInfo(
                    pid: Int32(4200 + i), name: s.name, cwd: "\(Samples.home)/code/\(s.name)", state: s.state,
                    waitingFor: s.waitingFor, kind: "interactive"
                )
            },
            sessionsRead: true, status: ServiceStatus(indicator: "none"), statusAt: now
        )
    }
}
