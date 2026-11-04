import CoreGraphics
import ClawBarShared

/// Clawd standing in a skin, as the original's Settings cards show him.
public enum ClawdPreview {
    /// The frame upstream's skin cards share: the sprite box from his feet up to the highest accessory, at most 12 rows
    /// above his head.
    public static func frame(fitting skins: [Skin]) -> CGRect {
        let highest = skins.flatMap { $0.layers.flatMap(\.pixels) }.map(\.y).min() ?? 0
        let top = -Double(min(12, max(0, -highest))) * ClawdTables.py
        // The grid's two lowest rows stay empty while he stands.
        let feet = Double(ClawdTables.height - 2) * ClawdTables.py
        return CGRect(x: 0, y: top, width: ClawdTables.boxWidth, height: feet - top)
    }

    /// Body, eyes and the skin's accessories, in the 36 × 26.4 sprite box's coordinates; a hat reaches above it.
    public static func standing(in skin: Skin) -> [DrawOp] {
        let geo = ClawdSprite.render(ClawdPose(), skin: skin)
        let layers = [(geo.body, skin.body), (geo.eyes, skin.eyes)] + zip(geo.accessories, skin.layers.map(\.color))
        return layers.filter { !$0.0.isEmpty }.map { .rects($0.0, $0.1, opacity: 1) }
    }
}
