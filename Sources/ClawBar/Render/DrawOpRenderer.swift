import CoreGraphics
import SwiftUI
import ClawBarShared

/// WPF's line box for Segoe UI, in ems: (ascent + descent) / unitsPerEm and ascent / unitsPerEm.
enum WPFLineBox {
    static let height = 2724.0 / 2048
    static let baseline = 2210.0 / 2048

    /// The top-left of the line box a text anchor names; `width` is the measured text width.
    static func topLeft(anchor: TextAnchor, at p: CGPoint, size: Double, width: Double) -> CGPoint {
        switch anchor {
        case .topLeading: p
        case .bottomLeading: CGPoint(x: p.x, y: p.y - height * size)
        case .bottom: CGPoint(x: p.x - width / 2, y: p.y - height * size)
        case .topTrailing: CGPoint(x: p.x - width, y: p.y)
        case .top: CGPoint(x: p.x - width / 2, y: p.y)
        }
    }
}

extension FontWeight {
    var swiftUI: Font.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// Paints the engines' DrawOps into a GraphicsContext already scaled to base units.
enum DrawOpRenderer {
    /// The ops worth drawing, with consecutive opaque rect layers of one colour folded into one Path.
    /// Translucent layers stay apart: WPF composites each element separately, so overlaps would blend differently.
    static func layers(_ ops: [DrawOp]) -> [DrawOp] {
        var out: [DrawOp] = []
        for op in ops {
            guard let op = visible(op) else { continue }
            if case let .rects(rects, color, opacity) = op, color.a == 255, opacity >= 1,
               case let .rects(previous, previousColor, previousOpacity)? = out.last,
               previousColor == color, previousOpacity >= 1 {
                out[out.count - 1] = .rects(previous + rects, color, opacity: previousOpacity)
            } else {
                out.append(op)
            }
        }
        return out
    }

    /// nil when the op would leave no mark; rect lists lose their empty rects.
    private static func visible(_ op: DrawOp) -> DrawOp? {
        switch op {
        case let .rects(rects, color, opacity):
            let kept = rects.filter { $0.width > 0 && $0.height > 0 }
            return kept.isEmpty || color.a == 0 || opacity <= 0 ? nil : .rects(kept, color, opacity: opacity)
        case let .text(s, _, size, _, color, opacity, _):
            return s.isEmpty || size <= 0 || color.a == 0 || opacity <= 0 ? nil : op
        case let .radialGlow(rect, inner, outer, opacity):
            return rect.isEmpty || opacity <= 0 || (inner.a == 0 && outer.a == 0) ? nil : op
        case let .hGradient(rect, stops, opacity):
            return rect.isEmpty || opacity <= 0 || !stops.contains(where: { $0.color.a > 0 }) ? nil : op
        }
    }

    /// Clawd's ops on either side of the developer caption, where the engine placed it.
    static func captionSplit(_ frame: ClawdFrame) -> (below: [DrawOp], above: [DrawOp]) {
        let i = min(frame.ops.count, max(0, frame.captionIndex ?? frame.ops.count))
        return (Array(frame.ops[..<i]), Array(frame.ops[i...]))
    }

    static func draw(_ layers: [DrawOp], in ctx: inout GraphicsContext) {
        for op in layers {
            switch op {
            case let .rects(rects, color, opacity):
                var path = Path()
                path.addRects(rects)
                // One fill of one path, so the opacity can ride on the colour.
                ctx.fill(path, with: .color(Color(rgba: color).opacity(opacity)))
            case let .text(s, at, size, weight, color, opacity, anchor):
                drawText(s, at: at, size: size, weight: weight, color: color, opacity: opacity, anchor: anchor, in: ctx)
            case let .radialGlow(rect, inner, outer, opacity):
                var g = ctx
                g.opacity *= opacity
                // A unit circle stretched to the rect, like WPF's RadialGradientBrush on its bounding box.
                g.translateBy(x: rect.midX, y: rect.midY)
                g.scaleBy(x: rect.width / 2, y: rect.height / 2)
                g.fill(
                    Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color(rgba: inner), Color(rgba: outer)]), center: .zero, startRadius: 0, endRadius: 1
                    )
                )
            case let .hGradient(rect, stops, opacity):
                var g = ctx
                g.opacity *= opacity
                let gradient = Gradient(stops: stops.map { .init(color: Color(rgba: $0.color), location: $0.location) })
                g.fill(
                    Path(rect),
                    with: .linearGradient(gradient, startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY))
                )
            }
        }
    }

    /// Places SF so its baseline sits where Segoe UI's would in the same WPF line box.
    static func drawText(
        _ s: String, at p: CGPoint, size: Double, weight: FontWeight, color: RGBA, opacity: Double, anchor: TextAnchor,
        in ctx: GraphicsContext
    ) {
        var t = ctx
        t.opacity *= opacity
        let resolved = t.resolve(Text(s).font(.system(size: size, weight: weight.swiftUI)).foregroundColor(Color(rgba: color)))
        let measured = resolved.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        let box = WPFLineBox.topLeft(anchor: anchor, at: p, size: size, width: measured.width)
        let baseline = box.y + WPFLineBox.baseline * size
        t.draw(resolved, at: CGPoint(x: box.x, y: baseline - resolved.firstBaseline(in: measured)), anchor: .topLeading)
    }
}
