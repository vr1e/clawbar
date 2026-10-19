import CoreGraphics
import Testing
@testable import ClawBarGame
import ClawBarShared

/// A round already running with Clawd back on the ground after the starting jump.
private func running(seed: UInt64 = 1) -> RunnerEngine {
    let e = RunnerEngine(random: SeededRandomSource(seed: seed))
    e.step(RunnerInput(jump: true))
    while e.airborne { e.step(RunnerInput(jump: true)) }
    e.step(RunnerInput())
    return e
}

/// Places one obstacle 160 ahead and plays it with `policy` until it has passed Clawd or he hit it.
private func pass(
    _ kind: RunnerEngine.Kind, bottom: Double = RunnerTuning.groundY, policy: (RunnerEngine) -> RunnerInput
) -> RunnerPhase {
    let e = running()
    e.place(kind, x: RunnerTuning.clawdX + 160, bottom: bottom)
    var ticks = 0
    while e.phase == .running, ticks < 120 {
        e.step(policy(e))
        ticks += 1
        if let o = e.obstacles.first, o.x + o.width < RunnerTuning.clawdX { break }
    }
    return e.phase
}

private func stand(_ e: RunnerEngine) -> RunnerInput { RunnerInput() }
private func duck(_ e: RunnerEngine) -> RunnerInput { RunnerInput(duck: true) }

/// Jumps when the obstacle is close, holding the rise.
private func jump(_ e: RunnerEngine) -> RunnerInput {
    if e.airborne { return RunnerInput(jump: e.velocity < 0) }
    guard let o = e.obstacles.first else { return RunnerInput() }
    return RunnerInput(jump: o.x - (RunnerTuning.clawdX + 54) < e.speed * 6)
}

@Suite struct RunnerEngineTests {
    @Test func aRoundWaitsForTheFirstJump() {
        let e = RunnerEngine(random: SeededRandomSource(seed: 1))
        for _ in 0 ..< 100 { e.step(RunnerInput(duck: true)) }
        #expect(e.phase == .ready)
        #expect(e.score == 0)
        e.step(RunnerInput(jump: true))
        #expect(e.phase == .running)
        #expect(e.velocity == RunnerTuning.jumpVelocity)
    }

    @Test func aHeldJumpRisesHigherThanATapAndLands() {
        func peak(holding ticks: Int) -> Double {
            let e = running()
            var top = 0.0
            var t = 0
            e.step(RunnerInput(jump: true))
            repeat {
                t += 1
                e.step(RunnerInput(jump: t < ticks))
                top = max(top, e.lift)
            } while e.airborne && t < 200
            #expect(!e.airborne && e.lift == 0)
            return top
        }
        let held = peak(holding: 100), tapped = peak(holding: 1)
        #expect(held > 80 && held < 95)
        #expect(tapped < held - 25)
        // The tallest cactus is 45 high; a held jump clears it with room.
        #expect(held > Double(RunnerArt.usedHeight(RunnerArt.cactusLarge)) * RunnerTuning.px + 20)
    }

    @Test func aHeldKeyJumpsOnce() {
        let e = running()
        var jumps = 0
        var wasAirborne = false
        for _ in 0 ..< 200 {
            e.step(RunnerInput(jump: true))
            if e.airborne, !wasAirborne { jumps += 1 }
            wasAirborne = e.airborne
        }
        #expect(jumps == 1)
    }

    @Test func cactiAreJumpedNotDuckedOrWaitedOut() {
        #expect(pass(.cactusSmall, policy: stand) == .over)
        #expect(pass(.cactusLarge, policy: duck) == .over)
        #expect(pass(.cactusSmall, policy: jump) == .running)
        #expect(pass(.cactusLarge, policy: jump) == .running)
    }

    @Test func eachBugHeightHasItsAnswer() {
        let low = RunnerEngine.bugBottoms[0], middle = RunnerEngine.bugBottoms[1], high = RunnerEngine.bugBottoms[2]
        #expect(pass(.bug, bottom: low, policy: stand) == .over)
        #expect(pass(.bug, bottom: low, policy: duck) == .over)
        #expect(pass(.bug, bottom: low, policy: jump) == .running)
        #expect(pass(.bug, bottom: middle, policy: stand) == .over)
        #expect(pass(.bug, bottom: middle, policy: duck) == .running)
        #expect(pass(.bug, bottom: high, policy: stand) == .running)
    }

    @Test func runningAddsScoreAndSpeedUpToTheLimit() {
        let e = running()
        let before = e.score
        for _ in 0 ..< 60 { e.step(RunnerInput()) }
        #expect(e.score > before)
        #expect(e.speed > RunnerTuning.startSpeed && e.speed <= RunnerTuning.maxSpeed)
    }

    @Test(arguments: [1, 2, 3, 4, 5] as [UInt64])
    func everyCourseCanBeCleared(seed: UInt64) {
        let e = RunnerEngine(random: SeededRandomSource(seed: seed))
        e.step(RunnerInput(jump: true))
        var sawBug = false
        for _ in 0 ..< 7500 where e.phase == .running {
            e.step(e.demoInput)
            sawBug = sawBug || e.obstacles.contains { $0.kind == .bug }
        }
        #expect(e.phase == .running, "seed \(seed) crashed at \(e.score)")
        #expect(e.speed == RunnerTuning.maxSpeed)
        #expect(sawBug)
    }

    @Test func aCrashKeepsTheHighScoreAndAJumpRestartsAfterTheDelay() {
        let e = running(seed: 3)
        while e.phase == .running { e.step(RunnerInput()) }
        let score = e.score
        #expect(score > 0)
        #expect(e.highScore == score)
        // Mashing jump right after the crash does nothing.
        for i in 0 ..< RunnerTuning.restartDelayTicks - 1 { e.step(RunnerInput(jump: i % 2 == 0)) }
        #expect(e.phase == .over)
        e.step(RunnerInput())
        e.step(RunnerInput(jump: true))
        #expect(e.phase == .running)
        #expect(e.score == 0)
        #expect(e.obstacles.isEmpty)
        #expect(e.highScore == score)
    }

    @Test func aSeedReplaysTheSameRound() {
        func play() -> [RunnerFrame] {
            let e = RunnerEngine(random: SeededRandomSource(seed: 9))
            e.step(RunnerInput(jump: true))
            return (0 ..< 900).map { _ in
                e.step(e.demoInput)
                return e.frame(lang: .en, caption: "")
            }
        }
        #expect(play() == play())
    }

    @Test func theFrameShowsWhatThePhaseAsksFor() {
        func texts(_ f: RunnerFrame) -> [String] {
            f.ops.compactMap { op -> String? in
                if case let .text(s, _, _, _, _, _, _) = op { return s }
                return nil
            }
        }
        let e = RunnerEngine(random: SeededRandomSource(seed: 3), highScore: 42)
        #expect(texts(e.frame(lang: .en, caption: "resets in 1h 05m")).contains("Press Space or click to jump"))
        #expect(texts(e.frame(lang: .en, caption: "resets in 1h 05m")).contains("resets in 1h 05m"))
        #expect(texts(e.frame(lang: .en, caption: "")).contains("HI 00042  00000"))
        #expect(texts(e.frame(lang: .de, caption: "", paused: true)).contains(L10n.t(.gamePaused, .de)))
        e.step(RunnerInput(jump: true))
        while e.phase == .running { e.step(RunnerInput()) }
        #expect(texts(e.frame(lang: .de, caption: "")).contains("SPIEL VORBEI"))
        #expect(!texts(e.frame(lang: .en, caption: "")).contains("Space or click to run again"))
        for _ in 0 ..< RunnerTuning.restartDelayTicks { e.step(RunnerInput()) }
        #expect(texts(e.frame(lang: .en, caption: "")).contains("Space or click to run again"))
    }

    @Test func theScoreHasFiveDigits() {
        #expect(RunnerEngine.digits(0) == "00000")
        #expect(RunnerEngine.digits(1234) == "01234")
        #expect(RunnerEngine.digits(123_456) == "99999")
    }

    @Test func everySpriteStaysOnTheCanvas() {
        let e = running()
        for _ in 0 ..< 2000 where e.phase == .running {
            e.step(e.demoInput)
            let clawd = e.clawdRects("#")
            #expect(clawd.allSatisfy { $0.minY >= 0 && $0.maxY <= RunnerTuning.groundY + 0.001 })
        }
    }
}
