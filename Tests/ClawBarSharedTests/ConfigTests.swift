import Foundation
import Testing
import ClawBarShared

@Suite struct ConfigTests {
    @Test func defaultsMatchThePlan() {
        let c = Config()
        #expect(c.scale == 1.2)
        #expect(c.opacity == 1.0)
        #expect(c.warnPercent == 60)
        #expect(c.critPercent == 85)
        #expect(c.refreshSeconds == 10)
        #expect(c.usageIntervalSeconds == 60)
        #expect(c.versionIntervalSeconds == 3600)
        #expect(c.statusIntervalSeconds == 120)
        #expect(c.accountIntervalSeconds == 600)
        #expect(c.weatherIntervalSeconds == 900)
        #expect(c.topmost == false)
        #expect(c.expanded == false)
        #expect(c.showStats && c.showStatus && c.showSessions && c.showAccount && c.showMascot && c.showSky)
        #expect(c.showHistory == false)
        #expect(c.weatherLat == nil && c.weatherLon == nil)
        #expect(c.left == nil && c.top == nil)
        #expect(c.claudePath == nil)
        #expect(c.launchAtLogin == true)
        #expect(c.menuBarMascot == true)
        #expect(c.lang == .en)
    }

    @Test func clampedPullsEveryNumberIntoItsRange() {
        var c = Config()
        c.refreshSeconds = 1
        c.usageIntervalSeconds = 99999
        c.statusIntervalSeconds = 5
        c.accountIntervalSeconds = 10
        c.versionIntervalSeconds = 100
        c.weatherIntervalSeconds = 100_000
        c.scale = 9
        c.opacity = 0
        let k = c.clamped()
        #expect(k.refreshSeconds == 2)
        #expect(k.usageIntervalSeconds == 3600)
        #expect(k.statusIntervalSeconds == 30)
        #expect(k.accountIntervalSeconds == 60)
        #expect(k.versionIntervalSeconds == 600)
        #expect(k.weatherIntervalSeconds == 86400)
        #expect(k.scale == 4.0)
        #expect(k.opacity == 0.2)
    }

    @Test func warnNeverExceedsCrit() {
        var c = Config()
        c.warnPercent = 90
        c.critPercent = 70
        let k = c.clamped()
        #expect(k.warnPercent == 70)
        #expect(k.critPercent == 70)
    }

    @Test func percentThresholdsStayWithinOneToHundred() {
        var c = Config()
        c.warnPercent = 0
        c.critPercent = 150
        let k = c.clamped()
        #expect(k.warnPercent == 1)
        #expect(k.critPercent == 100)
    }

    @Test func outOfRangeCoordinatesBecomeUnset() {
        var c = Config()
        c.weatherLat = 91
        c.weatherLon = -200
        let k = c.clamped()
        #expect(k.weatherLat == nil)
        #expect(k.weatherLon == nil)
        c.weatherLat = 48.2
        c.weatherLon = 16.37
        #expect(c.clamped().weatherLat == 48.2)
        #expect(c.clamped().weatherLon == 16.37)
    }

    @Test func nonFiniteNumbersFallBackToDefaults() {
        var c = Config()
        c.scale = .nan
        c.opacity = .infinity
        c.left = .nan
        c.top = -.infinity
        let k = c.clamped()
        #expect(k.scale == 1.2)
        #expect(k.opacity == 1.0)
        #expect(k.left == nil)
        #expect(k.top == nil)
    }

    @Test func blankClaudePathIsUnset() {
        var c = Config()
        c.claudePath = "   "
        #expect(c.clamped().claudePath == nil)
        c.claudePath = " /opt/claude "
        #expect(c.clamped().claudePath == "/opt/claude")
    }

    @Test func languageIsCaseInsensitiveAndFallsBackToEnglish() {
        #expect(Lang(configValue: "DE") == .de)
        #expect(Lang(configValue: " de ") == .de)
        #expect(Lang(configValue: "ru") == .en)
        #expect(Lang(configValue: nil) == .en)
        #expect(Lang.de.nativeName == "Deutsch")
        #expect(Lang.en.nativeName == "English")
    }

    @Test func everyConfigKeyHasAStableJSONName() {
        #expect(ConfigKey.allCases.count == 27)
        #expect(ConfigKey.showHistory.rawValue == "showHistory")
        #expect(ConfigKey.usageIntervalSeconds.rawValue == "usageIntervalSeconds")
        #expect(ConfigKey.launchAtLogin.rawValue == "launchAtLogin")
        #expect(ConfigKey.menuBarMascot.rawValue == "menuBarMascot")
    }
}
