import CoreGraphics
import Foundation
import ClawBarShared

/// scene.ps1: the theme's scene, stepped on one counter at a steady pace. A scene is built the first time its theme
/// shows and kept, so switching back resumes it, as upstream's built-at-startup scenes do.
public final class SceneEngine {
    /// A scene's pace, whatever the animation tick's: upstream's speeds up during a Claude Code sequence.
    public static let stepMilliseconds = 90

    private struct Pace {
        var last: Date
        /// Time owed to the scene, in milliseconds, kept within half a step either way.
        var carry: Double
    }

    private let random: any RandomSource
    private var built: [SceneID: any ThemeScene] = [:]
    private var tick = 0
    private var pace: Pace?

    public init(random: any RandomSource) {
        self.random = random
    }

    /// One step of the scene, or nil while none is due; a size of zero draws nothing, as upstream's guard returns.
    public func step(_ id: SceneID, inputs: SceneInputs) -> SceneFrame? {
        guard due(inputs.now) else { return nil }
        tick += 1
        let scene = built[id] ?? Self.make(id, random: random)
        built[id] = scene
        guard inputs.size.width > 0, inputs.size.height > 0 else { return .empty }
        let backdrop = scene.backdrop(tick: tick, inputs: inputs, random: random)
        // Hidden, the sky layer waits where it was, as upstream's returns early.
        let sky = inputs.skyVisible ? scene.sky(tick: tick, inputs: inputs, random: random) : []
        return SceneFrame(backdrop: backdrop, sky: sky)
    }

    /// At most one step a tick, due once half a step has built up, so a timer that fires a little early never skips
    /// one. The capped carry keeps a late tick from being made up later, and after a gap the scene simply goes on.
    private func due(_ now: Date) -> Bool {
        let step = Double(Self.stepMilliseconds)
        guard let pace, case let elapsed = now.timeIntervalSince(pace.last) * 1000, (0 ... 2 * step).contains(elapsed) else {
            pace = Pace(last: now, carry: 0)
            return true
        }
        var carry = pace.carry + elapsed
        let due = carry >= step / 2
        if due { carry -= step }
        self.pace = Pace(last: now, carry: min(max(carry, -step / 2), step / 2))
        return due
    }

    private static func make(_ id: SceneID, random: any RandomSource) -> any ThemeScene {
        switch id {
        case .christmas: ChristmasScene(random: random)
        case .space: SpaceScene(random: random)
        }
    }
}

/// One scene's state and its two layers' steps; a class, so stepping never copies its arrays.
protocol ThemeScene: AnyObject {
    /// The layer over the card, which always moves.
    func backdrop(tick t: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp]
    /// The sky row's layer, stepped only while the row shows.
    func sky(tick t: Int, inputs: SceneInputs, random: any RandomSource) -> [DrawOp]
}

/// scene.ps1's New-ScenePixels: pixel art, one layer per colour letter, drawn from its top-left.
struct ScenePixels: Sendable {
    struct Layer: Sendable {
        var color: RGBA
        var rects: [CGRect]
    }

    let layers: [Layer]

    init(layers: [Layer]) {
        self.layers = layers
    }

    /// '.' and letters missing from `colors` are empty; layers in letter order, as no two pixels overlap.
    init(_ art: [String], px: Double, colors: [Character: String]) {
        layers = colors.sorted { $0.key < $1.key }.map { letter, hex in
            Layer(color: RGBA(hex), rects: PixelArt.rects(art, value: letter, px: px, py: px))
        }
    }

    /// The art at `p`; fading each layer looks like upstream's fading the whole canvas, since none overlap.
    func ops(at p: CGPoint, opacity: Double = 1) -> [DrawOp] {
        layers.map { .rects($0.rects.map { $0.offsetBy(dx: p.x, dy: p.y) }, $0.color, opacity: opacity) }
    }
}

/// scene.ps1's New-Glow in an ellipse of `rect`: the colour at alpha `a` in the middle, fading out to its edge.
func glow(_ hex: String, _ a: Double, in rect: CGRect, opacity: Double = 1) -> DrawOp {
    glow(RGBA(hex), a, in: rect, opacity: opacity)
}

func glow(_ c: RGBA, _ a: Double, in rect: CGRect, opacity: Double = 1) -> DrawOp {
    .radialGlow(rect, inner: c.withAlpha(RGBA.byte(255 * a)), outer: c.withAlpha(0), opacity: opacity)
}
