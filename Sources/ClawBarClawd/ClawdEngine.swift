import CoreGraphics
import Foundation
import ClawBarShared

/// Clawd's whole state machine, tick by tick, as mascot.ps1, mascot-step.ps1 and hearts.ps1 run it.
public final class ClawdEngine {
    /// 60 while a Claude Code sequence plays, else 90.
    public private(set) var tickMilliseconds = 90

    /// The developer overrides, for the menu's check marks.
    public var devState: ClawdDevState {
        ClawdDevState(
            forcedMood: force, forceCrit: forceCrit, forceHearts: forceHearts,
            demoRunning: demo >= 0, drainRunning: drainT >= 0
        )
    }

    private let random: any RandomSource
    private let sprite = ClawdSprite()

    // $script:Mz, field by field.
    private var x = -1.0
    private var dir = 1
    private var target: Double?
    private var look = 0
    private var tick = 0
    private var blinkAt = 30
    private var mood: Mood = .idle
    /// The effective mood of the last tick.
    private var cur: Mood?
    private var crit = false
    private var idleSince: Date
    private var act: ClawdAct?
    private var actT = 0
    private var force: Mood?
    private var forceCrit = false
    private var demo = -1
    private var demoT = 0
    private var pct: Int?
    private var hearts = HeartsTracker()
    private var forceHearts: Int?
    private var drainT = -1
    private var loveT = -1
    private var noteT = -1
    private var confT = -1
    /// −1 until the first data: the first refresh never counts as a finished reply.
    private var busy = -1
    private var waiting = 0
    private var lastReset: Date?
    private var lastPct: Int?
    private var buried = false
    private var confetti = [ConfettiPiece](repeating: ConfettiPiece(), count: 12)

    /// Picks the random entrance act.
    public init(random: any RandomSource, now: Date) {
        self.random = random
        idleSince = now
        startAct(ClawdTables.entranceActs[random.nextInt(ClawdTables.entranceActs.count)])
    }

    // MARK: - Inputs

    /// New data: mood, crit, the finished-reply jump and the reset celebration. Repeating the same input changes nothing.
    public func apply(_ input: ClawdDataInput, now: Date) {
        let newMood: Mood
        if let p = input.pct, p >= 100 {
            newMood = .dead
        } else if input.waiting > 0 {
            newMood = .wait
        } else if input.busy > 0 {
            newMood = .work
        } else if input.sessionCount > 0 {
            newMood = .idle
        } else {
            newMood = .sleep
        }
        if newMood != mood { idleSince = now }
        mood = newMood

        // A session finished its reply rather than stopping to wait for us.
        if busy > 0, input.busy < busy, input.waiting <= waiting, act == nil { startAct(.jump) }
        busy = input.busy
        waiting = input.waiting
        crit = input.pct.map { $0 >= input.critPercent } ?? false
        pct = input.pct

        // The 5-hour window reset: the reset time moved forward and the percentage dropped.
        if let reset = input.sessionReset {
            if let lastReset, reset > lastReset, let lastPct, let p = input.pct, p < lastPct { startAct(.celebrate) }
            lastReset = reset
            lastPct = input.pct
        }
    }

    /// A left click on the sprite.
    public func click(now: Date) {
        idleSince = now
        // Lying with the limit used up: the soul leaves instead, and no heart.
        if mood == .dead || cur == .dead {
            if act == nil { startAct(.soul) }
            return
        }
        loveT = 0
        // Asleep in the burrow: does not come out, only looks around.
        if buried, cur == .sleep {
            if act == nil { startAct(.stir) }
            return
        }
        if act != nil { return }
        startAct(ClawdTables.clickActs[random.nextInt(ClawdTables.clickActs.count)])
    }

    /// The play area was hidden (showMascot off): forget the hearts.
    public func resetHearts() { hearts.forget() }

    /// The drain alone, as record-gif.ps1 starts it; the menu's `.drain` also stops what is playing.
    public func startDrain() { drainT = 0 }

    /// A developer-menu action; the sky cases are ignored here.
    public func perform(_ action: DevAction) {
        switch action {
        case .auto:
            stopDemo()
            forceHearts = nil
        case .mood(let m):
            stopDemo()
            force = m
        case .act(let a):
            startAct(a)
        case .sweat(let on):
            forceCrit = on
        case .hearts(let h):
            if drainT >= 0 { stopDemo() }
            forceHearts = h
        case .drain:
            stopDemo()
            drainT = 0
        case .demo:
            stopDemo()
            demo = 0
        case .skyPhase, .skyWeather:
            break
        }
    }

    // MARK: - Acts and the demo

    private func startAct(_ a: ClawdAct) {
        act = a
        actT = 0
        if a == .celebrate { startConfetti() }
    }

    private func startConfetti() {
        for i in confetti.indices {
            confetti[i].x = x - 12 + random.nextDouble() * (ClawdTables.boxWidth + 24)
            confetti[i].y = 34 + random.nextDouble() * 12
            confetti[i].v = 0.9 + random.nextDouble() * 1.2
            confetti[i].d = (random.nextDouble() - 0.5) * 0.8
        }
        confT = 0
    }

    /// Step-MascotAct: one frame of the running act, then the act ends when its length is reached.
    private func stepAct(_ f: inout TickFrame) -> String {
        guard let a = act else { return "" }
        let bubble = ClawdActFrames.apply(a, t: actT, to: &f)
        actT += 1
        if actT >= ClawdActFrames.length(a) { act = nil }
        return bubble
    }

    private func stopDemo() {
        demo = -1
        demoT = 0
        force = nil
        forceCrit = false
        act = nil
        if drainT >= 0 {
            drainT = -1
            forceHearts = nil
        }
    }

    private func stepDemo() {
        let entry = ClawdTables.demo[demo]
        if demoT == 0 {
            forceCrit = false
            switch entry {
            case .mood(let m):
                force = m
                act = nil
            case .crit(let m):
                force = m
                act = nil
                forceCrit = true
            case .act(let a):
                force = .idle
                target = nil
                startAct(a)
            case .drain:
                force = .work
                act = nil
                drainT = 0
            }
        }
        demoT += 1
        let length: Int
        switch entry {
        case .act(let a): length = ClawdActFrames.length(a) + 12
        case .drain: length = ClawdTables.drainLength + 10
        default: length = 55
        }
        if demoT >= length {
            demoT = 0
            demo += 1
            if demo >= ClawdTables.demo.count { stopDemo() }
        }
    }

    /// Get-MouseLook: −1, 0 or +1 towards the pointer, nil when it is not over the window.
    private func mouseLook(_ env: ClawdStepEnv) -> Int? {
        guard env.mouseOverWindow, let mx = env.mouseX else { return nil }
        let cx = x + ClawdTables.boxWidth / 2
        if mx > cx + 10 { return 1 }
        if mx < cx - 10 { return -1 }
        return 0
    }

    // MARK: - The tick

    /// One of Clawd's ticks: him and his hearts, without the sky.
    @discardableResult
    public func step(_ env: ClawdStepEnv) -> ClawdFrame {
        tick += 1
        let width = env.areaWidth.isFinite ? env.areaWidth : 0
        let span = max(0, width - ClawdTables.boxWidth)
        if x < 0 { x = span / 2 }
        if x > span { x = span }
        // Deviation 11a: a target beyond a narrowed area would be walked at in place forever.
        if let t = target { target = min(max(t, 0), span) }

        if demo >= 0 { stepDemo() }
        if drainT >= 0 {
            forceHearts = max(0, 6 - drainT / ClawdTables.drainStep)
            drainT += 1
            if drainT >= ClawdTables.drainLength {
                drainT = -1
                forceHearts = nil
            }
        }
        var mood = force ?? self.mood
        // Zero hearts always lie down, set by hand too.
        if forceHearts == 0 { mood = .dead }
        let tierN = ClawdHealth.tierNumber(ClawdHealth.halves(forceHearts: forceHearts, force: force, pct: pct))
        let tier = ClawdHealth.tier(tierN)
        // Lively enough to jump and whistle.
        let perky = tier.speed >= 0.9
        if env.mouseOverWindow { idleSince = env.now }
        if mood == .idle, force == nil, env.now.timeIntervalSince(idleSince) >= 600 { mood = .doze }

        // Falling asleep burrows in once the current act is over; waking climbs out at once.
        if mood == .sleep {
            if !buried, act == nil {
                buried = true
                startAct(.burrow)
            }
        } else if buried {
            buried = false
            startAct(.unburrow)
        }

        var f = TickFrame(pose: ClawdPose(look: look))
        // Once the work is over, the edge he was running to is no reason to walk on.
        if cur == .work, mood != .work { target = nil }
        cur = mood
        var bubble = ""
        var zzz = false
        var canBlink = true
        var dust = false

        if act != nil {
            bubble = stepAct(&f)
            canBlink = false
        } else {
            switch mood {
            case .sleep:
                f.pose.dig = ClawdTables.burrowDig
                f.pose.eyes = .closed
                f.pose.look = 0
                zzz = true
            case .doze:
                // Nods off, and sometimes startles and goggles.
                f.pose.look = 0
                let p = tick % 70
                if p < 6 {
                    f.pose.eyes = .wide
                    if p < 2 { f.lift = 1.5 }
                } else {
                    f.pose.eyes = .blink
                    zzz = true
                }
            case .dead:
                f.pose.flip = true
                f.pose.eyes = .x
                f.pose.look = 0
                // Now and then his legs twitch.
                let p = tick % 50
                if p < 6 { f.pose.feet = p % 2 != 0 ? .left : .right }
            case .wait:
                bubble = "?"
                f.pose.eyes = .wide
                f.pose.look = mouseLook(env) ?? 0
                // Hops and waves: someone is waiting for you.
                let p = tick % 40
                if p < 8 {
                    let k = Double(p) / 7
                    f.lift = 12 * k * (1 - k)
                    f.pose.arms = .right
                }
            case .work, .idle:
                dust = wander(&f, mood: mood, tier: tier, perky: perky, span: span, env: env)
            }
        }

        // Tired eyes over the normal and working ones.
        if let eyes = tier.eyes, act == nil, f.pose.eyes == .open || f.pose.eyes == .focus { f.pose.eyes = eyes }
        // Petted: pleased.
        if loveT >= 0, act == nil, f.pose.eyes == .open { f.pose.eyes = .happy }
        // Whistling: notes, when there is no other bubble.
        if noteT >= 0 {
            if bubble.isEmpty, mood == .idle { bubble = "\u{266A}" }
            noteT += 1
            if noteT >= 30 { noteT = -1 }
        }
        if canBlink, f.pose.eyes == .open, tick >= blinkAt {
            f.pose.eyes = .blink
            if tick >= blinkAt + 1 { blinkAt = tick + 25 + random.nextInt(45) }
        }

        let geo = sprite.geometry(f.pose)
        tickMilliseconds = act.map(ClawdActFrames.isSequence) == true ? ClawdTables.sequenceFrameMs : 90

        // Barely alive: sways.
        var rx = x
        if tier.stagger, mood != .sleep, mood != .dead { rx += 1.5 * sin(Double(tick) / 3) }
        let box = CGRect(
            x: rx.rounded(.toNearestOrEven), y: ClawdTables.sink - f.lift - ClawdTables.boxHeight,
            width: ClawdTables.boxWidth, height: ClawdTables.boxHeight
        )

        var ops: [DrawOp] = []
        func layer(_ rects: [CGRect], _ color: RGBA) {
            guard !rects.isEmpty else { return }
            let moved = rects.map { CGRect(x: box.origin.x + $0.origin.x, y: box.origin.y + $0.origin.y, width: $0.width, height: $0.height) }
            ops.append(.rects(moved, color, opacity: 1))
        }
        layer(geo.body, Palette.clawdBody)
        layer(geo.eyes, Palette.clawdEyes)
        layer(geo.fx, Palette.clawdFx)
        layer(geo.sand, Palette.sand)

        // Near the limit: sweats, on the side away from the gaze.
        if crit || forceCrit || tier.sweat, mood != .sleep, mood != .dead {
            let p = Double(tick % 20) / 20
            let left = f.pose.look < 0 ? 31.0 : 2.0
            // Quirk 11b kept: the box has already moved up by lift, and the drop subtracts it again.
            let top = -2 + 6 * p - f.lift
            ops.append(.rects(
                [CGRect(x: box.minX + left, y: box.minY + top, width: ClawdTables.sweatWidth, height: ClawdTables.sweatHeight)],
                Palette.sweat, opacity: 1 - p
            ))
        }

        // Asleep: a 'z' floats up from behind the head and fades.
        if zzz {
            let p = Double(tick % 30) / 30
            let base: Double = f.pose.dig > 0 ? 9 : f.pose.off > 0 ? 12 : 19
            ops.append(.text(
                "z", at: CGPoint(x: x + 28 + 3 * sin(p * 2 * Double.pi), y: -(base + 14 * p)),
                size: 7 + 4 * p, weight: .semibold, color: Palette.zzz, opacity: 1 - p, anchor: .bottomLeading
            ))
        }

        if !bubble.isEmpty {
            let color = bubble == "?" ? Palette.bubbleQuestion : bubble == "!" ? Palette.bubbleBang : Palette.bubbleNote
            let left = x + ClawdTables.boxWidth / 2 - ClawdTables.bubbleWidth / 2
            ops.append(.text(
                bubble, at: CGPoint(x: left + ClawdTables.bubbleWidth / 2, y: -(22 + f.lift + 1.5 * sin(Double(tick) / 3))),
                size: ClawdTables.bubbleFontSize, weight: .bold, color: color, opacity: 1, anchor: .bottom
            ))
        }

        let heartsFrame = hearts.step(
            ClawdHealth.halves(forceHearts: forceHearts, force: force, pct: pct),
            pct: pct, forced: forceHearts != nil, tick: tick, lang: env.lang
        )

        // Confetti: falls, drifts sideways and shimmers as it flips.
        if confT >= 0 {
            for i in confetti.indices {
                confetti[i].y -= confetti[i].v
                confetti[i].x += confetti[i].d
                confetti[i].shown = confetti[i].y > 0
                confetti[i].width = ((tick + i) / 2) % 2 != 0 ? 2.5 : 1.2
            }
            confT += 1
            if confT >= 45 {
                confT = -1
                for i in confetti.indices { confetti[i].shown = false }
            }
        }

        // Petted: a heart floats up.
        if loveT >= 0 {
            let k = Double(loveT) / 20
            let heartHeight = Double(PixelArt.heart.count) * PixelArt.heartPx
            // The original places the heart's bottom edge, 23 + lift + 14k above the ground.
            let origin = CGPoint(
                x: x + ClawdTables.boxWidth / 2 - 5 + 2 * sin(k * 6),
                y: -(23 + f.lift + 14 * k) - heartHeight
            )
            ops.append(.rects(
                PixelArt.rects(PixelArt.heart, value: "#", px: PixelArt.heartPx, py: PixelArt.heartPx, origin: origin),
                Palette.love, opacity: 1 - k
            ))
            loveT += 1
            if loveT >= 20 { loveT = -1 }
        }

        // The soul leaves the mouth of the lying body and shimmers.
        if f.soul > 0.5 {
            let ox = x + 9.5 * ClawdTables.px, oy = -(f.lift + 6 * ClawdTables.py)
            let rects = ClawdSprite.soul(height: f.soul, t: f.soulT)
                .map { CGRect(x: ox + $0.origin.x, y: oy + $0.origin.y, width: $0.width, height: $0.height) }
            ops.append(.rects(rects, Palette.soul, opacity: 0.7 + 0.15 * sin(Double(f.soulT) / 1.7)))
        }
        // MascotTag comes next in widget.xaml; the particles were added after it at runtime.
        let captionIndex = ops.count

        // A piece's y is its bottom edge above the ground.
        for (i, c) in confetti.enumerated() where c.shown {
            ops.append(.rects(
                [CGRect(x: c.x, y: -c.y - 2.5, width: c.width, height: 2.5)],
                Palette.confetti[i % Palette.confetti.count], opacity: 1
            ))
        }

        // Dust from under the feet while running.
        if dust {
            for i in 0 ..< 3 {
                let p = Double((tick + i * 3) % 9) / 9
                let dx = dir > 0 ? 4 - 8 * p - 2 * Double(i) : ClawdTables.boxWidth - 6 + 8 * p + 2 * Double(i)
                ops.append(.rects([CGRect(x: x + dx, y: -4 * p - 2, width: 2, height: 2)], Palette.dust, opacity: 0.7 * (1 - p)))
            }
        }

        return ClawdFrame(
            ops: ops, spriteRect: box, devCaption: caption(mood: mood, tierN: tierN, lang: env.lang), captionIndex: captionIndex,
            hearts: heartsFrame
        )
    }

    /// The work and idle branch: targets, walking, the step cadence and the random extras. Returns whether dust flies.
    private func wander(_ f: inout TickFrame, mood: Mood, tier: HealthTier, perky: Bool, span: Double, env: ClawdStepEnv) -> Bool {
        var dust = false
        let speed: Double
        if mood == .work {
            speed = 1.6 * tier.speed
            // Runs from edge to edge.
            if target == nil { target = dir > 0 ? span : 0 }
        } else {
            speed = 0.6 * tier.speed
            if target == nil {
                if random.nextInt(70) == 0 {
                    target = random.nextDouble() * span
                } else if random.nextInt(45) == 0 {
                    look = random.nextInt(3) - 1
                } else if random.nextInt(400) == 0 {
                    startAct([ClawdAct.wave, .stretch, .look][random.nextInt(3)])
                }
            }
        }
        var walking = false
        if let t = target {
            let d = t - x
            if abs(d) <= speed {
                x = t
                target = nil
                if mood == .work { dir = -dir }
            } else {
                dir = d > 0 ? 1 : -1
                x += speed * Double(dir)
                look = dir
                walking = true
            }
        }
        if walking {
            // The less energy, the slower the steps.
            var cadence = mood == .work ? 2 : 3
            if tier.speed < 0.8 { cadence += 1 }
            if tier.speed < 0.5 { cadence += 1 }
            f.pose.feet = (tick / cadence) % 2 != 0 ? .left : .right
            if mood == .work {
                if f.pose.feet == .left, perky { f.lift = 1 }
                dust = true
                if perky, random.nextInt(150) == 0 { startAct(.jump) }
            } else if perky, noteT < 0, random.nextInt(80) == 0 {
                noteT = 0
            }
            if let n = tier.stumble, random.nextInt(n) == 0 { startAct(.stumble) }
        } else if crit || forceCrit {
            // The limit is running out: the eyes dart nervously.
            look = (tick / 5) % 2 != 0 ? -1 : 1
        } else if let ml = mouseLook(env) {
            // Standing: follows the pointer.
            look = ml
        }
        f.pose.look = look
        if mood == .work { f.pose.eyes = .focus }
        // Full of energy: jumps for joy; tired: yawns.
        if act == nil {
            if let n = tier.hop, random.nextInt(n) == 0 { startAct(.jump) }
            if let n = tier.yawn, random.nextInt(n) == 0 { startAct(.yawn) }
        }
        return dust
    }

    /// The developer-mode caption: what is being shown now; empty outside developer mode.
    private func caption(mood: Mood, tierN: Int, lang: Lang) -> String {
        guard demo >= 0 || force != nil || forceCrit || forceHearts != nil else { return "" }
        var tag: String
        if drainT >= 0 {
            tag = mood == .dead ? L10n.mood(.dead, lang) : L10n.health(tierN, lang)
        } else if let act {
            tag = L10n.act(act, lang)
        } else if forceCrit {
            tag = L10n.t(.tagSweat, lang)
        } else {
            tag = L10n.mood(mood, lang)
        }
        // Hearts set by hand: the health level too.
        if forceHearts != nil, drainT < 0, mood != .dead { tag += " · " + L10n.health(tierN, lang) }
        return demo >= 0 ? L10n.t(.tagDemo, lang, demo + 1, ClawdTables.demo.count, tag) : "dev · " + tag
    }
}
