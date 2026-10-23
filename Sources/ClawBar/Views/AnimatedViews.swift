import SwiftUI
import ClawBarShared

/// Clawd's layer: a 262 × 59 surface whose ground line is 53 down, the play area starting right of the number.
struct MascotView: View {
    let animation: AnimationModel
    let layout: LayoutModel
    /// The developer caption is text, so it takes the label's role while Clawd keeps his colours.
    let captionColor: RGBA
    /// How far the surface reaches above the percent row; confetti spawns up to 46 above the ground.
    static let top = 10.0
    /// 10 above the row, the play area down to the ground, and 6 below it for the hanging sprite box.
    static let height = top + PlayArea.height + 6

    @Environment(\.uiScale) private var k

    var body: some View {
        let frame = animation.clawd
        let split = DrawOpRenderer.captionSplit(frame)
        let below = DrawOpRenderer.layers(split.below)
        let above = DrawOpRenderer.layers(split.above)
        let caption = frame.devCaption
        // The play area's left edge: the card's 13 of padding and border, the number, then MascotArea's margin 10.
        let origin = CGPoint(x: 13 + layout.numberWidth + PlayArea.margin, y: Self.top + PlayArea.height)
        let scale = k
        let captionColor = captionColor
        Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: origin.x, y: origin.y)
            DrawOpRenderer.draw(below, in: &ctx)
            if !caption.isEmpty {
                // MascotTag at the play area's top-left, 8 pt, between the soul and the confetti.
                DrawOpRenderer.drawText(
                    caption, at: CGPoint(x: 0, y: -PlayArea.height), size: 8, weight: .regular, color: captionColor, opacity: 1,
                    anchor: .topLeading, in: ctx
                )
            }
            DrawOpRenderer.draw(above, in: &ctx)
        }
    }
}

/// The sky behind the percent row: the gradient, then the sprites faded as one layer, then the edge fade.
struct SkyView: View {
    let animation: AnimationModel
    @Environment(\.uiScale) private var k

    var body: some View {
        let frame = animation.sky
        let layers = DrawOpRenderer.layers(frame.ops)
        let scale = k
        ZStack {
            LinearGradient(colors: [Color(rgba: frame.top), Color(rgba: frame.bottom)], startPoint: .top, endPoint: .bottom)
            // A Canvas is one layer, so opacity 0.7 fades the sprites as a group like SkyFx's Opacity.
            Canvas { ctx, _ in
                ctx.scaleBy(x: scale, y: scale)
                DrawOpRenderer.draw(layers, in: &ctx)
            }
            .opacity(0.7)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                    .init(color: .black, location: 0.9), .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .clipped()
    }
}

/// The three header hearts: a grey full heart under a red full, half or no heart, each beating around its centre.
struct HeartsView: View {
    let animation: AnimationModel
    let layout: LayoutModel
    let off: RGBA
    @Environment(\.uiScale) private var k

    var body: some View {
        let h = animation.hearts
        if h.visible {
            HStack(spacing: PixelArt.heartGap * k) {
                ForEach(0 ..< 3, id: \.self) { i in
                    HeartCell(halves: h.shownHalves - 2 * i, beat: h.beatScale, off: off)
                }
            }
            .publish(.hearts, to: layout)
            .padding(.trailing, 12 * k)
        }
    }
}

private struct HeartCell: View {
    let halves: Int
    let beat: Double
    let off: RGBA
    @Environment(\.uiScale) private var k

    static let full = PixelArt.rects(PixelArt.heart, value: "#", px: PixelArt.heartPx, py: PixelArt.heartPx)
    static let half = PixelArt.rects(
        PixelArt.heart, value: "#", px: PixelArt.heartPx, py: PixelArt.heartPx, maxColumn: PixelArt.heartHalfColumns
    )

    var body: some View {
        let front: [CGRect] = halves >= 2 ? Self.full : halves == 1 ? Self.half : []
        let scale = k
        let off = off
        Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            var back = Path()
            back.addRects(Self.full)
            ctx.fill(back, with: .color(Color(rgba: off)))
            guard !front.isEmpty else { return }
            var on = Path()
            on.addRects(front)
            ctx.fill(on, with: .color(Color(rgba: Palette.heartOn)))
        }
        .frame(width: 7 * PixelArt.heartPx * k, height: 6 * PixelArt.heartPx * k)
        // A render transform, like WPF's: the beat never moves the header's layout.
        .scaleEffect(beat)
    }
}
