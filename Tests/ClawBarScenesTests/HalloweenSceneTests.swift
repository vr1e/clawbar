import CoreGraphics
import Foundation
import Testing
import ClawBarScenes
import ClawBarShared

/// halloween.ps1's scene: fog, wisps, the spider's cycle, the bats, the ghost's crossings, the graveyard row, and the
/// midnight scare's trigger and sequence.
@Suite struct HalloweenSceneTests {
    static let web = RGBA("#59E9D5FF"), bat = RGBA("#FF7353A0"), ghost = RGBA("#FFF5F3FF"), moon = RGBA("#FFFDE68A")
    static let pumpkinFace = RGBA("#FFFDE047"), ground = RGBA("#FF2E1F3D")

    private func run(_ steps: Int) -> [SceneFrame] {
        runScene(.halloween, steps)
    }

    private func thread(_ f: SceneFrame) -> CGRect? {
        rects(f.backdrop, Self.web).first { $0.width == 1 }
    }

    private func ghostAt(_ f: SceneFrame) -> CGPoint? {
        let r = rects(f.backdrop, Self.ghost)
        guard let x = r.map(\.minX).min(), let y = r.map(\.minY).min() else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func layerOpacity(_ ops: [DrawOp], _ color: RGBA) -> Double? {
        ops.lazy.compactMap { if case let .rects(_, c, o) = $0, c == color { o } else { nil } }.first
    }

    @Test func fogCreepsAlongTheBottomAndWispsWander() {
        let f = run(1)[0]
        let fog = f.backdrop.prefix(4).compactMap { if case let .radialGlow(r, _, _, _) = $0 { r } else { nil } }
        #expect(fog.map(\.width) == [0.7, 0.85, 1, 1.15].map { 260 * $0 })
        #expect(fog.map(\.height) == [70, 85, 100, 115])
        // Each reaches 45% of its height below the card's bottom.
        #expect(fog.allSatisfy { abs($0.maxY - (220 + $0.height * 0.45)) < 1e-9 })
        let wisps = f.backdrop.filter { if case .group = $0 { true } else { false } }
        #expect(wisps.count == 6)
    }

    @Test func theSpiderLetsItselfDownFromTheWebAndClimbsBack() {
        let frames = run(400)
        let heights = frames.map { thread($0)?.height ?? -1 }
        #expect(heights[0 ..< 149].allSatisfy { $0 == 10 })
        #expect(abs(heights[189] - 35) < 1e-9)
        #expect(heights[229 ..< 299].allSatisfy { (58 ... 62).contains($0) })
        #expect(heights[399] == 10)
        // Hanging from the web in the top-right corner, clear of the card's edge.
        #expect(thread(frames[0])?.minX == 252)
        #expect(rects(frames[0].backdrop, Self.web).map(\.maxX).max() == 260)
    }

    @Test func batsFlapAcrossAndComeBackFromTheLeft() {
        let frames = run(1_000)
        let lefts = frames.map { rects($0.backdrop, Self.bat).map(\.minX) }
        // The first three set off anywhere in the card, later ones out of sight on the left.
        #expect(lefts[0].allSatisfy { (-20 ... 280).contains($0) })
        let returned = zip(lefts, lefts.dropFirst()).contains { before, after in
            (after.min() ?? 0) < -20 && (before.min() ?? 0) >= -20
        }
        #expect(returned)
    }

    @Test func theGhostFloatsAcrossNowAndThen() {
        let frames = run(1_200)
        let shown = frames.indices.filter { ghostAt(frames[$0]) != nil }
        // Launched on step 80, drawn from the next, 0.004 of the way a step from the right edge.
        #expect(shown.first == 80)
        let first = shown.prefix { $0 < 80 + 260 }
        #expect((249 ... 250).contains(first.count))
        #expect(ghostAt(frames[81])!.x > ghostAt(frames[200])!.x)
        #expect(layerOpacity(frames[205].backdrop, Self.ghost).map { $0 > 0.44 } == true)
        // Away 300–799 steps before it comes back.
        let again = shown.drop { $0 < 80 + 260 }.first
        #expect(again.map { $0 >= first.last! + 300 } ?? true)
    }

    @Test func theSkyRowIsAGraveyardUnderTheMoon() {
        let f = run(1)[0]
        #expect(rects(f.sky, Self.moon).map(\.minX).min() == 109)
        // The ground's bottom row sits on the row's floor line, 3 pixels high.
        #expect(rects(f.sky, Self.ground).map(\.maxY).max().map { abs($0 - 43) < 1e-9 } == true)
        // The pumpkins' faces flicker like candles.
        let flicker = run(40).compactMap { layerOpacity($0.sky, Self.pumpkinFace) }
        #expect(flicker.allSatisfy { (0.3 ... 1).contains($0) } && Set(flicker).count > 20)
    }

    // MARK: The midnight scare

    private func midnight() throws -> Date {
        try #require(Calendar.gregorian(in: Samples.timeZone).date(from: DateComponents(year: 2026, month: 11, day: 2)))
    }

    @Test func midnightStrikesOneNightInThreeAndOnlyOnce() throws {
        let midnight = try midnight()
        let calendar = Calendar.gregorian(in: Samples.timeZone)
        var scared = 0
        for seed in UInt64(0) ..< 30 {
            let starts = secretStarts(.halloween, around: midnight, seed: seed)
            #expect(starts.count <= 1, "seed \(seed)")
            #expect(starts.allSatisfy { calendar.dateComponents([.hour, .minute], from: $0) == DateComponents(hour: 0, minute: 0) })
            scared += starts.count
        }
        #expect((4 ... 18).contains(scared))
    }

    @Test func theNextNightGetsAFreshChance() throws {
        // Many nights on one scene: about one in three is scary, never more than one scare a night.
        let starts = secretStarts(.halloween, around: try midnight(), seed: 0, nights: 30)
        let calendar = Calendar.gregorian(in: Samples.timeZone)
        #expect(Set(starts.map { calendar.startOfDay(for: $0) }).count == starts.count)
        #expect((4 ... 18).contains(starts.count))
    }

    @Test func theScareFlashesDarkensLoomsAndClawdJumpsAsTheLightsReturn() {
        var clock = SceneClock(.halloween, seed: 3)
        _ = clock.step()
        clock.engine.play(.scare)
        let frames = (0 ..< 75).map { _ in clock.step().secret }
        func opacities(_ s: SceneSecretFrame?) -> [Double] {
            (s?.overlay ?? []).map { op -> Double in
                switch op {
                case let .rects(_, _, o), let .group(_, _, o, _): o
                default: -1
                }
            }
        }
        // Dark, flash, face.
        #expect(opacities(frames[0]) == [0, 0.5, 0])
        #expect(opacities(frames[3]) == [0, 0.4, 0])
        #expect(zip(opacities(frames[8]), [0.4, 0, 0]).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(opacities(frames[35]) == [0.8, 0, 1])
        #expect(abs((frames[8]?.skyOpacity ?? 1) - 0.7) < 1e-9)
        #expect(frames[12 ..< 58].allSatisfy { abs(($0?.skyOpacity ?? 1) - 0.4) < 1e-9 })
        // The eyes shut for three steps.
        func layers(_ s: SceneSecretFrame?) -> Int {
            s?.overlay.last.map { if case let .group(c, _, _, _) = $0 { c.count } else { 0 } } ?? 0
        }
        #expect(frames[39 ..< 44].map(layers) == [6, 4, 4, 4, 6])
        // Creeping closer, about its middle.
        guard case let .group(_, near, _, _)? = frames[50]?.overlay.last, case let .group(_, far, _, _)? = frames[13]?.overlay.last else {
            Issue.record("face")
            return
        }
        #expect(near.a > far.a)
        #expect(frames.indices.filter { frames[$0]?.cues.isEmpty == false } == [60])
        #expect(frames[60]?.cues == [.act(.jump)])
        // The lights are back before the last step draws.
        #expect(frames[68] != nil)
        #expect(frames[69 ..< 75].allSatisfy { $0 == nil })
    }

    @Test func aScareCanStartPartWayThrough() {
        var clock = SceneClock(.halloween, seed: 3)
        clock.engine.play(.scare, at: 60)
        #expect(clock.step().secret?.cues == [.act(.jump)])
    }
}
