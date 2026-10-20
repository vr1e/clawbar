import AppKit
import ClawBarShared

/// The menu bar item: left-click toggles the widget, right- or ctrl-click opens the menu.
final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let cache = StatusItemImageCache()
    private var tooltip: String?
    var onToggle: () -> Void = {}
    /// Built on every open, so titles follow the language and check marks the settings.
    var menuProvider: () -> NSMenu = { NSMenu() }

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
    }

    func update(text: String, color: RGBA, mascot: Bool, tooltip: String) {
        let image = cache.image(text: text, color: color, mascot: mascot)
        if item.button?.image !== image { item.button?.image = image }
        if tooltip != self.tooltip {
            self.tooltip = tooltip
            item.button?.toolTip = tooltip.isEmpty ? nil : tooltip
            item.button?.setAccessibilityLabel(tooltip.isEmpty ? AppInfo.name : tooltip)
        }
    }

    var isVisible: Bool { item.isVisible && item.button?.window != nil }
    /// The item's window on screen, for `--dump-state`.
    var screenFrame: CGRect? { item.button?.window?.frame }

    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            // Attaching the menu only for this click keeps the left click free for toggling.
            item.menu = menuProvider()
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            onToggle()
        }
    }
}
