import AppKit
import SwiftUI
import ClawBarAnimation
import ClawBarData
import ClawBarPresenter
import ClawBarShared

/// The running app: one data tick, one session poll, one animation tick, the status item and the widget.
final class AppController: NSObject, WidgetPanelDelegate {
    let paths: AppPaths
    private let errorLog: ErrorLog
    private let configStore: ConfigStore
    private var config: Config
    private let data: DataController
    private let engine: AnimationEngine
    /// The Mac's zone, for the presenter, the animation tick and the sky's tooltip alike.
    private let zone = TimeZone.autoupdatingCurrent

    let app = AppModel()
    let animation = AnimationModel()
    let layout = LayoutModel()
    private let host: CardHostView
    private let panel: WidgetPanel
    private let tooltips: TooltipRegistrar
    private let statusItem = StatusItemController()
    private let loginItem: LoginItemController
    private let ipc = IPCListener()
    private let game = GameWindowController()
    private let settings = SettingsWindowController()

    private var dataTimer: Timer?
    private var sessionTimer: Timer?
    private var animationTimer: Timer?
    private var animationInterval = 0
    private var saveTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var widgetVisible = false
    private var occluded = false
    private var regionRefreshPending = false
    /// Card space, while the pointer is over the widget.
    private var pointer: CGPoint?

    init(paths: AppPaths) {
        self.paths = paths
        errorLog = ErrorLog(url: paths.errorLog)
        configStore = ConfigStore(paths: paths)
        config = configStore.load()
        data = DataController(config: config, paths: paths)
        engine = AnimationEngine(random: SystemRandomSource(), config: config, now: Date())
        host = CardHostView(root: WidgetRootView(app: app, animation: animation, layout: layout))
        panel = WidgetPanel(content: host)
        tooltips = TooltipRegistrar(view: host)
        let installed = LaunchAtLogin.managesLoginItem(installed: LaunchAtLogin.runsFromInstalledApp, paths: paths)
        loginItem = LoginItemController(service: MainAppLoginItem(), installed: installed, log: errorLog)
        super.init()
    }

    // MARK: Lifecycle

    func start() {
        apply(config: config, initial: true)
        panel.widgetDelegate = self
        tooltips.text = { [unowned self] id in
            CardRegions.text(id, view: app.view, hearts: animation.hearts) { self.engine.skyTooltip(now: Date(), timeZone: self.zone) }
        }
        layout.onCardSize = { [unowned self] _ in
            // After SwiftUI's layout pass: resizing the window inside its geometry callback would re-enter it.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.panel.fit(contentSize: self.layout.cardSize)
                    // The window server takes the shadow from what is drawn, so redo it once the new size is on screen.
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.panel.invalidateShadow() } }
                }
            }
        }
        layout.onRectsChange = { [unowned self] in scheduleRegionRefresh() }
        data.onChange = { [weak self] in self?.recompute() }

        statusItem.onToggle = { [unowned self] in toggleWidget() }
        statusItem.menuProvider = { [unowned self] in statusMenu() }
        settings.perform = { [unowned self] in perform($0) }

        // The card publishes its size during layout; with sizingOptions = [] the hosting view reports none itself.
        host.hosting.layoutSubtreeIfNeeded()
        let size = layout.cardSize == .zero ? host.hosting.fittingSize : layout.cardSize
        let topLeft = PanelPlacement.topLeft(saved: savedTopLeft, size: size, screens: panel.screens())
        panel.setFrame(WindowPlacement.frame(topLeft: topLeft, size: size, primaryMaxY: panel.screens().primaryMaxY), display: false)

        observe()
        ipc.onShow = { [unowned self] in showWidget() }
        ipc.onCommand = { [unowned self] in run($0) }
        ipc.onDumpState = { [unowned self] in writeStateDump(nonce: $0) }
        ipc.start(channel: IPC.channel(paths))

        let now = Date()
        data.tick(now: now)
        data.pollSessions(now: now)
        recompute(now: now)
        showWidget()
        scheduleDataTimer()
        sessionTimer = Timer.onMain(every: 2) { [unowned self] in
            let now = Date()
            data.pollSessions(now: now)
            recompute(now: now)
        }
        loginItem.reconcile(desired: config.launchAtLogin)
    }

    func stop() {
        for t in [dataTimer, sessionTimer, animationTimer, saveTimer] { t?.invalidate() }
        game.close()
        settings.close()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        ipc.stop()
        savePosition()
        data.shutdown()
    }

    private func observe() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main, using: onMain { [unowned self] in
            scheduleSave()
        }))
        observers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main, using: onMain { [unowned self] in
            occluded = !panel.occlusionState.contains(.visible)
            syncAnimation()
        }))
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: onMain { [unowned self] in
            if panel.revalidatePlacement() { savePosition() }
        }))
    }

    /// A notification block that runs `body` on the main actor; observers are registered on the main queue.
    private func onMain(_ body: @escaping @MainActor () -> Void) -> @Sendable (Notification) -> Void {
        { _ in MainActor.assumeIsolated { body() } }
    }

    // MARK: Ticks

    private func scheduleDataTimer() {
        dataTimer?.invalidate()
        dataTimer = Timer.onMain(every: Double(config.refreshSeconds)) { [unowned self] in dataTick() }
    }

    /// update.ps1's Update-Widget: live config, the probes on their cadence, then everything rendered.
    private func dataTick() {
        let now = Date()
        if let fresh = configStore.reloadIfChanged() { apply(config: fresh) }
        data.tick(now: now)
        recompute(now: now)
    }

    /// The presenter's view of the latest data snapshot, into the card and the menu bar item; the same data into the
    /// animation.
    private func recompute(now: Date = Date()) {
        let input = presenterInput(now: now)
        let view = WidgetPresenter.make(input)
        if view != app.view { app.view = view }
        statusItem.update(text: view.trayText, color: view.trayColor, mascot: view.trayMascot, tooltip: view.trayTooltip)
        game.update(caption: view.gameCaption, lang: config.lang, palette: view.palette)
        engine.apply(input.data, config: config, now: now)
        syncVisibility()
        animation.publish(engine.frame)
        syncAnimation()
        scheduleRegionRefresh()
    }

    private func presenterInput(now: Date) -> PresenterInput {
        // The original's "error" stamp marked a failed tick; here the one failure a tick can hit is an unparsable config.json.
        PresenterInput(
            config: config, now: now, timeZone: zone, data: data.snapshot, tickError: configStore.isUnreadable,
            appVersion: AppInfo.version, homeDirectory: NSHomeDirectory()
        )
    }

    /// The engine decides what shows: the play area with Clawd and the hearts, and the sky behind the row.
    private func syncVisibility() {
        if app.mascotVisible != engine.mascotVisible { app.mascotVisible = engine.mascotVisible }
        if app.skyVisible != engine.skyVisible { app.skyVisible = engine.skyVisible }
    }

    /// The chart's readout under the pointer, or the legend again once it is off the chart.
    private func updateHistoryHover(_ regions: CardRegions? = nil) {
        var hover: HistoryHover?
        if let p = pointer, let chart = app.view.history, let x = (regions ?? self.regions()).chartX(at: p) {
            hover = HistoryReadout.hover(x: x, chart: chart, input: presenterInput(now: Date()))
        }
        if hover != app.historyHover { app.historyHover = hover }
    }

    /// Sync-Mascot: the animation runs only while the widget shows, is not covered and has something to move.
    private func syncAnimation() {
        guard widgetVisible, !occluded, let ms = engine.tickMilliseconds else {
            animationTimer?.invalidate()
            animationTimer = nil
            return
        }
        guard animationTimer == nil || ms != animationInterval else { return }
        animationTimer?.invalidate()
        animationInterval = ms
        animationTimer = Timer.onMain(every: Double(ms) / 1000, tolerance: 0.004) { [unowned self] in animationTick() }
    }

    private func animationTick() {
        let k = config.scale
        let mouse = NSEvent.mouseLocation
        // Over the window only when our panel is the topmost window there, so covering windows count.
        let over = NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0) == panel.windowNumber
        var mouseX: Double?
        if over {
            // The engine needs x whenever the pointer is over the window; before the first layout the row sits at 13.
            let row = layout.rects[.percentRow] ?? CGRect(x: 13 * k, y: 0, width: CardView.content * k, height: 40 * k)
            mouseX = PlayArea.mouseX(cardX: mouse.x - panel.frame.minX, row: row, numberWidth: layout.numberWidth, scale: k)
        }
        let heartsVisibleBefore = animation.hearts.visible
        animation.publish(engine.step(AnimationInputs(
            now: Date(), timeZone: zone, numberWidth: layout.numberWidth, mouseOverWindow: over, mouseX: mouseX
        )))
        if animation.hearts.visible != heartsVisibleBefore { scheduleRegionRefresh() }
        if engine.tickMilliseconds != animationInterval { syncAnimation() }
    }

    // MARK: Config

    private var savedTopLeft: CGPoint? {
        guard let l = config.left, let t = config.top else { return nil }
        return CGPoint(x: l, y: t)
    }

    /// Sync-Config: a reloaded or edited config takes effect at once. The window owns its position, so the
    /// in-memory left/top survive a reload.
    private func apply(config fresh: Config, initial: Bool = false) {
        var c = fresh.clamped()
        if !initial {
            c.left = config.left
            c.top = config.top
        }
        let old = config
        config = c
        if !initial { data.apply(config: c) }
        app.scale = c.scale
        panel.alphaValue = c.opacity
        panel.apply(topmost: c.topmost)
        settings.update(config: c)
        guard !initial else { return }
        if c.refreshSeconds != old.refreshSeconds { scheduleDataTimer() }
        if c.launchAtLogin != old.launchAtLogin { loginItem.reconcile(desired: c.launchAtLogin) }
        recompute()
    }

    /// Writes only what `edit` changes; a failed write still applies in memory and is logged.
    private func change(_ edit: (inout Config) -> Void) {
        do {
            apply(config: try configStore.update(edit))
        } catch {
            errorLog.append("config: \(error)")
            var next = config
            edit(&next)
            apply(config: next.clamped())
        }
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.onMain(after: 0.5) { [unowned self] in savePosition() }
    }

    /// The top-left, WPF-style and rounded like the original's [math]::Round, written only when it moved.
    private func savePosition() {
        let tl = panel.topLeft
        let left = tl.x.rounded(.toNearestOrEven), top = tl.y.rounded(.toNearestOrEven)
        guard config.left != left || config.top != top else { return }
        config.left = left
        config.top = top
        do {
            let merged = try configStore.update {
                $0.left = left
                $0.top = top
            }
            // The save read the file afresh: a hand edit since the last tick takes effect now, not never.
            if merged != config { apply(config: merged) }
        } catch {
            errorLog.append("config: saving the position failed: \(error)")
        }
    }

    // MARK: Widget

    func showWidget() {
        panel.orderFrontRegardless()
        widgetVisible = true
        // The occlusion notification corrects this once the window server has placed the panel.
        occluded = false
        syncAnimation()
        scheduleRegionRefresh()
    }

    private func hideWidget() {
        panel.orderOut(nil)
        widgetVisible = false
        syncAnimation()
    }

    private func toggleWidget() {
        widgetVisible ? hideWidget() : showWidget()
    }

    /// The tooltip regions and the chart's readout, once SwiftUI has published the rects they read.
    private func scheduleRegionRefresh() {
        guard !regionRefreshPending else { return }
        regionRefreshPending = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.regionRefreshPending = false
                let regions = self.regions()
                self.tooltips.update(regions.tooltips)
                // The chart can move or close under a resting pointer.
                self.updateHistoryHover(regions)
            }
        }
    }

    // MARK: WidgetPanelDelegate

    func regions() -> CardRegions {
        .make(app: app, animation: animation, layout: layout)
    }

    func clawdClicked() {
        engine.click(now: Date())
    }

    func clicked(_ click: CardClick) {
        switch click {
        case .toggleDetails: change { $0.expanded.toggle() }
        case .hide: hideWidget()
        case .quit: NSApp.terminate(nil)
        case .play: game.show()
        case .open(let url): NSWorkspace.shared.open(url)
        case .runUpdate:
            data.startClaudeUpdate()
            recompute()
        case .nothing: break
        }
    }

    func developerMenu() -> NSMenu? {
        DevMenuBuilder.menu(engine.developerMenu()) { [unowned self] in performDev($0) }
    }

    func pointerMoved(to p: CGPoint, over regions: CardRegions) {
        pointer = p
        updateHistoryHover(regions)
    }

    func pointerLeft() {
        pointer = nil
        updateHistoryHover()
    }

    private func performDev(_ action: DevAction) {
        engine.perform(action)
        syncAnimation()
    }

    // MARK: Menu bar

    private func statusMenu() -> NSMenu {
        let entries = StatusMenu.entries(config: config, widgetVisible: widgetVisible, limitReached: app.view.limitReached)
        return MenuBuilder.menu(entries) { [unowned self] in perform($0) }
    }

    private func perform(_ action: StatusMenuAction) {
        switch action {
        case .toggleWidget: toggleWidget()
        case .refresh: data.refreshNow()
        case .settings: settings.show(beside: panel.frame, on: (panel.screen ?? NSScreen.main)?.visibleFrame)
        case .play: game.show()
        case .quit: NSApp.terminate(nil)
        }
    }

    private func perform(_ action: SettingsAction) {
        switch action {
        case .step(let s, let up): change { $0[keyPath: s.key] = s.next(from: $0[keyPath: s.key], up: up) ?? $0[keyPath: s.key] }
        case .toggleTopmost: change { $0.topmost.toggle() }
        case .toggleLaunchAtLogin: change { $0.launchAtLogin.toggle() }
        case .toggleMenuBarMascot: change { $0.menuBarMascot.toggle() }
        case .language(let l): change { $0.language = l.rawValue }
        case .toggleBlock(let b): change { $0[keyPath: b.flag].toggle() }
        case .openConfig: openConfig()
        }
    }

    /// `--command` from another process.
    private func run(_ command: RemoteCommand) {
        switch command {
        case .toggle: toggleWidget()
        case .show: showWidget()
        case .larger: perform(SettingsAction.step(.size, up: true))
        case .smaller: perform(SettingsAction.step(.size, up: false))
        case .refresh: perform(StatusMenuAction.refresh)
        case .settings: perform(StatusMenuAction.settings)
        case .quit: perform(StatusMenuAction.quit)
        case .lang(let l): perform(SettingsAction.language(l))
        }
    }

    /// Writes every key first when the file is missing, then opens it in TextEdit: .json often has no handler.
    private func openConfig() {
        do {
            try configStore.ensureExists()
        } catch {
            errorLog.append("config: \(error)")
        }
        let url = configStore.url
        let log = errorLog
        guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { log.append("config: opening config.json failed: \(error)") }
        }
    }

    // MARK: Dump

    private func writeStateDump(nonce: String) {
        let dump = StateDump(
            nonce: nonce, pid: ProcessInfo.processInfo.processIdentifier,
            statusItemVisible: statusItem.isVisible, statusItemFrame: statusItem.screenFrame,
            widgetVisible: widgetVisible, occluded: occluded, panelFrame: panel.frame,
            screenFrames: NSScreen.screens.map(\.frame), topLeft: panel.topLeft,
            animating: animationTimer != nil, tickMilliseconds: animationInterval, config: config,
            loginItemStatus: loginItem.status.rawValue, installedApp: loginItem.installed,
            snapshot: data.snapshot, view: app.view
        )
        do {
            try dump.render().write(to: IPC.dumpFile(paths), atomically: true, encoding: .utf8)
        } catch {
            errorLog.append("dump-state: \(error)")
        }
    }
}
