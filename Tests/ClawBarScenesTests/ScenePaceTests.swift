import CoreGraphics
import Foundation
import Testing
import ClawBarScenes
import ClawBarShared

/// A scene's own 90 ms pace, whatever the animation tick's: upstream's plays 1.5× fast during a Claude Code sequence.
@Suite struct ScenePaceTests {
    /// Whether the scene stepped on each tick, `ms` apart.
    private func steps(_ ms: [Double]) -> [Bool] {
        let engine = SceneEngine(random: SeededRandomSource(seed: 1))
        var now = Samples.now
        return ms.map { gap in
            now = now.addingTimeInterval(gap / 1000)
            return engine.step(.christmas, inputs: SceneInputs(now: now, timeZone: Samples.timeZone, size: CGSize(width: 260, height: 220), skyVisible: true)) != nil
        }
    }

    @Test func atNinetyMillisecondsEveryTickSteps() {
        #expect(steps(Array(repeating: 90, count: 20)).allSatisfy { $0 })
    }

    @Test func atSixtyMillisecondsTwoTicksInThreeStep() {
        let stepped = steps([0] + Array(repeating: 60, count: 30))
        #expect(stepped.dropFirst().filter { $0 }.count == 20)
    }

    @Test func lateTicksAreNotMadeUpLater() {
        // Ten ticks 80 ms late, then a Claude Code sequence: the scene keeps to two steps in three rather than catching up.
        let stepped = steps([0] + Array(repeating: 170, count: 10) + Array(repeating: 60, count: 30))
        #expect(stepped.suffix(30).filter { $0 }.count <= 21)
    }

    @Test func afterAGapTheSceneGoesOnWithoutCatchingUp() {
        // Two and a half seconds away: one step, not twenty-seven.
        #expect(steps([0, 90, 2_500, 30]) == [true, true, true, false])
    }
}
