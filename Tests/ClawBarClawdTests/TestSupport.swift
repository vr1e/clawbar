import CoreGraphics
import Foundation
import Testing
@testable import ClawBarClawd
import ClawBarShared

/// A random source that never fires a random event: every `nextInt(n)` answers n − 1 and every
/// `nextDouble()` 0.5, unless an answer for that upper bound is queued.
final class ScriptedRandom: RandomSource {
    private var answers: [Int: [Int]]
    private(set) var asked: [Int] = []

    init(_ answers: [Int: [Int]] = [:]) { self.answers = answers }

    func nextDouble() -> Double { 0.5 }

    func nextInt(_ upperBound: Int) -> Int {
        asked.append(upperBound)
        if var queue = answers[upperBound], !queue.isEmpty {
            let v = queue.removeFirst()
            answers[upperBound] = queue
            return v
        }
        return max(0, upperBound - 1)
    }

    func queue(_ upperBound: Int, _ values: Int...) { answers[upperBound, default: []] += values }
}

let t0 = Samples.now

func env(width: Double = 180, over: Bool = false, mouseX: Double? = nil, at now: Date = t0, lang: Lang = .en) -> ClawdStepEnv {
    ClawdStepEnv(areaWidth: width, mouseOverWindow: over, mouseX: mouseX, now: now, lang: lang)
}

func input(busy: Int = 0, waiting: Int = 0, sessions: Int? = nil, pct: Int? = nil, reset: Date? = nil, crit: Int = 85) -> ClawdDataInput {
    ClawdDataInput(busy: busy, waiting: waiting, sessionCount: sessions ?? (busy + waiting), pct: pct, sessionReset: reset, critPercent: crit)
}

extension ClawdEngine {
    /// `n` ticks with the same environment; the frames in order.
    @discardableResult
    func run(_ n: Int, _ e: ClawdStepEnv = env()) -> [ClawdFrame] {
        (0 ..< n).map { _ in step(e) }
    }

    /// A fresh engine with its entrance act cut short, so a test starts from a standing Clawd.
    static func settled(_ random: ScriptedRandom = ScriptedRandom()) -> ClawdEngine {
        let engine = ClawdEngine(random: random, now: t0)
        engine.perform(.auto)
        return engine
    }
}

/// A rect list rasterised back into the 18 × 12 grid: '#' body, 'o' black, '.' empty.
func grid(body: [CGRect], eyes: [CGRect], origin: CGPoint = .zero) -> [String] {
    var g = Array(repeating: Array(repeating: Character("."), count: 18), count: 12)
    func paint(_ rects: [CGRect], _ c: Character) {
        for r in rects {
            let y = Int(((r.minY - origin.y) / 2.2).rounded())
            let x0 = Int(((r.minX - origin.x) / 2.0).rounded()), x1 = Int(((r.maxX - origin.x) / 2.0).rounded())
            #expect(abs(r.height - 2.2) < 1e-9 && (0 ..< 12).contains(y) && x0 >= 0 && x1 <= 18, "rect \(r) leaves the grid")
            guard (0 ..< 12).contains(y), x0 >= 0, x1 <= 18 else { continue }
            for x in x0 ..< x1 {
                #expect(g[y][x] == ".", "pixel \(x),\(y) painted twice")
                g[y][x] = c
            }
        }
    }
    paint(body, "#")
    paint(eyes, "o")
    return g.map { String($0) }
}

func grid(_ geometry: SpriteGeometry) -> [String] { grid(body: geometry.body, eyes: geometry.eyes) }

let emptyRow = String(repeating: ".", count: 18)

func close(_ a: CGRect, _ b: CGRect, _ eps: Double = 1e-9) -> Bool {
    abs(a.minX - b.minX) < eps && abs(a.minY - b.minY) < eps && abs(a.width - b.width) < eps && abs(a.height - b.height) < eps
}

func close(_ a: [CGRect], _ b: [CGRect]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { close($0, $1) } }

/// What one frame draws, sorted out by layer (the ops keep the original's child order).
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
    var dust: [(rects: [CGRect], opacity: Double)] { rectOps(Palette.dust) }

    var texts: [(text: String, at: CGPoint, size: Double, color: RGBA, opacity: Double, anchor: TextAnchor)] {
        frame.ops.compactMap {
            if case .text(let s, let at, let size, _, let c, let o, let a) = $0 { return (s, at, size, c, o, a) }
            return nil
        }
    }

    var bubble: String? { texts.first { $0.text != "z" }?.text }
    var z: Bool { texts.contains { $0.text == "z" } }

    /// Body and eyes relative to the sprite box, as the 18 × 12 grid.
    var pixels: [String] { grid(body: body, eyes: eyes, origin: frame.spriteRect.origin) }
}
