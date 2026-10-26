import CoreGraphics

/// The keys held during one tick. The engine finds the presses itself, so a held key jumps once.
public struct RunnerInput: Sendable, Hashable {
    /// Space, ↑ or a mouse button.
    public var jump: Bool
    /// ↓.
    public var duck: Bool

    public init(jump: Bool = false, duck: Bool = false) {
        self.jump = jump
        self.duck = duck
    }
}

/// Everything Clawd Run draws in one tick, in base units on a `RunnerTuning.width` × `height` canvas, y down.
public struct RunnerFrame: Sendable, Equatable {
    /// Fills the whole window, past the canvas when its shape differs.
    public var background: RGBA
    public var ops: [DrawOp]

    public init(background: RGBA, ops: [DrawOp]) {
        self.background = background
        self.ops = ops
    }

    public static let empty = RunnerFrame(background: ThemePalette.classic.background, ops: [])
}

/// Clawd Run's canvas and clock, which the window needs too; the game's other numbers stay in `ClawBarGame`.
public enum RunnerTuning {
    public static let width = 600.0
    public static let height = 150.0
    public static let ticksPerSecond = 60.0
}
