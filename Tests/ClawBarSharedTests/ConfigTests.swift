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

    @Test func mainLimitIsTheWeekOnlyWhenItSaysSo() {
        #expect(Config().mainLimit == .session)
        #expect(MainLimit(configValue: "WEEK") == .week)
        #expect(MainLimit(configValue: "weekly") == .session)
        #expect(MainLimit(configValue: nil) == .session)
        #expect(MainLimit.week.other == .session && MainLimit.session.other == .week)
    }

    @Test func theThemeIsClassicUnlessItNamesAnother() {
        #expect(Config().theme == .fixed(.classic))
        #expect(ThemeChoice(configValue: " Auto ") == .bySeason)
        #expect(ThemeChoice(configValue: "OCEAN") == .fixed(.ocean))
        #expect(ThemeChoice(configValue: "cyberpunk") == .fixed(.classic))
        #expect(ThemeChoice(configValue: nil) == .fixed(.classic))
        #expect(ThemeChoice.all.map(\.configValue) == [
            "auto", "classic", "oled", "midnight", "mocha", "forest", "halloween", "space", "ocean",
        ])
    }

    @Test func bySeasonIsHalloweenFromSeptemberToNovemberInTheGivenZone() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        // 31 August, 23:30 UTC: already September in Berlin.
        let edge = Date(timeIntervalSince1970: 1_788_219_000)
        #expect(ThemeChoice.bySeason.theme(at: edge, in: berlin) == .halloween)
        #expect(ThemeChoice.bySeason.theme(at: edge, in: utc) == .classic)
        // 30 November, 23:30 UTC: already December in Berlin.
        let end = Date(timeIntervalSince1970: 1_796_081_400)
        #expect(ThemeChoice.bySeason.theme(at: end, in: utc) == .halloween)
        #expect(ThemeChoice.bySeason.theme(at: end, in: berlin) == .classic)
        #expect(ThemeChoice.fixed(.mocha).theme(at: edge, in: berlin) == .mocha)
    }

    @Test func anAccentThatDoesNotParseIsDropped() {
        #expect(Config(accent: " #F472B6 ").clamped().accent == "#F472B6")
        #expect(Config(accent: "#F472B6").accentColor == RGBA("#FFF472B6"))
        #expect(Config(accent: "#80F472B6").accentColor == RGBA("#80F472B6"))
        for bad in ["F472B6", "#F472B", "#GG72B6", "#+472B6", "pink", ""] {
            #expect(Config(accent: bad).clamped().accent == nil, "\(bad)")
        }
    }

    @Test func everyConfigKeyHasAStableJSONName() {
        #expect(ConfigKey.allCases.count == 30)
        #expect(ConfigKey.theme.rawValue == "theme" && ConfigKey.accent.rawValue == "accent")
        #expect(ConfigKey.mainLimit.rawValue == "mainLimit")
        #expect(ConfigKey.showHistory.rawValue == "showHistory")
        #expect(ConfigKey.usageIntervalSeconds.rawValue == "usageIntervalSeconds")
        #expect(ConfigKey.launchAtLogin.rawValue == "launchAtLogin")
        #expect(ConfigKey.menuBarMascot.rawValue == "menuBarMascot")
    }
}
