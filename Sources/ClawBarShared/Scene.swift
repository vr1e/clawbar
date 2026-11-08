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
    /// Cyberpunk's 20:77 malfunction.
    case relic

    public var scene: SceneID {
        switch self {
        case .scare: .halloween
        case .relic: .cyberpunk
        }
    }
}

/// What a scene asks of Clawd, which `AnimationEngine` carries out in the same tick.
public enum SceneCue: Sendable, Hashable {
    /// Starts the act unless he is busy with one, lying dead or buried.
    case act(ClawdAct)
    /// Forces him awake while his data mood is sleep and nothing else forces one.
    case wake
    /// Lets him sleep again, unless his mood was set by hand since `wake`.
    case letSleep
    /// Puts the Netrunner skin on him, or his own back, without saving it.
    case jack(Bool)
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
    /// The language a secret's text is in.
    public var lang: Lang
    /// Clawd shows and his data mood is sleep, which the 20:77 secret waits for.
    public var clawdAsleep: Bool

    public init(now: Date, timeZone: TimeZone, size: CGSize, skyRow: CGRect?, lang: Lang = .en, clawdAsleep: Bool = false) {
        self.now = now
        self.timeZone = timeZone
        self.size = size
        self.skyRow = skyRow
        self.lang = lang
        self.clawdAsleep = clawdAsleep
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
    /// The 20:77 secret's error box over the overlay, while it shows.
    public var errorBox: SceneErrorBox?
    /// The 20:77 secret scrambling the card's texts and bars, while it does.
    public var haywire: SceneHaywire?

    public init(
        overlay: [DrawOp], skyOpacity: Double = 1, cues: [SceneCue] = [], errorBox: SceneErrorBox? = nil, haywire: SceneHaywire? = nil
    ) {
        self.overlay = overlay
        self.skyOpacity = skyOpacity
        self.cues = cues
        self.errorBox = errorBox
        self.haywire = haywire
    }
}

/// cyberpunk.ps1's RelicBox: a header and a quote typing itself, in a red-rimmed box.
public struct SceneErrorBox: Sendable, Hashable {
    /// Its top-left in the backdrop.
    public var origin: CGPoint
    public var width: Double
    public var header: String
    /// The quote typed so far, with its cursor while it types.
    public var quote: String
    /// How far the quote's red and cyan copies sit off the white one, jittering.
    public var redShift: Double
    public var cyanShift: Double

    public init(origin: CGPoint, width: Double, header: String, quote: String, redShift: Double, cyanShift: Double) {
        self.origin = origin
        self.width = width
        self.header = header
        self.quote = quote
        self.redShift = redShift
        self.cyanShift = cyanShift
    }
}

/// How hard the card goes haywire: the app scrambles the presented view state with a generator on `seed`, so the same
/// value gives the same scramble.
public struct SceneHaywire: Sendable, Hashable {
    /// The chance that a character other than a digit or a space turns to junk.
    public var strength: Double
    public var seed: UInt64

    public init(strength: Double, seed: UInt64) {
        self.strength = strength
        self.seed = seed
    }
}
