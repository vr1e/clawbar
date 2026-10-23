import CoreGraphics
import Foundation
import Testing
import ClawBarAnimation
@testable import ClawBarClawd
import ClawBarShared

let t0 = Samples.now

func engine(seed: UInt64 = 2026, config: Config = Config()) -> AnimationEngine {
    AnimationEngine(random: SeededRandomSource(seed: seed), config: config, now: t0)
}

/// A fresh engine with Clawd's entrance act cut short, so a test starts from a standing Clawd.
func settled(seed: UInt64 = 2026) -> AnimationEngine {
    let engine = engine(seed: seed)
    engine.perform(.auto)
    return engine
}

func inputs(now: Date = t0, over: Bool = false, mouseX: Double? = nil, zone: TimeZone = Samples.timeZone) -> AnimationInputs {
    AnimationInputs(now: now, timeZone: zone, numberWidth: 32, mouseOverWindow: over, mouseX: mouseX)
}

/// Fake data: `sessions` of them idle, plus the busy and waiting ones; `read` is the registry's first read.
func data(
    busy: Int = 0, waiting: Int = 0, sessions: Int = 0, pct: Int? = nil, read: Bool = true,
    weather: WeatherSnapshot? = nil, place: Place? = nil
) -> DataSnapshot {
    let states = Array(repeating: SessionState.busy, count: busy) + Array(repeating: .waiting, count: waiting)
        + Array(repeating: .idle, count: sessions)
    return DataSnapshot(
        usage: pct.map { UsageSnapshot(sessionPercent: $0, weekPercent: 41) }, usageAt: t0, usageProbeCompleted: true,
        sessions: states.enumerated().map { i, s in
            SessionInfo(pid: Int32(100 + i), name: "s\(i)", cwd: "\(Samples.home)/code/s\(i)", state: s, waitingFor: nil, kind: "interactive")
        },
        sessionsRead: read, weather: weather, place: place
    )
}

/// What one of Clawd's frames draws, sorted out by layer; the colours are the original's.
struct FrameView {
    let frame: ClawdFrame

    init(_ frame: ClawdFrame) { self.frame = frame }

    private func rectOps(_ color: RGBA) -> [(rects: [CGRect], opacity: Double)] {
        frame.ops.compactMap {
            if case .rects(let r, let c, let o) = $0, c == color { return (r, o) }
            return nil
        }
    }

    var body: [CGRect] { rectOps(Palette.clawdBody).first?.rects ?? [] }
    var eyes: [CGRect] { rectOps(Palette.clawdEyes).first?.rects ?? [] }
    var fx: [CGRect] { rectOps(Palette.clawdFx).first?.rects ?? [] }
    var sand: [CGRect] { rectOps(Palette.sand).first?.rects ?? [] }
    var sweat: [(rects: [CGRect], opacity: Double)] { rectOps(Palette.sweat) }
    var soul: [(rects: [CGRect], opacity: Double)] { rectOps(Palette.soul) }
    /// The floating heart: the love-coloured layer with the heart's 7 runs.
    var love: (rects: [CGRect], opacity: Double)? { rectOps(Palette.love).first { $0.rects.count == 7 } }
    /// Single 2.5-tall rects in a confetti colour.
    var confetti: [CGRect] {
        frame.ops.compactMap {
            if case .rects(let r, let c, _) = $0, r.count == 1, Palette.confetti.contains(c), abs(r[0].height - 2.5) < 1e-9 { return r[0] }
            return nil
        }
    }

    var texts: [String] {
        frame.ops.compactMap {
            if case .text(let s, _, _, _, _, _, _) = $0 { return s }
            return nil
        }
    }

    var bubble: String? { texts.first { $0 != "z" } }
    var z: Bool { texts.contains("z") }
}

func close(_ a: CGRect, _ b: CGRect, _ eps: Double = 1e-9) -> Bool {
    abs(a.minX - b.minX) < eps && abs(a.minY - b.minY) < eps && abs(a.width - b.width) < eps && abs(a.height - b.height) < eps
}
func close(_ a: [CGRect], _ b: [CGRect]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { close($0, $1) } }

/// The frame draws exactly `pose`: its four layers, in the sprite box's own coordinates.
func expectPose(_ frame: ClawdFrame, _ pose: ClawdPose, sourceLocation: SourceLocation = #_sourceLocation) {
    let view = FrameView(frame), want = ClawdSprite.render(pose), o = frame.spriteRect.origin
    func local(_ r: [CGRect]) -> [CGRect] { r.map { $0.offsetBy(dx: -o.x, dy: -o.y) } }
    #expect(close(local(view.body), want.body), "body of \(pose)", sourceLocation: sourceLocation)
    #expect(close(local(view.eyes), want.eyes), "eyes of \(pose)", sourceLocation: sourceLocation)
    #expect(close(local(view.fx), want.fx), "fx of \(pose)", sourceLocation: sourceLocation)
    #expect(close(local(view.sand), want.sand), "sand of \(pose)", sourceLocation: sourceLocation)
}

/// The sky's sprites the scripts reach, recognised by the original's colours and pixel sizes.
struct Sprites {
    var sun: [CGRect]?
    var drops: [CGRect]?
    var flakes: [CGRect]?
    var ground: RGBA?

    init(_ frame: SkyFrame) {
        for op in frame.ops {
            guard case .rects(let rects, let color, _) = op else { continue }
            let height = rects.first?.height ?? 0
            switch color {
            case RGBA("#8093C5FD"): drops = rects
            case RGBA("#C0E4E4E7"): flakes = rects
            case RGBA("#2EE5E7EB"), RGBA("#FFF1F5F9"), RGBA("#FFF8FAFC"): break
            default:
                if abs(height - 1.4) < 1e-9 {
                    sun = rects
                } else if abs(height - 2) < 1e-9 {
                    // A cloud.
                    continue
                } else {
                    ground = color
                }
            }
        }
    }
}

/// A scenario's frames, as the recorder sees them before it blanks the caption.
func replay(_ s: RecordScenario, seed: UInt64, numberWidth: Double = 32) -> [AnimationFrame] {
    let run = ScenarioRun(s, seed: seed)
    var frames: [AnimationFrame] = []
    while let f = run.next(numberWidth: numberWidth) { frames.append(f.animation) }
    return frames
}
