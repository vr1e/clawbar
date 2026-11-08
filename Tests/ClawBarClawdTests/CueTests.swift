import Foundation
import Testing
@testable import ClawBarClawd
import ClawBarShared

/// A scene's cue, such as Halloween's scare: an act behind upstream's guards.
@Suite struct CueTests {
    /// The act shown on the next tick; the developer caption names it, so sweat is forced on to show the caption.
    private func caption(_ engine: ClawdEngine) -> String {
        engine.step(env()).devCaption
    }

    private func cued(_ engine: ClawdEngine) -> String {
        engine.perform(.sweat(true))
        _ = engine.step(env())
        engine.cue(.jump)
        return caption(engine)
    }

    @Test func aCueStartsTheAct() {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1), now: t0)
        #expect(cued(engine) == "dev · jump")
    }

    @Test func aRunningActKeepsGoing() {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1), now: t0)
        engine.perform(.act(.wave))
        #expect(cued(engine) == "dev · wave")
    }

    @Test func notWhileLyingWithTheLimitUsedUp() {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1, pct: 100), now: t0)
        engine.run(5)
        #expect(cued(engine) != "dev · jump")
    }

    @Test func notWhileShownLyingDeadEvenWithLimitLeft() {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 1), now: t0)
        engine.perform(.mood(.dead))
        engine.run(5)
        #expect(caption(engine) == "dev · " + L10n.mood(.dead, .en))
        engine.cue(.jump)
        #expect(caption(engine) == "dev · " + L10n.mood(.dead, .en))
    }

    @Test func notWhileAsleepInTheBurrow() {
        let engine = ClawdEngine.settled()
        engine.apply(input(sessions: 0), now: t0)
        engine.run(31)
        #expect(cued(engine) != "dev · jump")
    }
}
