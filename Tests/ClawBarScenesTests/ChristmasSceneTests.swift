import CoreGraphics
import Foundation
import Testing
import ClawBarScenes
import ClawBarShared

/// christmas.ps1's scene, as tools/christmas-test.ps1 checks it: snow, the garland, Santa's cycle and bounded output.
@Suite struct ChristmasSceneTests {
    static let card = CGSize(width: 260, height: 220)
    static let sleighRed = RGBA("#FFEF4444")

    private func run(_ steps: Int, size: CGSize = card, sky: Bool = true, seed: UInt64 = 3) -> [SceneFrame] {
        var clock = SceneClock(seed: seed)
        return (0 ..< steps).map { _ in clock.step(size: size, sky: sky) }
    }

    /// The layers drawn in `color`, with their opacity.
    private func layers(_ ops: [DrawOp], _ color: RGBA) -> [(rects: [CGRect], opacity: Double)] {
        ops.compactMap { op in
            guard case let .rects(r, c, o) = op, c == color else { return nil }
            return (r, o)
        }
    }

    private func rects(_ ops: [DrawOp], _ color: RGBA) -> [CGRect] {
        layers(ops, color).flatMap(\.rects)
    }

    /// The sleigh's left edge, while it shows.
    private func sleighX(_ f: SceneFrame) -> Double? {
        rects(f.sky, Self.sleighRed).map { Double($0.minX) }.min()
    }

    @Test func snowFallsAFractionOfAUnitEachStep() {
        let frames = run(3)
        let speck = RGBA("#B3F8FAFC")
        let (a, b) = (rects(frames[1].backdrop, speck), rects(frames[2].backdrop, speck))
        #expect(a.count == 38 && b.count == 38)
        // 0.25 to 0.75 down a step; a respawned flake jumps, so most is enough.
        let falling = zip(a, b).filter { (0.25 ... 0.75).contains($1.minY - $0.minY) }
        #expect(falling.count >= 34)
    }

    @Test func theGarlandLightsOneColourAfterAnotherEveryEightSteps() {
        let frames = run(16)
        func dotOpacities(_ f: SceneFrame) -> [Double] {
            ["#F87171", "#FCD34D", "#4ADE80", "#60A5FA"].compactMap { layers(f.backdrop, RGBA($0)).first?.opacity }
        }
        // Step 7 is still the red bulbs' turn; step 8 lights the yellow ones, as upstream's test checks.
        #expect(dotOpacities(frames[6]) == [1, 0.55, 0.55, 0.55])
        #expect(dotOpacities(frames[7]) == [0.55, 1, 0.55, 0.55])
    }

    @Test func bulbsStopWhereTheCardDoes() {
        let narrow = run(1, size: CGSize(width: 100, height: 200))[0]
        let glows = narrow.backdrop.filter { if case .radialGlow = $0 { true } else { false } }
        // Bulbs at 7, 21, … 91; the next at 105 is past 100 − 4.
        #expect(glows.count == 7)
    }

    @Test func santaCrossesAfterAWhileAndComesBackLater() {
        let frames = run(1_100)
        let shown = frames.indices.filter { sleighX(frames[$0]) != nil }
        // Launched on step 120 off the left edge, drawn from the next; 0.7 a step across 236 + 52.8.
        #expect(shown.first == 120)
        let firstCrossing = shown.prefix { $0 < 120 + 413 }
        #expect(firstCrossing.count == 412)
        #expect(sleighX(frames[121])! < sleighX(frames[200])!)
        // Away 400–999 steps, so not back yet at 1,100 at the earliest return.
        #expect(shown.allSatisfy { $0 < 120 + 413 } || shown.last! >= 120 + 413 + 400)
    }

    @Test func theSkyLayerWaitsWhileTheSkyRowIsHidden() {
        var clock = SceneClock(seed: 3)
        for _ in 0 ..< 200 {
            #expect(clock.step(size: Self.card, sky: false).sky.isEmpty)
        }
        // The sleigh's wait only counts down while the row shows.
        let visible = (0 ..< 121).map { _ in clock.step(size: Self.card, sky: true) }
        #expect(visible.prefix(120).allSatisfy { sleighX($0) == nil })
        #expect(sleighX(visible[120]) != nil)
    }

    @Test func theOutputStaysBoundedAtEverySize() {
        for size in [CGSize(width: 260, height: 140), Self.card, CGSize(width: 260, height: 520)] {
            let frames = run(1_000, size: size)
            let counts = Set(frames.dropFirst().map { $0.backdrop.count })
            // Two snow layers, the wire, a glow per bulb and a dot layer per colour: nothing piles up.
            #expect(counts == [2 + 1 + 18 + 4])
            #expect(frames.allSatisfy { $0.sky.count <= 60 })
        }
    }

    @Test func nothingDrawsBeforeTheCardHasASize() {
        #expect(run(3, size: .zero).allSatisfy { $0 == .empty })
    }
}

/// A scene engine stepped every 90 ms, so every step is due.
struct SceneClock {
    let engine: SceneEngine
    var now = Samples.now

    init(seed: UInt64) {
        engine = SceneEngine(random: SeededRandomSource(seed: seed))
    }

    mutating func step(size: CGSize, sky: Bool = true) -> SceneFrame {
        defer { now = now.addingTimeInterval(0.09) }
        return engine.step(.christmas, inputs: SceneInputs(now: now, size: size, skyVisible: sky)) ?? .empty
    }
}
