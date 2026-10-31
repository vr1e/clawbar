import AppKit
import Observation
import SwiftUI
import ClawBarShared

/// The config the open pages show; set on every applied change, so a hand edit of config.json shows too.
@Observable
final class SettingsModel {
    var config = Config()
}

/// One tab's page: its sections as a grouped form.
struct SettingsPageView: View {
    static let width: CGFloat = 440

    let tab: SettingsTab
    let model: SettingsModel
    let perform: (SettingsAction) -> Void

    var body: some View {
        Form {
            ForEach(Array(SettingsPage.sections(tab, config: model.config).enumerated()), id: \.offset) { _, section in
                Section {
                    ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in self.row(row) }
                } header: {
                    if let header = section.header { Text(header) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func row(_ row: SettingsRow) -> some View {
        switch row {
        case .toggle(let o):
            Toggle(o.title, isOn: Binding(get: { o.on }, set: { _ in perform(o.action) }))
                .disabled(!o.enabled)
        case .picker(let title, let options):
            Picker(title, selection: Binding(
                get: { options.firstIndex(where: \.on) ?? 0 },
                set: { perform(options[$0].action) }
            )) {
                ForEach(options.indices, id: \.self) { Text(options[$0].title).tag($0) }
            }
        case .stepper(let title, let value, let down, let up):
            // A nil closure disables that half of the stepper.
            Stepper(onIncrement: up.map { a in { perform(a) } }, onDecrement: down.map { a in { perform(a) } }) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(value).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        case .note(let text):
            Text(text).font(.callout).foregroundStyle(.secondary)
        case .button(let title, let action):
            Button(title) { perform(action) }
        }
    }
}

/// Closes on Esc and ⌘W, which an accessory app without a main menu does not get for free.
final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The Settings window: opened from the menu, beside the widget like the original's; a change is saved and shown at once.
final class SettingsWindowController {
    var perform: (SettingsAction) -> Void = { _ in }
    private let model = SettingsModel()
    private var window: NSWindow?
    private var tabs: NSTabViewController?

    var isVisible: Bool { window?.isVisible == true }

    func update(config: Config) {
        guard config != model.config else { return }
        let relabel = config.lang != model.config.lang
        model.config = config
        if relabel { label() }
        // As the original: on top of other windows when the widget is.
        window?.level = config.topmost ? .floating : .normal
    }

    /// Placed anew beside the widget each time it opens; brought forward where it is when already open.
    func show(beside widget: CGRect, on screen: CGRect?) {
        let w = window ?? makeWindow()
        if !w.isVisible, let screen {
            // The page's own size, which the tab controller would otherwise apply only after the window is placed.
            if let tabs, let page = tabs.tabViewItems[tabs.selectedTabViewItemIndex].viewController?.view {
                w.setContentSize(page.fittingSize)
            }
            w.setFrameOrigin(SettingsPlacement.origin(size: w.frame.size, widget: widget, visible: screen))
        }
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let page = SettingsPageView(tab: tab, model: model) { [weak self] in self?.perform($0) }
            let host = NSHostingController(rootView: page)
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }
        let w = SettingsWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable]
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.moveToActiveSpace]
        w.level = model.config.topmost ? .floating : .normal
        self.tabs = tabs
        window = w
        label()
        return w
    }

    /// The tabs' names in the current language; the window's title is the selected tab's, as in System Settings.
    private func label() {
        guard let tabs else { return }
        for (item, tab) in zip(tabs.tabViewItems, SettingsTab.allCases) {
            let title = L10n.t(tab.title, model.config.lang)
            item.label = title
            item.viewController?.title = title
        }
        window?.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
    }
}

enum SettingsPlacement {
    static let gap: CGFloat = 8

    /// Left of the widget with the tops aligned, or right of it when the left side lacks room, then kept on screen.
    /// AppKit coordinates.
    static func origin(size: CGSize, widget: CGRect, visible: CGRect) -> CGPoint {
        var x = widget.minX - gap - size.width
        if x < visible.minX, widget.maxX + gap + size.width <= visible.maxX { x = widget.maxX + gap }
        let y = widget.maxY - size.height
        return CGPoint(
            x: min(max(x, visible.minX), visible.maxX - size.width),
            y: min(max(y, visible.minY), visible.maxY - size.height)
        )
    }
}
