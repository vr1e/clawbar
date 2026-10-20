import ClawBarShared

/// Clawd Run's numbers, after the Chrome dinosaur's at 60 ticks a second. Speeds are units per tick.
extension RunnerTuning {
    /// The ground line, from the top.
    static let groundY = 127.0
    /// The size of one sprite pixel.
    static let px = 3.0
    /// Clawd's left edge.
    static let clawdX = 40.0

    static let startSpeed = 6.0
    static let maxSpeed = 13.0
    static let acceleration = 0.001
    static let gravity = 0.6
    static let jumpVelocity = -10.0
    /// Letting go of jump early cuts the rise to this, so a tap hops lower than a hold.
    static let shortJumpVelocity = -5.0
    /// Extra pull while ↓ is held in the air.
    static let dropGravity = 1.8
    /// Score points per unit run.
    static let scorePerUnit = 0.025
    /// Flying bugs appear from this speed on.
    static let bugSpeed = 8.5
    /// Half a second after a crash before a jump restarts, so a mashed key does not skip the score.
    static let restartDelayTicks = 30
    /// The score blinks for this long every 100 points.
    static let milestoneTicks = 45
    /// Shrinks every hit rect by this much on each side, so a graze is forgiven; under half a pixel, or rows vanish.
    static let hitInset = 1.0
    /// The least room after an obstacle in ticks of running: a held jump's airtime and a little more,
    /// so landing never comes too late to jump the next one.
    static let minGapTicks = 36.0
}

extension Palette {
    static let runnerCloud = RGBA("#FF2E2E35")
    static let runnerGround = RGBA("#FF6B7280")
    static let runnerCactus = RGBA("#FF8B8B94")
    static let runnerBug = RGBA("#FFA78BFA")
}
