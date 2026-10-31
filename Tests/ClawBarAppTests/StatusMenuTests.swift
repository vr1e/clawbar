import AppKit
import Testing
@testable import ClawBar
import ClawBarShared

@Suite struct StatusMenuTests {
    private func titles(_ entries: [MenuEntry<StatusMenuAction>]) -> [String] {
        entries.map { $0.isSeparator ? "---" : $0.title }
    }

    private func entries(_ config: Config = Config(), widgetVisible: Bool = true, limitReached: Bool = false) -> [StatusMenu.Entry] {
        StatusMenu.entries(config: config, widgetVisible: widgetVisible, limitReached: limitReached)
    }

    @Test func theOriginalsShortMenuSince1_10() {
        #expect(titles(entries()) == ["ClawBar v\(AppInfo.version)", "---", "Hide widget", "Refresh now", "Settings…", "---", "Quit ClawBar"])
    }

    @Test func aUsedUpLimitAddsClawdRunAfterTheWidgetToggle() {
        let base = entries()
        let e = entries(limitReached: true)
        #expect(e.count == base.count + 1)
        #expect(e[3].title == "Play Clawd Run…")
        #expect(e[3].action == .play && e[3].enabled)
        #expect(titles(Array(e[..<3]) + Array(e[4...])) == titles(base))
        let de = entries(Config(language: "de"), limitReached: true)
        #expect(de[3].title == L10n.t(.menuPlay, .de))
    }

    @Test func theToggleSaysShowWhileTheWidgetIsHidden() {
        let e = entries(widgetVisible: false)
        #expect(e[2].title == "Show widget")
        #expect(e[2].action == .toggleWidget)
    }

    @Test func germanTitlesComeFromTheGermanTable() {
        let e = entries(Config(language: "de"))
        #expect(Array(titles(e)[2 ... 4]) == [L10nKey.menuHide, .menuRefresh, .menuSettings].map { L10n.t($0, .de) })
        #expect(e.last?.title == L10n.t(.menuQuit, .de))
        #expect(e[0].title == "ClawBar v\(AppInfo.version)")
    }

    @Test func onlyTheHeaderIsDisabledAndEveryItemHasItsAction() {
        let e = entries()
        #expect(!e[0].enabled && e[0].action == nil)
        #expect(e.dropFirst().filter { !$0.isSeparator }.allSatisfy { $0.enabled && !$0.checkable && $0.children.isEmpty })
        #expect(e.compactMap(\.action) == [.toggleWidget, .refresh, .settings, .quit])
    }

    @Test func theNSMenuMirrorsTheModelAndRoutesClicks() {
        let e = entries()
        var got: [StatusMenuAction] = []
        let menu = MenuBuilder.menu(e) { got.append($0) }
        #expect(!menu.autoenablesItems)
        #expect(menu.items.map { $0.isSeparatorItem ? "---" : $0.title } == titles(e))
        #expect(!menu.items[0].isEnabled)
        click(menu.items[3])
        click(menu.items[4])
        click(menu.items[6])
        #expect(got == [.refresh, .settings, .quit])
    }

    @Test func theTextDumpShowsTheDisabledHeader() {
        let dump = MenuEntry.dump(entries(widgetVisible: false))
        #expect(dump.contains("ClawBar v\(AppInfo.version)  (disabled)"))
        #expect(dump.contains("Show widget"))
    }
}

/// Fires an item the way AppKit does, without needing NSApp in the test process.
func click(_ item: NSMenuItem) {
    guard let target = item.target as? NSObject, let action = item.action else {
        Issue.record("\(item.title) has no target/action")
        return
    }
    target.perform(action, with: item)
}
