import CoreGraphics
import Foundation

/// A theme's scene, as theme.ps1's `scene` names it; `ocean` is the Underwater theme's.
public enum SceneID: String, Sendable, CaseIterable {
    case christmas, space, ocean, halloween, cyberpunk
}

/// A scene's rare secret, which snapshot mode and the tests start through `AnimationEngine.play(_:)`.
public enum SceneSecret: Sendable, Hashable {
    /// Halloween's midnight scare.
    case scare

    public var scene: SceneID {
        switch self {
        case .scare: .halloween
        }
    }
}

/// What a scene asks of Clawd, which `AnimationEngine` carries out in the same tick.
public enum SceneCue: Sendable, Hashable {
    /// Starts the act unless he is busy with one, lying dead or buried.
    case act(ClawdAct)
}

/// What one scene step sees, in base units.
public struct SceneInputs: Sendable, Hashable {
    /// The animation tick's clock, which sets the scene's own pace.
    public var now: Date
    /// The zone a secret's minute is read in.
    public var timeZone: TimeZone
    /// The card inside its border: the backdrop's size.
    public var size: CGSize
    /// The sky row in the backdrop, or nil while it is hidden, when the scene's sky layer waits where it was, as
    /// upstream's returns early.
    public var skyRow: CGRect?

    public init(now: Date, timeZone: TimeZone, size: CGSize, skyRow: CGRect?) {
        self.now = now
        self.timeZone = timeZone
        self.size = size
        self.skyRow = skyRow
    }
}

/// Everything one scene step drew, each layer in the original's z-order.
public struct SceneFrame: Sendable, Equatable {
    /// Over the pattern and under the content, from the card's top-left inside its border.
    public var backdrop: [DrawOp]
    /// The sky row's layer in the weather's place, from the row's top-left.
    public var sky: [DrawOp]
    /// The secret playing now, if any.
    public var secret: SceneSecretFrame?

    public init(backdrop: [DrawOp], sky: [DrawOp], secret: SceneSecretFrame? = nil) {
        self.backdrop = backdrop
        self.sky = sky
        self.secret = secret
    }

    public static let empty = SceneFrame(backdrop: [], sky: [])
}

/// A secret's share of a scene step, so ending it is dropping this one value.
public struct SceneSecretFrame: Sendable, Equatable {
    /// Over all the content, Clawd included, from the card's top-left inside its border.
    public var overlay: [DrawOp]
    /// The sky layer's opacity, which Halloween's scare dims.
    public var skyOpacity: Double
    /// What this step asks of Clawd.
    public var cues: [SceneCue]

    public init(overlay: [DrawOp], skyOpacity: Double = 1, cues: [SceneCue] = []) {
        self.overlay = overlay
        self.skyOpacity = skyOpacity
        self.cues = cues
    }
}
