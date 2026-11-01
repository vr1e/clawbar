import CoreGraphics
import Foundation
import Testing
@testable import ClawBarClawd
import ClawBarShared

/// hearts.ps1: halves, the tooltip, the lost-heart blink, the heartbeat, the tiers and the drain demo.
@Suite struct HeartsTests {
    static func hearts(pct: Int?) -> HeartsFrame {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1, pct: pct), now: t0)
        return engine.step(env()).hearts
    }

    /// hearts.ps1's integer mapping: 0–16 % → 6, 17–33 → 5, 34–49 → 4, 50–66 → 3, 67–83 → 2, 84–99 → 1, 100+ → 0.
    @Test(arguments: [(0, 6), (16, 6), (17, 5), (33, 5), (34, 4), (49, 4), (50, 3), (66, 3), (67, 2), (83, 2), (84, 1), (99, 1), (100, 0), (130, 0)])
    func halvesFromTheSessionPercent(_ pct: Int, _ halves: Int) {
        let h = Self.hearts(pct: pct)
        #expect(h.visible && h.shownHalves == halves)
    }

    @Test func aBareDrainLeavesTheRunningActAloneUnlikeTheMenusPlayLosingHearts() {
        // record-gif.ps1 sets drainT = 0 and nothing else; the menu item stops the act first.
        let bare = ClawdEngine.settled()
        bare.perform(.act(.jump))
        _ = bare.step(env())
        bare.startDrain()
        _ = bare.step(env())
        #expect(bare.devState.drainRunning && bare.tickMilliseconds == 60)

        let menu = ClawdEngine.settled()
        menu.perform(.act(.jump))
        _ = menu.step(env())
        menu.perform(.drain)
        _ = menu.step(env())
        #expect(menu.devState.drainRunning && menu.tickMilliseconds == 90)
    }

    @Test func noDataHidesTheHearts() {
        #expect(Self.hearts(pct: nil) == .hidden)
    }

    @Test func theTooltipNamesTheTierAndWhatIsLeft() {
        #expect(Self.hearts(pct: 34).tooltip == "a bit tired · 66% of the session limit left")
        #expect(Self.hearts(pct: 0).tooltip == "full of energy · 100% of the session limit left")
        let forced = ClawdEngine.settled()
        forced.apply(input(sessions: 1, pct: 34), now: t0)
        forced.perform(.hearts(5))
        #expect(forced.step(env()).hearts.tooltip == "fine")
        // A forced 'dead' empties the hearts; the limit is still real, so the tooltip keeps it.
        forced.perform(.mood(.dead))
        forced.perform(.hearts(nil))
        let dead = forced.step(env()).hearts
        #expect(dead.tooltip == "out of strength · 66% of the session limit left")
        #expect(forced.run(16).last?.hearts.shownHalves == 0)
    }

    @Test func aLostHeartBlinksForSixteenTicks() {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1, pct: 34), now: t0)
        #expect(engine.step(env()).hearts.shownHalves == 4)
        engine.apply(input(sessions: 1, pct: 50), now: t0)
        let shown = engine.run(18).map(\.hearts.shownHalves)
        #expect(shown == [4, 4, 3, 3, 4, 4, 3, 3, 4, 4, 3, 3, 4, 4, 3, 3, 3, 3])
        // Gaining hearts never blinks.
        engine.apply(input(sessions: 1, pct: 0), now: t0)
        #expect(engine.run(3).map(\.hearts.shownHalves) == [6, 6, 6])
    }

    @Test func switchingTheMainLimitIsNoLostHeartAndTheTooltipNamesTheWeek() {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1, pct: 34), now: t0)
        engine.step(env())
        engine.apply(input(sessions: 1, limit: .week, pct: 59), now: t0)
        let frames = engine.run(4).map(\.hearts)
        #expect(frames.map(\.shownHalves) == [3, 3, 3, 3])
        #expect(frames[0].tooltip == "tired · 41% of the weekly limit left")
    }

    @Test func resetHeartsForgetsTheLastValue() {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1, pct: 34), now: t0)
        engine.step(env())
        engine.resetHearts()
        engine.apply(input(sessions: 1, pct: 50), now: t0)
        #expect(engine.run(2).map(\.hearts.shownHalves) == [3, 3])
    }

    @Test(arguments: [(70, true), (90, true), (50, false), (100, false)])
    func theHeartsBeatAtOneOrTwoHalves(_ pct: Int, _ beats: Bool) {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1, pct: pct), now: t0)
        let scales = engine.run(25).map(\.hearts.beatScale)
        var want = Array(repeating: 1.0, count: 25)
        if beats {
            // tick mod 12: 0 → 1.3, 1 → 1.15; the first tick is 1.
            want[0] = 1.15
            want[11] = 1.3
            want[12] = 1.15
            want[23] = 1.3
            want[24] = 1.15
        }
        #expect(scales == want)
    }

    @Test func theDrainTimeline() {
        let engine = ClawdEngine.settled()
        engine.perform(.drain)
        #expect(engine.devState == ClawdDevState(drainRunning: true))
        let frames = engine.run(168)
        let names = ["out of strength", "barely alive", "exhausted", "tired", "a bit tired", "fine", "full of energy"]
        for (i, frame) in frames.prefix(166).enumerated() {
            let s = i + 1
            let halves = max(0, 6 - (s - 1) / 22)
            var shown = halves
            // Each lost half blinks for 16 ticks from the step it drops.
            let drop = ((s - 1) / 22) * 22 + 1
            if s > 22, s - drop < 16, halves < 6, (s - drop) % 4 < 2, (s - 1) / 22 <= 6 { shown = halves + 1 }
            #expect(frame.hearts.visible && frame.hearts.shownHalves == shown, "step \(s)")
            #expect(frame.devCaption == "dev · " + (halves == 0 ? "limit reached" : names[halves]), "step \(s)")
        }
        // 0 halves from step 133: belly-up (tick 133 mod 50 is past the leg twitch).
        expectPose(frames[132], ClawdPose(eyes: .x, flip: true))
        // Step 167 is back to live data: no data, so no hearts, and no developer caption.
        #expect(frames[166].hearts == .hidden && frames[166].devCaption.isEmpty)
        #expect(engine.devState == ClawdDevState())
    }

    @Test func choosingHeartsStopsADrain() {
        let engine = ClawdEngine.settled()
        engine.perform(.drain)
        engine.run(30)
        engine.perform(.hearts(2))
        #expect(engine.devState == ClawdDevState(forceHearts: 2))
        // From the drain's 5 to 2 is a loss too: it blinks, then holds.
        let shown = engine.run(30).map(\.hearts.shownHalves)
        #expect(Array(shown.prefix(16)) == [5, 5, 2, 2, 5, 5, 2, 2, 5, 5, 2, 2, 5, 5, 2, 2])
        #expect(shown.dropFirst(16).allSatisfy { $0 == 2 })
    }

    /// Work mood runs 1.6 × the tier's speed; tier 1 also sways ±1.5 with sin(tick / 3).
    @Test(arguments: [(0, 2.0), (20, 1.6), (40, 1.44), (60, 1.2), (70, 0.88), (90, 0.56)])
    func theTierSetsTheRunningSpeed(_ pct: Int, _ speed: Double) {
        let engine = ClawdEngine.settled()
        engine.apply(input(busy: 1, pct: pct), now: t0)
        let frames = engine.run(10)
        for (i, f) in frames.enumerated() {
            let tick = Double(i + 1)
            var x = 72 + speed * tick
            if pct == 90 { x += 1.5 * sin(tick / 3) }
            #expect(Double(f.spriteRect.minX) == x.rounded(.toNearestOrEven), "tick \(tick)")
        }
    }

    @Test func stepsSlowWithTheTierAndThePerkyBob() {
        // Tier 5: a step every 2 ticks, left foot on odd ⌊tick / 2⌋, lifted by 1 while perky.
        let perky = ClawdEngine.settled()
        perky.apply(input(busy: 1, pct: 20), now: t0)
        let fast = perky.run(6)
        let feet: [ClawdFeet] = [.right, .left, .left, .right, .right, .left]
        for (i, f) in fast.enumerated() {
            expectPose(f, ClawdPose(eyes: .focus, feet: feet[i], look: 1), lift: feet[i] == .left ? 1 : 0)
        }
        // Tier 3 (speed 0.75): a step every 3 ticks and no bob.
        let tired = ClawdEngine.settled()
        tired.apply(input(busy: 1, pct: 60), now: t0)
        let slow = tired.run(6)
        let feet3: [ClawdFeet] = [.right, .right, .left, .left, .left, .right]
        for (i, f) in slow.enumerated() { expectPose(f, ClawdPose(eyes: .focus, feet: feet3[i], look: 1)) }
    }

    @Test func tiredTiersChangeTheEyes() {
        let tired = ClawdEngine.settled()
        tired.apply(input(sessions: 1, pct: 60), now: t0)
        expectPose(tired.step(env()), ClawdPose(eyes: .focus))
        // Below the crit line, so the eyes do not dart.
        let barely = ClawdEngine.settled()
        barely.apply(input(sessions: 1, pct: 90, crit: 100), now: t0)
        let f = barely.step(env())
        #expect(FrameView(f).pixels == grid(ClawdSprite.render(ClawdPose(eyes: .blink))))
        #expect(FrameView(f).sweat.count == 1)
    }

    @Test func tiersRollForHopsYawnsAndStumbles() {
        let hop = ScriptedRandom()
        let lively = ClawdEngine.settled(hop)
        lively.apply(input(sessions: 1, pct: 0), now: t0)
        hop.queue(300, 0)
        lively.step(env())
        #expect(lively.tickMilliseconds == 60)

        let yawn = ScriptedRandom()
        let sleepy = ClawdEngine.settled(yawn)
        sleepy.apply(input(sessions: 1, pct: 40), now: t0)
        yawn.queue(350, 0)
        sleepy.step(env())
        let yawning = sleepy.run(4)
        expectPose(yawning[0], ClawdPose(eyes: .closed))
        expectPose(yawning[3], ClawdPose(eyes: .yawn))

        let trip = ScriptedRandom()
        let weak = ClawdEngine.settled(trip)
        weak.apply(input(busy: 1, pct: 90), now: t0)
        trip.queue(220, 0)
        weak.step(env())
        #expect(FrameView(weak.step(env())).pixels == grid(ClawdSprite.render(ClawdPose(eyes: .closed, off: 1))))
    }
}
