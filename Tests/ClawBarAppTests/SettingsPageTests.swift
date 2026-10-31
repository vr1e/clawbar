import CoreGraphics
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

    @Test func theWidgetTabKeepsTheOriginalsOrderAndAddsClawBarsSystemSwitches() {
        let s = widget()
        #expect(s.map(\.header) == [nil, "In the widget", "System", nil])
        #expect(toggles(s).map(\.action) == [.toggleTopmost] + WidgetBlock.allCases.map { .toggleBlock($0) } + [
            .toggleLaunchAtLogin, .toggleMenuBarMascot,
        ])
        #expect(toggles(s).map(\.title) == [
            "Always on top", "Clawd", "Sky and weather behind him", "Anthropic status", "Running sessions", "Plan and account",
            "Last 24 hours and 7 days (details)", "7-day chart and top projects (details)", "Launch at login", "Clawd in menu bar",
        ])
    }

    @Test func switchesFollowTheConfigAndTheSkyNeedsClawd() {
        var config = Config(topmost: true, launchAtLogin: false)
        config.showStats = false
        #expect(toggles(widget(config)).map(\.on) == [true, true, true, true, true, true, false, false, false, true])
        #expect(toggles(widget(config)).allSatisfy { $0.enabled })
        config.showMascot = false
        let sky = toggles(widget(config))[2]
        #expect(sky.action == .toggleBlock(.sky) && sky.on && !sky.enabled)
    }

    @Test func eachBlockTogglesItsOwnConfigKey() {
        // Every block shows by default but the chart, as in the original.
        #expect(WidgetBlock.shown(in: Config()) == Set(WidgetBlock.allCases).subtracting([.history]))
        for b in WidgetBlock.allCases {
            var config = Config()
            config[keyPath: b.flag].toggle()
            #expect(WidgetBlock.shown(in: config).symmetricDifference(WidgetBlock.shown(in: Config())) == [b])
        }
    }

    @Test func steppersShowPercentAndStopAtTheirEnds() {
        #expect(widget()[0].rows[0] == .stepper(title: "Size", value: "120%", decrease: .smaller, increase: .larger))
        #expect(widget()[0].rows[1] == .stepper(title: "Opacity", value: "100%", decrease: .lessOpaque, increase: nil))
        let ends = widget(Config(scale: 4.0, opacity: 0.3))[0].rows
        #expect(ends[0] == .stepper(title: "Size", value: "400%", decrease: .smaller, increase: nil))
        #expect(ends[1] == .stepper(title: "Opacity", value: "30%", decrease: nil, increase: .moreOpaque))
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
        #expect(dump.contains("  Look:\n      Language: (•) English  ( ) Deutsch"))
        #expect(dump.contains("      Size: − 120% +"))
        #expect(dump.contains("      Opacity:   30% +"))
        #expect(dump.contains("      [x] Always on top"))
        #expect(dump.contains("    IN THE WIDGET\n      [ ] Clawd\n      [x] Sky and weather behind him  (disabled)"))
        #expect(dump.contains("      [Open config.json]"))
    }
}

@Suite struct ConfigStepTests {
    @Test func sizeMovesByATenthRoundedToTwoDecimals() {
        #expect(ConfigStep.larger(1.2) == 1.3)
        #expect(ConfigStep.smaller(1.2) == 1.1)
        #expect(ConfigStep.larger(1.25) == 1.35)
        #expect(ConfigStep.smaller(1.3) == 1.2)
    }

    @Test func sizeStopsAtTheConfigsRange() {
        #expect(ConfigStep.larger(3.95) == 4.0)
        #expect(ConfigStep.larger(4.0) == nil)
        #expect(ConfigStep.smaller(0.65) == 0.6)
        #expect(ConfigStep.smaller(0.6) == nil)
    }

    @Test func opacityMovesByATwentiethWithinTheOriginalWindowsRange() {
        #expect(ConfigStep.lessOpaque(1.0) == 0.95)
        #expect(ConfigStep.moreOpaque(0.95) == 1.0)
        #expect(ConfigStep.moreOpaque(1.0) == nil)
        #expect(ConfigStep.lessOpaque(0.32) == 0.3)
        #expect(ConfigStep.lessOpaque(0.3) == nil)
    }

    @Test func aHandSetOpacityBelowTheRangeOnlyMovesBackIntoIt() {
        #expect(ConfigStep.lessOpaque(0.2) == nil)
        #expect(ConfigStep.moreOpaque(0.2) == 0.3)
    }

    @Test func tenStepsUpAndDownLeaveNoDrift() {
        var s = 1.2, o = 1.0
        for _ in 0 ..< 10 {
            s = ConfigStep.larger(s)!
            o = ConfigStep.lessOpaque(o)!
        }
        #expect(s == 2.2 && o == 0.5)
        for _ in 0 ..< 10 {
            s = ConfigStep.smaller(s)!
            o = ConfigStep.moreOpaque(o)!
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
