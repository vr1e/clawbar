import CoreGraphics
import Foundation
import ClawBarShared

/// halloween.ps1, a spooky night: fog creeping along the bottom of the card, will-o'-the-wisps, bats, a ghost now and
/// then and a spider on its thread from the web in the corner; in the sky row a big moon over a graveyard with a dead
/// tree and flickering jack-o'-lanterns. At midnight, one night in three, the midnight scare.
final class HalloweenScene: ThemeScene {
    static let px = 1.6
    static let scareLength = 70

    private struct Fog {
        let color: RGBA
        let alpha, phase: Double
    }

    private struct Wisp {
        var fx, fy: Double
        let phase, speed: Double
    }

    private struct Bat {
        /// Unset until it sets off.
        var x: Double?
        var first = true
        var y = 0.0, speed = 0.0, amp = 0.0, phase = 0.0

        /// A new flight, the first time from anywhere in the card, later from off the left edge; returns where it starts.
        mutating func launch(w: Double, h: Double, random: any RandomSource) -> Double {
            let x = first ? w * random.nextDouble() : -20 - w * 2 * random.nextDouble()
            first = false
            y = h * (0.05 + 0.5 * random.nextDouble())
            speed = 0.9 + 0.8 * random.nextDouble()
            amp = 4 + 10 * random.nextDouble()
            phase = random.phase()
            return x
        }
    }

    private struct Ghost {
        /// 0 to 1 across the card, from the right.
        var progress: Double
        let y: Double
    }

    private struct Pumpkin {
        let at: CGPoint
        let phase: Double
        /// Its body and the dark face behind the flickering one, which never change.
        let ops: [DrawOp]
    }

    private let fog: [Fog]
    private var wisps: [Wisp]
    private var spiderT = 0
    private var bats = [Bat](repeating: Bat(), count: 3)
    private var ghost: Ghost?
    /// Steps until the ghost's next crossing.
    private var ghostWait = 80
    private let pumpkins: [Pumpkin]
    private let groundOps: [DrawOp]
    /// The scare's step, or nil while none plays.
    private var scare: Int?
    /// The start of the last local day whose midnight was checked, so each night gets one chance.
    private var night: Date?

    init(random: any RandomSource) {
        fog = [("#86EFAC", 0.10), ("#A78BFA", 0.12), ("#86EFAC", 0.08), ("#C4B5FD", 0.10)].map {
            Fog(color: RGBA($0), alpha: $1, phase: random.phase())
        }
        wisps = (0 ..< 6).map { _ in
            let (fx, fy) = Self.wispSpot(random)
            return Wisp(fx: fx, fy: fy, phase: random.phase(), speed: 0.02 + 0.03 * random.nextDouble())
        }
        pumpkins = [0.24, 0.58].map { fx in
            let at = CGPoint(x: (PlayArea.skySize.width * fx).rounded(.toNearestOrEven), y: Self.floor + Self.px - 7 * Self.px)
            return Pumpkin(at: at, phase: random.phase(), ops: Self.pumpkin.ops(at: at) + Self.pumpkinDark.ops(at: at))
        }
        var art = ["", "", ""]
        for _ in 0 ..< 170 {
            art[0].append(random.nextInt(5) == 0 ? "g" : ".")
            art[1].append(random.nextInt(3) == 0 ? "g" : "d")
            art[2].append("d")
        }
        groundOps = ScenePixels(art, px: Self.px, colors: ["d": "#FF2E1F3D", "g": "#FF3F2F52"]).ops(at: CGPoint(x: 0, y: Self.floor))
    }

    func backdrop(tick: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let w = inputs.size.width, h = inputs.size.height, t = Double(tick)
        var ops: [DrawOp] = []
        for (i, f) in fog.enumerated() {
            let fw = w * (0.7 + 0.15 * Double(i)), fh = 70 + 15 * Double(i)
            let x = w * (0.5 + 0.45 * sin(t / (260 + 40 * Double(i)) + f.phase)) - fw / 2
            ops.append(glow(f.color, f.alpha, in: CGRect(x: x, y: h - fh * 0.55, width: fw, height: fh), opacity: 0.7 + 0.3 * sin(t / 40 + f.phase)))
        }

        for i in wisps.indices {
            var o = wisps[i]
            let opacity = max(0, sin(t * o.speed + o.phase))
            if opacity <= 0.01 { (o.fx, o.fy) = Self.wispSpot(random) }
            wisps[i] = o
            // The dot sits on its glow, so they fade as one.
            let at = Transform2D.translation(o.fx * w + 6 * sin(t / 23 + o.phase), o.fy * h + 4 * cos(t / 31 + o.phase))
            ops.append(.group(Self.wisp, at, opacity: opacity, clip: nil))
        }

        // The spider rests up in the web, then lets itself down and climbs back; the thread is clear of the buttons.
        ops += Self.web.ops(at: CGPoint(x: w - 22, y: 0))
        spiderT += 1
        let cycle = spiderT % 400
        let down = cycle < 150 ? 0 : cycle < 230 ? Double(cycle - 150) / 80 : cycle < 300 ? 1 : 1 - Double(cycle - 300) / 100
        let sy = 10 + 50 * down + (cycle >= 230 && cycle < 300 ? 2 * sin(t / 6) : 0)
        ops.append(.rects([CGRect(x: w - 8, y: 0, width: 1, height: sy)], Self.webColor, opacity: 1))
        ops += Self.spider.ops(at: CGPoint(x: w - 14, y: sy))

        for i in bats.indices {
            var b = bats[i]
            let start: Double
            if let x = b.x { start = x } else { start = b.launch(w: w, h: h, random: random) }
            let x = start + b.speed
            // Gone past the right edge, where upstream leaves it out of sight.
            let gone = x > w + 20
            b.x = gone ? nil : x
            bats[i] = b
            if gone { continue }
            let flap = Int((t / 2 + b.phase).rounded(.down)) % 2 == 0
            ops += (flap ? Self.batUp : Self.batDown).ops(at: pixelPoint(x, b.y + b.amp * sin(t / 9 + b.phase)))
        }

        // The ghost: after a while away, across the card from the right, fading in and out. Its launch step draws
        // nothing, where upstream's shows it for one tick where it last was.
        if var g = ghost {
            g.progress += 0.004
            if g.progress >= 1 {
                ghost = nil
                ghostWait = 300 + random.nextInt(500)
            } else {
                ghost = g
                let at = pixelPoint(w - (w + 22) * g.progress, g.y + 6 * sin(t / 12))
                ops += Self.ghost[(tick / 5) % 2].ops(at: at, opacity: 0.45 * sin(.pi * g.progress))
            }
        } else {
            ghostWait -= 1
            if ghostWait <= 0 { ghost = Ghost(progress: 0, y: h * (0.25 + 0.4 * random.nextDouble())) }
        }
        return ops
    }

    /// Midnight strikes, one night in three, while the widget shows; then the scare's step.
    func secret(tick: Int, inputs: SceneInputs, random: any RandomSource) -> SceneSecretFrame? {
        if scare == nil, tick % 10 == 0 {
            let calendar = Calendar.gregorian(in: inputs.timeZone)
            let c = calendar.dateComponents([.hour, .minute], from: inputs.now)
            let today = calendar.startOfDay(for: inputs.now)
            if c.hour == 0, c.minute == 0, night != today {
                night = today
                if random.nextInt(3) == 0 { scare = 0 }
            }
        }
        guard let k = scare else { return nil }
        // Upstream's last step puts the lights back before anything renders.
        guard k + 1 < Self.scareLength else {
            scare = nil
            return nil
        }
        scare = k + 1
        return Self.scareFrame(k, size: inputs.size)
    }

    func play(_ secret: SceneSecret, at step: Int) { scare = step }

    func endSecret() { scare = nil }

    func sky(tick: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp] {
        let t = Double(tick), px = Self.px
        var ops = [glow(Self.moonGlow, 0.45, in: Self.moonGlowRect, opacity: 0.8 + 0.2 * sin(t / 30))] + Self.graveyard
        // The face is a layer of its own over a dark one, flickering like a candle inside.
        for p in pumpkins {
            let flicker = 0.65 + 0.2 * sin(t / 2.3 + p.phase) + 0.15 * sin(t / 1.3 + p.phase * 2)
            let glowRect = CGRect(x: p.at.x + 4.5 * px - 13, y: p.at.y + 3.5 * px - 13, width: 26, height: 26)
            ops.append(glow(Self.pumpkinGlow, 0.5, in: glowRect, opacity: flicker))
            ops += p.ops + Self.pumpkinFace.ops(at: p.at, opacity: flicker)
        }
        return ops + groundOps
    }

    /// Step-Scare: two flashes of lightning, the dark falls, the face looms closer, holds, blinks and fades; as the
    /// lights come back, Clawd jumps.
    static func scareFrame(_ k: Int, size: CGSize) -> SceneSecretFrame {
        let w = size.width, h = size.height, n = scareLength
        let flash: Double = [0: 0.5, 1: 0.15, 3: 0.4, 4: 0.1][k] ?? 0
        let dark: Double = k < 4 ? 0 : k < 12 ? Double(k - 4) / 8 : k < n - 12 ? 1 : Double(n - k) / 12
        let face: Double = k < 12 ? 0 : k < 30 ? Double(k - 12) / 18 : k < n - 16 ? 1 : max(0, Double(n - 6 - k) / 10)
        let whole = CGRect(origin: .zero, size: size)
        let z: Double = 0.9 + 0.15 * Double(k) / Double(n)
        let left: Double = ((w - faceSize.width) / 2).rounded(.toNearestOrEven)
        let top: Double = ((h - faceSize.height) * 0.4).rounded(.toNearestOrEven)
        let place = Transform2D.scale(z, z).about(CGPoint(x: faceSize.width / 2, y: faceSize.height / 2)).concatenating(.translation(left, top))
        // The eyes shut for a blink.
        let looming: [DrawOp] = faceGlows + faceMouth + ((40 ..< 43).contains(k) ? [] : faceEyes)
        let overlay: [DrawOp] = [
            .rects([whole], darkColor, opacity: 0.8 * dark),
            .rects([whole], flashColor, opacity: flash),
            .group(looming, place, opacity: face, clip: nil),
        ]
        return SceneSecretFrame(
            overlay: overlay,
            skyOpacity: 1 - 0.6 * dark,
            cues: k == n - 10 ? [.act(.jump)] : []
        )
    }

    // MARK: Art

    static let floor = PlayArea.skySize.height - 3 * px

    /// A wisp's new place, as fractions of the card.
    static func wispSpot(_ random: any RandomSource) -> (Double, Double) {
        let fx = random.nextDouble()
        return (fx, 0.2 + 0.75 * random.nextDouble())
    }

    static let webColor = RGBA("#59E9D5FF")
    static let darkColor = RGBA("#FF07040B")
    static let flashColor = RGBA("#FFF5F3FF")
    static let wisp: [DrawOp] = [
        glow("#4ADE80", 0.5, in: CGRect(x: -6, y: -6, width: 12, height: 12)),
        .rects([CGRect(x: -1, y: -1, width: 2, height: 2)], RGBA("#FFBBF7D0"), opacity: 1),
    ]
    static let web = ScenePixels([
        "w..w...w..w",
        ".w.w..w..w.",
        "..wwwwwww..",
        "ww.w.w..w..",
        "..w..ww.w..",
        ".w..w..ww..",
        "w..w...w.w.",
        "..w...w..w.",
        ".w...w....w",
        "w...w......",
    ], px: 2, colors: ["w": "#59E9D5FF"])
    static let spider = ScenePixels(["w..kk..w", ".wkkkkw.", "wkrkkrkw", ".wkkkkw.", "w.w..w.w"], px: 1.5, colors: [
        "k": "#FF1C1326", "w": "#FF9F86C0", "r": "#FFF87171",
    ])
    static let batColors: [Character: String] = ["b": "#FF7353A0", "r": "#FFF87171"]
    static let batUp = ScenePixels(["b.........b", "bb..b.b..bb", ".bbbrbrbbb.", "....bbb...."], px: px, colors: batColors)
    static let batDown = ScenePixels(["....b.b....", "..bbrbrbb..", ".bbbbbbbbb.", "bb.......bb"], px: px, colors: batColors)
    /// The ghost's body with its hem in two frames.
    static let ghost = [["ww.www.www.", "w...w...w.."], [".www.www.ww", "..w...w...w"]].map { hem in
        ScenePixels([
            "...wwwww...", ".wwwwwwwww.", "wwwwwwwwwww", "wwkkwwwkkww", "wwkkwwwkkww", "wwwwwwwwwww",
            "wwwwwkwwwww", "wwwwkkkwwww", "wwwwwkwwwww", "wwwwwwwwwww", "wwwwwwwwwww",
        ] + hem, px: 2, colors: ["w": "#FFF5F3FF", "k": "#FF1C1326"])
    }

    static let moon = ScenePixels([
        "...mmmmm...",
        "..mmmmmmm..",
        ".mmmmmmcmm.",
        "mmccmmmmmmm",
        "mmccmmmmmmm",
        "mmmmmmmmccm",
        "mmmmmmmmccm",
        ".mmmcmmmmm.",
        "..mmmmmmm..",
        "...mmmmm...",
    ], px: px, colors: ["m": "#FFFDE68A", "c": "#FFF5C66B"])
    static let tree = ScenePixels([
        ".t.....t....",
        "..t...t..t..",
        "t..t.t..t...",
        ".t..tt.t....",
        "..t.tttt....",
        "...ttt......",
        "....tt......",
        "....tt......",
        "....tt......",
        "...tttt.....",
    ], px: px, colors: ["t": "#FF5B4A66"])
    static let tombColors: [Character: String] = ["s": "#FF6B6478", "d": "#FF453E52"]
    static let moonAt = CGPoint(x: (PlayArea.skySize.width * 0.46).rounded(.toNearestOrEven), y: 3)
    static let moonGlow = RGBA("#FDBA74")
    static let moonGlowRect = CGRect(x: moonAt.x + 5.5 * px - 22, y: moonAt.y + 5.5 * px - 22, width: 44, height: 44)
    static let pumpkinGlow = RGBA("#FB923C")

    /// The moon, the dead tree, two tombstones and the cross, which never move: each stone by its place across the row
    /// and its height in pixels.
    static let graveyard: [DrawOp] = {
        let sw = PlayArea.skySize.width
        let stones: [(art: ScenePixels, fx: Double, rows: Double)] = [
            (ScenePixels(["..sss..", ".sssss.", "sssdsss", "ssdddss", "sssdsss", "sssdsss", "sssssss", "sssssss"], px: px, colors: tombColors), 0.31, 8),
            (ScenePixels(["..c..", "ccccc", "..c..", "..c..", "..c..", "..c.."], px: px, colors: ["c": "#FF6B6478"]), 0.38, 6),
            (ScenePixels([".sssss.", "sssssss", "sdsdsds", "sssssss", "sssssss"], px: px, colors: tombColors), 0.66, 5),
        ]
        return moon.ops(at: moonAt) + tree.ops(at: CGPoint(x: (sw * 0.13).rounded(.toNearestOrEven), y: floor + px - 10 * px))
            + stones.flatMap { $0.art.ops(at: CGPoint(x: (sw * $0.fx).rounded(.toNearestOrEven), y: floor + px - $0.rows * px)) }
    }()
    static let pumpkinArt = ["....g....", ".ooogooo.", "oyyoooyyo", "ooyoooyoo", "ooooooooo", "oyoyyyoyo", ".oyyyyyo."]
    static let pumpkin = ScenePixels(pumpkinArt, px: px, colors: ["o": "#FFEA580C", "g": "#FF4D7C0F"])
    static let pumpkinDark = ScenePixels(pumpkinArt, px: px, colors: ["y": "#FF7C2D12"])
    static let pumpkinFace = ScenePixels(pumpkinArt, px: px, colors: ["y": "#FFFDE047"])

    static let facePx = 6.0
    static let faceArt = [
        "rrr................rrr",
        "rrrrr............rrrrr",
        "rryyrr..........rryyrr",
        "rryyrr..........rryyrr",
        "rryyrr..........rryyrr",
        ".rrrr............rrrr.",
        "......................",
        "......................",
        "m....................m",
        "mm..................mm",
        ".mmwmmwmmwmmwmmwmmwmm.",
        "..mmmmmmmmmmmmmmmmmm..",
        "....mmwmmwmmwmmwmm....",
        ".......mmmmmmmm.......",
    ]
    static let faceSize = CGSize(width: 22 * facePx, height: 14 * facePx)
    static let faceGlows = [3.0, 19].map { x in
        glow("#DC2626", 0.6, in: CGRect(x: x * facePx - 35, y: 3 * facePx - 35, width: 70, height: 70))
    }
    static let faceMouth = ScenePixels(faceArt, px: facePx, colors: ["m": "#FFEA580C", "w": "#FF07040B"]).ops(at: .zero)
    static let faceEyes = ScenePixels(faceArt, px: facePx, colors: ["r": "#FFDC2626", "y": "#FFFEF08A"]).ops(at: .zero)
}
