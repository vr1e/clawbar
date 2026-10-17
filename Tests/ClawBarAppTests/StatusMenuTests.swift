import AppKit
import Testing
@testable import ClawBar
import ClawBarShared

@Suite struct StatusMenuTests {
    private func titles(_ entries: [MenuEntry<StatusMenuAction>]) -> [String] {
        entries.map { $0.isSeparator ? "---" : $0.title }
    }

    @Test func englishTitlesInTheOriginalsOrder() {
        let e = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: false, launchAtLogin: false)
        #expect(titles(e) == [
            "ClawBar v0.1.1", "---", "Hide widget", "Refresh now", "Larger", "Smaller", "Always on top",
            "Launch at login", "Open config.json", "Language", "---", "Quit ClawBar",
        ])
        #expect(titles(e[9].children) == ["English", "Deutsch"])
    }

    @Test func theToggleSaysShowWhileTheWidgetIsHidden() {
        let e = StatusMenu.entries(lang: .en, widgetVisible: false, topmost: false, launchAtLogin: false)
        #expect(e[2].title == "Show widget")
        #expect(e[2].action == .toggleWidget)
    }

    @Test func germanTitlesComeFromTheGermanTableAndLanguageNamesStayNative() {
        let e = StatusMenu.entries(lang: .de, widgetVisible: true, topmost: false, launchAtLogin: false)
        let keys: [L10nKey] = [.menuHide, .menuRefresh, .menuBigger, .menuSmaller, .menuTopmost, .menuLogin, .menuConfig, .menuLanguage]
        #expect(Array(titles(e)[2 ... 9]) == keys.map { L10n.t($0, .de) })
        #expect(e.last?.title == L10n.t(.menuQuit, .de))
        #expect(e[0].title == "ClawBar v0.1.1")
        #expect(titles(e[9].children) == ["English", "Deutsch"])
    }

    @Test func checkMarksFollowTheSettings() {
        let off = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: false, launchAtLogin: false)
        #expect(!off[6].checked && !off[7].checked)
        #expect(off[9].children.map(\.checked) == [true, false])
        let on = StatusMenu.entries(lang: .de, widgetVisible: true, topmost: true, launchAtLogin: true)
        #expect(on[6].checked && on[7].checked)
        #expect(on[9].children.map(\.checked) == [false, true])
        #expect(on.filter { !$0.isSeparator && $0.title != on[6].title && $0.title != on[7].title }.allSatisfy { !$0.checked })
    }

    @Test func onlyTheHeaderIsDisabledAndEveryItemHasItsAction() {
        let e = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: false, launchAtLogin: false)
        #expect(!e[0].enabled && e[0].action == nil)
        #expect(e.dropFirst().filter { !$0.isSeparator }.allSatisfy { $0.enabled })
        #expect(e.compactMap(\.action) == [
            .toggleWidget, .refresh, .larger, .smaller, .toggleTopmost, .toggleLaunchAtLogin, .openConfig, .quit,
        ])
        #expect(e[9].children.compactMap(\.action) == [.language(.en), .language(.de)])
    }

    @Test func theNSMenuMirrorsTheModelAndRoutesClicks() throws {
        let e = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: true, launchAtLogin: false)
        var got: [StatusMenuAction] = []
        let menu = MenuBuilder.menu(e) { got.append($0) }
        #expect(!menu.autoenablesItems)
        #expect(menu.items.map { $0.isSeparatorItem ? "---" : $0.title } == titles(e))
        #expect(!menu.items[0].isEnabled)
        #expect(menu.items[6].state == .on)
        #expect(menu.items[7].state == .off)
        let language = try #require(menu.items[9].submenu)
        #expect(language.items.map(\.title) == ["English", "Deutsch"])
        #expect(language.items.map(\.state) == [.on, .off])

        click(menu.items[3])
        click(language.items[1])
        click(menu.items[11])
        #expect(got == [.refresh, .language(.de), .quit])
    }

    @Test func theTextDumpShowsChecksAndDisabledItems() {
        let e = StatusMenu.entries(lang: .en, widgetVisible: false, topmost: true, launchAtLogin: false)
        let dump = MenuEntry.dump(e)
        #expect(dump.contains("ClawBar v0.1.1  (disabled)"))
        #expect(dump.contains("[x] Always on top"))
        #expect(dump.contains("[ ] Launch at login"))
        #expect(dump.contains("    [x] English"))
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

@Suite struct ScaleStepTests {
    @Test func largerAndSmallerMoveByATenthRoundedToTwoDecimals() {
        #expect(ScaleStep.larger(1.2) == 1.3)
        #expect(ScaleStep.smaller(1.2) == 1.1)
        #expect(ScaleStep.larger(1.25) == 1.35)
        #expect(ScaleStep.smaller(ScaleStep.larger(1.2)) == 1.2)
    }

    @Test func theStoredValueIsClampedUnlikeTheOriginal() {
        #expect(ScaleStep.larger(3.95) == 4.0)
        #expect(ScaleStep.larger(4.0) == 4.0)
        #expect(ScaleStep.smaller(0.65) == 0.6)
        #expect(ScaleStep.smaller(0.6) == 0.6)
    }

    @Test func tenStepsUpAndDownLeaveNoDrift() {
        var s = 1.2
        for _ in 0 ..< 10 { s = ScaleStep.larger(s) }
        #expect(s == 2.2)
        for _ in 0 ..< 10 { s = ScaleStep.smaller(s) }
        #expect(s == 1.2)
    }
}
