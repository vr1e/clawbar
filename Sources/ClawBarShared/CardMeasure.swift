import CoreGraphics
import Foundation

/// What the card measured of itself, for the card engine: points in card space at `scale`, zero before the first layout.
public struct CardMeasure: Sendable, Hashable {
    /// The card's rim; a scene's backdrop lies inside it.
    public static let border = 1.0
    /// The content's left inset: the padding and the rim.
    public static let inset = 13.0

    /// The number with its `%`, in base units.
    public var numberWidth: Double
    public var cardSize: CGSize
    public var percentRow: CGRect?
    public var scale: Double

    public init(numberWidth: Double, cardSize: CGSize = .zero, percentRow: CGRect? = nil, scale: Double = 1) {
        self.numberWidth = numberWidth
        self.cardSize = cardSize
        self.percentRow = percentRow
        self.scale = scale
    }

    /// What a scene's backdrop covers, in base units: the card inside its rim.
    public var backdropSize: CGSize {
        guard cardSize.width > 0, cardSize.height > 0 else { return .zero }
        let inset = 2 * Self.border
        return CGSize(width: cardSize.width / scale - inset, height: cardSize.height / scale - inset)
    }

    /// The sky row's top-left in the backdrop, in base units: the percent row's, inside the rim.
    public var skyOrigin: CGPoint {
        guard let row = percentRow else { return .zero }
        return CGPoint(x: row.minX / scale - Self.border, y: row.minY / scale - Self.border)
    }

    /// A pointer's x in play-area coordinates, from its x in card space.
    public func mouseX(cardX: Double) -> Double {
        // The engine needs x whenever the pointer is over the window; before the first layout the row sits at the inset.
        let row = percentRow ?? CGRect(x: Self.inset * scale, y: 0, width: PlayArea.content * scale, height: 40 * scale)
        return PlayArea.mouseX(cardX: cardX, row: row, numberWidth: numberWidth, scale: scale)
    }
}
