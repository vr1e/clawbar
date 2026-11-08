import CoreGraphics
import Foundation
import ClawBarScenes
import ClawBarShared

/// A widget card's inner size, the backdrop a scene covers.
let sceneCard = CGSize(width: 260, height: 220)
/// Where the card puts the sky row in that backdrop.
let sceneSkyRow = CGRect(origin: CGPoint(x: 12, y: 33.5), size: PlayArea.skySize)

/// `steps` scene steps, each due.
func runScene(_ scene: SceneID, _ steps: Int, size: CGSize = sceneCard, sky: Bool = true, seed: UInt64 = 3) -> [SceneFrame] {
    var clock = SceneClock(scene, seed: seed)
    return (0 ..< steps).map { _ in clock.step(size: size, sky: sky) }
}

/// Every rect drawn in `color` by the plain rect layers among `ops`.
func rects(_ ops: [DrawOp], _ color: RGBA) -> [CGRect] {
    ops.flatMap { op -> [CGRect] in
        guard case let .rects(r, c, _) = op, c == color else { return [] }
        return r
    }
}

/// The groups among `ops` with a layer drawn in `color`: how each is placed, and how faded.
func groups(_ ops: [DrawOp], _ color: RGBA) -> [(transform: Transform2D, opacity: Double)] {
    ops.compactMap {
        guard case let .group(children, t, o, _) = $0, !rects(children, color).isEmpty else { return nil }
        return (t, o)
    }
}

/// A scene engine stepped every 90 ms, so every step is due.
struct SceneClock {
    let engine: SceneEngine
    let scene: SceneID
    let zone: TimeZone
    var now: Date

    init(_ scene: SceneID, seed: UInt64, from start: Date = Samples.now, zone: TimeZone = Samples.timeZone) {
        engine = SceneEngine(random: SeededRandomSource(seed: seed))
        self.scene = scene
        self.zone = zone
        now = start
    }

    mutating func step(size: CGSize = sceneCard, sky: Bool = true) -> SceneFrame {
        defer { now = now.addingTimeInterval(0.09) }
        return engine.step(scene, inputs: SceneInputs(now: now, timeZone: zone, size: size, skyRow: sky ? sceneSkyRow : nil)) ?? .empty
    }
}
