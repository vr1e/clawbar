import AppKit
import CoreGraphics
import Foundation
import ClawBarClawd
import ClawBarGame
import ClawBarPresenter
import ClawBarShared
import ClawBarSky

/// One state of the widget for `--snapshot`: the data and settings the presenter sees.
struct SnapshotCase {
    var name: String
    var config = Config()
    var data = DataSnapshot.sample
    var tickError = false
    var skyDev = SkyDevState()
}

/// Every presenter state the data contract can express, all at `Samples.now` in Berlin.
enum SnapshotCases {
    static func all() -> [SnapshotCase] {
        let now = Samples.now
        var list: [SnapshotCase] = []
        func add(_ name: String, _ edit: (inout SnapshotCase) -> Void = { _ in }) {
            var c = SnapshotCase(name: name)
            edit(&c)
            list.append(c)
        }
        func noUsage(_ c: inout SnapshotCase, _ issue: UsageIssue?) {
            c.data.usage = nil
            c.data.usageAt = nil
            c.data.usageProbeCompleted = true
            c.data.usageIssue = issue
        }
        func failedUpdate(_ c: inout SnapshotCase, _ failure: UpdateFailure) {
            c.config.expanded = true
            c.data.version = VersionState(local: "2.1.300", latest: "2.1.302", updateFailure: failure, installHint: .homebrew)
        }

        add("sample")
        add("expanded") { $0.config.expanded = true }
        add("loading") { $0.data = DataSnapshot() }
        add("no-data") { noUsage(&$0, nil) }
        add("warn") { $0.data.usage?.sessionPercent = 72 }
        add("crit") { $0.data.usage?.sessionPercent = 91 }
        add("limit") { $0.data.usage?.sessionPercent = 100 }
        add("reset-passed") { $0.data.usage?.sessionReset = now.addingTimeInterval(-60) }
        add("claude-not-found") { noUsage(&$0, .claudeNotFound) }
        add("no-limits") {
            $0.data.usage = UsageSnapshot(day: DataSnapshot.sample.usage?.day, week7: DataSnapshot.sample.usage?.week7)
            $0.data.usageIssue = .noLimits
        }
        add("probe-failed") { $0.data.usageIssue = .probeFailed("exit 1") }
        add("flag-rejected") { noUsage(&$0, .flagRejected("--no-session-persistence")) }
        add("model-reached") { noUsage(&$0, .modelReached(turns: 1, costUSD: 0.0042, tokens: 18)) }
        add("update-available") {
            $0.config.expanded = true
            $0.data.version = VersionState(
                local: "2.1.300", latest: "2.1.302",
                changes: ChangesExcerpt(forVersion: "2.1.302", fromVersion: "2.1.300", items: ["Faster startup", "Fixed /usage in safe mode"])
            )
        }
        add("updating") {
            $0.config.expanded = true
            $0.data.version = VersionState(local: "2.1.300", latest: "2.1.302", updating: true)
        }
        add("update-failed") { failedUpdate(&$0, UpdateFailure(exitCode: 1, outputTail: "Error: permission denied")) }
        add("update-unchanged") { failedUpdate(&$0, UpdateFailure(exitCode: 0, outputTail: "Checking for updates...\nDone", from: "2.1.300")) }
        add("status-issues") {
            $0.data.status = ServiceStatus(
                indicator: "major", incidents: ["Elevated errors on Claude Opus"],
                broken: [BrokenComponent(name: "Claude API", state: "partial_outage"), BrokenComponent(name: "claude.ai", state: "degraded_performance")]
            )
        }
        add("maintenance") { $0.data.status = ServiceStatus(indicator: "maintenance") }
        add("status-offline") { $0.data.statusAt = now.addingTimeInterval(-3600) }
        add("logged-out") { $0.data.account = AccountInfo(loggedIn: false) }
        add("stale") { $0.data.usageAt = now.addingTimeInterval(-1200) }
        add("tick-error") { $0.tickError = true }
        add("model-weeks") {
            $0.data.usage?.modelWeeks = [
                ModelWeek(name: "Fable", percent: 8, reset: now.addingTimeInterval(4 * 86400)),
                ModelWeek(name: "Sonnet", percent: 23, reset: now.addingTimeInterval(4 * 86400)),
            ]
        }
        add("many-sessions") {
            $0.data.sessions = ["api", "web", "docs", "infra", "notes"].enumerated().map { i, name in
                SessionInfo(
                    pid: Int32(5000 + i), name: name, cwd: "\(Samples.home)/code/\(name)",
                    state: [.busy, .busy, .waiting, .idle, .idle][i], waitingFor: i == 2 ? "permission" : nil, kind: "interactive"
                )
            }
        }
        add("no-sessions") { $0.data.sessions = [] }
        add("rows-hidden") {
            $0.config.showSessions = false
            $0.config.showStatus = false
            $0.config.showAccount = false
        }
        add("no-mascot") { $0.config.showMascot = false }
        add("no-sky") { $0.config.showSky = false }
        add("night") { $0.skyDev = SkyDevState(phase: .night, weatherCode: 0) }
        add("storm") { $0.skyDev = SkyDevState(phase: .dusk, weatherCode: 95) }
        add("snow") { $0.skyDev = SkyDevState(phase: .day, weatherCode: 73) }

        return list
    }
}

/// `--snapshot <dir>`: the card in every state, EN and DE, at k 1.0, 1.2 and 2.0; the menu bar item, and its text and
/// tooltip in every state; both menus; Clawd Run's screens.
enum SnapshotMode {
    static let scales = [1.0, 1.2, 2.0]
    static let backdrop = RGBA(r: 13, g: 17, b: 23)

    static func run(dir: URL) -> Int32 {
        do {
            let files = try write(to: dir)
            print("wrote \(files.count) files to \(dir.path)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("ClawBar: \(error)\n".utf8))
            return 1
        }
    }

    static func write(to dir: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [URL] = []
        for c in SnapshotCases.all() {
            for lang in Lang.allCases {
                for k in scales {
                    guard let card = renderCard(c, lang: lang, scale: k), let image = Imaging.onBackdrop(card, pad: 24, color: backdrop) else {
                        throw CLIError(message: "rendering \(c.name) failed")
                    }
                    let url = dir.appendingPathComponent("\(c.name)-\(lang.rawValue)-k\(String(format: "%.1f", k)).png")
                    try Imaging.writePNG(image, to: url)
                    out.append(url)
                }
            }
        }
        out += try writeStatusItems(to: dir)
        out += try writeGame(to: dir)
        for lang in Lang.allCases {
            let url = dir.appendingPathComponent("menus-\(lang.rawValue).txt")
            try menuDump(lang: lang).write(to: url, atomically: true, encoding: .utf8)
            out.append(url)
            let bar = dir.appendingPathComponent("menu-bar-\(lang.rawValue).txt")
            try menuBarDump(lang: lang).write(to: bar, atomically: true, encoding: .utf8)
            out.append(bar)
        }
        return out
    }

    static func view(for c: SnapshotCase, lang: Lang) -> WidgetViewState {
        var config = c.config
        config.language = lang.rawValue
        return WidgetPresenter.make(PresenterInput(
            config: config, now: Samples.now, timeZone: Samples.timeZone, data: c.data, tickError: c.tickError,
            appVersion: AppInfo.version, homeDirectory: Samples.home
        ))
    }

    /// The card at 2 pixels per point, with Clawd and the sky after a few seeded ticks.
    static func renderCard(_ c: SnapshotCase, lang: Lang, scale k: Double) -> CGImage? {
        let view = view(for: c, lang: lang)
        let layout = LayoutModel()
        var scene = CardRenderer.Scene(view: view, mascotVisible: c.config.showMascot, skyVisible: c.config.showMascot && c.config.showSky)
        // A first pass measures the number, which sets the play area Clawd walks in.
        _ = CardRenderer.render(scene, scale: k, layout: layout)
        if scene.mascotVisible {
            scene.clawd = clawdFrame(c, lang: lang, numberWidth: layout.numberWidth)
        }
        if scene.skyVisible {
            scene.sky = skyFrame(c)
        }
        return CardRenderer.render(scene, scale: k, layout: layout)
    }

    static func clawdFrame(_ c: SnapshotCase, lang: Lang, numberWidth: Double) -> ClawdFrame {
        var now = Samples.now
        let engine = ClawdEngine(random: SeededRandomSource(seed: 7), now: now)
        if c.data.sessionsRead { engine.apply(ClawdDataInput(c.data, critPercent: c.config.critPercent), now: now) }
        var frame = ClawdFrame.empty
        for _ in 0 ..< 60 {
            frame = engine.step(ClawdStepEnv(
                areaWidth: PlayArea.width(numberWidth: numberWidth), areaHeight: PlayArea.height,
                mouseOverWindow: false, mouseX: nil, now: now, lang: lang
            ))
            now = now.addingTimeInterval(Double(engine.tickMilliseconds) / 1000)
        }
        return frame
    }

    static func skyFrame(_ c: SnapshotCase) -> SkyFrame {
        let now = Samples.now
        let inputs = SkyInfo.inputs(c.data.weather, place: c.data.place, now: now, localZone: Samples.timeZone, dev: c.skyDev)
        let sky = SkyEngine(random: SeededRandomSource(seed: 7))
        var frame = SkyFrame.empty
        for _ in 0 ..< 30 { frame = sky.step(size: CGSize(width: CardView.content, height: PlayArea.height), inputs: inputs) }
        return frame
    }

    /// The menu bar item on a light and a dark bar, at 2 pixels per point.
    static func writeStatusItems(to dir: URL) throws -> [URL] {
        let items: [(name: String, text: String, color: RGBA)] = [
            ("none", "--", Palette.dead), ("7", "7", Palette.ok), ("42", "42", Palette.ok), ("42-stale", "42", Palette.dead),
            ("60", "60", Palette.warn), ("85", "85", Palette.crit), ("100", "100", Palette.crit),
        ]
        let bars: [(String, RGBA)] = [("light", RGBA("#FFF2F2F2")), ("dark", RGBA("#FF262626"))]
        var out: [URL] = []
        for (name, text, color) in items {
            let image = StatusItemImage.make(text: text, color: color)
            for (bar, background) in bars {
                guard let cg = Imaging.image(image, pixelScale: 2, background: background, pad: 3) else { throw CLIError(message: "status item \(name)") }
                let url = dir.appendingPathComponent("status-item-\(name)-\(bar).png")
                try Imaging.writePNG(cg, to: url)
                out.append(url)
            }
        }
        return out
    }

    /// Clawd Run at the start, mid-round with a bug about, paused and after a crash, at 2 pixels per point.
    static func writeGame(to dir: URL) throws -> [URL] {
        var out: [URL] = []
        for lang in Lang.allCases {
            for (name, frame) in gameFrames(lang: lang) {
                guard let image = GameView.image(frame) else { throw CLIError(message: "rendering game-\(name) failed") }
                let url = dir.appendingPathComponent("game-\(name)-\(lang.rawValue).png")
                try Imaging.writePNG(image, to: url)
                out.append(url)
            }
        }
        return out
    }

    /// A seeded round played by the engine's demo player, so every run draws the same screens.
    static func gameFrames(lang: Lang) -> [(name: String, frame: RunnerFrame)] {
        let caption = L10n.t(.resetIn, lang, "1h 12m")
        let e = RunnerEngine(random: SeededRandomSource(seed: 2), highScore: 1234)
        var frames = [(name: "ready", frame: e.frame(lang: lang, caption: caption))]
        e.step(RunnerInput(jump: true))
        // Bugs fly from speed 8.5, some 2500 ticks in; stop once one is well on screen.
        for t in 0 ..< 6000 where e.phase == .running {
            e.step(e.demoInput)
            if t > 2500, bugOnScreen(e.frame(lang: lang, caption: "")) { break }
        }
        frames.append((name: "running", frame: e.frame(lang: lang, caption: caption)))
        frames.append((name: "paused", frame: e.frame(lang: lang, caption: caption, paused: true)))
        while e.phase == .running { e.step(RunnerInput()) }
        for _ in 0 ..< RunnerTuning.restartDelayTicks { e.step(RunnerInput()) }
        frames.append((name: "over", frame: e.frame(lang: lang, caption: L10n.t(.gameBack, lang))))
        return frames
    }

    /// A bug drawn in the left two thirds of the canvas.
    static func bugOnScreen(_ frame: RunnerFrame) -> Bool {
        frame.ops.contains { op in
            guard case let .rects(rects, color, _) = op, color == Palette.runnerBug else { return false }
            return rects.contains { $0.minX < 400 }
        }
    }

    /// The menu bar item's text, colour and tooltip in every state, since no PNG shows the tooltip.
    static func menuBarDump(lang: Lang) -> String {
        let states = SnapshotCases.all().map { c in
            let v = view(for: c, lang: lang)
            let level = Level.allCases.first { $0.color == v.trayColor }?.rawValue ?? v.trayColor.hex
            return "\(c.name): \(v.trayText) (\(level))\n  " + v.trayTooltip.replacingOccurrences(of: "\n", with: "\n  ")
        }
        return "ClawBar menu bar item (\(lang.rawValue))\n\n" + states.joined(separator: "\n\n") + "\n"
    }

    static func menuDump(lang: Lang) -> String {
        let forced = ClawdDevState(forcedMood: .work, forceCrit: true, forceHearts: 4)
        let sections: [(String, String)] = [
            (
                "Status menu, widget shown",
                MenuEntry.dump(StatusMenu.entries(lang: lang, widgetVisible: true, topmost: false, launchAtLogin: true, shown: Set(WidgetBlock.allCases)))
            ),
            (
                "Status menu, widget hidden, always on top, no Clawd or stats",
                MenuEntry.dump(StatusMenu.entries(
                    lang: lang, widgetVisible: false, topmost: true, launchAtLogin: false, shown: [.sky, .status, .sessions, .account]
                ))
            ),
            (
                "Status menu, session limit used up",
                MenuEntry.dump(StatusMenu.entries(
                    lang: lang, widgetVisible: true, topmost: false, launchAtLogin: true, shown: Set(WidgetBlock.allCases), limitReached: true
                ))
            ),
            ("Developer menu, live data", DevMenuBuilder.dump(DevMenu.build(dev: ClawdDevState(), sky: SkyDevState(), skyVisible: true, lang: lang))),
            (
                "Developer menu, working + sweating + 2 hearts, night snow, sky hidden",
                DevMenuBuilder.dump(DevMenu.build(dev: forced, sky: SkyDevState(phase: .night, weatherCode: 73), skyVisible: false, lang: lang))
            ),
        ]
        return "ClawBar menus (\(lang.rawValue))\n\n" + sections.map { "\($0.0):\n\($0.1)\n" }.joined(separator: "\n")
    }
}
