import CoreGraphics
import Foundation
import ClawBarScenes
import ClawBarShared

/// A widget card's inner size, the backdrop a scene covers.
let sceneCard = CGSize(width: 260, height: 220)

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
        return engine.step(scene, inputs: SceneInputs(now: now, timeZone: zone, size: size, skyVisible: sky)) ?? .empty
    }
}
