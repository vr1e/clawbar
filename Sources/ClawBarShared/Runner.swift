import CoreGraphics

/// Where a round of Clawd Run is.
public enum RunnerPhase: String, Sendable, CaseIterable {
    /// Clawd stands at the start until the first jump.
    case ready
    case running
    /// Clawd hit something; a jump after `RunnerTuning.restartDelayTicks` starts again.
    case over
}

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
    public var ops: [DrawOp]
    public var phase: RunnerPhase
    public var score: Int
    public var highScore: Int

    public init(ops: [DrawOp], phase: RunnerPhase, score: Int, highScore: Int) {
        self.ops = ops
        self.phase = phase
        self.score = score
        self.highScore = highScore
    }

    public static let empty = RunnerFrame(ops: [], phase: .ready, score: 0, highScore: 0)
}

/// Clawd Run's numbers, after the Chrome dinosaur's at 60 ticks a second. Speeds are units per tick.
public enum RunnerTuning {
    public static let width = 600.0
    public static let height = 150.0
    /// The ground line, from the top.
    public static let groundY = 127.0
    public static let ticksPerSecond = 60.0
    /// The size of one sprite pixel.
    public static let px = 3.0
    /// Clawd's left edge.
    public static let clawdX = 40.0

    public static let startSpeed = 6.0
    public static let maxSpeed = 13.0
    public static let acceleration = 0.001
    public static let gravity = 0.6
    public static let jumpVelocity = -10.0
    /// Letting go of jump early cuts the rise to this, so a tap hops lower than a hold.
    public static let shortJumpVelocity = -5.0
    /// Extra pull while ↓ is held in the air.
    public static let dropGravity = 1.8
    /// Score points per unit run.
    public static let scorePerUnit = 0.025
    /// Flying bugs appear from this speed on.
    public static let bugSpeed = 8.5
    /// Half a second after a crash before a jump restarts, so a mashed key does not skip the score.
    public static let restartDelayTicks = 30
    /// The score blinks for this long every 100 points.
    public static let milestoneTicks = 45
    /// Shrinks every hit rect by this much on each side, so a graze is forgiven; under half a pixel, or rows vanish.
    public static let hitInset = 1.0
    /// The least room after an obstacle in ticks of running: a held jump's airtime and a little more,
    /// so landing never comes too late to jump the next one.
    public static let minGapTicks = 36.0
}

extension Palette {
    public static let runnerCloud = RGBA("#FF2E2E35")
    public static let runnerGround = RGBA("#FF6B7280")
    public static let runnerCactus = RGBA("#FF8B8B94")
    public static let runnerBug = RGBA("#FFA78BFA")
}
