import CoreGraphics
import Foundation
import Testing
@testable import ClawBarClawd
import ClawBarShared

/// Walking: the span, the edge-to-edge run and its end with the work, idle targets, and the clamped target when the area
/// narrows (deviation 11a).
@Suite struct WalkTests {
    @Test func workRunsEdgeToEdge() throws {
        let engine = ClawdEngine.settled()
        engine.apply(input(busy: 1), now: t0)
        // From the centre (72) to the right edge (144) at 1.6 a tick: 45 ticks; then back.
        let xs = engine.run(100).map { Double($0.spriteRect.minX) }
        let edge = try #require(xs.firstIndex(of: 144))
        #expect(edge == 44)
        #expect(xs[edge + 2] < 144 && xs[99] < 100)
        #expect(xs.allSatisfy { (0 ... 144).contains($0) })
    }

    @Test func theEdgeIsForgottenWhenTheWorkEnds() {
        let engine = ClawdEngine.settled()
        engine.apply(input(busy: 1), now: t0)
        // Ten ticks into the run from the centre (72) to the right edge.
        let stop = Double(engine.run(10).last!.spriteRect.minX)
        engine.apply(input(sessions: 1), now: t0)
        let xs = engine.run(20).map { Double($0.spriteRect.minX) }
        #expect(stop < 144)
        #expect(xs.allSatisfy { $0 == stop })
    }

    @Test func aNarrowedAreaClampsTheTargetToo() {
        let engine = ClawdEngine.settled()
        engine.apply(input(busy: 1), now: t0)
        // Running right towards 200 in a 236-wide area.
        engine.run(30, env(width: 236))
        let narrow = env(width: 150)
        let xs = engine.run(20, narrow).map { Double($0.spriteRect.minX) }
        // The target follows the new edge at 114: reached at once, so he turns around instead of running in place.
        #expect(xs[0] == 114)
        #expect(xs[1] == (114 - 1.6).rounded(.toNearestOrEven))
        #expect(xs[19] < 100)
    }

    @Test func anIdleTargetBeyondTheNewEdgeIsReachedToo() {
        let random = ScriptedRandom()
        let engine = ClawdEngine.settled(random)
        engine.apply(input(sessions: 1), now: t0)
        // Centred in a narrow area first (x = 52), then a target rolled in a wide one: 0.5 × 200 = 100.
        engine.step(env(width: 140))
        random.queue(70, 0)
        engine.step(env(width: 236))
        // The area narrows to a span of 84: he walks to the new edge and stands there instead of walking in place.
        let frames = engine.run(70, env(width: 120))
        #expect(Double(frames.last!.spriteRect.minX) == 84)
        expectPose(frames.last!, ClawdPose(look: 1))
    }

    @Test func idleTargetsAndGlancesAreRandom() {
        let random = ScriptedRandom()
        let engine = ClawdEngine.settled(random)
        engine.apply(input(sessions: 1), now: t0)
        engine.step(env())
        // 1/45: a random glance, −1 … +1.
        random.queue(45, 0)
        random.queue(3, 0)
        expectPose(engine.step(env()), ClawdPose(look: -1))
        // 1/70: a random target (0.5 × 144 = 72: already there).
        random.queue(70, 0)
        expectPose(engine.step(env()), ClawdPose(look: -1))
        // 1/400: wave, stretch or look.
        random.queue(400, 0)
        random.queue(3, 0)
        engine.step(env())
        expectPose(engine.step(env()), ClawdPose(eyes: .happy, arms: .right))
    }

    @Test func idleWalkingWhistles() {
        let random = ScriptedRandom()
        let engine = ClawdEngine.settled(random)
        engine.apply(input(sessions: 1), now: t0)
        #expect(FrameView(engine.step(env(width: 140))).bubble == nil)
        random.queue(70, 0)
        random.queue(80, 0)
        let frames = engine.run(31, env(width: 236)).map(FrameView.init)
        // He starts walking and whistling on the same tick: a ♪ for 30 ticks.
        #expect(frames[0 ..< 30].allSatisfy { $0.bubble == "\u{266A}" })
        #expect(frames[30].bubble == nil)
        #expect(frames[0].texts.first?.color == Palette.bubbleNote)
    }

    @Test func theEyesFollowThePointerWhileStanding() {
        let engine = ClawdEngine.settled()
        expectPose(engine.step(env(over: true, mouseX: 72 + 18 + 11)), ClawdPose(look: 1))
        expectPose(engine.step(env(over: true, mouseX: 72 + 18 + 10)), ClawdPose())
        expectPose(engine.step(env(over: true, mouseX: 72 + 18 - 11)), ClawdPose(look: -1))
        // The pointer leaving keeps the last gaze.
        expectPose(engine.step(env()), ClawdPose(look: -1))
    }

    @Test func blinksLastTwoTicksAndComeEveryTwentyFiveToSeventyTicks() {
        let random = ScriptedRandom()
        let engine = ClawdEngine.settled(random)
        let frames = engine.run(30 + 1 + 25 + 1)
        // The first blink is at tick 30 and lasts two; the next comes 25 + 44 ticks after its second tick.
        expectPose(frames[28], ClawdPose())
        expectPose(frames[29], ClawdPose(eyes: .blink))
        expectPose(frames[30], ClawdPose(eyes: .blink))
        expectPose(frames[31], ClawdPose())
        let again = ScriptedRandom()
        let quick = ClawdEngine.settled(again)
        // Every idle tick rolls 1/45 for a glance first; the 32nd answer goes to the blink of tick 31.
        for _ in 0 ..< 31 { again.queue(45, 44) }
        again.queue(45, 0)
        let q = quick.run(57)
        expectPose(q[54], ClawdPose())
        expectPose(q[55], ClawdPose(eyes: .blink))
        expectPose(q[56], ClawdPose(eyes: .blink))
    }
}
