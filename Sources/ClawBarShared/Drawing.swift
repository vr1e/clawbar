import CoreGraphics
import Foundation

public enum FontWeight: String, Sendable, CaseIterable {
    case light, regular, semibold, bold
}

/// Which point of the text's line box `at` names. The line box is WPF's: 1.33 × the font size tall,
/// so a renderer with another font keeps the original's positions.
public enum TextAnchor: String, Sendable, CaseIterable {
    case topLeading
    case bottomLeading
    /// Bottom centre: the bubble's 12-wide centred box.
    case bottom
    /// Top right: Clawd Run's score.
    case topTrailing
    /// Top centre: Clawd Run's messages.
    case top
}

public struct GradientStop: Sendable, Hashable {
    /// 0...1 across the rect.
    public var location: Double
    public var color: RGBA

    public init(location: Double, color: RGBA) {
        self.location = location
        self.color = color
    }
}

/// One drawing instruction in base units. The engines emit them in the original's z-order.
public enum DrawOp: Sendable, Hashable {
    /// One layer: every rect filled in one colour, then faded by `opacity`.
    case rects([CGRect], RGBA, opacity: Double)
    case text(String, at: CGPoint, size: Double, weight: FontWeight, color: RGBA, opacity: Double, anchor: TextAnchor)
    /// An ellipse inscribed in the rect, `inner` at its centre fading to `outer` at its edge.
    case radialGlow(CGRect, inner: RGBA, outer: RGBA, opacity: Double)
    /// A rect filled with a left-to-right gradient.
    case hGradient(CGRect, stops: [GradientStop], opacity: Double)
    /// A rect filled with a top-to-bottom gradient.
    case vGradient(CGRect, stops: [GradientStop], opacity: Double)
    /// A polyline stroked in one colour, then faded by `opacity`.
    case stroke([CGPoint], RGBA, width: Double, opacity: Double)
    /// An ellipse's outline, stroked inside the rect as WPF's Ellipse, then faded by `opacity`.
    case strokedEllipse(CGRect, RGBA, width: Double, opacity: Double)
    /// A closed polygon filled with a top-to-bottom gradient across its bounding box.
    case polygon([CGPoint], stops: [GradientStop], opacity: Double)
    /// Ops drawn as one layer: placed by the transform, clipped to `clip` in their own space, then faded as a whole,
    /// as WPF fades a canvas, so overlapping children don't show through each other.
    case group([DrawOp], Transform2D, opacity: Double, clip: CGRect?)
}

/// An affine transform, as CGAffineTransform's fields: `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`. Its own type,
/// since CGAffineTransform isn't Hashable.
public struct Transform2D: Sendable, Hashable {
    public var a, b, c, d, tx, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        (self.a, self.b, self.c, self.d, self.tx, self.ty) = (a, b, c, d, tx, ty)
    }

    public static func translation(_ x: Double, _ y: Double) -> Transform2D {
        Transform2D(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    /// A turn by `radians` about the origin; y points down, so a positive turn is clockwise on screen.
    public static func rotation(_ radians: Double) -> Transform2D {
        Transform2D(a: cos(radians), b: sin(radians), c: -sin(radians), d: cos(radians), tx: 0, ty: 0)
    }

    /// WPF's SkewTransform with AngleX `degrees`: each row slides sideways by its height below the origin.
    public static func skewX(degrees: Double) -> Transform2D {
        Transform2D(a: 1, b: 0, c: tan(degrees * .pi / 180), d: 1, tx: 0, ty: 0)
    }

    public static func scale(_ sx: Double, _ sy: Double) -> Transform2D {
        Transform2D(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    /// This transform, then `next`; a WPF render transform then the element's place is `.concatenating(.translation(…))`.
    public func concatenating(_ next: Transform2D) -> Transform2D {
        Transform2D(
            a: next.a * a + next.c * b, b: next.b * a + next.d * b,
            c: next.a * c + next.c * d, d: next.b * c + next.d * d,
            tx: next.a * tx + next.c * ty + next.tx, ty: next.b * tx + next.d * ty + next.ty
        )
    }

    /// This transform about `p` rather than the origin, as WPF's CenterX and CenterY: `p` stays where it is.
    public func about(_ p: CGPoint) -> Transform2D {
        Transform2D.translation(-p.x, -p.y).concatenating(self).concatenating(.translation(p.x, p.y))
    }
}
