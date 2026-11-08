import CoreGraphics
import Foundation

/// A theme's scene, as theme.ps1's `scene` names it. Upstream's Underwater, Halloween and Cyberpunk scenes are not
/// ported yet.
public enum SceneID: String, Sendable, CaseIterable {
    case christmas, space
}

/// What one scene step sees, in base units.
public struct SceneInputs: Sendable, Hashable {
    /// The animation tick's clock, which sets the scene's own pace.
    public var now: Date
    /// The card inside its border: the backdrop's size.
    public var size: CGSize
    /// The sky row shows; hidden, the scene's sky layer waits where it was, as upstream's returns early.
    public var skyVisible: Bool

    public init(now: Date, size: CGSize, skyVisible: Bool) {
        self.now = now
        self.size = size
        self.skyVisible = skyVisible
    }
}

/// Everything one scene step drew, each layer in the original's z-order.
public struct SceneFrame: Sendable, Equatable {
    /// Over the pattern and under the content, from the card's top-left inside its border.
    public var backdrop: [DrawOp]
    /// The sky row's layer in the weather's place, from the row's top-left.
    public var sky: [DrawOp]

    public init(backdrop: [DrawOp], sky: [DrawOp]) {
        self.backdrop = backdrop
        self.sky = sky
    }

    public static let empty = SceneFrame(backdrop: [], sky: [])
}
