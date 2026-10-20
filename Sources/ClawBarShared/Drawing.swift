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

public struct GradientStop: Sendable, Equatable {
    /// 0...1 across the rect.
    public var location: Double
    public var color: RGBA

    public init(location: Double, color: RGBA) {
        self.location = location
        self.color = color
    }
}

/// One drawing instruction in base units. The engines emit them in the original's z-order.
public enum DrawOp: Sendable, Equatable {
    /// One layer: every rect filled in one colour, then faded by `opacity`.
    case rects([CGRect], RGBA, opacity: Double)
    case text(String, at: CGPoint, size: Double, weight: FontWeight, color: RGBA, opacity: Double, anchor: TextAnchor)
    /// An ellipse inscribed in the rect, `inner` at its centre fading to `outer` at its edge.
    case radialGlow(CGRect, inner: RGBA, outer: RGBA, opacity: Double)
    /// A rect filled with a left-to-right gradient.
    case hGradient(CGRect, stops: [GradientStop], opacity: Double)
}
