import AppKit
import ClawBarShared

enum StatusMenuAction: Hashable {
    case toggleWidget, refresh, settings, quit
    /// Opens Clawd Run; offered only while the main limit is used up.
    case play
    /// A recent session's item, by its id; `RecentSessionsMenu.click(for:terminal:)` says what it does.
    case recent(String)
}

/// One menu item as data, so menus can be tested and dumped as text.
struct MenuEntry<Action: Hashable>: Hashable {
    var title: String
    var checked = false
    var enabled = true
    var isSeparator = false
    var action: Action?
    var children: [MenuEntry] = []
    /// The item's hover popup.
    var tooltip = ""

    static var separator: MenuEntry { MenuEntry(title: "", enabled: false, isSeparator: true) }

    /// One line per item: `[x]` for checked items, `▸` for submenus, `(disabled)`, and a tooltip's lines under it.
    static func dump(_ entries: [MenuEntry], indent: String = "  ") -> String {
        var lines: [String] = []
        for e in entries {
            if e.isSeparator {
                lines.append(indent + "---")
                continue
            }
            var line = indent
            if e.checked { line += "[x] " }
            line += e.title
            if !e.children.isEmpty { line += " ▸" }
            if !e.enabled { line += "  (disabled)" }
            lines.append(line)
            lines += e.tooltip.split(separator: "\n").map { indent + "    " + $0 }
            if !e.children.isEmpty { lines.append(dump(e.children, indent: indent + "    ")) }
        }
        return lines.joined(separator: "\n")
    }
}

enum StatusMenu {
    typealias Entry = MenuEntry<StatusMenuAction>

    /// The original's menu since 1.10.0: everything else is in the Settings window. Rebuilt on every open, so titles
    /// follow the language; a used-up main limit adds Clawd Run after the widget toggle. `recent` is ClawBar's own
    /// submenu, nil while it is switched off.
    static func entries(
        config: Config, widgetVisible: Bool, limitReached: Bool = false, recent: [RecentSessionItem]? = nil
    ) -> [Entry] {
        func item(_ key: L10nKey, _ action: StatusMenuAction) -> Entry {
            Entry(title: L10n.t(key, config.lang), action: action)
        }
        let play = limitReached ? [item(.menuPlay, .play)] : []
        return [
            Entry(title: AppInfo.title, enabled: false),
            .separator,
            item(widgetVisible ? .menuHide : .menuShow, .toggleWidget),
        ] + play + (recent.map { [submenu($0, lang: config.lang)] } ?? []) + [
            item(.menuRefresh, .refresh),
            item(.menuSettings, .settings),
            .separator,
            item(.menuQuit, .quit),
        ]
    }

    /// Recent sessions ▸, one item per session.
    private static func submenu(_ items: [RecentSessionItem], lang: Lang) -> Entry {
        let children = items.map { i in
            Entry(title: i.title, enabled: i.clickable, action: i.clickable ? .recent(i.sessionId) : nil, tooltip: i.tooltip)
        }
        let none = [Entry(title: L10n.t(.recentNone, lang), enabled: false)]
        return Entry(title: L10n.t(.menuRecent, lang), children: children.isEmpty ? none : children)
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
            if !e.tooltip.isEmpty { item.toolTip = e.tooltip }
            if !e.children.isEmpty { item.submenu = menu(e.children, perform: perform) }
            result.addItem(item)
        }
        return result
    }
}
