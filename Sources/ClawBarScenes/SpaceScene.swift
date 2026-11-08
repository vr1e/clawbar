import CoreGraphics
import Foundation
import ClawBarShared

/// space.ps1: a starfield over the card with drifting nebulae, twinkling and flaring stars and now and then a shooting
/// star; in the sky row two turning pixel planets, one ringed, and a little ship crossing.
final class SpaceScene: ThemeScene {
    static let px = 1.6
    /// Stars sit over a strip taller than the card ever gets, so opening the details uncovers more of them.
    static let field = CGSize(width: 262, height: 900)
    static let starColors = ["#FFFFFFFF", "#FFE9D5FF", "#FFC4B5FD", "#FFF9A8D4", "#FFA5B4FC", "#FF93C5FD"].map(RGBA.init)
    static let starGroups = 10
    /// Steps a shooting star takes, fading out on the last.
    static let shootingSteps = 14

    /// A star's own rhythm: 0 to 1 and back.
    private struct Twinkle {
        var phase, speed: Double

        init(random: any RandomSource) {
            phase = random.nextDouble() * 6.28
            speed = 0.05 + 0.15 * random.nextDouble()
        }

        func sine(at t: Double) -> Double { sin(t * speed + phase) }
    }

    /// Faint stars twinkling together: one layer each.
    private struct StarGroup {
        var color: RGBA
        var stars: [CGRect] = []
        var twinkle: Twinkle
    }

    /// A bright star that flares with a cross of light.
    private struct BrightStar {
        var color: RGBA
        var x: Double
        /// Unrounded, as upstream decides by it whether the card is tall enough to show the star.
        var top: Double
        var twinkle: Twinkle
    }

    private struct ShootingStar {
        var step = 0
        var x, y: Double
    }

    private var groups: [StarGroup]
    private var bright: [BrightStar]
    private var shooting: ShootingStar?
    /// The ship's x as a fraction of the sky row.
    private var ship = 0.25

    init(random: any RandomSource) {
        let w = Self.field.width, h = Self.field.height
        groups = (0 ..< Self.starGroups).map { g in
            StarGroup(color: Self.starColors[g % Self.starColors.count], twinkle: Twinkle(random: random))
        }
        for _ in 0 ..< Int((w * h / 1100).rounded(.toNearestOrEven)) {
            let side = [1, 1, 1, 1.5, 1.5, 2][random.nextInt(6)]
            let g = random.nextInt(Self.starGroups)
            let x = (random.nextDouble() * w).rounded(.toNearestOrEven), y = (random.nextDouble() * h).rounded(.toNearestOrEven)
            groups[g].stars.append(CGRect(x: x, y: y, width: side, height: side))
        }
        bright = (0 ..< 14).map { _ in
            let color = Self.starColors[random.nextInt(Self.starColors.count)]
            let top = random.nextDouble() * h
            return BrightStar(color: color, x: (random.nextDouble() * w).rounded(.toNearestOrEven), top: top, twinkle: Twinkle(random: random))
        }
    }

    func backdrop(tick: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let w = inputs.size.width, h = inputs.size.height, t = Double(tick)
        var ops: [DrawOp] = []

        for (i, (color, a)) in Self.nebulae.enumerated() {
            let i = Double(i)
            let k = t / 300 + i * 2.1
            let rad = w * (0.45 + 0.1 * i)
            let x = w * (0.5 + 0.35 * sin(k + i)) - rad
            let y = h * (0.3 + 0.25 * i + 0.05 * cos(k * 1.3)) - rad * 0.6
            ops.append(glow(color, a, in: CGRect(x: x, y: y, width: rad * 2, height: rad * 1.2)))
        }
        for g in groups {
            ops.append(.rects(g.stars, g.color, opacity: 0.25 + 0.3 * (1 + g.twinkle.sine(at: t))))
        }
        // Upstream stops updating a star below the card, which stays out of sight; leaving it out looks the same.
        for b in bright where b.top <= h + 8 {
            let flare = 0.5 + 0.5 * b.twinkle.sine(at: t)
            let len = 4 + 8 * flare
            // A group, so the rays don't brighten where they cross the glow and the core; the glow bounds it.
            ops.append(.group([
                glow(b.color, 0.25, in: Self.brightGlow),
                .rects([CGRect(x: -len / 2, y: -0.5, width: len, height: 1)], b.color, opacity: 0.6),
                .rects([CGRect(x: -0.5, y: -len / 2, width: 1, height: len)], b.color, opacity: 0.6),
                .rects([CGRect(x: -1, y: -1, width: 2, height: 2)], b.color, opacity: 1),
            ], .translation(b.x, b.top.rounded(.toNearestOrEven)), opacity: 0.55 + 0.45 * flare, clip: Self.brightGlow))
        }

        // A shooting star now and then, down and to the left, fading.
        if shooting == nil, random.nextInt(220) == 0 {
            let x = w * (0.3 + 0.7 * random.nextDouble())
            shooting = ShootingStar(x: x, y: h * 0.35 * random.nextDouble())
        }
        if let s = shooting {
            let k = Double(s.step) / Double(Self.shootingSteps)
            ops.append(.group(Self.shootingStar, .translation(s.x - k * 120, s.y + k * 45), opacity: 1 - k, clip: Self.shootingBounds))
            shooting?.step += 1
            if s.step >= Self.shootingSteps { shooting = nil }
        }
        return ops
    }

    /// The sky row: the planets sway to and fro, turning and bobbing, and the ship crosses.
    func sky(tick: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let t = Double(tick), sw = PlayArea.skySize.width, sh = PlayArea.skySize.height
        var ops: [DrawOp] = []
        for (i, p) in Self.planets.enumerated() {
            let centre = CGPoint(x: sw * (p.fx + p.amp * sin(t / 250 + p.seed)), y: sh * p.fy + 2 * sin(t / 45 + p.seed))
            let d = p.side
            let at = CGPoint(x: (centre.x - d / 2).rounded(.toNearestOrEven), y: (centre.y - d / 2).rounded(.toNearestOrEven))
            ops.append(glow(p.colors[2], 0.28, in: CGRect(x: centre.x - d, y: centre.y - d, width: d * 2, height: d * 2)))
            if p.ring { ops.append(Self.ringHalf(p, centre: centre, back: true)) }
            ops += Self.turns[i][Int((t * p.spin).rounded(.down)) % Self.turnFrames].ops(at: at)
            if p.ring { ops.append(Self.ringHalf(p, centre: centre, back: false)) }
        }

        // Past the row's end it waits off screen, then comes in from just off the left edge, where upstream's
        // reappears a quarter of the way across.
        ship += 0.002
        if ship > 1.4 { ship = -Self.shipWidth / sw }
        let px = Self.px
        let at = CGPoint(x: (ship * sw).rounded(.toNearestOrEven), y: (3 + 2 * sin(t / 12)).rounded(.toNearestOrEven))
        let flame = Double(2 + tick % 4) * px
        ops += Self.ship.ops(at: at)
        ops.append(.rects([CGRect(x: at.x - flame, y: at.y + 3 * px, width: flame, height: px)], Self.flameColor, opacity: 1))
        ops.append(.rects([CGRect(x: at.x - px, y: at.y + 3 * px, width: px, height: px)], Self.sparkColor, opacity: 1))
        return ops
    }

    // MARK: Art

    static let nebulae = [(RGBA("#7C3AED"), 0.22), (RGBA("#DB2777"), 0.13), (RGBA("#4F46E5"), 0.15)]
    static let brightGlow = CGRect(x: -7, y: -7, width: 14, height: 14)

    /// A streak fading out behind a bright head, its tail running 26 right and 10 up.
    static let shootingStar: [DrawOp] = {
        let tail = (26.0 * 26 + 10 * 10).squareRoot()
        let stops = [GradientStop(location: 0, color: RGBA("#CCFFFFFF")), GradientStop(location: 1, color: RGBA("#00FFFFFF"))]
        return [
            .group([.hGradient(CGRect(x: 0, y: -0.6, width: tail, height: 1.2), stops: stops, opacity: 1)],
                   .rotation(atan2(-10, 26)), opacity: 1, clip: nil),
            .rects([CGRect(x: -1, y: -1, width: 2, height: 2)], RGBA("#FFFFFFFF"), opacity: 1),
        ]
    }()
    static let shootingBounds = CGRect(x: -1, y: -11, width: 28, height: 12)

    struct Planet {
        /// Where it sways about, as fractions of the sky row, and how far it sways.
        let fx, fy, amp: Double
        /// The sphere's radius in pixels.
        let r: Int
        let spin, seed: Double
        let ring: Bool
        let colors: [RGBA]

        init(fx: Double, fy: Double, amp: Double, r: Int, spin: Double, seed: Double, ring: Bool, palette: [String]) {
            (self.fx, self.fy, self.amp, self.r, self.spin, self.seed, self.ring) = (fx, fy, amp, r, spin, seed, ring)
            colors = palette.map(RGBA.init)
        }

        /// Its width and height on screen.
        var side: Double { Double(2 * r + 1) * SpaceScene.px }
    }

    static let planets = [
        Planet(fx: 0.47, fy: 0.45, amp: 0.06, r: 8, spin: 0.5, seed: 1.3, ring: false,
               palette: ["#FF2E1065", "#FF6D28D9", "#FFA855F7", "#FFF472B6", "#FF67E8F9", "#FFC084FC"]),
        Planet(fx: 0.7, fy: 0.32, amp: 0.03, r: 5, spin: 0.7, seed: 4.1, ring: true,
               palette: ["#FF1E1B4B", "#FF3730A3", "#FF6366F1", "#FFA5B4FC", "#FF818CF8"]),
    ]
    /// Frames in one turn of a planet.
    static let turnFrames = 120
    static let planetDark = RGBA("#FF0B0518")
    /// Every planet's turn, built the first time the scene shows, where upstream builds each frame when first needed.
    static let turns = planets.map { p in (0 ..< turnFrames).map { sphere(p, turn: $0) } }

    /// New-PlanetFrame: a pixel sphere with bands of colour wrapped round it, lit from the upper left, turned to frame
    /// `k`; one layer per colour, in the order the pixels first use them.
    static func sphere(_ p: Planet, turn k: Int) -> ScenePixels {
        let n = 2 * p.r + 1, half = Double(n) / 2
        let rot = 2 * Double.pi * Double(k) / Double(turnFrames)
        var layers: [ScenePixels.Layer] = [], index: [RGBA: Int] = [:]
        for j in 0 ..< n {
            for i in 0 ..< n {
                let dx = (Double(i) + 0.5 - half) / half, dy = (Double(j) + 0.5 - half) / half
                let rr = dx * dx + dy * dy
                guard rr <= 1 else { continue }
                let z = (1 - rr).squareRoot()
                let u = atan2(dx, z) + rot
                let noise = sin(u * 3 + sin(dy * 4 + p.seed) * 1.6) + 0.6 * sin(dy * 6 + u * 2 + p.seed) + 0.3 * sin(u * 7 - dy * 5)
                let band = min(p.colors.count - 1, max(0, Int(((noise + 1.9) / 3.8 * Double(p.colors.count)).rounded(.down))))
                let light = max(0.12, min(1, 0.3 + 0.9 * (-0.55 * dx - 0.45 * dy + 0.7 * z)))
                let c = RGBA.mix(planetDark, p.colors[band], light)
                let rect = CGRect(x: Double(i) * px, y: Double(j) * px, width: px, height: px)
                if let l = index[c] {
                    layers[l].rects.append(rect)
                } else {
                    index[c] = layers.count
                    layers.append(ScenePixels.Layer(color: c, rects: [rect]))
                }
            }
        }
        return ScenePixels(layers: layers)
    }

    /// New-RingHalf: the far half of the ring, behind the planet, or the near half in front of it.
    static func ringHalf(_ p: Planet, centre: CGPoint, back: Bool) -> DrawOp {
        let d = p.side
        let ring = DrawOp.strokedEllipse(CGRect(x: 0, y: 0, width: d * 1.9, height: d * 0.44), p.colors[3], width: 1.6, opacity: back ? 0.45 : 0.85)
        return .group([ring], .translation(centre.x - d * 0.95, centre.y - d * 0.22), opacity: 1,
                      clip: CGRect(x: 0, y: back ? 0 : d * 0.22, width: d * 1.9, height: d * 0.22))
    }

    /// A grey saucer with cyan windows; its flickering engine is drawn behind it.
    static let shipArt = ["....##....", "..######..", ".##o##o##.", "##########", ".#..##..#."]
    static let ship = ScenePixels(shipArt, px: px, colors: ["#": "#FF94A3B8", "o": "#FF67E8F9"])
    static let shipWidth = Double(shipArt[0].count) * px
    static let flameColor = RGBA("#D9F472B6")
    static let sparkColor = RGBA("#FFFDE68A")
}
