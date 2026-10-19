import AppKit
import Observation
import SwiftUI
import ClawBarGame
import ClawBarShared

/// Clawd Run's latest frame; only the game view reads it.
@Observable
final class GameModel {
    var frame: RunnerFrame = .empty
}

/// The game's canvas on the card's background, scaled to fit and centred.
struct GameView: View {
    let model: GameModel

    var body: some View {
        let layers = DrawOpRenderer.layers(model.frame.ops)
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgba: Palette.card)))
            let k = min(size.width / RunnerTuning.width, size.height / RunnerTuning.height)
            ctx.translateBy(x: (size.width - RunnerTuning.width * k) / 2, y: (size.height - RunnerTuning.height * k) / 2)
            ctx.scaleBy(x: k, y: k)
            DrawOpRenderer.draw(layers, in: &ctx)
        }
    }
}

extension GameView {
    /// One frame at its base size, `pixelScale` pixels per point, for `--snapshot`.
    static func image(_ frame: RunnerFrame, pixelScale: Double = 2) -> CGImage? {
        let model = GameModel()
        model.frame = frame
        let renderer = ImageRenderer(content: GameView(model: model).frame(width: RunnerTuning.width, height: RunnerTuning.height))
        renderer.scale = pixelScale
        return renderer.cgImage
    }
}

/// The window's content: hosts the canvas and takes every key and click itself, so SwiftUI never sees them.
final class GameHostView: NSView {
    let hosting: NSHostingView<GameView>
    var onKey: (NSEvent, Bool) -> Void = { _, _ in }
    var onMouse: (Bool) -> Void = { _ in }

    init(model: GameModel) {
        hosting = NSHostingView(rootView: GameView(model: model))
        super.init(frame: CGRect(x: 0, y: 0, width: RunnerTuning.width, height: RunnerTuning.height))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Not passed on: the responder chain would beep at every key.
    override func keyDown(with event: NSEvent) { onKey(event, true) }
    override func keyUp(with event: NSEvent) { onKey(event, false) }
    override func mouseDown(with event: NSEvent) { onMouse(true) }
    override func mouseUp(with event: NSEvent) { onMouse(false) }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }
}

/// Clawd Run's window: opened from the card's link or the menu while the session limit is used up.
/// Steps the engine in fixed ticks off the real clock, and pauses the round while the window is in the background.
final class GameWindowController: NSObject, NSWindowDelegate {
    static let jumpKeys: Set<UInt16> = [49, 126, 13] // Space, ↑, W
    static let duckKeys: Set<UInt16> = [125, 1] // ↓, S
    static let escape: UInt16 = 53
    static let maxStepsPerFire = 4

    /// Read every tick, so a language switch or a reset shows at once.
    var lang: () -> Lang = { .en }
    var caption: () -> String = { "" }

    private let model = GameModel()
    private var engine = RunnerEngine(random: SystemRandomSource())
    private var window: NSWindow?
    private var host: GameHostView?
    private var timer: Timer?
    private var held: Set<UInt16> = []
    private var mouseHeld = false
    /// A press since the last step, so a tap shorter than a tick still jumps.
    private var pressedSinceStep = false
    private var paused = false
    private var lastTime: TimeInterval = 0
    private var backlog: TimeInterval = 0

    var isOpen: Bool { window?.isVisible ?? false }

    func show() {
        let w = window ?? makeWindow()
        window = w
        tick(stepping: false)
        // An accessory app only gets keys once it is active.
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        if let host { w.makeFirstResponder(host) }
        startTimer()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let host = GameHostView(model: model)
        host.onKey = { [unowned self] event, down in key(event, down: down) }
        host.onMouse = { [unowned self] down in
            mouseHeld = down
            if down { pressedSinceStep = true }
        }
        self.host = host
        let w = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: RunnerTuning.width, height: RunnerTuning.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        w.title = L10n.t(.gameTitle, lang())
        w.contentView = host
        w.contentAspectRatio = CGSize(width: RunnerTuning.width, height: RunnerTuning.height)
        w.contentMinSize = CGSize(width: RunnerTuning.width / 2, height: RunnerTuning.height / 2)
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.moveToActiveSpace]
        w.delegate = self
        w.center()
        return w
    }

    private func key(_ event: NSEvent, down: Bool) {
        let code = event.keyCode
        if down, code == Self.escape || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w") {
            close()
            return
        }
        guard down else {
            held.remove(code)
            return
        }
        if Self.jumpKeys.contains(code), !event.isARepeat { pressedSinceStep = true }
        held.insert(code)
    }

    // MARK: Ticks

    private func startTimer() {
        guard timer == nil else { return }
        lastTime = ProcessInfo.processInfo.systemUptime
        backlog = 0
        // .common keeps the game running while a menu is open, like the widget's ticks.
        let t = Timer(timeInterval: 1 / RunnerTuning.ticksPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(stepping: true) }
        }
        t.tolerance = 0.002
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// As many fixed steps as real time asks for, at most a few, so a stall does not fast-forward into a crash.
    private func tick(stepping: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = 1 / RunnerTuning.ticksPerSecond
        backlog += now - lastTime
        lastTime = now
        if stepping, !paused {
            var steps = 0
            while backlog >= dt, steps < Self.maxStepsPerFire {
                let jump = pressedSinceStep || mouseHeld || !held.isDisjoint(with: Self.jumpKeys)
                engine.step(RunnerInput(jump: jump, duck: !held.isDisjoint(with: Self.duckKeys)))
                pressedSinceStep = false
                backlog -= dt
                steps += 1
            }
        }
        if paused || fellBehind(backlog: backlog, dt: dt) { backlog = 0 }
        let language = lang()
        model.frame = engine.frame(lang: language, caption: caption(), paused: paused)
        let title = L10n.t(.gameTitle, language)
        if let window, window.title != title { window.title = title }
    }

    /// Whether the backlog is past what the steps can catch up, after a stall or a pause.
    private func fellBehind(backlog: TimeInterval, dt: TimeInterval) -> Bool {
        backlog >= dt * Double(Self.maxStepsPerFire)
    }

    private func releaseKeys() {
        held.removeAll()
        mouseHeld = false
        pressedSinceStep = false
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        paused = false
        lastTime = ProcessInfo.processInfo.systemUptime
        backlog = 0
    }

    /// A round in the background would crash unseen, so it waits; key-ups go to the other window, so keys are let go.
    func windowDidResignKey(_ notification: Notification) {
        paused = engine.phase == .running
        releaseKeys()
    }

    /// Closing ends the round; the high score stays until ClawBar quits.
    func windowWillClose(_ notification: Notification) {
        stopTimer()
        releaseKeys()
        paused = false
        engine = RunnerEngine(random: SystemRandomSource(), highScore: engine.highScore)
    }
}
