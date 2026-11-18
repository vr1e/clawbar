import AppKit
import SwiftUI
import ClawBarCard
import ClawBarData
import ClawBarPresenter
import ClawBarShared

/// The running app: one data tick, one session poll, one animation tick, the status item and the widget.
final class AppController: NSObject, WidgetPanelDelegate {
    let paths: AppPaths
    private let errorLog: ErrorLog
    private let configStore: ConfigStore
    private var config: Config
    private let skinFolder: SkinFolder
    /// The built-in skins and the user's own, as the skins folder last read.
    private var skins: SkinCatalog
    private let data: DataController
    private let card: CardEngine
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
        skinFolder = SkinFolder(paths: paths)
        skins = skinFolder.reloadIfChanged() ?? .builtIn
        data = DataController(config: config, paths: paths)
        card = CardEngine(random: SystemRandomSource(), config: config, skins: skins, now: Date())
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
            CardRegions.text(id, view: card.presented, hearts: animation.hearts) { self.card.skyTooltip(now: Date(), timeZone: self.zone) }
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

        statusItem.onToggle = { [unowned self] in perform(.menu(.toggleWidget)) }
        statusItem.menuProvider = { [unowned self] in statusMenu() }
        settings.perform = { [unowned self] in perform(.settings($0)) }
        settings.update(skins: skins)

        // The card publishes its size during layout; with sizingOptions = [] the hosting view reports none itself.
        host.hosting.layoutSubtreeIfNeeded()
        let size = layout.cardSize == .zero ? host.hosting.fittingSize : layout.cardSize
        let topLeft = PanelPlacement.topLeft(saved: savedTopLeft, size: size, screens: panel.screens())
        panel.setFrame(WindowPlacement.frame(topLeft: topLeft, size: size, primaryMaxY: panel.screens().primaryMaxY), display: false)

        observe()
        ipc.onShow = { [unowned self] in showWidget() }
        ipc.onCommand = { [unowned self] in perform(.remote($0)) }
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
        reloadSkins()
        data.tick(now: now)
        recompute(now: now)
    }

    /// The latest data snapshot through the card engine, into the card and the menu bar item.
    private func recompute(now: Date = Date()) {
        card.present(presenterInput(now: now), skins: skins)
        let view = card.presented
        statusItem.update(text: view.trayText, color: view.trayColor, mascot: view.trayMascot, tooltip: view.trayTooltip)
        game.update(caption: view.gameCaption, lang: config.lang, palette: view.palette)
        publish()
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

    /// What the card engine has now, into the models the views observe; each is touched only when it changed.
    private func publish() {
        if app.mascotVisible != card.mascotVisible { app.mascotVisible = card.mascotVisible }
        if app.skyVisible != card.skyVisible { app.skyVisible = card.skyVisible }
        animation.publish(card.frame)
        if app.view != card.shown { app.view = card.shown }
        if app.historyHover != card.historyHover { app.historyHover = card.historyHover }
    }

    /// The chart's readout under the pointer, or the legend again once it is off the chart.
    private func updateHistoryHover(_ regions: CardRegions? = nil) {
        card.hover(chartX: pointer.flatMap { (regions ?? self.regions()).chartX(at: $0) })
        publish()
    }

    /// Sync-Mascot: the animation runs only while the widget shows, is not covered and has something to move.
    private func syncAnimation() {
        guard widgetVisible, !occluded, let ms = card.tickMilliseconds else {
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
        let mouse = NSEvent.mouseLocation
        // Topmost at the pointer, so covering windows count; the frame test first spares a WindowServer round trip.
        let over = panel.frame.contains(mouse)
            && NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0) == panel.windowNumber
        let heartsVisibleBefore = animation.hearts.visible
        card.step(
            now: Date(), timeZone: zone, measure: layout.measure(scale: config.scale),
            pointerX: over ? mouse.x - panel.frame.minX : nil
        )
        publish()
        if animation.hearts.visible != heartsVisibleBefore { scheduleRegionRefresh() }
        if card.tickMilliseconds != animationInterval { syncAnimation() }
    }

    // MARK: Config

    private var savedTopLeft: CGPoint? {
        guard let l = config.left, let t = config.top else { return nil }
        return CGPoint(x: l, y: t)
    }

    /// Sync-Config: a reloaded or edited config takes effect at once.
    private func apply(config fresh: Config, initial: Bool = false) {
        let reload = initial ? AppEngine.load(fresh) : AppEngine.reload(fresh, over: config)
        let c = reload.config
        config = c
        if !initial { data.apply(config: c) }
        app.scale = c.scale
        panel.alphaValue = c.opacity
        panel.apply(topmost: c.topmost)
        settings.update(config: c)
        guard !initial else { return }
        if reload.rescheduleDataTimer { scheduleDataTimer() }
        if reload.reconcileLoginItem { loginItem.reconcile(desired: c.launchAtLogin) }
        recompute()
    }

    /// Writes `edit` onto config.json as it is now, so a hand edit survives; a failed write still applies in memory.
    private func change(_ edit: ConfigEdit) {
        do {
            apply(config: try configStore.update { edit.apply(to: &$0) })
        } catch {
            errorLog.append("config: \(error)")
            var next = config
            edit.apply(to: &next)
            apply(config: next)
        }
    }

    /// Set-Skin on every update, so an added or edited skin file shows without a restart.
    @discardableResult
    private func reloadSkins() -> Bool {
        guard let fresh = skinFolder.reloadIfChanged() else { return false }
        skins = fresh
        settings.update(skins: fresh)
        return true
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.onMain(after: 0.5) { [unowned self] in savePosition() }
    }

    private func savePosition() {
        guard let (left, top) = AppEngine.position(of: panel.topLeft, saved: config) else { return }
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
        card.hide()
        publish()
        syncAnimation()
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
        .make(view: card.presented, app: app, animation: animation, layout: layout)
    }

    func clawdClicked() {
        card.click(now: Date())
    }

    func clicked(_ click: CardClick) {
        perform(.card(click))
    }

    func developerMenu() -> NSMenu? {
        DevMenuBuilder.menu(card.developerMenu()) { [unowned self] in performDev($0) }
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
        card.perform(action)
        syncAnimation()
    }

    // MARK: Menu bar

    private func statusMenu() -> NSMenu {
        let recent = config.showRecentSessions
            ? RecentSessionsMenu.items(presenterInput(now: Date()), terminal: SessionTerminal.ghosttyInstalled) : nil
        let entries = StatusMenu.entries(
            config: config, widgetVisible: widgetVisible, limitReached: card.presented.limitReached, recent: recent
        )
        return MenuBuilder.menu(entries) { [unowned self] in perform(.menu($0)) }
    }

    // MARK: Actions

    private func perform(_ action: AppAction) {
        guard let effect = AppEngine.effect(of: action, widgetVisible: widgetVisible) else { return }
        switch effect {
        case .edit(let edit): change(edit)
        case .showWidget: showWidget()
        case .hideWidget: hideWidget()
        case .refresh: data.refreshNow()
        case .showSettings:
            if reloadSkins() { recompute() }
            settings.show(beside: panel.frame, on: (panel.screen ?? NSScreen.main)?.visibleFrame)
        case .showGame: game.show()
        case .open(let url): NSWorkspace.shared.open(url)
        case .startClaudeUpdate:
            data.startClaudeUpdate()
            recompute()
        case .resumeSession(let id): resume(id)
        case .openConfig: openConfig()
        case .openSkinsFolder: openSkinsFolder()
        case .quit: NSApp.terminate(nil)
        }
    }

    /// What the click does is asked now, not when the menu opened: the session may have started or ended since.
    private func resume(_ sessionId: String) {
        guard let session = data.snapshot.recentSessions.first(where: { $0.sessionId == sessionId }),
              let click = RecentSessionsMenu.click(for: session, terminal: SessionTerminal.ghosttyInstalled)
        else { return }
        SessionTerminal.perform(click, on: session) { [weak self] in
            // Automation was refused, or Ghostty could not open the tab.
            self?.errorLog.append("recent: Ghostty opened no tab; the resume command is on the clipboard")
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

    /// Upstream's Your own card: the folder in Finder, created first so there is one to open.
    private func openSkinsFolder() {
        do {
            try skinFolder.ensureExists()
        } catch {
            errorLog.append("skins: \(error)")
            return
        }
        NSWorkspace.shared.open(skinFolder.url)
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
            snapshot: data.snapshot, view: card.presented, skins: skins
        )
        do {
            try dump.render().write(to: IPC.dumpFile(paths), atomically: true, encoding: .utf8)
        } catch {
            errorLog.append("dump-state: \(error)")
        }
    }
}
