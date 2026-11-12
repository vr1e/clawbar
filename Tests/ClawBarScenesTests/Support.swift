import CoreGraphics
import Foundation
import ClawBarScenes
import ClawBarShared

/// A widget card's inner size, the backdrop a scene covers.
let sceneCard = CGSize(width: 260, height: 220)
/// Where the card puts the sky row in that backdrop.
let sceneSkyRow = CGRect(origin: CGPoint(x: 12, y: 33.5), size: PlayArea.skySize)

/// `steps` scene steps, each due.
func runScene(_ scene: SceneID, _ steps: Int, size: CGSize = sceneCard, sky: Bool = true) -> [SceneFrame] {
    var clock = SceneClock(scene, seed: 3)
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

/// When a scene's secret starts, stepping from ten seconds before `minute` to a minute and ten past it,
/// on that many nights in a row with one engine.
func secretStarts(_ scene: SceneID, around minute: Date, seed: UInt64, zone: TimeZone = Samples.timeZone, asleep: Bool = false, nights: Int = 1) -> [Date] {
    var clock = SceneClock(scene, seed: seed, zone: zone)
    var starts: [Date] = []
    for night in 0 ..< nights {
        clock.now = minute.addingTimeInterval(Double(night) * 86_400 - 10)
        var on = false
        for _ in 0 ..< 900 {
            let now = clock.now
            let playing = clock.step(asleep: asleep).secret != nil
            if playing, !on { starts.append(now) }
            on = playing
        }
    }
    return starts
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

    mutating func step(size: CGSize = sceneCard, sky: Bool = true, asleep: Bool = false, lang: Lang = .en) -> SceneFrame {
        defer { now = now.addingTimeInterval(0.09) }
        let inputs = SceneInputs(now: now, timeZone: zone, size: size, skyRow: sky ? sceneSkyRow : nil, lang: lang, clawdAsleep: asleep)
        return engine.step(scene, inputs: inputs) ?? .empty
    }
}
