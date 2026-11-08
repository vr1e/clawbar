import CoreGraphics
import Foundation
import Testing
import ClawBarScenes
import ClawBarShared

/// ocean.ps1's scene: beams, bubbles, kelp swaying about its foot, the jellyfish's pulse, the fish's cycle and
/// bounded output.
@Suite struct OceanSceneTests {
    static let yellowFish = RGBA("#FFFACC15"), pinkFish = RGBA("#FFFB7185")
    static let kelp = RGBA("#FF15803D"), bell = RGBA("#D9F0ABFC"), tentacle = RGBA("#B3F0ABFC")
    static let flowerCentre = RGBA("#FFFEF9C3")

    private func run(_ steps: Int, size: CGSize = sceneCard, sky: Bool = true) -> [SceneFrame] {
        runScene(.ocean, steps, size: size, sky: sky)
    }

    private func bubbles(_ f: SceneFrame) -> [CGRect] {
        f.backdrop.compactMap { if case let .strokedEllipse(r, _, _, _) = $0 { r } else { nil } }
    }

    /// The fish's top-left while it shows.
    private func fish(_ f: SceneFrame, _ color: RGBA) -> CGPoint? {
        let r = rects(f.sky, color)
        guard let x = r.map(\.minX).min(), let y = r.map(\.minY).min() else { return nil }
        return CGPoint(x: x, y: y)
    }

    @Test func lightFallsFromTheSurfaceInFourSwayingBeams() {
        let f = run(1)[0]
        guard case let .vGradient(surface, stops, _) = f.backdrop[0] else { Issue.record("surface"); return }
        #expect(surface == CGRect(x: 0, y: 0, width: 260, height: 70))
        #expect(stops.map(\.color.a) == [41, 0])
        let beams = f.backdrop.compactMap { op -> Transform2D? in
            guard case let .group(children, t, _, _) = op, case .vGradient? = children.first else { return nil }
            return t
        }
        #expect(beams.map(\.tx) == [0.12, 0.38, 0.6, 0.84].map { $0 * 260 })
        // Leaning −20° ± 4°: each row slides left by its depth.
        #expect(beams.allSatisfy { (tan(-24 * .pi / 180) ... tan(-16 * .pi / 180)).contains($0.c) })
    }

    @Test func bubblesRiseAndComeBackFromBelowTheCard() {
        let frames = run(600)
        #expect(frames.allSatisfy { bubbles($0).count == 14 })
        // All start somewhere in the card, then rise 0.35 to 0.95 a step.
        #expect(bubbles(frames[0]).allSatisfy { (-1 ... 220).contains($0.minY) && (3 ... 7).contains($0.width) })
        let (a, b) = (bubbles(frames[10]), bubbles(frames[11]))
        #expect(zip(a, b).filter { (0.35 ... 0.95).contains($0.minY - $1.minY) }.count >= 12)
        // One that left over the top is back just below the bottom.
        let respawned = zip(frames, frames.dropFirst()).flatMap { before, after in
            zip(bubbles(before), bubbles(after)).filter { $1.minY > $0.minY }.map(\.1)
        }
        #expect(!respawned.isEmpty && respawned.allSatisfy { (224 ... 225).contains($0.minY) })
    }

    @Test func kelpSwaysAboutItsFootInTheSand() {
        let kelp = run(40).map { groups($0.sky, Self.kelp).map(\.transform) }
        let floor = PlayArea.skySize.height - 3 * 1.6
        for strands in kelp {
            #expect(strands.count == 4)
            for (t, (fx, rows)) in zip(strands, [(0.31, 14.0), (0.36, 10), (0.62, 12), (0.74, 16)]) {
                let height = rows * 1.6
                // ±9°, and the bottom row stays where it was planted.
                #expect(abs(t.c) <= tan(9 * .pi / 180) + 1e-9)
                #expect(abs(t.ty + height - (floor + 1.6)) < 1e-9)
                #expect(abs(t.tx + t.c * height - (PlayArea.skySize.width * fx).rounded()) < 1e-9)
            }
        }
        #expect(Set(kelp.map { $0[0].c }).count > 20)
    }

    @Test func theJellyfishPulsesAndWavesItsTentacles() {
        let frames = run(16)
        let bells = frames.map { groups($0.sky, Self.bell)[0].transform }
        #expect(bells.allSatisfy { (1 ... 1.08 + 1e-9).contains($0.a) && (0.85 - 1e-9 ... 1).contains($0.d) })
        #expect(bells.contains { $0.a > 1.05 } && bells.contains { $0.a == 1 })
        // Two poses of tentacles, four steps each: in the second the tips start a pixel right of the row above them.
        let pose = frames.map { f -> Int in
            let t = rects(f.sky, Self.tentacle)
            let bottom = t.map(\.minY).max()!
            return t.filter { $0.minY == bottom }.map(\.minX).min()! > t.map(\.minX).min()! ? 1 : 0
        }
        #expect(pose == frames.indices.map { (($0 + 1) / 4) % 2 })
    }

    @Test func eachFishCrossesThenComesBackAtAnotherDepth() {
        let frames = run(4_000)
        for (color, leftward) in [(Self.yellowFish, true), (Self.pinkFish, false)] {
            // Crossings: runs of steps in which it shows, between the steps on which it leaves.
            let crossings = frames.map { fish($0, color) }.split { $0 == nil }.map { $0.compactMap { $0 } }
            #expect(crossings.count >= 3, "\(color)")
            for c in crossings.dropLast() {
                let xs = c.map(\.x)
                #expect(leftward ? xs.first! > xs.last! : xs.first! < xs.last!)
            }
            #expect(Set(crossings.map { $0[0].y }).count > 1)
        }
    }

    @Test func flowersDriftRightAndWrapToJustOffTheLeftEdge() {
        let frames = run(3_000)
        let wrapped = zip(frames, frames.dropFirst()).flatMap { before, after in
            zip(rects(before.sky, Self.flowerCentre), rects(after.sky, Self.flowerCentre)).filter { $1.minX < $0.minX - 100 }.map(\.1)
        }
        // At −its width, so its centre is left of the edge and no flower is wider than 21.
        #expect(!wrapped.isEmpty && wrapped.allSatisfy { $0.maxX < 0 && $0.minX > -21 })
    }

    @Test func theSkyLayerWaitsWhileTheSkyRowIsHidden() {
        var clock = SceneClock(.ocean, seed: 3)
        for _ in 0 ..< 200 {
            let f = clock.step(size: sceneCard, sky: false)
            #expect(f.sky.isEmpty && !f.backdrop.isEmpty)
        }
        // Fish are placed on the row's first step, off its edges, and have moved one step since.
        let first = clock.step(size: sceneCard)
        #expect(fish(first, Self.yellowFish)!.x >= PlayArea.skySize.width - 1)
        #expect(fish(first, Self.pinkFish)!.x < 0)
    }

    @Test func theOutputStaysBoundedAtEverySize() {
        for size in [CGSize(width: 260, height: 140), sceneCard, CGSize(width: 260, height: 520)] {
            let frames = run(1_000, size: size)
            // The surface, four beams and fourteen bubbles.
            #expect(frames.allSatisfy { $0.backdrop.count == 1 + 4 + 14 })
            // Four flowers of two colours, sand, starfish, four kelp, two fish, the bell and its tentacles.
            #expect(frames.allSatisfy { $0.sky.count <= 8 + 2 + 1 + 4 + 5 + 1 + 1 })
        }
    }

    @Test func nothingDrawsBeforeTheCardHasASize() {
        #expect(run(3, size: .zero).allSatisfy { $0 == .empty })
    }
}
