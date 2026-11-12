import CoreGraphics
import Foundation
import Testing
import ClawBarScenes
import ClawBarShared

/// space.ps1's scene: the starfield, the shooting star, the planets and their ring, the ship's cycle and bounded output.
@Suite struct SpaceSceneTests {
    static let shipGrey = RGBA("#FF94A3B8")

    private func run(_ steps: Int, size: CGSize = sceneCard) -> [SceneFrame] {
        runScene(.space, steps, size: size)
    }

    /// The faint stars' layers: the backdrop's only plain rects.
    private func starLayers(_ f: SceneFrame) -> [(rects: [CGRect], opacity: Double)] {
        f.backdrop.compactMap { if case let .rects(r, _, o) = $0 { (r, o) } else { nil } }
    }

    /// The bright stars: groups of a glow, two rays and a core, where they sit and how bright.
    private func brightStars(_ f: SceneFrame) -> [(at: Transform2D, opacity: Double)] {
        f.backdrop.compactMap {
            guard case let .group(children, t, o, _) = $0, case .radialGlow = children.first else { return nil }
            return (t, o)
        }
    }

    /// The shooting star, a group led by its rotated tail, while it flies.
    private func shootingStar(_ f: SceneFrame) -> (at: Transform2D, opacity: Double)? {
        f.backdrop.lazy.compactMap {
            guard case let .group(children, t, o, _) = $0, case .group = children.first else { return nil }
            return (t, o)
        }.first
    }

    /// The ship's left edge.
    private func shipX(_ f: SceneFrame) -> Double? {
        rects(f.sky, Self.shipGrey).map { Double($0.minX) }.min()
    }

    /// A ring half: where it sits among the sky's ops, its clip and its opacity.
    private func ringHalves(_ sky: [DrawOp]) -> [(index: Int, clip: CGRect, opacity: Double)] {
        sky.indices.compactMap { i in
            guard case let .group(children, _, _, clip?) = sky[i], case let .strokedEllipse(_, _, _, o)? = children.first else { return nil }
            return (i, clip, o)
        }
    }

    @Test func faintStarsTwinkleInTenLayersOverAStripTallerThanTheCard() {
        let frames = run(2)
        let layers = starLayers(frames[0])
        #expect(layers.count == 10)
        // 262 × 900 / 1100 stars, each at whole units within the strip.
        let stars = layers.flatMap(\.rects)
        #expect(stars.count == 214)
        #expect(stars.allSatisfy { (0 ... 262).contains($0.minX) && (0 ... 900).contains($0.minY) && $0.minX == $0.minX.rounded() })
        #expect(layers.allSatisfy { (0.25 ... 0.85).contains($0.opacity) })
        #expect(zip(layers, starLayers(frames[1])).contains { $0.opacity != $1.opacity })
    }

    @Test func brightStarsBelowTheCardAreLeftOut() {
        let tall = brightStars(run(1, size: CGSize(width: 260, height: 900))[0])
        #expect(tall.count == 14)
        let short = brightStars(run(1, size: CGSize(width: 260, height: 140))[0])
        #expect(short.count < 14)
        #expect(short.allSatisfy { $0.at.ty <= 148 && (0.55 ... 1).contains($0.opacity) })
    }

    @Test func aShootingStarFliesDownAndLeftForFifteenStepsFadingOut() throws {
        let frames = run(3_000)
        let flying = frames.indices.filter { shootingStar(frames[$0]) != nil }
        let first = try #require(flying.first)
        let flight = Array(first ..< first + 15)
        #expect(Array(flying.prefix(15)) == flight)
        #expect(!flying.contains(first + 15))
        let start = try #require(shootingStar(frames[first])), end = try #require(shootingStar(frames[first + 14]))
        #expect(start.opacity == 1 && end.opacity == 0)
        #expect(abs(start.at.tx - end.at.tx - 120) < 1e-9 && abs(end.at.ty - start.at.ty - 45) < 1e-9)
        // About one in 220 steps, never two at once.
        #expect((5 ... 40).contains(flying.count / 15))
    }

    @Test func theShipComesBackFromJustOffTheLeftEdge() {
        let xs = run(1_400).map { shipX($0)! }
        // It starts a quarter of the way across, 0.002 of the row a step.
        #expect(xs[0] == 59)
        let wraps = xs.indices.dropFirst().filter { xs[$0] < xs[$0 - 1] }
        #expect(wraps.count == 2)
        for i in wraps {
            #expect(xs[i - 1] >= 330 && xs[i] == -16)
        }
        // From −16 to 1.4 of the row's 236.
        #expect((733 ... 735).contains(wraps[1] - wraps[0]))
    }

    @Test func theRingsFarHalfIsBehindThePlanetAndItsNearHalfInFront() throws {
        let sky = run(1)[0].sky
        let rings = ringHalves(sky)
        try #require(rings.count == 2)
        let (back, front) = (rings[0], rings[1])
        #expect(back.opacity == 0.45 && front.opacity == 0.85)
        // The small planet is 11 pixels of 1.6; each half is the ellipse's top or bottom 0.22 of that.
        #expect(back.clip.minY == 0 && abs(front.clip.minY - 17.6 * 0.22) < 1e-9)
        // The planet's pixels lie between the halves.
        #expect(front.index - back.index > 1)
        #expect(sky[back.index + 1 ..< front.index].allSatisfy { if case .rects = $0 { true } else { false } })
    }

    @Test func thePlanetsTurnWithoutLosingAPixel() throws {
        let frames = run(300)
        func discs(_ f: SceneFrame) throws -> (pixels: Int, colours: Set<RGBA>) {
            var n = 0, colours = Set<RGBA>()
            // Both planets come before the ring's near half and the ship after it, whose windows share a planet's cyan.
            let near = try #require(ringHalves(f.sky).last).index
            for case let .rects(r, c, _) in f.sky[..<near] {
                n += r.count
                colours.insert(c)
            }
            return (n, colours)
        }
        #expect(try Set(frames.map { try discs($0).pixels }).count == 1)
        #expect(try discs(frames[0]).colours != discs(frames[100]).colours)
    }

    @Test func theShipStandsStillWhileTheSkyRowIsHidden() {
        var clock = SceneClock(.space, seed: 3)
        for _ in 0 ..< 200 { _ = clock.step(size: sceneCard, sky: false) }
        // One step of the ship, not 201.
        #expect(shipX(clock.step(size: sceneCard)) == 59)
    }
}
