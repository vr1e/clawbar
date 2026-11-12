import CoreGraphics
import Foundation
import Testing
@testable import ClawBar
import ClawBarShared

@Suite struct AppEngineTests {
    private func effect(_ action: AppAction, visible: Bool = true) -> AppEffect? {
        AppEngine.effect(of: action, widgetVisible: visible)
    }

    /// The config an action's edit leaves, from `start`.
    private func edited(_ action: AppAction, from start: Config = Config()) -> Config? {
        guard case .edit(let edit) = effect(action) else { return nil }
        var c = start
        edit.apply(to: &c)
        return c
    }

    @Test func everySettingsSwitchFlipsItsOwnSettingAndNoOther() {
        let start = Config()
        let switches: [(SettingsAction, WritableKeyPath<Config, Bool>)] = [
            (.toggleTopmost, \.topmost), (.toggleLaunchAtLogin, \.launchAtLogin),
            (.toggleMenuBarMascot, \.menuBarMascot), (.toggleRecentSessions, \.showRecentSessions),
        ] + WidgetBlock.allCases.map { (.toggleBlock($0), $0.flag) }
        for (action, flag) in switches {
            var expected = start
            expected[keyPath: flag].toggle()
            #expect(edited(.settings(action), from: start) == expected, "\(action)")
        }
    }

    @Test func settingsChoicesWriteTheirValue() {
        #expect(edited(.settings(.toggleMainWeek))?.mainLimit == Config().mainLimit.other)
        #expect(edited(.settings(.language(.de)))?.language == "de")
        #expect(edited(.settings(.theme(.fixed(.ocean))))?.theme == .fixed(.ocean))
        #expect(edited(.settings(.skin("pirate")))?.skin == "pirate")
        #expect(effect(.settings(.openConfig)) == .openConfig)
        #expect(effect(.settings(.openSkinsFolder)) == .openSkinsFolder)
    }

    @Test func aStepAtItsEndLeavesTheValue() {
        var c = Config()
        c.scale = 1.0
        #expect(edited(.settings(.step(.size, up: true)), from: c)?.scale == 1.1)
        c.scale = ConfigKey.scale.setting.range!.upperBound
        #expect(edited(.settings(.step(.size, up: true)), from: c) == c)
    }

    @Test func togglingTheWidgetDependsOnWhetherItShows() {
        #expect(effect(.menu(.toggleWidget), visible: true) == .hideWidget)
        #expect(effect(.menu(.toggleWidget), visible: false) == .showWidget)
        #expect(effect(.remote(.toggle), visible: true) == .hideWidget)
        #expect(effect(.remote(.toggle), visible: false) == .showWidget)
        #expect(effect(.remote(.show), visible: true) == .showWidget)
    }

    @Test func menuItems() {
        #expect(effect(.menu(.refresh)) == .refresh)
        #expect(effect(.menu(.settings)) == .showSettings)
        #expect(effect(.menu(.play)) == .showGame)
        #expect(effect(.menu(.recent("abc"))) == .resumeSession("abc"))
        #expect(effect(.menu(.quit)) == .quit)
    }

    @Test func remoteCommands() {
        #expect(effect(.remote(.larger)) == .edit(.step(.size, up: true)))
        #expect(effect(.remote(.smaller)) == .edit(.step(.size, up: false)))
        #expect(effect(.remote(.lang(.en))) == .edit(.language(.en)))
        #expect(effect(.remote(.refresh)) == .refresh)
        #expect(effect(.remote(.settings)) == .showSettings)
        #expect(effect(.remote(.quit)) == .quit)
    }

    @Test func cardClicks() {
        #expect(edited(.card(.toggleDetails))?.expanded == !Config().expanded)
        #expect(effect(.card(.hide)) == .hideWidget)
        #expect(effect(.card(.play)) == .showGame)
        #expect(effect(.card(.quit)) == .quit)
        #expect(effect(.card(.open(AppInfo.statusPage))) == .open(AppInfo.statusPage))
        #expect(effect(.card(.runUpdate)) == .startClaudeUpdate)
        // The version line while an update runs: a control that does nothing.
        #expect(effect(.card(.nothing)) == nil)
    }

    @Test func theLaunchLoadTakesTheSavedPositionAndReschedulesNothing() {
        var c = Config()
        c.left = 5
        c.top = 6
        c.scale = 99
        let r = AppEngine.load(c)
        #expect(r.config.left == 5 && r.config.top == 6)
        #expect(r.config.scale == ConfigKey.scale.setting.range!.upperBound)
        #expect(!r.rescheduleDataTimer && !r.reconcileLoginItem)
    }

    @Test func aReloadKeepsTheWindowsPositionAndClampsTheRest() {
        var current = Config()
        current.left = 100
        current.top = 200
        var fresh = Config()
        fresh.left = 5
        fresh.top = nil
        fresh.scale = 99
        let r = AppEngine.reload(fresh, over: current)
        #expect(r.config.left == 100 && r.config.top == 200)
        #expect(r.config.scale == ConfigKey.scale.setting.range!.upperBound)
        #expect(!r.rescheduleDataTimer && !r.reconcileLoginItem)
    }

    @Test func aReloadReschedulesOnlyWhatChanged() {
        let current = Config()
        var fresh = current
        fresh.refreshSeconds = current.refreshSeconds + 5
        #expect(AppEngine.reload(fresh, over: current).rescheduleDataTimer)
        #expect(!AppEngine.reload(fresh, over: current).reconcileLoginItem)
        fresh = current
        fresh.launchAtLogin.toggle()
        #expect(AppEngine.reload(fresh, over: current).reconcileLoginItem)
        #expect(!AppEngine.reload(fresh, over: current).rescheduleDataTimer)
    }

    @Test func aPositionIsRoundedHalfToEvenAndWrittenOnlyWhenItMoved() throws {
        var saved = Config()
        let first = try #require(AppEngine.position(of: CGPoint(x: 10.5, y: 11.5), saved: saved))
        #expect(first == (10, 12))
        saved.left = 10
        saved.top = 12
        #expect(AppEngine.position(of: CGPoint(x: 10.4, y: 11.6), saved: saved) == nil)
        #expect(AppEngine.position(of: CGPoint(x: 10, y: 13), saved: saved) != nil)
    }
}
