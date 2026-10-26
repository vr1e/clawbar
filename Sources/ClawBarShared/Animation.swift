import CoreGraphics
import Foundation

/// Clawd's play area and the sky behind it, in base units. Both reach 3 below the 40-tall percent row, where the
/// ground line Clawd stands on is; the sky spans the card's content width, the play area starts right of the number.
public enum PlayArea {
    /// The card's content width, which the sky spans.
    public static let content = 236.0
    /// The percent row's 40 plus the 3 it reaches below it: its bottom is the ground line.
    public static let height = 43.0
    /// MascotArea's left margin after the number.
    public static let margin = 10.0
    public static let skySize = CGSize(width: content, height: height)

    /// What the number with its `%` leaves of the row.
    public static func width(numberWidth: Double) -> Double {
        max(0, content - numberWidth - margin)
    }

    /// The play area's left end of the ground line in card space, from the percent row's published rect.
    public static func ground(row: CGRect, numberWidth: Double, scale k: Double) -> CGPoint {
        CGPoint(x: row.minX + (numberWidth + margin) * k, y: row.minY + height * k)
    }

    /// A pointer's x in play-area coordinates, from its x in card space.
    public static func mouseX(cardX: Double, row: CGRect, numberWidth: Double, scale k: Double) -> Double {
        (cardX - ground(row: row, numberWidth: numberWidth, scale: k).x) / k
    }
}

/// What one animation tick sees.
public struct AnimationInputs: Sendable, Hashable {
    public var now: Date
    /// The Mac's zone: the sky's fallback without a weather location.
    public var timeZone: TimeZone
    /// The number with its `%` as the card measured it, in base units; the play area is what it leaves of the row.
    public var numberWidth: Double
    /// The pointer is over the widget window, even when another window covers it partly.
    public var mouseOverWindow: Bool
    /// The pointer's x in play-area coordinates, when over the window.
    public var mouseX: Double?

    public init(now: Date, timeZone: TimeZone, numberWidth: Double, mouseOverWindow: Bool = false, mouseX: Double? = nil) {
        self.now = now
        self.timeZone = timeZone
        self.numberWidth = numberWidth
        self.mouseOverWindow = mouseOverWindow
        self.mouseX = mouseX
    }
}

/// Everything one animation tick drew.
public struct AnimationFrame: Sendable, Equatable {
    /// Clawd with his hearts; empty while he is hidden.
    public var clawd: ClawdFrame
    /// The sky's last frame, kept while the sky is hidden, when no view draws it.
    public var sky: SkyFrame

    public init(clawd: ClawdFrame, sky: SkyFrame) {
        self.clawd = clawd
        self.sky = sky
    }

    public static let empty = AnimationFrame(clawd: .empty, sky: .empty)
}
