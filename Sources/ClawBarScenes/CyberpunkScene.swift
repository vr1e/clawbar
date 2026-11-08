import CoreGraphics
import Foundation
import ClawBarShared

/// cyberpunk.ps1, a night in a neon megacity: neon rain over the card, the city's glow along the bottom and now and
/// then a glitch tearing across; in the sky row a skyline with flickering windows, a tower with a blinking beacon and
/// searchlights, stuttering neon signs and flying cars between the towers.
final class CyberpunkScene: ThemeScene {
    static let px = 1.6
    static let rows = 26, cols = 170
    static let towerX = 92

    private struct Glow {
        let color: RGBA
        let alpha, phase: Double
    }

    private struct Drop {
        let color: RGBA
        let height: Double
        /// Unset until its first step places it.
        var y: Double?
        var x = 0.0, speed = 0.0
    }

    private struct Block {
        var x, w, h: Int
        /// A wall without windows: the tower's upper storeys and its antenna.
        var blank = false
    }

    /// A group of lit windows, dimming now and then on its own.
    private struct Lights {
        let rects: [CGRect]
        let color: RGBA
        let phase: Double
    }

    /// A row of buildings: its walls, which never change, and its window groups.
    private struct Skyline {
        let walls: [DrawOp]
        let lights: [Lights]

        init(_ art: [String], wall: String, lights hexes: [(Character, String)], random: any RandomSource) {
            walls = ScenePixels(art, px: px, colors: ["b": wall]).ops(at: CGPoint(x: 0, y: top))
            lights = hexes.map { letter, hex in
                Lights(rects: PixelArt.rects(art, value: letter, px: px, py: px, origin: CGPoint(x: 0, y: top)), color: RGBA(hex), phase: random.phase())
            }
        }

        /// The windows mostly on, a group dimming slowly now and then.
        func ops(_ t: Double) -> [DrawOp] {
            walls + lights.map { .rects($0.rects, $0.color, opacity: max(0.15, min(1, 0.75 + 0.5 * sin(t / 70 + $0.phase)))) }
        }
    }

    private struct Car {
        /// Its glow and body, from its top-left.
        let art: [DrawOp]
        let dir, speed, width, opacity: Double
        /// Unset while it waits off screen for its next crossing.
        var x: Double?
        var fy = 0.0, phase = 0.0
    }

    private struct Sign {
        let ops: [DrawOp]
        /// Its place in the sky row while the glitch leaves it alone.
        let at: CGPoint
        /// Steps left of a stutter.
        var stutterLeft = 0
    }

    private let glows: [Glow]
    private var rain: [Drop]
    /// The glitch's step, or nil while the next one is `glitchWait` steps away.
    private var glitch: Int?
    private var glitchWait = 150
    /// Upstream's `jx`: how far the glitch jerks the skyline aside.
    private var skylineShift = 0.0
    private let far: Skyline
    private var cars = CyberpunkScene.cars
    private let near: Skyline
    private var signs: [Sign]

    init(random: any RandomSource) {
        glows = [("#FF2A6D", 0.13), ("#05D9E8", 0.10), ("#B026FF", 0.10)].map { Glow(color: RGBA($0), alpha: $1, phase: random.phase()) }
        rain = (0 ..< 36).map { i in
            Drop(color: Self.rainColors[i % 4], height: Double(6 + random.nextInt(7)))
        }

        // Far: a crowd of towers in haze, and the tallest one with its antenna.
        let farBlocks = Self.blocks(width: 5, widthSpread: 8, height: 8, heightSpread: 10, gapSpread: 2, random: random) + [
            Block(x: Self.towerX, w: 9, h: 21),
            Block(x: Self.towerX + 2, w: 5, h: 24, blank: true),
            Block(x: Self.towerX + 4, w: 1, h: 26, blank: true),
        ]
        far = Skyline(
            Self.cityArt(farBlocks, lit: 22, windows: "xyz", random: random), wall: "#FF1E1436",
            lights: [("x", "#B3FCEE0A"), ("y", "#9905D9E8"), ("z", "#99FF2A6D")], random: random
        )

        // Near: lower and darker blocks in front, brighter windows. The signs go on two of them, between the
        // percentage and Clawd, raised and widened to carry them.
        var nearBlocks = Self.blocks(width: 6, widthSpread: 9, height: 3, heightSpread: 7, gapSpread: 3, random: random)
        let roof = Self.tallest(nearBlocks, from: 0.45, to: 0.55), side = Self.tallest(nearBlocks, from: 0.26, to: 0.36)
        nearBlocks[roof].h = max(nearBlocks[roof].h, 6)
        nearBlocks[roof].w = max(nearBlocks[roof].w, 13)
        nearBlocks[side].h = max(nearBlocks[side].h, 12)
        near = Skyline(
            Self.cityArt(nearBlocks, lit: 30, windows: "uv", random: random), wall: "#FF0B0716",
            lights: [("u", "#FFFCEE0A"), ("v", "#E605D9E8")], random: random
        )

        func on(_ b: Block, dx: Int, dy: Int) -> CGPoint {
            CGPoint(x: Double(b.x + dx) * Self.px, y: Self.top + Double(Self.rows - b.h + dy) * Self.px)
        }
        let r = nearBlocks[roof], s = nearBlocks[side]
        // Centred on the roof, 6 pixels above it; on the wall's right, a pixel below its top.
        signs = [
            Sign(ops: Self.roofSign, at: on(r, dx: Int((Double(r.w - Self.roofSignArt[0].count) / 2).rounded(.down)), dy: -6)),
            Sign(ops: Self.sideSign, at: on(s, dx: s.w, dy: 1)),
        ]
    }

    func backdrop(tick: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let w = inputs.size.width, h = inputs.size.height, t = Double(tick)
        var ops: [DrawOp] = []
        for (i, g) in glows.enumerated() {
            let gw = w * (0.8 + 0.2 * Double(i)), gh = 90 + 20 * Double(i)
            let x = w * (0.5 + 0.4 * sin(t / (300 + 50 * Double(i)) + g.phase)) - gw / 2
            ops.append(glow(g.color, g.alpha, in: CGRect(x: x, y: h - gh * 0.5, width: gw, height: gh), opacity: 0.75 + 0.25 * sin(t / 35 + g.phase)))
        }

        // The first step scatters the drops down the card, where upstream's wait above it for good.
        for i in rain.indices {
            var d = rain[i]
            var y: Double
            if let last = d.y, last <= h {
                y = last
            } else {
                d.x = (random.nextDouble() * w).rounded(.toNearestOrEven)
                y = d.y == nil ? random.nextDouble() * h : -12 - 40 * random.nextDouble()
                d.speed = 5 + 4 * random.nextDouble()
            }
            y += d.speed
            d.y = y
            rain[i] = d
            ops.append(.rects([CGRect(x: d.x, y: y.rounded(.toNearestOrEven), width: 1, height: d.height)], d.color, opacity: 1))
        }

        // The glitch: a few steps of torn bars, the skyline jerking aside with them; its last step draws none.
        if glitch == nil {
            glitchWait -= 1
            if glitchWait <= 0 { glitch = 0 }
        }
        if let g = glitch {
            var bars: [DrawOp] = []
            for color in Self.barColors where random.nextInt(3) != 0 {
                let bw = w * (0.2 + 0.7 * random.nextDouble()), bh = Double(1 + random.nextInt(4))
                bars.append(.rects([CGRect(x: random.nextDouble() * (w - bw), y: random.nextDouble() * h, width: bw, height: bh)], color, opacity: 1))
            }
            skylineShift = random.nextInt(2) == 0 ? -2 : 2
            if g + 1 < Self.glitchLength {
                glitch = g + 1
                ops += bars
            } else {
                glitch = nil
                glitchWait = 250 + random.nextInt(450)
                skylineShift = 0
            }
        }

        // The searchlights sweep up from the tower's top, over the card since the tower reaches the row's top edge.
        if let row = inputs.skyRow {
            let tip = CGPoint(x: row.minX + skylineShift + Self.beaconX + Self.px / 2, y: row.minY + Self.top)
            for phase in [0.0, 2.6] {
                let turn = Transform2D.rotation(38 * sin(t / 55 + phase) * .pi / 180)
                ops.append(.group([Self.beam], turn.concatenating(.translation(tip.x, tip.y)), opacity: 1, clip: nil))
            }
        }
        return ops
    }

    func sky(tick: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let t = Double(tick), sw = PlayArea.skySize.width, sh = PlayArea.skySize.height
        var back = far.ops(t)
        if tick % 14 < 4 { back += Self.beacon }
        var ops = shifted(back)

        for i in cars.indices {
            var c = cars[i]
            let start: Double
            if let x = c.x {
                start = x
            } else {
                start = c.dir < 0 ? sw + sw * random.nextDouble() : -c.width - sw * random.nextDouble()
                c.fy = 0.15 + 0.35 * random.nextDouble()
                c.phase = random.phase()
            }
            let x = start + c.dir * c.speed
            let gone = c.dir < 0 ? x < -c.width : x > sw
            c.x = gone ? nil : x
            cars[i] = c
            if gone { continue }
            let at = pixelPoint(x, c.fy * sh + 1.2 * sin(t / 13 + c.phase))
            ops.append(.group(c.art, .translation(at.x, at.y), opacity: c.opacity, clip: nil))
        }

        var front = near.ops(t)
        let n = Self.stutter.count
        for i in signs.indices {
            // Now and then a sign stutters, blinking off and on for a few steps.
            if signs[i].stutterLeft == 0, random.nextInt(160) == 0 { signs[i].stutterLeft = n }
            var lit = true
            if signs[i].stutterLeft > 0 {
                lit = Self.stutter[n - signs[i].stutterLeft]
                signs[i].stutterLeft -= 1
            }
            let s = signs[i]
            front.append(.group(s.ops, .translation(s.at.x, s.at.y), opacity: lit ? 0.85 + 0.15 * sin(t / 3) : 0.12, clip: nil))
        }
        return ops + shifted(front)
    }

    /// The skyline's ops, jerked aside while a glitch tears across; the cars between its rows stay put, as upstream's.
    private func shifted(_ ops: [DrawOp]) -> [DrawOp] {
        skylineShift == 0 ? ops : [.group(ops, .translation(skylineShift, 0), opacity: 1, clip: nil)]
    }

    // MARK: The skyline

    /// The skyline's top in the sky row, so its bottom sits on the floor line.
    static let top = (PlayArea.skySize.height - Double(rows) * px).rounded(.toNearestOrEven)
    /// The antenna's column in the sky row, where the beacon blinks and the searchlights rise.
    static let beaconX = Double(towerX + 4) * px

    /// Blocks side by side across the skyline, each `width` plus up to `widthSpread − 1` wide and so on.
    private static func blocks(width: Int, widthSpread: Int, height: Int, heightSpread: Int, gapSpread: Int, random: any RandomSource) -> [Block] {
        var out: [Block] = []
        var x = 0
        while x < cols {
            let w = width + random.nextInt(widthSpread)
            out.append(Block(x: x, w: w, h: height + random.nextInt(heightSpread)))
            x += w + random.nextInt(gapSpread)
        }
        return out
    }

    /// New-CityArt: the blocks bottom-aligned as `b`, every other cell inside the walls a window, `lit` in 100 of
    /// them lit in one of `windows`' letters.
    private static func cityArt(_ blocks: [Block], lit: Int, windows: String, random: any RandomSource) -> [String] {
        let letters = Array(windows)
        var g = [[Character]](repeating: [Character](repeating: ".", count: cols), count: rows)
        for b in blocks {
            for y in rows - b.h ..< rows {
                for x in b.x ..< min(cols, b.x + b.w) {
                    g[y][x] = "b"
                    let wx = x - b.x, wy = y - (rows - b.h)
                    if b.blank || wx < 1 || wx >= b.w - 1 || wy < 1 || wx % 2 == 0 || wy % 2 == 0 { continue }
                    if random.nextInt(100) < lit { g[y][x] = letters[random.nextInt(letters.count)] }
                }
            }
        }
        return g.map { String($0) }
    }

    /// Get-NearAt: the tallest block starting between the two fractions of the skyline. Blocks are at most 14 wide
    /// with gaps of at most 2, so every such range holds one.
    private static func tallest(_ blocks: [Block], from: Double, to: Double) -> Int {
        let range = Double(cols) * from ... Double(cols) * to
        return blocks.indices.filter { range.contains(Double(blocks[$0].x)) }.max { blocks[$0].h < blocks[$1].h } ?? 0
    }

    static let beacon: [DrawOp] = [
        .rects([CGRect(x: beaconX, y: top, width: px, height: px)], RGBA("#FFFF003C"), opacity: 1),
        glow("#FF003C", 0.6, in: CGRect(x: beaconX + px / 2 - 6, y: top + px / 2 - 6, width: 12, height: 12)),
    ]

    /// A big car heading right and a small one farther off heading left, headlights in front, tail lights behind.
    private static let cars = [
        car(["...kkkk...", "rkkkkkkkkh", "..k....k.."], px: px, dir: 1, speed: 0.9, opacity: 1),
        car([".kkk.", "hkkkr"], px: 1.2, dir: -1, speed: 0.5, opacity: 0.75),
    ]

    private static func car(_ art: [String], px: Double, dir: Double, speed: Double, opacity: Double) -> Car {
        let width = Double(art[0].count) * px
        let lamp = dir > 0 ? width : 0
        let ops = [glow("#E0FFFF", 0.45, in: CGRect(x: lamp - 5, y: px * 1.5 - 5, width: 10, height: 10))]
            + ScenePixels(art, px: px, colors: ["k": "#FF3B3656", "h": "#FFE0FFFF", "r": "#FFFF003C"]).ops(at: .zero)
        return Car(art: ops, dir: dir, speed: speed, width: width, opacity: opacity)
    }

    /// New-Sign: neon pixel art on a glow reaching `gw` and `gh` past it.
    private static func sign(_ art: [String], _ hex: String, gw: Double, gh: Double) -> [DrawOp] {
        let w = Double(art[0].count) * px, h = Double(art.count) * px
        return [glow(hex, 0.55, in: CGRect(x: -gw / 2, y: -gh / 2, width: w + gw, height: h + gh))]
            + ScenePixels(art, px: px, colors: ["n": hex]).ops(at: .zero)
    }

    /// "2077" on a roof.
    static let roofSignArt = ["nnn.nnn.nnn.nnn", "..n.n.n...n...n", "nnn.n.n...n...n", "n...n.n...n...n", "nnn.nnn...n...n"]
    static let roofSign = sign(roofSignArt, "#FF00F0FF", gw: 14, gh: 10)
    /// A column of glyphs on a wall.
    static let sideSign = sign(["nnn", "n.n", "nnn", "...", ".n.", "nnn", ".n.", "...", "n.n", ".n.", "n.n"], "#FFFF2A6D", gw: 10, gh: 14)
    static let stutter = [false, true, false, false, true, false, true, true]

    // MARK: Over the card

    static let rainColors = ["#8005D9E8", "#6605D9E8", "#66FF2A6D", "#4DE0F2FE"].map(RGBA.init)
    static let barColors = ["#66FF003C", "#5500F0FF", "#4DFF003C", "#4400F0FF", "#33FCEE0A"].map(RGBA.init)
    static let glitchLength = 7
    /// A searchlight's cone, widening upwards from its tip at the origin, which it turns about.
    static let beam = DrawOp.polygon(
        [.zero, CGPoint(x: -8, y: -80), CGPoint(x: 8, y: -80)],
        stops: [GradientStop(location: 0, color: RGBA("#0005D9E8")), GradientStop(location: 1, color: RGBA("#3305D9E8"))],
        opacity: 1
    )
}
