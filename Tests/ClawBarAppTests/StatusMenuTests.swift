import AppKit
import Testing
@testable import ClawBar
import ClawBarShared

@Suite struct StatusMenuTests {
    let all = Set(WidgetBlock.allCases)

    private func titles(_ entries: [MenuEntry<StatusMenuAction>]) -> [String] {
        entries.map { $0.isSeparator ? "---" : $0.title }
    }

    @Test func englishTitlesInTheOriginalsOrder() {
        let e = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: false, launchAtLogin: false, shown: all)
        #expect(titles(e) == [
            "ClawBar v\(AppInfo.version)", "---", "Hide widget", "Refresh now", "Larger", "Smaller", "Always on top",
            "Launch at login", "Open config.json", "Show in widget", "Language", "---", "Quit ClawBar",
        ])
        #expect(titles(e[9].children) == [
            "Clawd", "Sky and weather behind him", "Anthropic status", "Running sessions", "Plan and account",
            "Last 24 hours and 7 days (details)",
        ])
        #expect(titles(e[10].children) == ["English", "Deutsch"])
    }

    @Test func theToggleSaysShowWhileTheWidgetIsHidden() {
        let e = StatusMenu.entries(lang: .en, widgetVisible: false, topmost: false, launchAtLogin: false, shown: all)
        #expect(e[2].title == "Show widget")
        #expect(e[2].action == .toggleWidget)
    }

    @Test func germanTitlesComeFromTheGermanTableAndLanguageNamesStayNative() {
        let e = StatusMenu.entries(lang: .de, widgetVisible: true, topmost: false, launchAtLogin: false, shown: all)
        let keys: [L10nKey] = [
            .menuHide, .menuRefresh, .menuBigger, .menuSmaller, .menuTopmost, .menuLogin, .menuConfig, .menuShown, .menuLanguage,
        ]
        #expect(Array(titles(e)[2 ... 10]) == keys.map { L10n.t($0, .de) })
        #expect(titles(e[9].children) == WidgetBlock.allCases.map { L10n.t($0.title, .de) })
        #expect(e.last?.title == L10n.t(.menuQuit, .de))
        #expect(e[0].title == "ClawBar v\(AppInfo.version)")
        #expect(titles(e[10].children) == ["English", "Deutsch"])
    }

    @Test func checkMarksFollowTheSettings() {
        let off = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: false, launchAtLogin: false, shown: all)
        #expect(!off[6].checked && !off[7].checked)
        #expect(off[10].children.map(\.checked) == [true, false])
        let on = StatusMenu.entries(lang: .de, widgetVisible: true, topmost: true, launchAtLogin: true, shown: all)
        #expect(on[6].checked && on[7].checked)
        #expect(on[10].children.map(\.checked) == [false, true])
        #expect(on.filter { !$0.isSeparator && $0.title != on[6].title && $0.title != on[7].title }.allSatisfy { !$0.checked })
    }

    @Test func onlyTheHeaderIsDisabledAndEveryItemHasItsAction() {
        let e = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: false, launchAtLogin: false, shown: all)
        #expect(!e[0].enabled && e[0].action == nil)
        #expect(e.dropFirst().filter { !$0.isSeparator }.allSatisfy { $0.enabled })
        #expect(e.compactMap(\.action) == [
            .toggleWidget, .refresh, .larger, .smaller, .toggleTopmost, .toggleLaunchAtLogin, .openConfig, .quit,
        ])
        #expect(e[9].children.compactMap(\.action) == WidgetBlock.allCases.map { .toggleBlock($0) })
        #expect(e[10].children.compactMap(\.action) == [.language(.en), .language(.de)])
    }

    @Test func theNSMenuMirrorsTheModelAndRoutesClicks() throws {
        let e = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: true, launchAtLogin: false, shown: all)
        var got: [StatusMenuAction] = []
        let menu = MenuBuilder.menu(e) { got.append($0) }
        #expect(!menu.autoenablesItems)
        #expect(menu.items.map { $0.isSeparatorItem ? "---" : $0.title } == titles(e))
        #expect(!menu.items[0].isEnabled)
        #expect(menu.items[6].state == .on)
        #expect(menu.items[7].state == .off)
        let language = try #require(menu.items[10].submenu)
        #expect(language.items.map(\.title) == ["English", "Deutsch"])
        #expect(language.items.map(\.state) == [.on, .off])

        click(menu.items[3])
        click(language.items[1])
        let shown = try #require(menu.items[9].submenu)
        click(shown.items[4])
        click(menu.items[12])
        #expect(got == [.refresh, .language(.de), .toggleBlock(.account), .quit])
    }

    @Test func theShowInWidgetChecksFollowTheConfigAndTheSkyNeedsClawd() {
        var config = Config()
        config.showStats = false
        config.showAccount = false
        let e = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: false, launchAtLogin: false, shown: WidgetBlock.shown(in: config))
        #expect(e[9].children.map(\.checked) == [true, true, true, true, false, false])
        #expect(e[9].children.allSatisfy { $0.checkable && $0.enabled })
        config.showMascot = false
        let noClawd = StatusMenu.entries(lang: .en, widgetVisible: true, topmost: false, launchAtLogin: false, shown: WidgetBlock.shown(in: config))
        #expect(noClawd[9].children.map(\.checked) == [false, true, true, true, false, false])
        #expect(noClawd[9].children.map(\.enabled) == [true, false, true, true, true, true])
    }

    @Test func eachBlockTogglesItsOwnConfigKey() {
        for b in WidgetBlock.allCases {
            var config = Config()
            config[keyPath: b.flag].toggle()
            #expect(WidgetBlock.shown(in: config) == all.subtracting([b]))
        }
    }

    @Test func theTextDumpShowsChecksAndDisabledItems() {
        let e = StatusMenu.entries(lang: .en, widgetVisible: false, topmost: true, launchAtLogin: false, shown: all)
        let dump = MenuEntry.dump(e)
        #expect(dump.contains("ClawBar v\(AppInfo.version)  (disabled)"))
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
