import Foundation
import Testing
@testable import ClawBarAnimation
@testable import ClawBarClawd
import ClawBarShared

/// tools/record-gif.ps1's scenarios through the engine on the virtual clock, frame for frame.
@Suite struct ReplayTests {
    @Test(arguments: RecordScenario.allCases)
    func theSameSeedAndScriptReplayExactly(_ scenario: RecordScenario) {
        let a = replay(scenario, seed: 2026), b = replay(scenario, seed: 2026)
        #expect(a.count > 90)
        #expect(a == b)
        #expect(a.count == Scenarios.frameCount(Scenarios.script(scenario)))
    }

    @Test func anotherSeedChangesTheRun() {
        #expect(replay(.clicks, seed: 1) != replay(.clicks, seed: 2))
    }

    @Test func clicksGetHeartsAndActs() {
        let frames = replay(.clicks, seed: 2026).map { FrameView($0.clawd) }
        #expect(frames.count == 123)
        // A click due at T lands after the step of the first tick at or past T, so its heart shows a tick later.
        for k in [12, 39, 67, 95] {
            #expect(frames[k].love == nil && frames[k + 1].love != nil, "click at frame \(k)")
        }
        // Update-Texts ran before the first tick with no usage, so the first frame has no hearts yet.
        #expect(!frames[0].frame.hearts.visible)
        #expect(frames[1...].allSatisfy { $0.frame.hearts.shownHalves == 5 && $0.frame.devCaption.isEmpty })
    }

    @Test func theLimitTakesEveryHeartAndTheClickReleasesTheSoul() {
        let frames = replay(.limit, seed: 2026, numberWidth: 47).map { FrameView($0.clawd) }
        #expect(frames.allSatisfy { $0.love == nil })
        #expect(frames[1...].allSatisfy { $0.frame.hearts.shownHalves == 0 && $0.frame.hearts.tooltip == "out of strength · 0% of the session limit left" })
        // 47 leaves a 179 play area: lying down, he stays at half its 143 span.
        #expect(frames.allSatisfy { $0.frame.spriteRect.minX == 72 })
        #expect(frames[..<24].allSatisfy { $0.soul.isEmpty })
        // The click lands after frame 23: the soul act runs from frame 24, visible for t = 7 … 53.
        #expect(frames[30].soul.isEmpty && frames[31].soul.count == 1 && frames[77].soul.count == 1 && frames[78].soul.isEmpty)
        expectPose(frames[22].frame, ClawdPose(eyes: .x, flip: true))
    }

    @Test func theResetCelebrates() {
        let frames = replay(.reset, seed: 2026).map { FrameView($0.clawd) }
        #expect(frames[..<46].allSatisfy { $0.bubble != "!" })
        #expect(frames[46].bubble == "!" && frames[46].confetti.count == 12)
        // 96% leaves half a heart; after the reset, all six halves.
        #expect(frames[45].frame.hearts.shownHalves == 1 && frames[60].frame.hearts.shownHalves == 6)
    }

    @Test func noSessionsBurrowsInToSleep() {
        let frames = replay(.sleep, seed: 2026).map { FrameView($0.clawd) }
        // The sessions empty after frame 17; the 30-tick burrow runs frames 18 to 47, then the 'z'.
        #expect(frames.firstIndex { $0.z } == 48)
        #expect(frames.last!.z)
        expectPose(frames.last!.frame, ClawdPose(eyes: .closed, dig: 4))
    }

    @Test func theHeartsDrainAndComeBack() {
        let frames = replay(.hearts, seed: 2026).map(\.clawd)
        let shown = frames.map(\.hearts.shownHalves)
        #expect(shown[1] == 6 && shown.contains(0))
        // record-gif.ps1 only sets drainT, so the entrance act plays on in place instead of being cut short.
        #expect(frames[1 ... 4].allSatisfy { $0.spriteRect.minX == frames[0].spriteRect.minX })
        // The drain is a developer state, so the caption shows until the recorder blanks it.
        #expect(frames[150].devCaption == "dev · limit reached")
        #expect(frames.last!.hearts == HeartsFrame(visible: true, shownHalves: 6, tooltip: "full of energy · 90% of the session limit left"))
        #expect(frames.last!.devCaption.isEmpty)
    }

    @Test func theTourWaitsWithAQuestion() {
        let frames = replay(.tour, seed: 2026).map { FrameView($0.clawd) }
        #expect(frames[..<118].allSatisfy { $0.bubble != "?" })
        #expect(frames[118...].contains { $0.bubble == "?" })
    }

    @Test func theWeatherScriptChangesTheSkyOnTheTickAfterEachStep() {
        let skies = replay(.weather, seed: 2026).map(\.sky)
        #expect(skies.count == 134)
        // Frame 0 follows the clock; the steps at 3, 6 and 9 s land after frames 34, 67 and 100.
        let day = skies[1 ... 34].map(Sprites.init), night = skies[35 ... 67].map(Sprites.init)
        let dusk = skies[68 ... 100].map(Sprites.init), dawn = skies[101 ... 133].map(Sprites.init)
        #expect(day.allSatisfy { $0.drops != nil && $0.flakes == nil && $0.ground == nil })
        #expect(night.allSatisfy { $0.flakes != nil && $0.ground != nil && $0.drops == nil })
        #expect(dusk.allSatisfy { $0.drops != nil && $0.ground == nil })
        #expect(dawn.allSatisfy { $0.sun != nil && $0.drops == nil && $0.flakes == nil })
        #expect(Set([skies[1].top, skies[35].top, skies[68].top, skies[101].top]).count == 4)
        // Rain and snow move every tick.
        #expect(zip(day, day.dropFirst()).allSatisfy { $0.drops != $1.drops })
        #expect(zip(night, night.dropFirst()).allSatisfy { $0.flakes != $1.flakes })
    }

    @Test func aRunHandsBackTheDataOnTheFramesAStepRan() throws {
        let run = ScenarioRun(.sleep, seed: 7)
        #expect(run.data.sessions.isEmpty && run.data.usage == nil)
        let first = try #require(run.next(numberWidth: 32))
        #expect(first.at == Samples.now && first.data?.sessions.map(\.name) == ["api"])
        #expect(run.data.usage?.sessionPercent == 12)
        // The clock follows the cadence: the entrance act is a 60 ms sequence, then 90 ms ticks.
        var previous = first
        for n in 1 ..< 17 {
            let ms = try #require(run.engine.tickMilliseconds)
            let f = try #require(run.next(numberWidth: 32))
            #expect(f.data == nil && f.at == previous.at.addingTimeInterval(Double(ms) / 1000), "frame \(n)")
            if n == 1 { #expect(f.at == first.at.addingTimeInterval(0.06)) }
            previous = f
        }
        // 1.5 s is frame 16.67: the sessions empty out on frame 17, the last frame is 99.
        #expect(try #require(run.next(numberWidth: 32)).data?.sessions.isEmpty == true)
        var count = 18
        while run.next(numberWidth: 32) != nil { count += 1 }
        #expect(count == 100)

        // A click changes no data, and Update-Widget still ran: the data comes back on those frames too.
        let clicks = ScenarioRun(.clicks, seed: 7)
        var withData: [Int] = []
        var n = 0
        while let f = clicks.next(numberWidth: 32) {
            if f.data != nil { withData.append(n) }
            n += 1
        }
        #expect(withData == [0, 12, 39, 67, 95])
    }
}
