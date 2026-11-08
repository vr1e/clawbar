import CoreGraphics
import Foundation
import ClawBarShared

/// ocean.ps1, the Underwater theme's cartoon sea: sunbeams swaying down from the surface and bubbles rising over the
/// card; in the sky row pastel flowers drifting like clouds, sand with a starfish, swaying kelp, fish swimming across
/// and a pulsing jellyfish.
final class OceanScene: ThemeScene {
    static let px = 1.6

    private struct Beam {
        let fx, width, phase: Double
    }

    private struct Flower {
        let art: ScenePixels
        let width, fy, speed, phase: Double
        /// Unset until the sky row first shows, then somewhere across it.
        var x: Double?
    }

    private struct Bubble {
        let side: Double
        /// Far above the card, so the first step places it at a random height, as Christmas's flakes.
        var x = 0.0, y = -99.0, speed = 0.0, phase = 0.0
    }

    private struct Kelp {
        /// Drawn from its top-left, faded as upstream's canvas.
        let ops: [DrawOp]
        let fx, height, phase: Double
    }

    private struct Fish {
        let art: ScenePixels
        let width: Double
        /// −1 swimming left, 1 swimming right.
        let direction: Double
        let speed: Double
        /// Unset while it is away; it comes back in from its side at another depth.
        var x: Double?
        var fy = 0.0, phase = 0.0
    }

    private let beams: [Beam]
    private var flowers: [Flower]
    private var bubbles: [Bubble]
    /// The row's floor: seeded sand with the starfish on it, which never move.
    private let floorOps: [DrawOp]
    private let kelp: [Kelp]
    private var fish: [Fish]

    init(random: any RandomSource) {
        let px = Self.px
        beams = [(0.12, 18.0), (0.38, 26), (0.6, 14), (0.84, 22)].map { Beam(fx: $0, width: $1, phase: random.phase()) }
        flowers = ["#FF7DD3FC", "#FFF9A8D4", "#FF86EFAC", "#FFC4B5FD"].enumerated().map { i, petals in
            let n = [9, 11, 13][i % 3]
            let fy = 0.02 + 0.12 * random.nextDouble()
            let speed = 0.06 + 0.08 * random.nextDouble()
            let art = ScenePixels(Self.flower(n), px: px, colors: ["p": petals, "c": "#FFFEF9C3"])
            return Flower(art: art, width: Double(n) * px, fy: fy, speed: speed, phase: random.phase())
        }
        bubbles = (0 ..< 14).map { _ in Bubble(side: Double(3 + random.nextInt(5))) }
        var sand = ["", "", ""]
        for _ in 0 ..< 170 {
            sand[0].append(random.nextInt(10) < 3 ? "s" : ".")
            sand[1].append(random.nextInt(12) == 0 ? "d" : "s")
            sand[2].append("s")
        }
        floorOps = ScenePixels(sand, px: px, colors: ["s": "#CCE2C98F", "d": "#CCB8975F"]).ops(at: CGPoint(x: 0, y: Self.floor))
            + Self.starfish.ops(at: pixelPoint(PlayArea.skySize.width * 0.52, Self.floor - 3 * px))
        kelp = [(0.31, 14), (0.36, 10), (0.62, 12), (0.74, 16)].map { fx, rows in
            Kelp(ops: Self.kelp(fx: fx, rows: rows).ops(at: .zero, opacity: 0.85), fx: fx, height: Double(rows) * px, phase: random.phase())
        }
        fish = [
            Fish(art: Self.yellowFish, width: 11 * px, direction: -1, speed: 0.55),
            Fish(art: Self.pinkFish, width: 8 * px, direction: 1, speed: 0.8),
        ]
    }

    func backdrop(tick: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let w = inputs.size.width, h = inputs.size.height, t = Double(tick)
        var ops = [fade(Self.surfaceColor, 0.16, in: CGRect(x: 0, y: 0, width: w, height: 70))]
        for b in beams {
            let beam = fade(Self.beamColor, 0.05, in: CGRect(x: 0, y: 0, width: b.width, height: 320), opacity: 0.6 + 0.4 * sin(t / 25 + b.phase))
            let lean = Transform2D.skewX(degrees: -20 + 4 * sin(t / 60 + b.phase)).concatenating(.translation(b.fx * w, 0))
            ops.append(.group([beam], lean, opacity: 1, clip: nil))
        }
        for i in bubbles.indices {
            var b = bubbles[i]
            if b.y < -10 {
                b.x = random.nextDouble() * w
                b.y = b.y < -50 ? random.nextDouble() * h : h + 5
                b.speed = 0.35 + 0.6 * random.nextDouble()
                b.phase = random.phase()
            }
            b.y -= b.speed
            let rect = CGRect(x: b.x + 2 * sin(t / 8 + b.phase), y: b.y, width: b.side, height: b.side)
            ops.append(.strokedEllipse(rect, Self.bubbleColor, width: 1, opacity: 1))
            bubbles[i] = b
        }
        return ops
    }

    func sky(tick: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let t = Double(tick), px = Self.px, sw = PlayArea.skySize.width, sh = PlayArea.skySize.height
        // Flowers first, so they stay behind the rest of the row.
        var ops: [DrawOp] = []
        for i in flowers.indices {
            var f = flowers[i]
            var x = f.x ?? random.nextDouble() * sw
            x += f.speed
            if x > sw { x = -f.width }
            f.x = x
            flowers[i] = f
            ops += f.art.ops(at: pixelPoint(x, f.fy * sh + 3 * sin(t / 40 + f.phase)), opacity: 0.6)
        }

        ops += floorOps
        for k in kelp {
            // Swaying about its foot, which stays planted in the sand.
            let sway = Transform2D.skewX(degrees: 9 * sin(t / 14 + k.phase)).about(CGPoint(x: 0, y: k.height))
                .concatenating(.translation((sw * k.fx).rounded(.toNearestOrEven), Self.floor + px - k.height))
            ops.append(.group(k.ops, sway, opacity: 1, clip: nil))
        }

        for i in fish.indices {
            var f = fish[i]
            let start: Double
            if let x = f.x {
                start = x
            } else {
                start = f.direction < 0 ? sw + sw * random.nextDouble() : -f.width - sw * random.nextDouble()
                f.fy = 0.15 + 0.4 * random.nextDouble()
                f.phase = random.phase()
            }
            let x = start + f.direction * f.speed
            let gone = f.direction < 0 ? x < -f.width : x > sw
            f.x = gone ? nil : x
            fish[i] = f
            if !gone { ops += f.art.ops(at: pixelPoint(x, f.fy * sh + 1.5 * sin(t / 10 + f.phase))) }
        }

        // The jellyfish's bell squashes and widens on each pulse; its tentacles wave in two poses.
        let pulse = max(0, sin(t / 4))
        let jelly = pixelPoint(sw * (0.5 + 0.1 * sin(t / 220)), sh * 0.12 + 3 * sin(t / 18))
        let squash = Transform2D.scale(1 + 0.08 * pulse, 1 - 0.15 * pulse).about(CGPoint(x: 4.5 * px, y: 4 * px))
        ops.append(.group(Self.bellOps, squash.concatenating(.translation(jelly.x, jelly.y)), opacity: 1, clip: nil))
        ops += Self.tentacles[(tick / 4) % 2].ops(at: jelly)
        return ops
    }

    // MARK: Art

    static let floor = PlayArea.skySize.height - 3 * px
    static let surfaceColor = RGBA("#67E8F9")
    static let beamColor = RGBA("#E0F2FE")
    static let bubbleColor = RGBA("#99E0F2FE")

    /// New-FlowerArt: five round petals about a centre on an n × n grid.
    static func flower(_ n: Int) -> [String] {
        let half = Double(n) / 2
        return (0 ..< n).map { j in
            String((0 ..< n).map { i -> Character in
                let dx = (Double(i) + 0.5 - half) / half, dy = (Double(j) + 0.5 - half) / half
                let r = (dx * dx + dy * dy).squareRoot()
                let edge = 0.55 + 0.45 * abs(cos(2.5 * atan2(dy, dx)))
                return r < 0.3 ? "c" : r <= edge ? "p" : "."
            })
        }
    }

    static let starfish = ScenePixels(["..o..", "ooooo", ".ooo.", ".o.o."], px: px, colors: ["o": "#FFFB923C"])

    /// A strand of kelp with a leaf every fourth row, wavering as it grows.
    static func kelp(fx: Double, rows: Int) -> ScenePixels {
        let art = (0 ..< rows).map { r in
            let pos = Int((1.5 + 1.2 * sin(Double(r) * 0.8 + fx * 20)).rounded(.toNearestOrEven))
            return String(repeating: ".", count: pos) + "kk" + (r % 4 == 1 ? "l" : ".") + String(repeating: ".", count: 3 - pos)
        }
        return ScenePixels(art, px: px, colors: ["k": "#FF15803D", "l": "#FF4ADE80"])
    }

    /// A striped yellow fish swimming left and a small pink one swimming right.
    static let yellowFish = ScenePixels(["...yyyy....", ".yyybyyb.yy", "yeyybyybyyy", ".yyybyyb.yy", "...yyyy...."], px: px, colors: [
        "y": "#FFFACC15", "b": "#FF38BDF8", "e": "#FF0F172A",
    ])
    static let pinkFish = ScenePixels([".p.ppp..", "ppppppep", ".p.pppp."], px: px, colors: ["p": "#FFFB7185", "e": "#FF0F172A"])

    static let bellOps = ScenePixels(["...jjj...", ".jjjjjjj.", "jjhjjjjjj", "jjjjjjjjj"], px: px, colors: [
        "j": "#D9F0ABFC", "h": "#FFFFFFFF",
    ]).ops(at: .zero)
    static let tentacles = ["j.j.j.j..", "..j.j.j.j"].map { tips in
        ScenePixels(["", "", "", "", ".j.j.j.j.", tips], px: px, colors: ["j": "#B3F0ABFC"])
    }
}
