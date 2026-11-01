import Foundation
import Testing
import ClawBarShared

/// The presenter resolves the configured theme and accent into the view state's themed roles.
@Suite struct ThemeTests {
    @Test func theConfiguredThemeColoursTheCard() {
        let v = render(config: Config(theme: .fixed(.midnight)))
        #expect(v.palette == Theme.midnight.palette)
        #expect(v.palette.background == RGBA("#FF0F172A") && v.palette.label == RGBA("#FF64748B"))
        #expect(v.otherLimit.color == RGBA("#FF38BDF8"))
        // The levels are not themed.
        #expect(v.pctColor == Palette.ok)
    }

    @Test func oledChangesOnlyTheBackground() {
        let o = Theme.oled.palette, c = ThemePalette.classic
        #expect(o.background == RGBA("#FF000000") && c.background != o.background)
        #expect(
            [o.secondary, o.muted, o.label, o.footer, o.accent, o.modelWeekBar, o.heartOff]
                == [c.secondary, c.muted, c.label, c.footer, c.accent, c.modelWeekBar, c.heartOff]
        )
    }

    @Test func spaceKeepsTheModelWeeksApartFromItsVioletAccent() {
        let v = render(config: Config(theme: .fixed(.space)))
        #expect(v.otherLimit.color == Palette.modelWeekBar)
        #expect(v.modelWeeks.map(\.color) == [RGBA("#FFF472B6")])
        #expect(Theme.allCases.filter { $0 != .space }.allSatisfy { $0.palette.modelWeekBar == Palette.modelWeekBar })
    }

    @Test func bySeasonFollowsTheInputsMonth() {
        // Samples.now is in October.
        #expect(render(config: Config(theme: .bySeason)).palette == Theme.halloween.palette)
        let june = Samples.now.plus(seconds: -120 * 86400)
        #expect(render(config: Config(theme: .bySeason), now: june).palette == .classic)
    }

    @Test func aHandSetAccentReplacesTheThemesAndABadOneLeavesIt() {
        let pink = render(config: Config(theme: .fixed(.forest), accent: "#F472B6"))
        #expect(pink.palette.accent == RGBA("#FFF472B6") && pink.otherLimit.color == RGBA("#FFF472B6"))
        #expect(pink.palette.background == Theme.forest.palette.background)
        #expect(render(config: Config(theme: .fixed(.forest), accent: "pink")).palette == Theme.forest.palette)
    }

    @Test func classicIsTodaysPalette() {
        let c = ThemePalette.classic
        #expect(c.background == Palette.card)
        #expect(c.secondary == Palette.secondary)
        #expect(c.muted == Palette.muted)
        #expect(c.label == Palette.label)
        #expect(c.footer == Palette.footer)
        #expect(c.accent == Palette.weekBar)
        #expect(c.modelWeekBar == Palette.modelWeekBar)
        #expect(c.heartOff == Palette.heartOff)
        #expect(render().palette == c)
    }

    @Test func aNewLabelColourLeavesTheDeadGreyAlone() {
        // One value in classic: recolouring by value would grey the labels and recolour the dead number together.
        #expect(ThemePalette.classic.label == Palette.dead)
        var p = ThemePalette.classic
        p.label = RGBA("#FFFF00FF")
        let empty = render(.empty, palette: p)
        #expect(empty.palette.label == p.label)
        #expect(empty.pctColor == Palette.dead && empty.mainBarColor == Palette.dead)
        #expect(empty.trayColor == Palette.dead && empty.statusDotColor == Palette.dead)
        // The sample's usage is 25 s old and stale past 210 s.
        let stale = render(now: Samples.now.plus(seconds: 211 - 25), palette: p)
        #expect(stale.palette.label == p.label && stale.trayText == "34" && stale.trayColor == Palette.dead)
    }

    @Test func theWeekBarTakesTheAccentAndTheViewStateCarriesIt() throws {
        var p = ThemePalette.classic
        p.accent = RGBA("#FF00FFFF")
        let data = sample(data: { $0.history = Samples.history })
        let v = render(data, config: Config(expanded: true, showHistory: true), palette: p)
        #expect(v.otherLimit.color == p.accent)
        // CardView draws the chart's week line and its legend in this role.
        #expect(try #require(v.history).weekRuns.isEmpty == false)
        #expect(v.palette.accent == p.accent)
        #expect(v.modelWeeks.map(\.color) == [Palette.modelWeekBar])
        #expect(render(.empty, palette: p).otherLimit.color == p.accent)
    }
}
