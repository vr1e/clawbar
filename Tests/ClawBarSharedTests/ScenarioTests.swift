import Foundation
import Testing
import ClawBarShared

@Suite struct ScenarioScriptTests {
    @Test func everyScenarioMatchesRecordGifPs1() {
        let lengths: [RecordScenario: Double] = [.tour: 14.5, .sleep: 9, .limit: 9.5, .reset: 8.5, .hearts: 15.5, .weather: 12, .clicks: 11]
        for s in RecordScenario.allCases {
            let script = Scenarios.script(s)
            #expect(script.length == lengths[s], "\(s)")
            // Only the tour shows the whole card; the others crop below the reset line.
            #expect(script.crop == (s != .tour), "\(s)")
            #expect(script.steps.first?.at == 0)
            #expect(script.steps.map(\.at) == script.steps.map(\.at).sorted())
        }
    }

    @Test func theTourBusiesApiRaisesUsageThenMakesWebWait() {
        let steps = Scenarios.script(.tour).steps
        #expect(steps.map(\.at) == [0, 2.5, 4, 5.5, 7, 8.5, 10.5, 14.5])
        #expect(steps[0].actions == [
            .sky(.day, 2), .usage(34, resetMinutes: 192),
            .sessions([FakeSession("api"), FakeSession("web")]),
        ])
        #expect(steps[1].actions == [.sessions([FakeSession("api", .busy), FakeSession("web")])])
        #expect(steps[2...4].map(\.actions) == [[.usage(36, resetMinutes: 192)], [.usage(39, resetMinutes: 192)], [.usage(42, resetMinutes: 192)]])
        #expect(steps[6].actions == [.sessions([FakeSession("api"), FakeSession("web", .waiting, waitingFor: "permission")])])
        #expect(steps[7].actions.isEmpty)
    }

    @Test func clicksResetsAndTheDrainAreScripted() {
        #expect(Scenarios.script(.clicks).steps.filter { $0.actions == [.click] }.map(\.at) == [1, 3.5, 6, 8.5])
        #expect(Scenarios.script(.limit).steps[1].actions == [.click])
        #expect(Scenarios.script(.reset).steps[1].actions == [.usage(0, resetMinutes: 300)])
        #expect(Scenarios.script(.hearts).steps[0].actions.contains(.drain))
        #expect(Scenarios.script(.weather).steps.compactMap { step -> SkyPhase? in
            guard case let .sky(p, _)? = step.actions.first else { return nil }
            return p
        } == [.day, .night, .dusk, .dawn])
    }
}

@Suite struct ScenarioPlayerTests {
    @Test func stepsApplyOnTheFirstFrameAtOrAfterTheirTime() {
        let start = Samples.now
        let player = ScenarioPlayer(Scenarios.script(.sleep))
        #expect(player.advance(frame: 0, now: start).count == 3)
        #expect(player.advance(frame: 16, now: start).isEmpty)
        // 1.5 s is frame 16.67: the sessions empty out on frame 17.
        #expect(player.advance(frame: 17, now: start) == [.sessions([])])
        #expect(!player.finished)
        _ = player.advance(frame: 100, now: start)
        #expect(player.finished)
    }

    @Test func aRecordingHasOneFramePerTickBeforeTheEnd() {
        // record-gif.ps1 captures while frame × 0.09 is short of the last step's time.
        #expect(ScenarioPlayer.frameCount(Scenarios.script(.sleep)) == 100)
        #expect(ScenarioPlayer.frameCount(Scenarios.script(.tour)) == 162)
        #expect(ScenarioPlayer.frameCount(Scenarios.script(.limit)) == 106)
    }

    @Test func theFakeDataIsSetUsagesShape() throws {
        let start = Samples.now
        let player = ScenarioPlayer(Scenarios.script(.reset))
        _ = player.advance(frame: 0, now: start)
        let u = try #require(player.snapshot(now: start).usage)
        #expect(u.sessionPercent == 96 && u.weekPercent == 41)
        #expect(u.modelWeeks == [ModelWeek(name: "Fable", percent: 18, reset: start.addingTimeInterval(2.4 * 86400))])
        #expect(u.sessionReset == start.addingTimeInterval(3 * 60))
        let s = player.snapshot(now: start)
        #expect(s.sessions.map(\.name) == ["api"] && s.sessions[0].state == .busy)
        #expect(s.sessionsRead && s.usageProbeCompleted)
        #expect(s.status?.indicator == "none" && s.statusAt == start)
    }

    @Test func theSkyOverrideIsHandedBackForTheEngine() {
        let player = ScenarioPlayer(Scenarios.script(.reset))
        #expect(player.advance(frame: 0, now: Samples.now).first == .sky(.day, 1))
    }
}
