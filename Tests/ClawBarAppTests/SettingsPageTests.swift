import CoreGraphics
import Foundation
import Testing
@testable import ClawBar
import ClawBarShared

@Suite struct SettingsPageTests {
    private func toggles(_ sections: [SettingsSection]) -> [SettingsOption] {
        sections.flatMap(\.rows).compactMap { if case .toggle(let o) = $0 { o } else { nil } }
    }

    private func widget(_ config: Config = Config()) -> [SettingsSection] { SettingsPage.sections(.widget, config: config) }

    @Test func theLookTabPicksTheLanguageByItsOwnName() throws {
        let rows = SettingsPage.sections(.look, config: Config(language: "de")).flatMap(\.rows)
        guard case .picker(let title, let options) = try #require(rows.first) else {
            Issue.record("no language picker")
            return
        }
        #expect(title == "Sprache")
        #expect(options.map(\.title) == ["English", "Deutsch"])
        #expect(options.map(\.on) == [false, true])
        #expect(options.map(\.action) == [.language(.en), .language(.de)])
    }

    @Test func theLookTabPicksTheThemeWithASwatchOfItsColours() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let rows = SettingsPage.sections(.look, config: Config(theme: .bySeason), now: Samples.now, timeZone: berlin)
            .flatMap(\.rows)
        guard case .picker(let title, let options) = rows[1] else {
            Issue.record("no theme picker")
            return
        }
        #expect(title == "Theme")
        #expect(options.map(\.title) == [
            "By season", "Classic", "OLED black", "Midnight", "Mocha", "Forest", "Halloween", "Space", "Underwater",
        ])
        #expect(options.map(\.on) == [true] + Array(repeating: false, count: 8))
        #expect(options.map(\.action) == ThemeChoice.all.map { .theme($0) })
        // By season shows the season's colours: Halloween in October.
        #expect(options[0].swatch == Theme.halloween.palette)
        #expect(options.dropFirst().map(\.swatch) == Theme.allCases.map(\.palette))
    }

    @Test func theWidgetTabKeepsTheOriginalsOrderAndAddsClawBarsSystemSwitches() {
        let s = widget()
        #expect(s.map(\.header) == [nil, "In the widget", "System", nil])
        #expect(toggles(s).map(\.action) == [.toggleTopmost, .toggleMainWeek] + WidgetBlock.allCases.map { .toggleBlock($0) } + [
            .toggleLaunchAtLogin, .toggleMenuBarMascot,
        ])
        #expect(toggles(s).map(\.title) == [
            "Always on top", "Week as the main limit", "Clawd", "Sky and weather behind him", "Anthropic status", "Running sessions", "Plan and account",
            "Last 24 hours and 7 days (details)", "7-day chart and top projects (details)", "Launch at login", "Clawd in menu bar",
        ])
    }

    @Test func switchesFollowTheConfigAndTheSkyNeedsClawd() {
        var config = Config(topmost: true, launchAtLogin: false)
        config.showStats = false
        #expect(toggles(widget(config)).map(\.on) == [true, false, true, true, true, true, true, false, false, false, true])
        #expect(toggles(widget(config)).allSatisfy { $0.enabled })
        config.showMascot = false
        let sky = toggles(widget(config))[3]
        #expect(sky.action == .toggleBlock(.sky) && sky.on && !sky.enabled)
    }

    @Test func theMainWeekSwitchSaysWhatItChanges() {
        let week = toggles(widget(Config(mainLimit: .week)))[1]
        #expect(week.on && week.action == .toggleMainWeek)
        #expect(week.detail == L10n.t(.setMainWeekTip, .en))
        #expect(toggles(widget()).filter { $0.detail != nil }.count == 1)
    }

    @Test func eachBlockTogglesItsOwnConfigKey() {
        func shown(_ c: Config) -> Set<WidgetBlock> { Set(WidgetBlock.allCases.filter { c[keyPath: $0.flag] }) }
        // Every block shows by default but the chart, as in the original.
        #expect(shown(Config()) == Set(WidgetBlock.allCases).subtracting([.history]))
        for b in WidgetBlock.allCases {
            var config = Config()
            config[keyPath: b.flag].toggle()
            #expect(shown(config).symmetricDifference(shown(Config())) == [b])
        }
    }

    @Test func steppersShowPercentAndStopAtTheirEnds() {
        #expect(widget()[0].rows[0] == .stepper(title: "Size", value: "120%", decrease: .step(.size, up: false), increase: .step(.size, up: true)))
        #expect(widget()[0].rows[1] == .stepper(title: "Opacity", value: "100%", decrease: .step(.opacity, up: false), increase: nil))
        let ends = widget(Config(scale: 4.0, opacity: 0.3))[0].rows
        #expect(ends[0] == .stepper(title: "Size", value: "400%", decrease: .step(.size, up: false), increase: nil))
        #expect(ends[1] == .stepper(title: "Opacity", value: "30%", decrease: nil, increase: .step(.opacity, up: true)))
    }

    @Test func everyTabEndsWithConfigJson() {
        for tab in SettingsTab.allCases {
            #expect(SettingsPage.sections(tab, config: Config()).last?.rows.last == .button(title: "Open config.json", action: .openConfig))
        }
    }

    @Test func germanComesFromTheGermanTable() {
        let de = Config(language: "de")
        #expect(widget(de).map(\.header) == [nil, "Im Widget", "System", nil])
        #expect(SettingsTab.allCases.map { L10n.t($0.title, .de) } == ["Darstellung", "Widget"])
        #expect(toggles(widget(de)).last?.title == L10n.t(.setMenuBarMascot, .de))
    }

    @Test func theTextDumpShowsEveryControl() {
        let dump = SettingsPage.dump(config: Config(opacity: 0.3, topmost: true, showMascot: false))
        #expect(dump.contains("  Look:\n    Language: (•) English  ( ) Deutsch"))
        #expect(dump.contains("    Size: − 120% +"))
        #expect(dump.contains("    Opacity:   30% +"))
        #expect(dump.contains("    [x] Always on top\n    [ ] Week as the main limit\n        The big number"))
        #expect(dump.contains("    IN THE WIDGET\n      [ ] Clawd\n      [x] Sky and weather behind him  (disabled)"))
        // The footer stands apart from the System section above it.
        #expect(dump.contains("      [x] Clawd in menu bar\n    The rest"))
        #expect(dump.contains("    [Open config.json]"))
    }
}

@Suite struct SteppedSettingTests {
    @Test func sizeMovesByATenthRoundedToTwoDecimals() {
        #expect(SteppedSetting.size.next(from: 1.2, up: true) == 1.3)
        #expect(SteppedSetting.size.next(from: 1.2, up: false) == 1.1)
        #expect(SteppedSetting.size.next(from: 1.25, up: true) == 1.35)
        #expect(SteppedSetting.size.next(from: 1.3, up: false) == 1.2)
    }

    @Test func sizeStopsAtTheConfigsRange() {
        #expect(SteppedSetting.size.next(from: 3.95, up: true) == 4.0)
        #expect(SteppedSetting.size.next(from: 4.0, up: true) == nil)
        #expect(SteppedSetting.size.next(from: 0.65, up: false) == 0.6)
        #expect(SteppedSetting.size.next(from: 0.6, up: false) == nil)
    }

    @Test func opacityMovesByATwentiethWithinTheOriginalWindowsRange() {
        #expect(SteppedSetting.opacity.next(from: 1.0, up: false) == 0.95)
        #expect(SteppedSetting.opacity.next(from: 0.95, up: true) == 1.0)
        #expect(SteppedSetting.opacity.next(from: 1.0, up: true) == nil)
        #expect(SteppedSetting.opacity.next(from: 0.32, up: false) == 0.3)
        #expect(SteppedSetting.opacity.next(from: 0.3, up: false) == nil)
    }

    @Test func aHandSetOpacityBelowTheRangeStepsUpButNotDown() {
        #expect(SteppedSetting.opacity.next(from: 0.2, up: false) == nil)
        #expect(SteppedSetting.opacity.next(from: 0.2, up: true) == 0.25)
    }

    @Test func tenStepsUpAndDownLeaveNoDrift() {
        var s = 1.2, o = 1.0
        for _ in 0 ..< 10 {
            s = SteppedSetting.size.next(from: s, up: true)!
            o = SteppedSetting.opacity.next(from: o, up: false)!
        }
        #expect(s == 2.2 && o == 0.5)
        for _ in 0 ..< 10 {
            s = SteppedSetting.size.next(from: s, up: false)!
            o = SteppedSetting.opacity.next(from: o, up: true)!
        }
        #expect(s == 1.2 && o == 1.0)
    }
}

@Suite struct SettingsPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 440, height: 500)

    @Test func leftOfTheWidgetWithTheTopsAligned() {
        let widget = CGRect(x: 900, y: 600, width: 300, height: 200)
        #expect(SettingsPlacement.origin(size: size, widget: widget, visible: screen) == CGPoint(x: 452, y: 300))
    }

    @Test func rightOfTheWidgetWhenTheLeftLacksRoom() {
        let widget = CGRect(x: 100, y: 600, width: 300, height: 200)
        #expect(SettingsPlacement.origin(size: size, widget: widget, visible: screen) == CGPoint(x: 408, y: 300))
    }

    @Test func keptOnScreenWhenNeitherSideFitsOrTheWidgetSitsLow() {
        let wide = CGRect(x: 200, y: 50, width: 1100, height: 200)
        #expect(SettingsPlacement.origin(size: size, widget: wide, visible: screen) == CGPoint(x: 0, y: 0))
    }
}
