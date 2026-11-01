import CoreGraphics
import Foundation
import Testing
@testable import ClawBarClawd
import ClawBarShared

/// Set-MascotMood: the mood from sessions and limits, crit, the finished-reply jump and the reset celebration.
@Suite struct MoodTests {
    /// An engine whose caption reports the live mood: forced hearts turn developer mode on without forcing a mood.
    static func observed() -> ClawdEngine {
        let engine = ClawdEngine.settled()
        engine.perform(.hearts(6))
        return engine
    }

    static func caption(_ inputs: ClawdDataInput..., at now: Date = t0) -> String {
        let engine = observed()
        for i in inputs { engine.apply(i, now: now) }
        return engine.step(env(at: now)).devCaption
    }

    @Test func moodPriorityDeadWaitWorkIdleSleep() {
        #expect(Self.caption(input(busy: 1, waiting: 1, pct: 100)) == "dev · limit reached")
        #expect(Self.caption(input(busy: 1, waiting: 1, pct: 99)) == "dev · waiting for you · full of energy")
        #expect(Self.caption(input(busy: 1, waiting: 1)) == "dev · waiting for you · full of energy")
        #expect(Self.caption(input(busy: 1, pct: 40)) == "dev · working · full of energy")
        #expect(Self.caption(input(sessions: 2, pct: 40)) == "dev · wandering · full of energy")
        // No session at all: he burrows in to sleep.
        #expect(Self.caption(input(sessions: 0)) == "dev · burrows in · full of energy")
    }

    @Test func eachMoodHasItsPose() {
        let dead = ClawdEngine.settled()
        dead.apply(input(sessions: 1, pct: 100), now: t0)
        expectPose(dead.step(env()), ClawdPose(eyes: .x, feet: .left, flip: true))

        let wait = ClawdEngine.settled()
        wait.apply(input(waiting: 1), now: t0)
        let frame = wait.step(env())
        #expect(FrameView(frame).bubble == "?")
        #expect(FrameView(frame).texts.first?.color == Palette.bubbleQuestion)

        let sleep = ClawdEngine.settled()
        sleep.apply(input(sessions: 0), now: t0)
        let frames = sleep.run(31).map(FrameView.init)
        // After the 30-tick burrow: dug in to the eyes, asleep, with a 'z'.
        expectPose(frames[30].frame, ClawdPose(eyes: .closed, dig: 4))
        #expect(frames[30].z && !frames[29].z)
    }

    @Test func idleForTenMinutesDozes() {
        let engine = Self.observed()
        engine.apply(input(sessions: 1), now: t0)
        #expect(engine.step(env(at: t0 + 599)).devCaption == "dev · wandering · full of energy")
        #expect(engine.step(env(at: t0 + 600)).devCaption == "dev · dozing · full of energy")
        // The pointer over the window wakes him.
        #expect(engine.step(env(over: true, at: t0 + 601)).devCaption == "dev · wandering · full of energy")
        #expect(engine.step(env(at: t0 + 1200)).devCaption == "dev · wandering · full of energy")
        #expect(engine.step(env(at: t0 + 1201)).devCaption == "dev · dozing · full of energy")
        // So does a click, and so does a change of mood.
        engine.click(now: t0 + 1202)
        engine.run(30, env(at: t0 + 1203))
        #expect(engine.step(env(at: t0 + 1801)).devCaption == "dev · wandering · full of energy")
        engine.apply(input(busy: 1), now: t0 + 1900)
        // The reply finished: he jumps first.
        engine.apply(input(sessions: 1), now: t0 + 2000)
        engine.run(12, env(at: t0 + 2001))
        #expect(engine.step(env(at: t0 + 2599)).devCaption == "dev · wandering · full of energy")
        #expect(engine.step(env(at: t0 + 2600)).devCaption == "dev · dozing · full of energy")
    }

    @Test func aForcedIdleNeverDozes() {
        let engine = ClawdEngine.settled()
        engine.perform(.mood(.idle))
        #expect(engine.step(env(at: t0 + 3600)).devCaption == "dev · wandering")
    }

    @Test func aFinishedReplyJumps() {
        let engine = ClawdEngine.settled()
        engine.apply(input(busy: 2), now: t0)
        engine.step(env())
        #expect(engine.tickMilliseconds == 90)
        engine.apply(input(busy: 1), now: t0)
        engine.step(env())
        #expect(engine.tickMilliseconds == 60)
        expectPose(engine.run(2).last!, ClawdPose(arms: .up))
    }

    @Test func noJumpWhenTheSessionStartsWaitingOrOnTheFirstData() {
        let waits = ClawdEngine.settled()
        waits.apply(input(busy: 1), now: t0)
        waits.apply(input(busy: 0, waiting: 1), now: t0)
        waits.step(env())
        #expect(waits.tickMilliseconds == 90)

        // busy starts at −1: the first refresh never counts.
        let first = ClawdEngine.settled()
        first.apply(input(busy: 0, sessions: 1), now: t0)
        first.step(env())
        #expect(first.tickMilliseconds == 90)

        // A running act is not interrupted.
        let busyAct = Self.observed()
        busyAct.perform(.act(.wave))
        busyAct.apply(input(busy: 2), now: t0)
        busyAct.apply(input(busy: 1), now: t0)
        #expect(busyAct.step(env()).devCaption == "dev · wave · full of energy")
    }

    @Test func theSessionResetCelebrates() {
        let engine = ClawdEngine.settled()
        engine.apply(input(busy: 1, pct: 96, reset: t0 + 180), now: t0)
        let before = FrameView(engine.step(env()))
        #expect(before.bubble == nil && before.confetti.isEmpty)
        engine.apply(input(busy: 1, pct: 0, reset: t0 + 18_000), now: t0)
        let frames = engine.run(15).map(FrameView.init)
        #expect(engine.tickMilliseconds == 90)
        #expect(frames.allSatisfy { $0.bubble == "!" })
        #expect(frames[0].confetti.count == 12)
    }

    @Test func noCelebrationWithoutBothALaterResetAndALowerPercentage() {
        func celebrates(_ inputs: [ClawdDataInput]) -> Bool {
            let engine = ClawdEngine.settled()
            for i in inputs { engine.apply(i, now: t0) }
            return FrameView(engine.step(env())).bubble == "!"
        }
        #expect(!celebrates([input(sessions: 1, pct: 50, reset: t0 + 60)]))
        #expect(!celebrates([input(sessions: 1, pct: 50, reset: t0 + 60), input(sessions: 1, pct: 50, reset: t0 + 999)]))
        #expect(!celebrates([input(sessions: 1, pct: 50, reset: t0 + 60), input(sessions: 1, pct: 10, reset: t0 + 60)]))
        #expect(!celebrates([input(sessions: 1, pct: 50, reset: t0 + 60), input(sessions: 1, pct: 10, reset: t0 + 30)]))
        #expect(!celebrates([input(sessions: 1, reset: t0 + 60), input(sessions: 1, pct: 10, reset: t0 + 999)]))
        // A reset-less refresh in between keeps the remembered window.
        #expect(celebrates([input(sessions: 1, pct: 50, reset: t0 + 60), input(sessions: 1), input(sessions: 1, pct: 10, reset: t0 + 999)]))
    }

    @Test func switchingTheMainLimitIsNoReset() {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1, pct: 96, reset: t0 + 180), now: t0)
        engine.apply(input(sessions: 1, limit: .week, pct: 40, reset: t0 + 86_400), now: t0)
        #expect(FrameView(engine.step(env())).bubble == nil)
        // The week's own reset still celebrates.
        engine.apply(input(sessions: 1, limit: .week, pct: 0, reset: t0 + 7 * 86_400), now: t0)
        #expect(FrameView(engine.step(env())).bubble == "!")
    }

    @Test func celebrateReplacesARunningAct() {
        let engine = Self.observed()
        engine.apply(input(sessions: 1, pct: 50, reset: t0 + 60), now: t0)
        engine.perform(.act(.soul))
        engine.apply(input(sessions: 1, pct: 10, reset: t0 + 999), now: t0)
        #expect(engine.step(env()).devCaption == "dev · celebrate · full of energy")
    }

    @Test func critSweatsAndDartsTheEyes() {
        // 40% leaves 4 halves: a tier without tired eyes or sweat of its own.
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1, pct: 40, crit: 40), now: t0)
        let frames = engine.run(10).map(FrameView.init)
        #expect(frames.allSatisfy { $0.sweat.count == 1 })
        // Standing: the gaze flips every 5 ticks, right for ⌊tick / 5⌋ even.
        expectPose(frames[0].frame, ClawdPose(look: 1))
        expectPose(frames[4].frame, ClawdPose(look: -1))
        expectPose(frames[9].frame, ClawdPose(look: 1))

        let calm = ClawdEngine.settled()
        calm.apply(input(sessions: 1, pct: 39, crit: 40), now: t0)
        #expect(FrameView(calm.step(env())).sweat.isEmpty)
    }

    @Test func applyingTheSameInputTwiceChangesNothing() {
        let a = ClawdEngine(random: SeededRandomSource(seed: 7), now: t0)
        let b = ClawdEngine(random: SeededRandomSource(seed: 7), now: t0)
        let inputs = [
            input(busy: 2, pct: 40, reset: t0 + 600),
            input(busy: 1, pct: 41, reset: t0 + 600),
            input(busy: 1, pct: 10, reset: t0 + 18_600),
            input(busy: 0, sessions: 1, pct: 12, reset: t0 + 18_600),
        ]
        var now = t0
        for (n, i) in inputs.enumerated() {
            a.apply(i, now: now)
            b.apply(i, now: now)
            b.apply(i, now: now + 30)
            for _ in 0 ..< 60 {
                now += 0.09
                let e = env(over: n == 2, mouseX: 20, at: now)
                #expect(a.step(e) == b.step(e))
            }
        }
        // idleSince did not move on the repeats: both doze ten minutes after the last change of mood.
        let later = env(at: t0 + 3 * 5.4 + 615)
        #expect(a.step(later) == b.step(later))
    }
}
