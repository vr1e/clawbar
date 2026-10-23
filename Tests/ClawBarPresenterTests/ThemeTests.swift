import Foundation
import Testing
@testable import ClawBarPresenter
import ClawBarShared

/// The presenter resolves the themed roles into the view state; no config picks another palette yet, so these
/// hand one to `make` directly.
@Suite struct ThemeTests {
    private func themed(
        _ data: DataSnapshot = .sample, config: Config = Config(), now: Date = Samples.now, palette: ThemePalette
    ) -> WidgetViewState {
        WidgetPresenter.make(
            PresenterInput(config: config, now: now, timeZone: Samples.timeZone, data: data, homeDirectory: Samples.home),
            palette: palette
        )
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
        let empty = themed(.empty, palette: p)
        #expect(empty.palette.label == p.label)
        #expect(empty.pctColor == Palette.dead && empty.sessionBarColor == Palette.dead)
        #expect(empty.trayColor == Palette.dead && empty.statusDotColor == Palette.dead)
        // The sample's usage is 25 s old and stale past 210 s.
        let stale = themed(now: Samples.now.plus(seconds: 211 - 25), palette: p)
        #expect(stale.palette.label == p.label && stale.trayText == "34" && stale.trayColor == Palette.dead)
    }

    @Test func theWeekBarAndTheChartsWeekLineShareTheAccent() throws {
        var p = ThemePalette.classic
        p.accent = RGBA("#FF00FFFF")
        let data = sample(data: { $0.history = Samples.history })
        let v = themed(data, config: Config(expanded: true, showHistory: true), palette: p)
        #expect(v.week.color == p.accent)
        // CardView draws the chart's week line and its legend in this role.
        #expect(try #require(v.history).weekRuns.isEmpty == false)
        #expect(v.palette.accent == p.accent)
        #expect(v.modelWeeks.map(\.color) == [Palette.modelWeekBar])
        #expect(themed(.empty, palette: p).week.color == p.accent)
    }
}
