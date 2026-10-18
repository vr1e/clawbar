import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

@Suite struct PresenterTests {
    @Test func theSampleRendersAsDrawnByHand() {
        #expect(differences(render(), .sample) == [])
        #expect(render() == .sample)
    }

    @Test func nothingYetIsThePlaceholder() {
        #expect(differences(render(.empty), .placeholder) == [])
    }

    @Test func theSampleInGerman() {
        let expected = WidgetViewState(
            detailsTooltip: "Details ein-/ausblenden", hideTooltip: "Ausblenden", exitTooltip: "Beenden",
            pctText: "34", pctColor: Palette.ok, sessionFraction: 0.34, sessionBarColor: Palette.ok,
            resetText: "wird in 2h 05min zurückgesetzt",
            week: BarRow(label: "WOCHE", value: "59%  ·  4d 15h", fraction: 0.59, color: Palette.weekBar),
            modelWeeks: [BarRow(label: "FABLE · WOCHE", value: "8%  ·  4d 15h", fraction: 0.08, color: Palette.modelWeekBar)],
            sessionsLabel: "SITZUNGEN",
            sessionsText: "2 Sitzungen  ·  1 aktiv  ·  1 wartend",
            sessionsTooltip: "▶ clawbar — ~/Dev/clawbar\n? notes [permission] — ~/notes",
            statusDotColor: Palette.ok, statusText: "Alle Claude-Systeme betriebsbereit", statusTextColor: Palette.muted,
            statusTooltip: "status.claude.com öffnen",
            dayLabel: "LETZTE 24 STUNDEN · DIESER MAC", dayMain: "3875 Anfragen  ·  23 Sitzungen",
            dayExtra: "87% Subagent-lastige Sitzungen  ·  74% bei maximalem Aufwand  ·  Plugins: alpha 12%",
            week7Label: "LETZTE 7 TAGE", week7Main: "7589 Anfragen  ·  96 Sitzungen",
            week7Extra: "82% Subagent-lastige Sitzungen  ·  70% bei Kontext >150k  ·  Subagents: helper 35%, reviewer 7%, +1 weitere",
            versionText: "v2.1.302  ·  aktuell", versionColor: Palette.muted,
            versionTooltip: "Klicken für das Änderungsprotokoll von Claude Code", versionAction: .open(AppInfo.changelogPage),
            appVersionTooltip: "macOS-Portierung von clawd-usage-winwidget 1.3.0 (MIT)",
            accountText: "Max  ·  user@example.com", accountTooltip: "Max  ·  user@example.com",
            stampText: "14:04:35",
            trayText: "34", trayColor: Palette.ok,
            trayTooltip: "Sitzung 34% · 2h 05min\nWoche 59% · Fable 8%\n2 Sitzungen · 1 aktiv · 1 wartend"
        )
        #expect(differences(render(lang: .de), expected) == [])
    }

    @Test func theLanguageComesFromTheConfigNotTheSystem() {
        var config = Config()
        config.language = "DE "
        let state = WidgetPresenter.make(PresenterInput(
            config: config, now: Samples.now, timeZone: Samples.timeZone, data: .sample, homeDirectory: Samples.home
        ))
        #expect(state.resetText == "wird in 2h 05min zurückgesetzt")
        config.language = "ru"
        #expect(WidgetPresenter.make(PresenterInput(
            config: config, now: Samples.now, timeZone: Samples.timeZone, data: .sample, homeDirectory: Samples.home
        )).resetText == "resets in 2h 05m")
    }

    /// The sample's date is close to the real one, so a stray system clock could pass unnoticed; 2001 cannot.
    @Test func theClockAndZoneAreTheInputsAlone() {
        let then = Date(timeIntervalSince1970: 1_000_000_000)
        var d = DataSnapshot.sample
        d.usage?.sessionReset = then.plus(hours: 2, minutes: 5)
        d.usage?.weekReset = then.plus(days: 4, hours: 15, minutes: 55)
        d.usage?.modelWeeks = []
        d.usageAt = then.plus(seconds: -25)
        d.statusAt = then.plus(seconds: -40)
        let v = WidgetPresenter.make(PresenterInput(
            config: Config(), now: then, timeZone: TimeZone(identifier: "Asia/Tokyo")!, data: d, homeDirectory: Samples.home
        ))
        #expect(v.resetText == "resets in 2h 05m")
        #expect(v.week.value == "59%  ·  4d 15h")
        #expect(v.stampText == "10:46:15")
        #expect(v.statusText == "All Claude systems operational")
    }

    @Test func theSameInputAlwaysGivesTheSameState() {
        #expect(render() == render())
        #expect(render(.empty, lang: .de) == render(.empty, lang: .de))
    }
}
