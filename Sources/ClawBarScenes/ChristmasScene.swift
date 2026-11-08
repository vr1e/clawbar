import CoreGraphics
import Foundation
import ClawBarShared

/// christmas.ps1: snow falling over the card and a garland blinking along its top; in the sky row snowdrifts, a house
/// smoking from its chimney, a snowman, a twinkling tree and now and then Santa's sleigh.
final class ChristmasScene: ThemeScene {
    static let px = 1.6

    private struct Flake {
        /// The speck's side; nil for one of the little crosses.
        var side: Double?
        var x = 0.0, y = -99.0, speed = 0.0, phase = 0.0, sway = 0.0
    }

    /// One bulb of the garland: its glow, and its colour's index in `bulbColors`.
    private struct Bulb {
        var glow: CGRect
        var colour: Int
    }

    /// The wire and the bulbs that fit, laid out again only when the width changes.
    private struct Garland {
        var width: Double
        var wire: [CGPoint]
        var bulbs: [Bulb]
        /// The bulbs' pixels, one layer per colour.
        var dots: [[CGRect]]
    }

    private var flakes: [Flake]
    private var garland: Garland?
    /// The sleigh's x while it crosses.
    private var sleigh: Double?
    /// Steps until the sleigh's next crossing.
    private var sleighWait = 120

    init(random: any RandomSource) {
        flakes = (0 ..< 44).map { i in
            Flake(side: i % 8 == 0 ? nil : [1, 1.5, 1.5, 2][random.nextInt(4)])
        }
    }

    func backdrop(tick t: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let w = inputs.size.width, h = inputs.size.height
        let time = Double(t)
        if garland?.width != w { garland = Self.garland(width: w) }

        var specks: [CGRect] = [], crosses: [CGRect] = []
        for i in flakes.indices {
            var f = flakes[i]
            if f.y > h + 4 || f.y < -50 {
                f.x = random.nextDouble() * w
                f.y = f.y < -50 ? random.nextDouble() * h : -4
                f.speed = 0.25 + 0.5 * random.nextDouble()
                f.sway = 1 + 3 * random.nextDouble()
                f.phase = random.nextDouble() * 6.28
            }
            f.y += f.speed
            let at = CGPoint(x: f.x + f.sway * sin(time / 15 + f.phase), y: f.y)
            if let d = f.side {
                specks.append(CGRect(origin: at, size: CGSize(width: d, height: d)))
            } else {
                crosses += Self.cross.map { $0.offsetBy(dx: at.x, dy: at.y) }
            }
            flakes[i] = f
        }
        // One layer per kind, where upstream stacks the flakes one by one: overlaps of this faint white look the same.
        var backdrop: [DrawOp] = [.rects(specks, RGBA("#B3F8FAFC"), opacity: 1), .rects(crosses, Self.crossColor, opacity: 1)]

        // One colour after another lights up brightly while the rest glow dimly.
        let litColour = (t / 8) % 4
        if let g = garland {
            backdrop.append(.stroke(g.wire, RGBA("#80584A4E"), width: 1, opacity: 1))
            // Bulbs sit 14 apart and their glows reach 5, so drawing the glows first changes nothing.
            backdrop += g.bulbs.map {
                glow(Self.bulbColors[$0.colour], 0.45, in: $0.glow, opacity: $0.colour == litColour ? 0.9 : 0.25)
            }
            for (colour, dots) in g.dots.enumerated() {
                backdrop.append(.rects(dots, RGBA(Self.bulbColors[colour]), opacity: colour == litColour ? 1 : 0.55))
            }
        }
        return backdrop
    }

    /// The sky row: the house, the snowman and the tree with the drift in front of them, then the sleigh.
    func sky(tick: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let t = Double(tick), px = Self.px
        let sw = PlayArea.skySize.width, sh = PlayArea.skySize.height
        let ground = sh - 3 * px
        var ops: [DrawOp] = []

        // The window flickers like a fire inside; smoke puffs rise from the chimney and fade.
        let house = CGPoint(x: (sw * 0.24).rounded(.toNearestOrEven), y: ground - 11 * px)
        let flicker = 0.75 + 0.15 * sin(t / 3) + 0.1 * sin(t / 1.7)
        ops += Self.house.ops(at: house)
        ops += Self.houseLight.ops(at: house, opacity: flicker)
        ops.append(glow("#FCD34D", 0.5, in: CGRect(x: house.x + 3.5 * px - 7, y: house.y + 9 * px - 7, width: 14, height: 14), opacity: flicker))
        for i in 0 ..< 4 {
            let pk = Double(i) / 4
            let k = (t / 60 + pk).truncatingRemainder(dividingBy: 1)
            let side = px * (1 + k)
            let at = CGPoint(x: house.x + 8.5 * px + 2 * k + sin(t / 9 + pk * 6) * k * 2, y: house.y - k * 14)
            ops.append(.rects([CGRect(origin: at, size: CGSize(width: side, height: side))], RGBA("#FFCBD5E1"), opacity: 0.7 * (1 - k)))
        }

        ops += Self.snowman.ops(at: CGPoint(x: (sw * 0.41).rounded(.toNearestOrEven), y: ground - 13 * px))

        // Tree lights twinkle in three groups; the star breathes.
        let tree = CGPoint(x: (sw * 0.56).rounded(.toNearestOrEven), y: ground - 16 * px)
        ops.append(glow("#FDE047", 0.55, in: CGRect(x: tree.x + 6.5 * px - 8, y: tree.y + px - 8, width: 16, height: 16), opacity: 0.6 + 0.4 * sin(t / 7)))
        ops += Self.tree.ops(at: tree)
        ops += Self.treeOff.ops(at: tree)
        for (i, lights) in Self.treeLights.enumerated() {
            ops += lights.ops(at: tree, opacity: max(0, min(1, 0.5 + 0.7 * sin(t / 5 + Double(i) * 2.1))))
        }

        ops += Self.drift.ops(at: CGPoint(x: 0, y: ground - 2 * px))

        // The sleigh: after a while away, across the sky from the left, bobbing.
        if let x = sleigh {
            let next = x + 0.7
            if next > sw {
                sleigh = nil
                sleighWait = 400 + random.nextInt(600)
            } else {
                sleigh = next
                let legs = Self.sleighFrames[Int(t / 3) % 2]
                ops += legs.ops(at: CGPoint(x: next.rounded(.toNearestOrEven), y: (4 + 2 * sin(t / 10)).rounded(.toNearestOrEven)))
            }
        } else {
            sleighWait -= 1
            // It launches off the left edge, so this step draws nothing.
            if sleighWait <= 0 { sleigh = -Self.sleighWidth }
        }
        return ops
    }

    // MARK: Art

    static let bulbColors = ["#F87171", "#FCD34D", "#4ADE80", "#60A5FA"]

    /// The sag of the wire at x: zero at the hooks 56 apart, deepest between them.
    static func sag(_ x: Double) -> Double { 2 + 5 * sin(.pi * (x.truncatingRemainder(dividingBy: 56) / 56)) }

    private static func garland(width w: Double) -> Garland {
        let wire = stride(from: 0, through: w, by: 2).map { CGPoint(x: $0, y: sag($0)) }
        var bulbs: [Bulb] = [], dots = Array(repeating: [CGRect](), count: bulbColors.count)
        for i in 0 ..< 36 {
            let x = 7 + Double(i) * 14
            guard x < w - 4 else { break }
            let y = sag(x)
            bulbs.append(Bulb(glow: CGRect(x: x - 5, y: y - 3, width: 10, height: 10), colour: i % 4))
            dots[i % 4].append(CGRect(x: x - 1, y: y + 0.5, width: 2, height: 3))
        }
        return Garland(width: w, wire: wire, bulbs: bulbs, dots: dots)
    }

    /// The little crosses among the specks.
    static let cross = PixelArt.rects([".w.", "www", ".w."], value: "w", px: 1.2, py: 1.2)
    static let crossColor = RGBA("#CCF8FAFC")

    static let houseArt = [
        "......w.cc...",
        ".....wwwcc...",
        "....wwwwwc...",
        "...wwwwwww...",
        "..wwwwwwwww..",
        ".wwwwwwwwwww.",
        "..rrrrrrrrr..",
        "..hhhhhhhhh..",
        "..hyyhhhddh..",
        "..hyyhhhddh..",
        "..hhhhhhddh..",
    ]
    static let house = ScenePixels(houseArt, px: px, colors: [
        "c": "#FF7F1D1D", "w": "#FFF1F5F9", "r": "#FF991B1B", "h": "#FF92400E", "d": "#FF451A03",
    ])
    static let houseLight = ScenePixels(houseArt, px: px, colors: ["y": "#FFFDE68A"])

    static let snowman = ScenePixels([
        "....kkk....",
        "....kkk....",
        "...kkkkk...",
        "...wwwww...",
        "...wewew...",
        "...wwwnn...",
        "...wwwww...",
        "..rrrrrrr..",
        "a..wwwwr..a",
        ".awwwbwwra.",
        "..wwwwwwww.",
        ".wwwwbwwww.",
        ".wwwwwwwww.",
        "..wwwwwww..",
    ], px: px, colors: [
        "k": "#FF1F2937", "w": "#FFF8FAFC", "e": "#FF0F172A", "n": "#FFFB923C", "r": "#FFDC2626", "b": "#FF334155",
        "a": "#FF92400E",
    ])

    static let treeArt = [
        "......s......",
        ".....sss.....",
        "......g......",
        ".....ggg.....",
        "....gggrg....",
        "...ggwggwg...",
        ".....gyg.....",
        "....ggggb....",
        "...grggggg...",
        "..gwgggywgg..",
        "....bgggg....",
        "...ggggrgg...",
        "..gyggggggb..",
        ".wggrgggyggw.",
        "gggggbggggrgg",
        ".....ttt.....",
        ".....ttt.....",
    ]
    static let tree = ScenePixels(treeArt, px: px, colors: ["g": "#FF15803D", "w": "#FFE2E8F0", "t": "#FF78350F", "s": "#FFFDE047"])
    /// What the twinkling falls back to: dark bulbs on the tree.
    static let treeOff = ScenePixels(treeArt, px: px, colors: ["r": "#FF14532D", "y": "#FF14532D", "b": "#FF14532D"])
    static let treeLights = [("r", "#FFF87171"), ("y", "#FFFCD34D"), ("b", "#FF60A5FA")].map {
        ScenePixels(treeArt, px: px, colors: [Character($0.0): $0.1])
    }

    /// Snowdrifts with a bluish shade along their tops.
    static let drift: ScenePixels = {
        var rows = Array(repeating: "", count: 5)
        for x in 0 ..< 170 {
            let top = Int((1.6 + 1.2 * sin(Double(x) / 9) + 0.8 * sin(Double(x) / 4 + 1)).rounded(.toNearestOrEven))
            for r in 0 ..< 5 { rows[r].append(r < top ? "." : r == top && r < 4 ? "b" : "w") }
        }
        return ScenePixels(rows, px: px, colors: ["w": "#F2F1F5F9", "b": "#FFFFFFFF"])
    }()

    /// Santa's sleigh behind two reindeer, the front one with a red nose; two frames of legs.
    static let sleighFrames = [0, 1].map { f in
        let legs = f == 0 ? ".e...e..." : "e.....e.."
        let sleigh = ["....w......", "...rr......", "..rffr.....", "..wwwwkk...", "y.rrrrkkk..", "yqqqqqqqqq.", ".yyyyyyyyyy"]
        let deer = [".........", "......a.a", ".......a.", "......ddn", ".ddddddd.", ".dddddd..", legs]
        let reins = ["..", "..", "..", "..", "ll", "..", ".."]
        let rows = (0 ..< 7).map { r in
            sleigh[r] + reins[r] + deer[r].replacingOccurrences(of: "n", with: "d") + reins[r] + deer[r]
        }
        return ScenePixels(rows, px: px, colors: [
            "r": "#FFEF4444", "w": "#FFF8FAFC", "f": "#FFFED7AA", "y": "#FFFBBF24", "q": "#FFB91C1C", "k": "#FF78350F",
            "l": "#FFFCD34D", "a": "#FFD6A35C", "d": "#FFB45309", "e": "#FF78350F", "n": "#FFF87171",
        ])
    }
    static let sleighWidth = 33 * px
}
