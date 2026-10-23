import AppKit
import Testing
@testable import ClawBar
import ClawBarShared

@Suite struct StatusMenuTests {
    let all = Set(WidgetBlock.allCases)

    private func titles(_ entries: [MenuEntry<StatusMenuAction>]) -> [String] {
        entries.map { $0.isSeparator ? "---" : $0.title }
    }

    private func entries(_ config: Config = Config(), widgetVisible: Bool = true, limitReached: Bool = false) -> [StatusMenu.Entry] {
        StatusMenu.entries(config: config, widgetVisible: widgetVisible, limitReached: limitReached)
    }

    @Test func englishTitlesInTheOriginalsOrder() {
        let e = entries()
        #expect(titles(e) == [
            "ClawBar v\(AppInfo.version)", "---", "Hide widget", "Refresh now", "Larger", "Smaller", "Always on top",
            "Launch at login", "Clawd in menu bar", "Open config.json", "Show in widget", "Language", "---", "Quit ClawBar",
        ])
        #expect(titles(e[10].children) == [
            "Clawd", "Sky and weather behind him", "Anthropic status", "Running sessions", "Plan and account",
            "Last 24 hours and 7 days (details)", "7-day chart and top projects (details)",
        ])
        #expect(titles(e[11].children) == ["English", "Deutsch"])
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

    @Test func germanTitlesComeFromTheGermanTableAndLanguageNamesStayNative() {
        let e = entries(Config(language: "de"))
        let keys: [L10nKey] = [
            .menuHide, .menuRefresh, .menuBigger, .menuSmaller, .menuTopmost, .menuLogin, .menuClawd, .menuConfig, .menuShown,
            .menuLanguage,
        ]
        #expect(Array(titles(e)[2 ... 11]) == keys.map { L10n.t($0, .de) })
        #expect(titles(e[10].children) == WidgetBlock.allCases.map { L10n.t($0.title, .de) })
        #expect(e.last?.title == L10n.t(.menuQuit, .de))
        #expect(e[0].title == "ClawBar v\(AppInfo.version)")
        #expect(titles(e[11].children) == ["English", "Deutsch"])
    }

    @Test func checkMarksFollowTheSettings() {
        let off = entries(Config(launchAtLogin: false, menuBarMascot: false))
        #expect(off.filter(\.checked).isEmpty)
        #expect(off[11].children.map(\.checked) == [true, false])
        let on = entries(Config(language: "de", topmost: true))
        #expect(on.filter(\.checked).map(\.action) == [.toggleTopmost, .toggleLaunchAtLogin, .toggleMenuBarMascot])
        #expect(on[11].children.map(\.checked) == [false, true])
    }

    @Test func onlyTheHeaderIsDisabledAndEveryItemHasItsAction() {
        let e = entries()
        #expect(!e[0].enabled && e[0].action == nil)
        #expect(e.dropFirst().filter { !$0.isSeparator }.allSatisfy { $0.enabled })
        #expect(e.compactMap(\.action) == [
            .toggleWidget, .refresh, .larger, .smaller, .toggleTopmost, .toggleLaunchAtLogin, .toggleMenuBarMascot, .openConfig, .quit,
        ])
        #expect(e[10].children.compactMap(\.action) == WidgetBlock.allCases.map { .toggleBlock($0) })
        #expect(e[11].children.compactMap(\.action) == [.language(.en), .language(.de)])
    }

    @Test func theNSMenuMirrorsTheModelAndRoutesClicks() throws {
        let e = entries(Config(topmost: true, launchAtLogin: false))
        var got: [StatusMenuAction] = []
        let menu = MenuBuilder.menu(e) { got.append($0) }
        #expect(!menu.autoenablesItems)
        #expect(menu.items.map { $0.isSeparatorItem ? "---" : $0.title } == titles(e))
        #expect(!menu.items[0].isEnabled)
        #expect(menu.items[6].state == .on)
        #expect(menu.items[7].state == .off)
        let language = try #require(menu.items[11].submenu)
        #expect(language.items.map(\.title) == ["English", "Deutsch"])
        #expect(language.items.map(\.state) == [.on, .off])

        click(menu.items[3])
        click(menu.items[8])
        click(language.items[1])
        let shown = try #require(menu.items[10].submenu)
        click(shown.items[4])
        click(menu.items[13])
        #expect(got == [.refresh, .toggleMenuBarMascot, .language(.de), .toggleBlock(.account), .quit])
    }

    @Test func theShowInWidgetChecksFollowTheConfigAndTheSkyNeedsClawd() {
        var config = Config()
        config.showStats = false
        config.showAccount = false
        let e = entries(config)
        #expect(e[10].children.map(\.checked) == [true, true, true, true, false, false, false])
        #expect(e[10].children.allSatisfy { $0.checkable && $0.enabled })
        config.showMascot = false
        config.showHistory = true
        let noClawd = entries(config)
        #expect(noClawd[10].children.map(\.checked) == [false, true, true, true, false, false, true])
        #expect(noClawd[10].children.map(\.enabled) == [true, false, true, true, true, true, true])
    }

    @Test func eachBlockTogglesItsOwnConfigKey() {
        // Every block shows by default but the chart, as in the original.
        #expect(WidgetBlock.shown(in: Config()) == all.subtracting([.history]))
        for b in WidgetBlock.allCases {
            var config = Config()
            config[keyPath: b.flag].toggle()
            #expect(WidgetBlock.shown(in: config).symmetricDifference(WidgetBlock.shown(in: Config())) == [b])
        }
    }

    @Test func theTextDumpShowsChecksAndDisabledItems() {
        let e = entries(Config(topmost: true, launchAtLogin: false, menuBarMascot: false), widgetVisible: false)
        let dump = MenuEntry.dump(e)
        #expect(dump.contains("ClawBar v\(AppInfo.version)  (disabled)"))
        #expect(dump.contains("[x] Always on top"))
        #expect(dump.contains("[ ] Launch at login"))
        #expect(dump.contains("[ ] Clawd in menu bar"))
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
