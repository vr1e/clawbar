import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI
import ClawBarGame
import ClawBarShared

/// Clawd Run's latest frame; only the game view reads it.
@Observable
final class GameModel {
    var frame: RunnerFrame = .empty
}

/// The game's canvas on its frame's background, scaled to fit and centred.
struct GameView: View {
    let model: GameModel

    var body: some View {
        let frame = model.frame
        let layers = DrawOpRenderer.layers(frame.ops)
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgba: frame.background)))
            let k = min(size.width / RunnerTuning.width, size.height / RunnerTuning.height)
            ctx.translateBy(x: (size.width - RunnerTuning.width * k) / 2, y: (size.height - RunnerTuning.height * k) / 2)
            ctx.scaleBy(x: k, y: k)
            DrawOpRenderer.draw(layers, in: &ctx)
        }
    }
}

/// The window's content: hosts the canvas and takes every key and click itself, so SwiftUI never sees them.
final class GameHostView: HostView<GameView> {
    var onKey: (NSEvent, Bool) -> Void = { _, _ in }
    var onMouse: (Bool) -> Void = { _ in }

    convenience init(model: GameModel) {
        self.init(rootView: GameView(model: model), size: CGSize(width: RunnerTuning.width, height: RunnerTuning.height))
    }

    override var acceptsFirstResponder: Bool { true }

    // Not passed on: the responder chain would beep at every key.
    override func keyDown(with event: NSEvent) { onKey(event, true) }
    override func keyUp(with event: NSEvent) { onKey(event, false) }
    override func mouseDown(with event: NSEvent) { onMouse(true) }
    override func mouseUp(with event: NSEvent) { onMouse(false) }
}

/// Clawd Run's window: opened from the card's button or the menu while the main limit is used up.
/// Steps the engine in fixed ticks off the real clock while the window is key; behind other windows the round waits.
final class GameWindowController: NSObject, NSWindowDelegate {
    static let jumpKeys = Set([kVK_Space, kVK_UpArrow, kVK_ANSI_W].map(UInt16.init))
    static let duckKeys = Set([kVK_DownArrow, kVK_ANSI_S].map(UInt16.init))
    static let escape = UInt16(kVK_Escape)
    static let maxStepsPerFire = 4

    private var lang = Lang.en
    private var caption = ""
    private var palette = ThemePalette.classic
    private let model = GameModel()
    private let engine = RunnerEngine(random: SystemRandomSource())
    private var window: NSWindow?
    private var timer: Timer?
    private var held: Set<UInt16> = []
    private var mouseHeld = false
    /// A press since the last step, so a tap shorter than a tick still jumps.
    private var pressedSinceStep = false
    private var lastTime: TimeInterval = 0
    private var backlog: TimeInterval = 0

    /// The corner's caption, the language and the themed colours from each new view state, so a reset, a language
    /// switch or a new look shows at once.
    func update(caption: String, lang: Lang, palette: ThemePalette) {
        guard caption != self.caption || lang != self.lang || palette != self.palette else { return }
        self.caption = caption
        self.lang = lang
        self.palette = palette
        render()
    }

    /// Becoming key starts the ticks.
    func show() {
        let w = window ?? makeWindow()
        window = w
        render()
        // An accessory app only gets keys once it is active.
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(w.contentView)
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
        let w = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: RunnerTuning.width, height: RunnerTuning.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        // A proper name, the same in both languages.
        w.title = L10n.t(.gameTitle, lang)
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
        if down, code == Self.escape || event.isCloseWindowShortcut {
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
        stopTimer()
        lastTime = ProcessInfo.processInfo.systemUptime
        backlog = 0
        timer = Timer.onMain(every: 1 / RunnerTuning.ticksPerSecond) { [weak self] in self?.tick() }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// As many fixed steps as real time asks for, at most a few, so a stall does not fast-forward into a crash.
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = 1 / RunnerTuning.ticksPerSecond
        backlog += now - lastTime
        lastTime = now
        var steps = 0
        while backlog >= dt, steps < Self.maxStepsPerFire {
            let jump = pressedSinceStep || mouseHeld || !held.isDisjoint(with: Self.jumpKeys)
            engine.step(RunnerInput(jump: jump, duck: !held.isDisjoint(with: Self.duckKeys)))
            pressedSinceStep = false
            backlog -= dt
            steps += 1
        }
        // Past what the steps can catch up, after a stall.
        if backlog >= dt * Double(Self.maxStepsPerFire) { backlog = 0 }
        render()
    }

    /// Only a changed frame is published, so a still screen is not redrawn every tick.
    private func render() {
        let frame = engine.frame(lang: lang, caption: caption, palette: palette)
        if frame != model.frame { model.frame = frame }
    }

    private func releaseKeys() {
        held.removeAll()
        mouseHeld = false
        pressedSinceStep = false
    }

    // MARK: NSWindowDelegate

    /// A paused round stays paused until the next press, which the engine takes.
    func windowDidBecomeKey(_ notification: Notification) {
        startTimer()
    }

    /// Key-ups go to the other window, so keys are let go; a running round waits, drawn at once with its note.
    func windowDidResignKey(_ notification: Notification) {
        stopTimer()
        releaseKeys()
        engine.pause()
        render()
    }

    /// Closing ends the round; the high score stays until ClawBar quits.
    func windowWillClose(_ notification: Notification) {
        stopTimer()
        releaseKeys()
        engine.newRound()
    }
}
