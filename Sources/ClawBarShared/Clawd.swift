import CoreGraphics
import Foundation

public enum Mood: String, Sendable, CaseIterable {
    case sleep, doze, idle, work, wait, dead
}

/// Every act, in the original's order (the Animation menu and the demo).
public enum ClawdAct: String, Sendable, CaseIterable {
    case jump, look, celebrate, skip, spin, peekaboo, drop, waddle, peek, wink, boop, tap, sneeze, turn
    case coinHop = "coin-hop"
    case wave, stretch, yawn, stumble, soul, burrow, unburrow, stir
}

/// What the data layer tells Clawd on every refresh.
public struct ClawdDataInput: Sendable, Hashable {
    public var busy: Int
    public var waiting: Int
    public var sessionCount: Int
    /// Which limit he follows; a switch starts his reset and heart memory over.
    public var limit: MainLimit
    /// The main limit's percentage, nil without data.
    public var pct: Int?
    public var reset: Date?
    public var critPercent: Int

    public init(
        busy: Int, waiting: Int, sessionCount: Int, limit: MainLimit = .session, pct: Int?, reset: Date?, critPercent: Int
    ) {
        self.busy = busy
        self.waiting = waiting
        self.sessionCount = sessionCount
        self.limit = limit
        self.pct = pct
        self.reset = reset
        self.critPercent = critPercent
    }

    /// What a snapshot tells Clawd: the sessions by state and the main limit.
    public init(_ s: DataSnapshot, mainLimit: MainLimit, critPercent: Int) {
        let main = mainLimit.of(s.usage)
        self.init(
            busy: s.count(of: .busy), waiting: s.count(of: .waiting), sessionCount: s.sessions.count,
            limit: mainLimit, pct: main.percent, reset: main.reset, critPercent: critPercent
        )
    }
}

/// What Clawd's part of an animation tick sees. Sizes are base units (before the global scale).
public struct ClawdStepEnv: Sendable, Hashable {
    /// The play area's width, `PlayArea.width(numberWidth:)`: what the number leaves of the row.
    public var areaWidth: Double
    /// The pointer is over the widget window, even when another window covers it partly.
    public var mouseOverWindow: Bool
    /// The pointer's x in play-area coordinates, when over the window.
    public var mouseX: Double?
    public var now: Date
    public var lang: Lang

    public init(areaWidth: Double, mouseOverWindow: Bool, mouseX: Double?, now: Date, lang: Lang) {
        self.areaWidth = areaWidth
        self.mouseOverWindow = mouseOverWindow
        self.mouseX = mouseX
        self.now = now
        self.lang = lang
    }
}

/// The three header hearts.
public struct HeartsFrame: Sendable, Hashable {
    public var visible: Bool
    /// Halves to draw, 0...6 (the old value while a lost heart blinks).
    public var shownHalves: Int
    /// Heartbeat scale around each heart's centre: 1.3, 1.15 or 1.0.
    public var beatScale: Double
    public var tooltip: String

    public init(visible: Bool, shownHalves: Int, beatScale: Double = 1.0, tooltip: String = "") {
        self.visible = visible
        self.shownHalves = shownHalves
        self.beatScale = beatScale
        self.tooltip = tooltip
    }

    public static let hidden = HeartsFrame(visible: false, shownHalves: 0)
}

/// Everything Clawd draws in one tick.
public struct ClawdFrame: Sendable, Equatable {
    /// x from the play area's left edge, y DOWN from the ground line (above ground is negative),
    /// in the original's child order: body, eyes, fx, sand, sweat, z, bubble, love, soul, confetti, dust.
    public var ops: [DrawOp]
    /// The sprite box (36 × 26.4) in the same coordinates: clicks here go to Clawd.
    public var spriteRect: CGRect
    /// The developer caption for the play area's top-left; empty outside developer mode.
    public var devCaption: String
    /// The caption's place in the z-order: drawn before `ops[captionIndex]`; nil draws it last.
    public var captionIndex: Int?
    public var hearts: HeartsFrame

    public init(
        ops: [DrawOp], spriteRect: CGRect, devCaption: String = "", captionIndex: Int? = nil, hearts: HeartsFrame = .hidden
    ) {
        self.ops = ops
        self.spriteRect = spriteRect
        self.devCaption = devCaption
        self.captionIndex = captionIndex
        self.hearts = hearts
    }

    public static let empty = ClawdFrame(ops: [], spriteRect: .zero)
}

/// Developer-mode overrides of Clawd, for the menu's check marks.
public struct ClawdDevState: Sendable, Hashable {
    public var forcedMood: Mood?
    public var forceCrit: Bool
    /// 0...6 halves, nil = from the limit.
    public var forceHearts: Int?
    public var demoRunning: Bool
    public var drainRunning: Bool

    public init(
        forcedMood: Mood? = nil, forceCrit: Bool = false, forceHearts: Int? = nil,
        demoRunning: Bool = false, drainRunning: Bool = false
    ) {
        self.forcedMood = forcedMood
        self.forceCrit = forceCrit
        self.forceHearts = forceHearts
        self.demoRunning = demoRunning
        self.drainRunning = drainRunning
    }

    /// "Auto (live data)" is checked.
    public var isAuto: Bool { forcedMood == nil && !forceCrit && forceHearts == nil && !demoRunning }
}
