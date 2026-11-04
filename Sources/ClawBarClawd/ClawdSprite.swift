import CoreGraphics
import Foundation
import ClawBarShared

/// Everything Get-MascotGeo keys its geometry on: eyes|arms|feet|look|flip|off|x|facing|poof|shadow|dig|spray.
struct ClawdPose: Hashable, Sendable {
    var eyes: ClawdEyes = .open
    var arms: ClawdArms = .down
    var feet: ClawdFeet = .both
    /// −1, 0, +1: picks the side-glance eyes or shifts the pupils.
    var look = 0
    /// Belly-up: rows 0–9 mirrored.
    var flip = false
    /// Glyph rows lowered (negative: above the frame).
    var off = 0
    /// Glyph columns shifted (negative: left of the frame).
    var x = 0
    var facing: ClawdFacing?
    var poof: ClawdPoof?
    var shadow: ClawdShadow?
    /// Pixel rows sunk into the sand.
    var dig = 0
    /// Phase of the sand grains flying from the legs; 0 = none.
    var spray = 0
}

/// The layers inside the 36 × 26.4 sprite box, in the box's own coordinates (y down from its top).
struct SpriteGeometry: Sendable, Equatable {
    var body: [CGRect] = []
    var eyes: [CGRect] = []
    var fx: [CGRect] = []
    var sand: [CGRect] = []
    /// One per layer of the skin, in its order; a hat reaches above the box.
    var accessories: [[CGRect]] = []
}

/// mascot.ps1's glyph rasterizer with its geometry cache, kept per engine so no static state mutates.
final class ClawdSprite {
    private var cache: [ClawdPose: SpriteGeometry] = [:]

    /// The original keys its cache on the skin too, so another skin starts it over.
    var skin = Skin.classic {
        didSet { if skin != oldValue { cache = [:] } }
    }

    /// Cached forever, as in the original: the poses Clawd uses are a small set.
    func geometry(_ pose: ClawdPose) -> SpriteGeometry {
        if let geo = cache[pose] { return geo }
        let geo = Self.render(pose, skin: skin)
        cache[pose] = geo
        return geo
    }

    private enum PaintMode {
        /// Lit quadrants become body, unlit ones stay empty.
        case plain
        /// Unlit quadrants become the black face.
        case eyes
    }

    /// The 18 × 12 grid before the frame transform, as `grid[x][y]`: 0 empty, 1 body, 2 black.
    static func pixels(_ pose: ClawdPose) -> [[UInt8]] {
        let w = ClawdTables.width, h = ClawdTables.height
        var g = [[UInt8]](repeating: [UInt8](repeating: 0, count: h), count: w)

        func set(_ x: Int, _ y: Int, _ v: UInt8) {
            guard (0 ..< w).contains(x), (0 ..< h).contains(y) else { return }
            g[x][y] = v
        }

        func paint<S: Sequence<Character>>(_ glyphs: S, col: Int, row: Int, mode: PaintMode) {
            let bg: UInt8 = mode == .eyes ? 2 : 0
            for (i, c) in glyphs.enumerated() {
                for sy in 0 ..< 4 {
                    for sx in 0 ..< 2 {
                        let on: Bool
                        if c == "▂" {
                            on = sy == 3
                        } else {
                            let bit = (sy < 2 ? 1 : 4) * (sx == 0 ? 1 : 2)
                            on = (ClawdTables.quadrants[c] ?? 0) & bit != 0
                        }
                        // Zero is never written: painting never erases.
                        let v: UInt8 = on ? 1 : bg
                        if v != 0 { set(2 * (col + i) + sx, 4 * row + sy, v) }
                    }
                }
            }
        }

        if let facing = pose.facing, let rows = ClawdTables.facing[facing] {
            for (r, row) in rows.enumerated() {
                let s = Array(row.glyphs)
                paint(s[0 ..< row.from], col: 0, row: r, mode: .plain)
                paint(s[row.from ..< row.to], col: row.from, row: r, mode: .eyes)
                paint(s[row.to...], col: row.to, row: r, mode: .plain)
            }
            return g
        }

        let arms = ClawdTables.arms[pose.arms]!
        paint(arms.r1L, col: 0, row: 0, mode: .plain)
        paint("██████", col: 2, row: 0, mode: .eyes)
        paint(arms.r1R, col: 8, row: 0, mode: .plain)
        paint(arms.r2L, col: 0, row: 1, mode: .plain)
        paint("█████", col: 2, row: 1, mode: .eyes)
        paint(arms.r2R, col: 7, row: 1, mode: .plain)
        paint(ClawdTables.feet[pose.feet]!, col: 0, row: 2, mode: .plain)

        // Open eyes glancing sideways use Claude Code's ready-made poses; other shapes shift their pupils.
        var eyes = pose.eyes
        var shift = 0
        if eyes == .open, pose.look < 0 {
            eyes = .left
        } else if eyes == .open, pose.look > 0 {
            eyes = .right
        } else if ![.open, .left, .right, .wink].contains(eyes) {
            shift = pose.look
        }
        let shapes = ClawdTables.eyeShapes[eyes]!
        for (k, ex) in [4, 12].enumerated() {
            for dot in shapes[min(k, shapes.count - 1)] { set(ex + dot.dx + shift, dot.dy, 2) }
        }
        if eyes == .yawn || eyes == .gasp {
            for x in 8 ... 10 {
                set(x, 4, 2)
                set(x, 5, 2)
            }
        }
        return g
    }

    /// Get-MascotGeo without the cache: the frame transform, run merging, the skin, poof, shadow, sand and spray.
    static func render(_ pose: ClawdPose, skin: Skin = .classic) -> SpriteGeometry {
        let g = pixels(pose)
        let w = ClawdTables.width, h = ClawdTables.height
        let px = ClawdTables.px, py = ClawdTables.py
        var geo = SpriteGeometry()

        let oy = 4 * pose.off + pose.dig, ox = 2 * pose.x
        // What sank into the burrow is clipped at the ground line.
        let lim = pose.dig > 0 ? h - 2 : h
        for y in 0 ..< h {
            var sy = y
            if pose.flip {
                // Belly-up: the empty lower half-row does not count.
                if y >= h - 2 { continue }
                sy = h - 3 - y
            }
            let yy = sy + oy
            if yy < 0 || yy >= lim { continue }
            var x = 0
            while x < w {
                let c = g[x][y]
                if c == 0 {
                    x += 1
                    continue
                }
                let x0 = x
                while x < w, g[x][y] == c { x += 1 }
                let l = max(0, x0 + ox), r = min(w, x + ox)
                if r <= l { continue }
                let rect = CGRect(x: Double(l) * px, y: Double(yy) * py, width: Double(r - l) * px, height: py)
                if c == 2 { geo.eyes.append(rect) } else { geo.body.append(rect) }
            }
        }

        geo.accessories = skin.layers.map { accessory($0, pose: pose, ox: ox, oy: oy, lim: lim) }

        let wd = Double(w), hd = Double(h)
        if let poof = pose.poof, pose.off > 0 {
            let puffs: [(Double, Double, Double, Double)] = poof == .dot
                ? [(0.6, 9.4, 0.8, 0.9)]
                : [(0.0, 9.6, 0.7, 0.6), (0.7, 9.1, 0.6, 0.6), (1.3, 9.6, 0.7, 0.6)]
            for cx in [0, wd - 2] {
                for p in puffs {
                    geo.fx.append(CGRect(x: (cx + p.0) * px, y: p.1 * py, width: p.2 * px, height: p.3 * py))
                }
            }
        }
        if let shadow = pose.shadow {
            let (sc, sw): (Double, Double) = shadow == .wide ? (6, 6) : (8, 2)
            geo.fx.append(CGRect(x: sc * px, y: (hd - 0.5) * py, width: sw * px, height: 0.5 * py))
        }

        func sand(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
            geo.sand.append(CGRect(x: x * px, y: y * py, width: width * px, height: height * py))
        }
        if pose.dig >= 1 { sand(-2, hd - 3, wd + 4, 1) }
        if pose.dig >= 2 { sand(-1, hd - 4, wd + 2, 1) }
        if pose.dig >= 3 {
            sand(-1, hd - 5, 2, 1)
            sand(wd - 1, hd - 5, 2, 1)
        }
        if pose.spray > 0 {
            let s = Double(pose.spray)
            for k in 0 ..< 2 {
                let d = s + 2 * Double(k)
                let sx = 1.5 + 0.9 * d, sy = (hd - 4) - 0.9 * d * (5 - d) / 2
                sand(-sx, sy, 0.8, 0.8)
                sand(wd - 0.8 + sx, sy, 0.8, 0.8)
            }
        }
        return geo
    }

    /// A skin layer's pixels where the frame puts them, merged into runs per row. Above the head they show while the head
    /// is in the frame, on the body as the body does; turned, only what is above the head stays; belly-up, nothing.
    private static func accessory(_ layer: SkinLayer, pose: ClawdPose, ox: Int, oy: Int, lim: Int) -> [CGRect] {
        guard !pose.flip else { return [] }
        let w = ClawdTables.width
        var rows: [Int: [Int]] = [:]
        for p in layer.pixels {
            if p.y >= 0, pose.facing != nil { continue }
            let x = p.x + ox, yy = p.y + oy
            if x < 0 || x >= w || yy >= lim { continue }
            if p.y < 0 ? oy < 0 : yy < 0 { continue }
            rows[yy, default: []].append(x)
        }
        var out: [CGRect] = []
        for yy in rows.keys.sorted() {
            let xs = rows[yy]!.sorted()
            var i = 0
            while i < xs.count {
                var j = i + 1
                while j < xs.count, xs[j] == xs[j - 1] + 1 { j += 1 }
                out.append(CGRect(
                    x: Double(xs[i]) * ClawdTables.px, y: Double(yy) * ClawdTables.py,
                    width: Double(j - i) * ClawdTables.px, height: ClawdTables.py
                ))
                i = j
            }
        }
        return out
    }

    /// Get-SoulGeo: the soul at height `h` above the mouth (the origin), swaying, on its thread.
    static func soul(height h: Double, t: Int) -> [CGRect] {
        let p = ClawdTables.soulPx
        let sway = 2.5 * sin(Double(t) / 4)
        var out: [CGRect] = []
        let n = Int((h / p).rounded(.down))
        for i in 0 ..< max(0, n) {
            let k = Double(i) / Double(max(1, n))
            let dx = sway * k + 1.2 * sin(Double(t) / 2 + Double(i) * 0.7) * sin(k * Double.pi)
            out.append(CGRect(x: (dx / p).rounded(.toNearestOrEven) * p - p / 2, y: -Double(i + 1) * p, width: p, height: p))
        }
        let top = -h - Double(ClawdTables.soulArt.count) * p
        let x0 = (sway / p).rounded(.toNearestOrEven) * p - 6 * p
        out += PixelArt.rects(ClawdTables.soulArt, value: "#", px: p, py: p, origin: CGPoint(x: x0, y: top))
        return out
    }
}
