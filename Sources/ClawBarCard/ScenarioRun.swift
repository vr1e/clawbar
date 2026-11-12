import Foundation
import ClawBarShared

/// record-gif.ps1 with a seeded generator and a virtual clock: one scenario through a `CardEngine` on
/// record-gif.ps1's config.json, a frame per tick. The steps set the fake data; the clock advances by the cadence.
public final class ScenarioRun {
    /// record-gif.ps1's config.json.
    let config = Scenarios.config
    /// The fake data as of the last frame.
    private(set) var data = DataSnapshot.empty
    /// The card as of the last frame, so the recorder draws what the app would.
    public let card: CardEngine
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
        card = CardEngine(random: SeededRandomSource(seed: seed), config: config, skins: .builtIn, now: now)
        data = fakeData(now: now)
        present(now: now)
    }

    /// Crop below the reset line, as every scenario but the tour does.
    public var crop: Bool { script.crop }

    /// The mascot timer's own handler first, then record-gif.ps1's: the due steps, then Update-Widget. Nil once the
    /// last step is due, which ends the recording.
    public func next(_ measure: CardMeasure) -> ScenarioFrame? {
        let at = now
        card.step(now: at, timeZone: Samples.timeZone, measure: measure)
        let animation = card.frame
        var applied = 0
        while due < script.steps.count, script.steps[due].at <= Scenarios.time(frame: n) {
            for action in script.steps[due].actions { apply(action, now: at) }
            applied += script.steps[due].actions.count
            due += 1
        }
        var fresh: DataSnapshot?
        if applied > 0 {
            data = fakeData(now: at)
            present(now: at)
            fresh = data
        }
        if due >= script.steps.count { return nil }
        // record-gif.ps1's config shows Clawd, so a tick always has a cadence.
        now = at.addingTimeInterval(Double(card.tickMilliseconds!) / 1000)
        n += 1
        return ScenarioFrame(animation: animation, at: at, data: fresh)
    }

    private func present(now: Date) {
        card.present(
            PresenterInput(config: config, now: now, timeZone: Samples.timeZone, data: data, homeDirectory: Samples.home),
            skins: .builtIn
        )
    }

    /// Set-Sky, Set-Usage and the session list as record-gif.ps1 applies them: the overrides, the click and the drain
    /// go to the engine, the data waits for Update-Widget.
    private func apply(_ action: ScenarioAction, now: Date) {
        switch action {
        case let .sky(phase, code):
            card.perform(.skyPhase(phase))
            card.perform(.skyWeather(code))
        case let .usage(p, minutes):
            pct = p
            sessionReset = now.addingTimeInterval(minutes * 60)
            weekReset = now.addingTimeInterval(2.4 * 86400)
            usageAt = now
        case let .sessions(s): sessions = s
        case .click: card.click(now: now)
        case .drain: card.startDrain()
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
