import Foundation
import Testing
@testable import ClawBarAnimation
import ClawBarShared

@Suite struct ScenarioRunTests {
    @Test func theFakeDataIsSetUsagesShape() throws {
        let start = Samples.now
        let run = ScenarioRun(.reset, seed: 1)
        #expect(run.config.showMascot && run.config.showSky && run.crop)
        _ = run.next(numberWidth: 32)
        let u = try #require(run.data.usage)
        #expect(u.sessionPercent == 96 && u.weekPercent == 41)
        #expect(u.modelWeeks == [ModelWeek(name: "Fable", percent: 18, reset: start.addingTimeInterval(2.4 * 86400))])
        #expect(u.sessionReset == start.addingTimeInterval(3 * 60))
        let s = run.data
        #expect(s.sessions.map(\.name) == ["api"] && s.sessions[0].state == .busy)
        #expect(s.sessionsRead && s.usageProbeCompleted)
        #expect(s.status?.indicator == "none" && s.statusAt == start)
        #expect(run.engine.skyDev == SkyDevState(phase: .day, weatherCode: 1))
    }
}
