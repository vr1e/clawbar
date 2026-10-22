import AppKit
import ClawBarShared

enum StatusMenuAction: Hashable {
    case toggleWidget, refresh, larger, smaller, toggleTopmost, toggleLaunchAtLogin, toggleMenuBarMascot, openConfig, quit
    /// Opens Clawd Run; offered only while the session limit is used up.
    case play
    case language(Lang)
    case toggleBlock(WidgetBlock)
}

/// The widget's switchable blocks, in the original Settings window's order.
enum WidgetBlock: CaseIterable, Hashable {
    case mascot, sky, status, sessions, account, stats, history

    var title: L10nKey {
        switch self {
        case .mascot: .setShowMascot
        case .sky: .setShowSky
        case .status: .setShowStatus
        case .sessions: .setShowSessions
        case .account: .setShowAccount
        case .stats: .setShowStats
        case .history: .setShowHistory
        }
    }

    var flag: WritableKeyPath<Config, Bool> {
        switch self {
        case .mascot: \.showMascot
        case .sky: \.showSky
        case .status: \.showStatus
        case .sessions: \.showSessions
        case .account: \.showAccount
        case .stats: \.showStats
        case .history: \.showHistory
        }
    }

    static func shown(in config: Config) -> Set<WidgetBlock> { Set(allCases.filter { config[keyPath: $0.flag] }) }
}

/// One menu item as data, so menus can be tested and dumped as text.
struct MenuEntry<Action: Hashable>: Hashable {
    var title: String
    var checked = false
    /// Shows a check box in the text dump even while unchecked.
    var checkable = false
    var enabled = true
    var isSeparator = false
    var action: Action?
    var children: [MenuEntry] = []

    static var separator: MenuEntry { MenuEntry(title: "", enabled: false, isSeparator: true) }

    /// One line per item: `[x]` / `[ ]` for checkable items, `▸` for submenus, `(disabled)`.
    static func dump(_ entries: [MenuEntry], indent: String = "  ") -> String {
        var lines: [String] = []
        for e in entries {
            if e.isSeparator {
                lines.append(indent + "---")
                continue
            }
            var line = indent
            if e.checked || e.checkable { line += e.checked ? "[x] " : "[ ] " }
            line += e.title
            if !e.children.isEmpty { line += " ▸" }
            if !e.enabled { line += "  (disabled)" }
            lines.append(line)
            if !e.children.isEmpty { lines.append(dump(e.children, indent: indent + "    ")) }
        }
        return lines.joined(separator: "\n")
    }
}

enum StatusMenu {
    typealias Entry = MenuEntry<StatusMenuAction>

    /// The menu bar item's menu, rebuilt on every open so titles follow the language and checks the settings.
    /// A used-up session limit adds Clawd Run after the widget toggle.
    static func entries(config: Config, widgetVisible: Bool, limitReached: Bool = false) -> [Entry] {
        let lang = config.lang
        let shown = WidgetBlock.shown(in: config)
        func item(_ key: L10nKey, _ action: StatusMenuAction) -> Entry {
            Entry(title: L10n.t(key, lang), action: action)
        }
        func toggle(_ key: L10nKey, _ on: Bool, _ action: StatusMenuAction, enabled: Bool = true) -> Entry {
            Entry(title: L10n.t(key, lang), checked: on, checkable: true, enabled: enabled, action: action)
        }
        let languages = Lang.allCases.map { l in
            Entry(title: l.nativeName, checked: l == lang, checkable: true, action: .language(l))
        }
        // The sky sits in Clawd's play area, so it cannot show without him.
        let blocks = WidgetBlock.allCases.map { b in
            toggle(b.title, shown.contains(b), .toggleBlock(b), enabled: b != .sky || shown.contains(.mascot))
        }
        let play = limitReached ? [item(.menuPlay, .play)] : []
        return [
            Entry(title: AppInfo.title, enabled: false),
            .separator,
            item(widgetVisible ? .menuHide : .menuShow, .toggleWidget),
        ] + play + [
            item(.menuRefresh, .refresh),
            item(.menuBigger, .larger),
            item(.menuSmaller, .smaller),
            toggle(.menuTopmost, config.topmost, .toggleTopmost),
            toggle(.menuLogin, config.launchAtLogin, .toggleLaunchAtLogin),
            toggle(.menuClawd, config.menuBarMascot, .toggleMenuBarMascot),
            item(.menuConfig, .openConfig),
            Entry(title: L10n.t(.menuShown, lang), children: blocks),
            Entry(title: L10n.t(.menuLanguage, lang), children: languages),
            .separator,
            item(.menuQuit, .quit),
        ]
    }
}

/// Runs a closure for a menu item. NSMenuItem holds its target weakly, so the item's representedObject keeps it alive.
final class MenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) { self.run = run }

    @objc func fire(_ sender: Any?) { run() }

    static func item(_ title: String, run: @escaping () -> Void) -> NSMenuItem {
        let box = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        item.target = box
        item.representedObject = box
        return item
    }
}

enum MenuBuilder {
    /// Enabled states are taken as given: AppKit's auto-enabling would enable the disabled header.
    static func menu<Action: Hashable>(_ entries: [MenuEntry<Action>], perform: @escaping (Action) -> Void) -> NSMenu {
        let result = NSMenu()
        result.autoenablesItems = false
        for e in entries {
            if e.isSeparator {
                result.addItem(.separator())
                continue
            }
            let item: NSMenuItem
            if let action = e.action {
                item = MenuAction.item(e.title) { perform(action) }
            } else {
                item = NSMenuItem(title: e.title, action: nil, keyEquivalent: "")
            }
            item.state = e.checked ? .on : .off
            item.isEnabled = e.enabled
            if !e.children.isEmpty { item.submenu = menu(e.children, perform: perform) }
            result.addItem(item)
        }
        return result
    }
}

/// Larger / Smaller: ±0.1 rounded to two decimals like [math]::Round, then clamped so the stored value stays usable.
enum ScaleStep {
    static func larger(_ scale: Double) -> Double { step(scale, ConfigLimits.scaleStep) }
    static func smaller(_ scale: Double) -> Double { step(scale, -ConfigLimits.scaleStep) }

    private static func step(_ scale: Double, _ delta: Double) -> Double {
        let r = ConfigLimits.ranges[.scale]!
        let v = ((scale + delta) * 100).rounded(.toNearestOrEven) / 100
        return min(r.upperBound, max(r.lowerBound, v))
    }
}
