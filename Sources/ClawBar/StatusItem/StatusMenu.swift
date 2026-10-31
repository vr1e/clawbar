import AppKit
import ClawBarShared

enum StatusMenuAction: Hashable {
    case toggleWidget, refresh, settings, quit
    /// Opens Clawd Run; offered only while the session limit is used up.
    case play
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

    /// The original's menu since 1.10.0: everything else is in the Settings window. Rebuilt on every open, so titles
    /// follow the language; a used-up session limit adds Clawd Run after the widget toggle.
    static func entries(config: Config, widgetVisible: Bool, limitReached: Bool = false) -> [Entry] {
        func item(_ key: L10nKey, _ action: StatusMenuAction) -> Entry {
            Entry(title: L10n.t(key, config.lang), action: action)
        }
        let play = limitReached ? [item(.menuPlay, .play)] : []
        return [
            Entry(title: AppInfo.title, enabled: false),
            .separator,
            item(widgetVisible ? .menuHide : .menuShow, .toggleWidget),
        ] + play + [
            item(.menuRefresh, .refresh),
            item(.menuSettings, .settings),
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
