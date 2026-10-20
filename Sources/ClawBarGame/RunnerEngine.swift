import CoreGraphics
import Foundation
import ClawBarShared

/// Clawd Run: the Chrome dinosaur's game with Clawd, for while the session limit is used up.
/// Advances one fixed tick per `step`; randomness is injected, so a seed replays a round exactly.
public final class RunnerEngine {
    typealias T = RunnerTuning

    enum Kind {
        case cactusSmall, cactusLarge, bug

        var sprite: Sprite {
            switch self {
            case .cactusSmall: RunnerArt.cactusSmall
            case .cactusLarge: RunnerArt.cactusLarge
            case .bug: RunnerArt.bugA
            }
        }

        /// The least room after one, before the speed widens it.
        var minGap: Double { self == .bug ? 150 : 120 }
    }

    struct Obstacle: Equatable {
        var kind: Kind
        /// Cacti stand in groups of one to three.
        var count: Int
        var x: Double
        /// The bottom edge, from the top; cacti stand on the ground line.
        var bottom: Double
        /// The room left after this one before the next appears.
        var gap: Double

        var width: Double { kind.sprite.width * Double(count) }
    }

    /// The bottoms of a bug's three heights: jump the low one, duck or jump the middle one, run under the high one.
    static let bugBottoms = [T.groundY - 3, T.groundY - 24, T.groundY - 48]

    private let random: RandomSource
    public private(set) var phase: RunnerPhase = .ready
    public private(set) var highScore: Int
    /// The window is in the background: a running round waits, since it would crash unseen.
    public private(set) var paused = false
    private(set) var speed = T.startSpeed
    /// Units run this round.
    private(set) var distance = 0.0
    /// How far Clawd's feet are above the ground.
    private(set) var lift = 0.0
    /// Units per tick, negative while rising.
    private(set) var velocity = 0.0
    private(set) var ducking = false
    private(set) var obstacles: [Obstacle] = []
    /// Each cloud's top-left.
    private var clouds: [CGPoint] = []
    /// The ground's specks: x, and y below the ground line.
    private var specks: [CGPoint] = []
    private var jumpHeld = false
    private var ticks = 0
    private var overTicks = 0
    private var milestoneLeft = 0

    public init(random: RandomSource, highScore: Int = 0) {
        self.random = random
        self.highScore = highScore
        layOutScenery()
    }

    var score: Int { Int(distance * T.scorePerUnit) }

    var airborne: Bool { lift > 0 || velocity < 0 }

    // MARK: Ticks

    public func step(_ input: RunnerInput) {
        guard !paused else { return }
        let pressed = input.jump && !jumpHeld
        jumpHeld = input.jump
        ticks += 1
        switch phase {
        case .ready:
            ducking = false
            if pressed {
                phase = .running
                velocity = T.jumpVelocity
            }
        case .over:
            overTicks += 1
            if pressed, overTicks >= T.restartDelayTicks { restart() }
        case .running:
            run(input, pressed: pressed)
        }
    }

    // MARK: Rounds

    /// Only a running round pauses: one at the start or after a crash has nothing to lose.
    public func pause() {
        if phase == .running { paused = true }
    }

    public func resume() {
        paused = false
    }

    /// Back to the start with fresh scenery; the high score stays.
    public func newRound() {
        clearCourse()
        phase = .ready
        paused = false
        jumpHeld = false
        ticks = 0
        layOutScenery()
    }

    private func restart() {
        clearCourse()
        phase = .running
    }

    private func clearCourse() {
        speed = T.startSpeed
        distance = 0
        lift = 0
        velocity = 0
        ducking = false
        obstacles = []
        overTicks = 0
        milestoneLeft = 0
    }

    private func layOutScenery() {
        specks = []
        var x = 0.0
        while x < T.width {
            specks.append(CGPoint(x: x, y: 3 + Double(random.nextInt(6))))
            x += 12 + Double(random.nextInt(40))
        }
        clouds = [CGPoint(x: 120, y: 40), CGPoint(x: 380, y: 25)]
    }

    private func run(_ input: RunnerInput, pressed: Bool) {
        if pressed, !airborne, !input.duck { velocity = T.jumpVelocity }
        if airborne {
            // Letting go early ends the rise sooner: a tap hops, a hold leaps.
            if !input.jump, velocity < T.shortJumpVelocity { velocity = T.shortJumpVelocity }
            lift -= velocity
            velocity += T.gravity + (input.duck ? T.dropGravity : 0)
            if lift <= 0 {
                lift = 0
                velocity = 0
            }
        }
        ducking = input.duck && !airborne

        let before = score
        speed = min(T.maxSpeed, speed + T.acceleration)
        distance += speed
        if score / 100 > before / 100 { milestoneLeft = T.milestoneTicks }
        if milestoneLeft > 0 { milestoneLeft -= 1 }

        scroll()
        spawn()
        if hit() {
            phase = .over
            overTicks = 0
            highScore = max(highScore, score)
        }
    }

    private func scroll() {
        for i in obstacles.indices {
            // Bugs fly into the wind a little, like the dinosaur's pterodactyls.
            obstacles[i].x -= speed + (obstacles[i].kind == .bug ? 0.6 : 0)
        }
        obstacles.removeAll { $0.x + $0.width < 0 }
        for i in specks.indices {
            specks[i].x -= speed
            if specks[i].x < -2 { specks[i] = CGPoint(x: specks[i].x + T.width + 4, y: 3 + Double(random.nextInt(6))) }
        }
        for i in clouds.indices { clouds[i].x -= speed * 0.2 }
        clouds.removeAll { $0.x + RunnerArt.cloud.width < 0 }
        if (clouds.last.map { $0.x < T.width - 150 } ?? true), random.nextDouble() < 0.01 {
            clouds.append(CGPoint(x: T.width, y: 15 + Double(random.nextInt(50))))
        }
    }

    /// A new obstacle at the right edge once the last one has left its gap; none for the first stretch.
    private func spawn() {
        guard distance > 400 else { return }
        if let last = obstacles.last, last.x + last.width + last.gap > T.width { return }
        let bug = speed >= T.bugSpeed && random.nextDouble() < 0.25
        let kind: Kind = bug ? .bug : random.nextInt(2) == 0 ? .cactusSmall : .cactusLarge
        let maxGroup = speed < 7.5 ? 1 : speed < 10 ? 2 : 3
        let count = bug ? 1 : 1 + random.nextInt(maxGroup)
        let bottom = bug ? Self.bugBottoms[random.nextInt(Self.bugBottoms.count)] : T.groundY
        var o = Obstacle(kind: kind, count: count, x: T.width, bottom: bottom, gap: 0)
        // The dinosaur's rule: the faster and wider, the more room after it, up to half as much again at random;
        // never less than a full jump needs.
        let gap = max((o.width * speed + kind.minGap * 0.6).rounded(), (speed * T.minGapTicks).rounded())
        o.gap = gap + Double(random.nextInt(Int(gap / 2) + 1))
        obstacles.append(o)
    }

    // MARK: Shapes

    var clawdSprite: Sprite {
        if phase == .over { return RunnerArt.clawdCrashed }
        if phase == .ready || airborne { return RunnerArt.clawdStanding }
        let even = (ticks / 6) % 2 == 0
        if ducking { return even ? RunnerArt.clawdDuckA : RunnerArt.clawdDuckB }
        return even ? RunnerArt.clawdRunA : RunnerArt.clawdRunB
    }

    /// The top-left of a sprite whose lowest drawn row sits on `bottom`.
    private func origin(_ sprite: Sprite, x: Double, bottom: Double) -> CGPoint {
        CGPoint(x: x, y: bottom - sprite.usedHeight)
    }

    func clawdRects(_ value: Character) -> [CGRect] {
        let sprite = clawdSprite
        return sprite.rects(value, at: origin(sprite, x: T.clawdX, bottom: T.groundY - lift))
    }

    func sprite(of o: Obstacle) -> Sprite {
        guard o.kind == .bug else { return o.kind.sprite }
        return (ticks / 10) % 2 == 0 ? RunnerArt.bugA : RunnerArt.bugB
    }

    func rects(of o: Obstacle, _ value: Character = "#") -> [CGRect] {
        let sprite = self.sprite(of: o)
        return (0 ..< o.count).flatMap { i in
            sprite.rects(value, at: origin(sprite, x: o.x + Double(i) * sprite.width, bottom: o.bottom))
        }
    }

    /// Pixel against pixel, each rect shrunk a little, so only a real touch ends the round.
    func hit() -> Bool {
        let clawd = (clawdRects("#") + clawdRects("o")).map { $0.insetBy(dx: T.hitInset, dy: T.hitInset) }
        let box = clawd.reduce(CGRect.null) { $0.union($1) }
        for o in obstacles where o.x < box.maxX && o.x + o.width > box.minX {
            for r in rects(of: o).map({ $0.insetBy(dx: T.hitInset, dy: T.hitInset) }) where r.intersects(box) {
                if clawd.contains(where: { $0.intersects(r) }) { return true }
            }
        }
        return false
    }

    // MARK: Drawing

    /// The scene, back to front: clouds, ground, obstacles, Clawd, then the score and messages.
    /// `caption` goes top left (the reset time); a paused round shows a note in place of the phase's.
    public func frame(lang: Lang, caption: String) -> RunnerFrame {
        var ops: [DrawOp] = []
        func fill(_ rects: [CGRect], _ color: RGBA) {
            ops.append(.rects(rects, color, opacity: 1))
        }
        func text(_ s: String, x: Double, y: Double, size: Double, weight: FontWeight = .regular, color: RGBA, anchor: TextAnchor) {
            ops.append(.text(s, at: CGPoint(x: x, y: y), size: size, weight: weight, color: color, opacity: 1, anchor: anchor))
        }
        func message(_ key: L10nKey, y: Double, size: Double = 13, weight: FontWeight = .regular, color: RGBA = Palette.secondary) {
            text(L10n.t(key, lang), x: T.width / 2, y: y, size: size, weight: weight, color: color, anchor: .top)
        }

        fill(clouds.flatMap { RunnerArt.cloud.rects("#", at: $0) }, Palette.runnerCloud)
        let ground = [CGRect(x: 0, y: T.groundY, width: T.width, height: 1)]
            + specks.map { CGRect(x: $0.x, y: T.groundY + $0.y, width: 2, height: 1) }
        fill(ground, Palette.runnerGround)
        let bugs = obstacles.filter { $0.kind == .bug }
        fill(obstacles.filter { $0.kind != .bug }.flatMap { rects(of: $0) }, Palette.runnerCactus)
        fill(bugs.flatMap { rects(of: $0) }, Palette.runnerBug)
        fill(bugs.flatMap { rects(of: $0, "o") }, Palette.clawdEyes)
        fill(clawdRects("#"), Palette.clawdBody)
        fill(clawdRects("o"), Palette.clawdEyes)

        // The score blinks for a moment at every hundred, like the dinosaur's.
        let blinkOff = milestoneLeft > 0 && (milestoneLeft / 8) % 2 == 1
        var hud = highScore > 0 ? "HI \(Self.digits(highScore))  " : ""
        hud += blinkOff ? "     " : Self.digits(score)
        text(hud, x: T.width - 12, y: 8, size: 12, weight: .semibold, color: Palette.secondary, anchor: .topTrailing)
        text(caption, x: 12, y: 8, size: 10, color: Palette.muted, anchor: .topLeading)
        text(L10n.t(.gameHint, lang), x: 12, y: T.groundY + 9, size: 9, color: Palette.footer, anchor: .topLeading)

        if paused {
            message(.gamePaused, y: 44)
        } else {
            switch phase {
            case .ready: message(.gameStart, y: 44)
            case .over:
                message(.gameOver, y: 36, size: 16, weight: .semibold)
                if overTicks >= T.restartDelayTicks { message(.gameRestart, y: 62, size: 11, color: Palette.muted) }
            case .running: break
            }
        }
        return RunnerFrame(ops: ops)
    }

    /// Five digits, zero-padded, like the dinosaur's counter.
    static func digits(_ n: Int) -> String {
        String(format: "%05ld", min(n, 99_999))
    }

    // MARK: Demo

    /// What a fair player presses now: jump what comes into reach and hold the rise, duck under a middle bug,
    /// run under a high one. Drives the snapshots, and shows in tests that every course can be cleared.
    public var demoInput: RunnerInput {
        if airborne { return RunnerInput(jump: velocity < 0) }
        let clawdRight = T.clawdX + RunnerArt.clawdStanding.width
        guard let next = obstacles.first(where: { $0.x + $0.width > T.clawdX }) else { return RunnerInput() }
        guard next.x - clawdRight < speed * 6 else { return RunnerInput() }
        if next.kind == .bug {
            if next.bottom == Self.bugBottoms[2] { return RunnerInput() }
            if next.bottom == Self.bugBottoms[1] { return RunnerInput(duck: true) }
        }
        return RunnerInput(jump: true)
    }

    // MARK: Tests

    /// Puts an obstacle on the course, for tests that need one at a known place.
    func place(_ kind: Kind, x: Double, bottom: Double = RunnerTuning.groundY, count: Int = 1) {
        obstacles.append(Obstacle(kind: kind, count: count, x: x, bottom: bottom, gap: T.width))
    }
}
