import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

// Each expectation is an update.ps1 rule applied by hand to the scenario's input.

/// The menu bar's last line for the sample's sessions.
private let sessionsLine = "\n2 sessions · 1 working · 1 waiting"
private let sessionsLineDE = "\n2 Sitzungen · 1 aktiv · 1 wartend"
@Suite struct SessionBlockTests {
    @Test(arguments: [(59, Palette.ok), (60, Palette.warn), (84, Palette.warn), (85, Palette.crit), (100, Palette.crit)])
    func theLevelColoursTheNumberTheBarAndTheMenuBar(pct: Int, color: RGBA) {
        let v = render(sample { $0.sessionPercent = pct })
        #expect(v.pctText == "\(pct)")
        #expect(v.pctColor == color && v.sessionBarColor == color && v.trayColor == color)
        #expect(v.trayText == "\(pct)")
        #expect(v.sessionFraction == Double(pct) / 100)
    }

    @Test func pastTheLimitTheBarIsFullAndTheNumberHonest() {
        let v = render(sample { $0.sessionPercent = 130 })
        #expect(v.pctText == "130")
        #expect(v.sessionFraction == 1)
    }

    @Test func thresholdsComeFromTheConfigClamped() {
        var config = Config()
        config.warnPercent = 30
        config.critPercent = 50
        #expect(render(sample { $0.sessionPercent = 34 }, config: config).pctColor == Palette.warn)
        // warn above crit is pulled down to crit, as Config.clamped() does.
        config.warnPercent = 90
        config.critPercent = 40
        #expect(render(sample { $0.sessionPercent = 39 }, config: config).pctColor == Palette.ok)
        #expect(render(sample { $0.sessionPercent = 40 }, config: config).pctColor == Palette.crit)
    }

    @Test func theResetLine() {
        #expect(render(sample { $0.sessionReset = Samples.now.plus(minutes: 35) }).resetText == "resets in 35m")
        #expect(render(sample { $0.sessionReset = Samples.now.plus(seconds: -1) }).resetText == "window closed")
        #expect(render(sample { $0.sessionReset = Samples.now }).resetText == "window closed")
        #expect(render(sample { $0.sessionReset = nil }).resetText == "")
        #expect(render(sample { $0.sessionReset = nil }).resetColor == Palette.secondary)
    }

    @Test func withoutASessionNumberItIsLoadingUntilAProbeFinishesThenNoData() {
        var d = DataSnapshot.empty
        #expect(render(d).resetText == "loading...")
        d.usageProbeCompleted = true
        let v = render(d)
        #expect(v.resetText == "no data")
        #expect(v.pctText == "--" && v.pctColor == Palette.dead && v.sessionFraction == 0)
        #expect(v.trayText == "--" && v.trayColor == Palette.dead && v.trayTooltip == "ClawBar: no data")
        #expect(render(d, lang: .de).resetText == "keine Daten")
        #expect(render(DataSnapshot.empty, lang: .de).resetText == "wird geladen …")
    }

    @Test func aWeekWithoutASessionStillShowsNoSessionNumber() {
        let v = render(sample { $0.sessionPercent = nil })
        #expect(v.pctText == "--")
        #expect(v.resetText == "no data")
        #expect(v.week.value == "59%  ·  4d 15h")
        #expect(v.trayTooltip == "ClawBar: no data" + sessionsLine)
    }
}

@Suite struct MenuBarTests {
    @Test func everyLimitGetsALineWithTheTimeLeftAndTheClockTimeOfItsReset() {
        let d = sample {
            $0.modelWeeks = [ModelWeek(name: "Sonnet", percent: 23), ModelWeek(name: "Fable", percent: 8, reset: Samples.now.plus(days: 1))]
        }
        #expect(render(d).trayTooltip
            == "34% of session · 2h 05m (16:10)\nweek 59% · 4d 15h (Thu 06:00)\nSonnet 23%\nFable 8% · 1d 0h (tomorrow 14:05)" + sessionsLine)
        #expect(render(d, lang: .de).trayTooltip
            == "Sitzung 34% · 2h 05min (16:10)\nWoche 59% · 4d 15h (Do. 06:00)\nSonnet 23%\nFable 8% · 1d 0h (morgen 14:05)" + sessionsLineDE)
    }

    @Test func aResetAWeekOutNamesItsDay() {
        let d = sample { $0.weekReset = Samples.now.plus(days: 7, minutes: -5) }
        #expect(render(d).trayTooltip.contains("\nweek 59% · 6d 23h (Sat 24 14:00)\n"))
        #expect(render(d, lang: .de).trayTooltip.contains("\nWoche 59% · 6d 23h (Sa. 24. 14:00)\n"))
    }

    @Test func partsThatAreMissingAreLeftOut() {
        let d = sample {
            $0.sessionReset = nil
            $0.weekPercent = nil
            $0.modelWeeks = []
        }
        #expect(render(d).trayTooltip == "34% of session" + sessionsLine)
        let closed = sample { $0.sessionReset = Samples.now.plus(minutes: -5) }
        #expect(render(closed).trayTooltip == "34% of session\nweek 59% · 4d 15h (Thu 06:00)\nFable 8% · 4d 15h (Thu 06:00)" + sessionsLine)
        // A latched probe keeps a week whose reset has passed; it shows no stale clock time.
        let weekOver = sample { $0.weekReset = Samples.now.plus(minutes: -5) }
        #expect(render(weekOver).trayTooltip.contains("\nweek 59%\nFable 8%"))
    }

    @Test func theTooltipIsNotCutAt63Characters() {
        let d = sample {
            $0.modelWeeks = [
                ModelWeek(name: "Sonnet", percent: 23), ModelWeek(name: "Fable", percent: 8),
                ModelWeek(name: "Opus", percent: 41), ModelWeek(name: "Haiku", percent: 2),
            ]
        }
        let tip = render(d).trayTooltip
        #expect(tip.count > 63)
        #expect(tip.contains("\nHaiku 2%\n"))
    }

    @Test func staleNumbersGreyThePillAndSayWhenTheyAreFrom() {
        // The sample's usage is 25 s old; stale past 3 × 60 s + 30 s, as the widget's stamp.
        let fresh = render(now: Samples.now.plus(seconds: 210 - 25))
        #expect(fresh.trayColor == Palette.ok && !fresh.trayTooltip.contains("stale"))
        let stale = render(now: Samples.now.plus(seconds: 211 - 25))
        #expect(stale.trayText == "34" && stale.trayColor == Palette.dead)
        #expect(stale.trayTooltip.hasSuffix("\nFable 8% · 4d 15h (Thu 06:00)\nstale · 14:04:35" + sessionsLine))
        #expect(render(lang: .de, now: Samples.now.plus(hours: 1)).trayTooltip.hasSuffix("\nFable 8% · 4d 14h (Do. 06:00)\nveraltet · 14:04:35" + sessionsLineDE))
        // The widget keeps its level colours; its stamp already says stale.
        #expect(stale.pctColor == Palette.ok)
    }

    @Test func theStaleLineComesBeforeAnIssueLine() {
        let d = sample(data: { $0.usageIssue = .flagRejected("--output-format") })
        let tip = render(d, now: Samples.now.plus(hours: 1)).trayTooltip
        #expect(tip.contains("\nFable 8% · 4d 14h (Thu 06:00)\nstale · 14:04:35\n"))
    }

    @Test func theSessionsLineComesLastAndOnlyWithSessionsShown() {
        let d = sample(data: { $0.usageIssue = .flagRejected("--output-format") })
        #expect(render(d, now: Samples.now.plus(hours: 1)).trayTooltip.hasSuffix(
            "\nstale · 14:04:35\nclaude rejects --output-format\nChecks paused until Claude Code updates" + sessionsLine
        ))
        let limitsOnly = "34% of session · 2h 05m (16:10)\nweek 59% · 4d 15h (Thu 06:00)\nFable 8% · 4d 15h (Thu 06:00)"
        #expect(render(sample(data: { $0.sessions = [] })).trayTooltip == limitsOnly)
        var hidden = Config()
        hidden.showSessions = false
        #expect(render(config: hidden).trayTooltip == limitsOnly)
    }
}

@Suite struct WeekRowTests {
    @Test func noWeekNumberIsNoData() {
        let v = render(sample { $0.weekPercent = nil })
        #expect(v.week == BarRow(label: "WEEK", value: "no data", fraction: 0, color: Palette.weekBar))
    }

    @Test func aPastOrMissingResetShowsOnlyThePercentage() {
        #expect(render(sample { $0.weekReset = Samples.now.plus(hours: -1) }).week.value == "59%")
        #expect(render(sample { $0.weekReset = nil }).week.value == "59%")
        #expect(render(sample { $0.weekPercent = 140 }).week.fraction == 1)
    }

    @Test func everyModelWeekGetsItsOwnRowInOrder() {
        let d = sample {
            $0.modelWeeks = [
                ModelWeek(name: "Sonnet", percent: 23, reset: Samples.now.plus(days: 6, hours: 23, minutes: 59)),
                ModelWeek(name: "Fable", percent: 8),
            ]
        }
        #expect(render(d).modelWeeks == [
            BarRow(label: "SONNET · WEEK", value: "23%  ·  6d 23h", fraction: 0.23, color: Palette.modelWeekBar),
            BarRow(label: "FABLE · WEEK", value: "8%", fraction: 0.08, color: Palette.modelWeekBar),
        ])
        #expect(render(d, lang: .de).modelWeeks.map(\.label) == ["SONNET · WOCHE", "FABLE · WOCHE"])
    }

    @Test func noUsageMeansNoModelRows() {
        #expect(render(.empty).modelWeeks.isEmpty)
        #expect(render(sample { $0.modelWeeks = [] }).modelWeeks.isEmpty)
    }
}

@Suite struct SessionsLineTests {
    private func session(_ name: String, _ state: SessionState, cwd: String = "", waitingFor: String? = nil) -> SessionInfo {
        SessionInfo(pid: 100, name: name, cwd: cwd, state: state, waitingFor: waitingFor)
    }

    private func line(_ sessions: [SessionInfo], _ lang: Lang = .en) -> String {
        render(sample(data: { $0.sessions = sessions }), lang: lang).sessionsText
    }

    @Test func theCountsFollowTheOriginalsRule() {
        #expect(line([]) == "none running")
        #expect(line([session("a", .busy)]) == "1 session  ·  1 working")
        #expect(line([session("a", .idle), session("b", .idle), session("c", .idle)]) == "3 sessions  ·  0 working")
        #expect(line([session("a", .waiting), session("b", .waiting)]) == "2 sessions  ·  2 waiting")
        #expect(line([session("a", .busy), session("b", .waiting), session("c", .idle)]) == "3 sessions  ·  1 working  ·  1 waiting")
    }

    @Test func inGerman() {
        #expect(line([], .de) == "keine offen")
        #expect(line([session("a", .busy)], .de) == "1 Sitzung  ·  1 aktiv")
        #expect(line([session("a", .idle), session("b", .waiting)], .de) == "2 Sitzungen  ·  1 wartend")
    }

    @Test func theTooltipMarksEachSessionAndShortensTheHome() {
        let tip = render(sample(data: {
            $0.sessions = [
                session("api", .busy, cwd: "/Users/example/Dev/api", waitingFor: "permission"),
                session("notes", .waiting, cwd: "/Users/example", waitingFor: "question"),
                session("ask", .waiting, cwd: "/Users/example/ask"),
                session("tmp", .idle, cwd: "/private/tmp/x"),
                session("twin", .idle, cwd: "/Users/example2/twin"),
                session("bare", .idle),
            ]
        })).tooltip(.sessions)
        #expect(tip == """
            ▶ api — ~/Dev/api
            ? notes [question] — ~
            ? ask — ~/ask
            ○ tmp — /private/tmp/x
            ○ twin — /Users/example2/twin
            ○ bare
            """)
    }

    @Test func aHomeWithATrailingSlashOrNoHomeAtAll() {
        func tooltip(home: String) -> String {
            WidgetPresenter.make(PresenterInput(
                config: Config(), now: Samples.now, timeZone: Samples.timeZone, data: .sample, homeDirectory: home
            )).tooltip(.sessions) ?? ""
        }
        #expect(tooltip(home: "/Users/example/") == "▶ clawbar — ~/Dev/clawbar\n? notes [permission] — ~/notes")
        #expect(tooltip(home: "") == "▶ clawbar — /Users/example/Dev/clawbar\n? notes [permission] — /Users/example/notes")
    }

    @Test func noSessionsMeansNoTooltip() {
        #expect(render(sample(data: { $0.sessions = [] })).tooltip(.sessions) == "")
    }
}

@Suite struct StatusRowTests {
    private func status(_ s: ServiceStatus?, age: TimeInterval = 40, lang: Lang = .en) -> WidgetViewState {
        render(sample(data: {
            $0.status = s
            $0.statusAt = s == nil ? nil : Samples.now.plus(seconds: -age)
        }), lang: lang)
    }

    @Test func nothingYetIsLoading() {
        let v = status(nil)
        #expect(v.statusText == "status: loading...")
        #expect(v.statusDotColor == Palette.dead && v.statusTextColor == Palette.muted && v.statusLine2 == "")
        #expect(v.tooltip(.status) == "Open status.claude.com")
    }

    @Test func anOldStatusIsNoConnection() {
        // 3 × 120 s + 30 s.
        #expect(status(ServiceStatus(indicator: "none"), age: 390).statusText == "All Claude systems operational")
        let v = status(ServiceStatus(indicator: "major", incidents: ["Outage"]), age: 391)
        #expect(v.statusText == "status: no connection")
        #expect(v.statusDotColor == Palette.dead && v.statusTextColor == Palette.muted && v.statusLine2 == "")
        #expect(status(ServiceStatus(indicator: "none"), age: 391, lang: .de).statusText == "Status: keine Verbindung")
    }

    @Test func allClear() {
        let v = status(ServiceStatus(indicator: "None"))
        #expect(v.statusText == "All Claude systems operational")
        #expect(v.statusDotColor == Palette.ok && v.statusTextColor == Palette.muted)
    }

    @Test func incidentsAreListedOnAnAmberOrRedDot() {
        let minor = status(ServiceStatus(indicator: "minor", incidents: ["Elevated errors", "Slow logins"]))
        #expect(minor.statusText == "Elevated errors  ·  Slow logins")
        #expect(minor.statusDotColor == Palette.warn && minor.statusTextColor == Palette.secondary)
        #expect(status(ServiceStatus(indicator: "major", incidents: ["Outage"])).statusDotColor == Palette.crit)
        #expect(status(ServiceStatus(indicator: "Critical", incidents: ["Outage"])).statusDotColor == Palette.crit)
        // Incidents under "none" still count as trouble.
        #expect(status(ServiceStatus(indicator: "none", incidents: ["Odd"])).statusDotColor == Palette.warn)
    }

    @Test func withoutIncidentsMaintenanceOrSomeIssues() {
        #expect(status(ServiceStatus(indicator: "maintenance")).statusText == "scheduled maintenance")
        #expect(status(ServiceStatus(indicator: "maintenance")).statusDotColor == Palette.warn)
        let broken = ServiceStatus(indicator: "major", broken: [
            BrokenComponent(name: "Claude API", state: "partial_outage"),
            BrokenComponent(name: "Console", state: "degraded_performance"),
            BrokenComponent(name: "Docs", state: "brand_new_state"),
        ])
        let v = status(broken)
        #expect(v.statusText == "some issues" && v.statusDotColor == Palette.crit)
        #expect(v.statusLine2 == "Claude API: partial outage  ·  Console: degraded  ·  Docs: brand_new_state")
        #expect(status(broken, lang: .de).statusLine2 == "Claude API: teilweiser Ausfall  ·  Console: eingeschränkt  ·  Docs: brand_new_state")
        #expect(status(ServiceStatus(indicator: "none", broken: [BrokenComponent(name: "Docs", state: "under_maintenance")]))
            .statusLine2 == "Docs: maintenance")
    }

    @Test func hiddenWhenTurnedOff() {
        var config = Config()
        config.showStatus = false
        #expect(!render(config: config).shows(.status))
        #expect(render().shows(.status))
    }
}

@Suite struct DetailsTests {
    @Test func periodsShowCountsThenStatLines() {
        let d = sample {
            $0.day = UsagePeriod(requests: 1, sessions: 1, lines: ["100% of your usage was at max effort"])
            $0.week7 = nil
        }
        let v = render(d)
        #expect(v.dayMain == "1 request  ·  1 session" && v.dayExtra == "100% at max effort")
        #expect(v.week7Main == "no data" && v.week7Extra == "")
        #expect(render(d, lang: .de).dayMain == "1 Anfrage  ·  1 Sitzung")
        #expect(render(sample { $0.day = UsagePeriod(requests: 52, sessions: 3) }).dayExtra == "")
    }

    @Test func theDetailsGlyphAndVisibilityFollowTheConfig() {
        var config = Config()
        #expect(render(config: config).detailsGlyph == "▾")
        config.expanded = true
        config.showStats = false
        config.showSessions = false
        config.menuBarMascot = false
        let v = render(config: config)
        #expect(v.detailsGlyph == "▴" && v.detailsExpanded)
        #expect(!v.statsVisible && !v.shows(.sessions) && !v.trayMascot)
        // Hiding a block changes nothing else, but hidden sessions leave the menu bar too; open details add the lines.
        var expected = WidgetViewState.sample
        expected.detailsGlyph = "▴"
        expected.detailsExpanded = true
        expected.statsVisible = false
        expected.parts.removeAll { $0.id == .sessions }
        expected.show(.version, tooltip: "Click for the Claude Code changelog")
        expected.show(.appVersion, tooltip: "macOS port of clawd-usage-winwidget 1.3.0, with some features of later releases (MIT)")
        expected.trayTooltip = "34% of session · 2h 05m (16:10)\nweek 59% · 4d 15h (Thu 06:00)\nFable 8% · 4d 15h (Thu 06:00)"
        expected.trayMascot = false
        #expect(differences(v, expected) == [])
    }

    @Test func theClawBarLineCarriesTheAppVersionAndCreditsTheOriginal() {
        let v = WidgetPresenter.make(PresenterInput(
            config: Config(expanded: true), now: Samples.now, timeZone: Samples.timeZone, data: .sample, appVersion: "9.9.9"
        ))
        #expect(v.appVersionText == "ClawBar v9.9.9")
        #expect(v.tooltip(.appVersion) == "macOS port of clawd-usage-winwidget 1.3.0, with some features of later releases (MIT)")
    }
}

@Suite struct FooterTests {
    @Test func loggedOutIsRed() {
        let v = render(sample(data: { $0.account = AccountInfo(loggedIn: false) }))
        #expect(v.accountText == "not logged in: claude /login" && v.accountColor == Palette.crit && v.tooltip(.account) == "")
        #expect(render(sample(data: { $0.account = AccountInfo(loggedIn: false) }), lang: .de).accountText
            == "nicht angemeldet: claude /login")
    }

    @Test func emptyPartsAreDropped() {
        let v = render(sample(data: { $0.account = AccountInfo(loggedIn: true, plan: "", email: "user@example.com") }))
        #expect(v.accountText == "user@example.com" && v.tooltip(.account) == "user@example.com" && v.accountColor == Palette.footer)
    }

    @Test func noAccountOrTurnedOffIsEmpty() {
        #expect(render(sample(data: { $0.account = nil })).accountText == "")
        var config = Config()
        config.showAccount = false
        let v = render(config: config)
        #expect(v.accountText == "" && !v.shows(.account))
    }

    @Test func theStampTurnsStaleAfterThreeIntervalsAndThirtySeconds() {
        // The sample's usage is 25 s old; stale past 3 × 60 s + 30 s.
        #expect(render(now: Samples.now.plus(seconds: 210 - 25)).stampText == "14:04:35")
        #expect(render(now: Samples.now.plus(seconds: 211 - 25)).stampText == "stale · 14:04:35")
        #expect(render(lang: .de, now: Samples.now.plus(hours: 1)).stampText == "veraltet · 14:04:35")
        var config = Config()
        config.usageIntervalSeconds = 600
        #expect(render(config: config, now: Samples.now.plus(seconds: 1000)).stampText == "14:04:35")
    }

    @Test func theStampUsesTheInputsZone() {
        let v = WidgetPresenter.make(PresenterInput(
            config: Config(), now: Samples.now, timeZone: TimeZone(identifier: "America/New_York")!, data: .sample
        ))
        #expect(v.stampText == "08:04:35")
    }

    @Test func aFailedTickSaysError() {
        #expect(render(tickError: true).stampText == "error")
        #expect(render(lang: .de, tickError: true).stampText == "Fehler")
        #expect(render(.empty, tickError: true).stampText == "error")
    }

    @Test func noUsageYetMeansNoStamp() {
        #expect(render(.empty).stampText == "")
        #expect(render(.empty).stampColor == Palette.footer)
    }
}
