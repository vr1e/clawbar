import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

// Expected values follow history.ps1 Show-HistPoint, with ClawBar's gap and weekday names.
@Suite struct HistoryReadoutTests {
    /// Samples.now's minute: Saturday 2026-10-17 14:05 in Berlin.
    static let m = UsageSample.minute(of: Samples.now)
    /// One minute per base unit, ending at Samples.now, so x = 236 − n is n minutes ago.
    static let minuteChart = HistoryView(label: "", start: m - 236, end: m)

    private func input(
        _ history: [UsageSample], lang: Lang = .en, interval: Int = 60, timeZone: TimeZone = Samples.timeZone,
        projects: ProjectUsage? = nil
    ) -> PresenterInput {
        var config = Config(expanded: true, showHistory: true)
        config.language = lang.rawValue
        config.usageIntervalSeconds = interval
        let data = sample(data: {
            $0.history = history
            $0.projects = projects
        })
        return PresenterInput(config: config, now: Samples.now, timeZone: timeZone, data: data, homeDirectory: Samples.home)
    }

    private func caption(
        minutesAgo n: Int, _ history: [UsageSample], interval: Int = 60, timeZone: TimeZone = Samples.timeZone,
        projects: ProjectUsage? = nil
    ) -> String {
        let i = input(history, interval: interval, timeZone: timeZone, projects: projects)
        return HistoryReadout.hover(x: Double(236 - n), chart: Self.minuteChart, input: i).caption
    }

    /// Samples every 5 minutes from two hours ago to 30 minutes ago.
    static let steady = stride(from: m - 120, through: m - 30, by: 5).map { UsageSample(minute: $0, session: 40, week: 50) }

    /// Each project's weight per quarter hour, keyed by how many minutes before Samples.now's minute it starts.
    private func usage(_ projects: [(path: String, quarters: [Int: Double])]) -> ProjectUsage {
        ProjectUsage(projects: projects.map { p in
            ProjectWeight(path: p.path, quarters: Dictionary(uniqueKeysWithValues: p.quarters.map { (Self.m - $0.key, $0.value) }))
        })
    }

    @Test func theRightEdgeReadsTheNewestSampleInBothLanguages() throws {
        for (lang, text) in [(Lang.en, "Sat 14:05  ·  5h 34%  ·  week 59%"), (.de, "Sa. 14:05  ·  5h 34%  ·  Woche 59%")] {
            let i = input(Samples.history, lang: lang)
            let chart = try #require(WidgetPresenter.make(i).history)
            let hover = HistoryReadout.hover(x: 236, chart: chart, input: i)
            #expect(hover == HistoryHover(x: 236, caption: text))
        }
    }

    @Test func aSampleHoldsUntilTheGapRunsOut() {
        let history = [UsageSample(minute: Self.m - 30, session: 40, week: 50)]
        #expect(caption(minutesAgo: 30, history) == "Sat 13:35  ·  5h 40%  ·  week 50%")
        #expect(caption(minutesAgo: 10, history) == "Sat 13:55  ·  5h 40%  ·  week 50%")
        #expect(caption(minutesAgo: 9, history) == "Sat 13:56  ·  no data")
        // An hourly probe stretches the gap to 180.5 minutes, as it does the chart's lines.
        #expect(caption(minutesAgo: 9, history, interval: 3600) == "Sat 13:56  ·  5h 40%  ·  week 50%")
    }

    @Test func beforeTheFirstSampleThereIsNoData() {
        #expect(caption(minutesAgo: 31, [UsageSample(minute: Self.m - 30, session: 40)]) == "Sat 13:34  ·  no data")
        #expect(caption(minutesAgo: 0, []) == "Sat 14:05  ·  no data")
    }

    @Test func aMissingSeriesIsLeftOut() {
        #expect(caption(minutesAgo: 0, [UsageSample(minute: Self.m, week: 52)]) == "Sat 14:05  ·  week 52%")
        #expect(caption(minutesAgo: 0, [UsageSample(minute: Self.m, session: 7)]) == "Sat 14:05  ·  5h 7%")
    }

    @Test func theCursorStaysOnTheChartAndItsMinuteRoundsHalfToEven() {
        func hover(_ x: Double) -> HistoryHover { HistoryReadout.hover(x: x, chart: Self.minuteChart, input: input([])) }
        #expect(hover(-5) == HistoryHover(x: 0, caption: "Sat 10:09  ·  no data"))
        #expect(hover(300) == HistoryHover(x: 236, caption: "Sat 14:05  ·  no data"))
        // The chart starts on an odd minute, so 10:09.5 rounds up and 10:10.5 down.
        #expect(hover(0.5).caption.hasPrefix("Sat 10:10"))
        #expect(hover(1.5).caption.hasPrefix("Sat 10:10"))
        #expect(hover(2.5).caption.hasPrefix("Sat 10:12"))
    }

    @Test func theTimeIsTheInputZones() {
        let hover = HistoryReadout.hover(x: 236, chart: Self.minuteChart, input: input([], timeZone: .gmt))
        #expect(hover.caption == "Sat 12:05  ·  no data")
    }

    /// The quarters of the hovered local hour add up, and the project with the most is named.
    @Test func theHoveredHoursBusiestProjectIsNamed() {
        // Samples.now is 14:05 in Berlin: 80 minutes ago is 12:45, 65 is 13:00, 5 is 14:00.
        let projects = usage([
            ("\(Samples.home)/code/api", [65: 3, 50: 3, 20: 1]),
            ("\(Samples.home)/code/web", [80: 9, 35: 5, 5: 9]),
        ])
        #expect(caption(minutesAgo: 35, Self.steady, projects: projects) == "Sat 13:30  ·  5h 40%  ·  week 50%  ·  api")
        // After a gap in the limits the project still shows, as Show-HistPoint adds it whatever the samples say.
        #expect(caption(minutesAgo: 6, Self.steady, projects: projects) == "Sat 13:59  ·  no data  ·  api")
        #expect(caption(minutesAgo: 0, Self.steady, projects: projects) == "Sat 14:05  ·  no data  ·  web")
    }

    /// India is 5:30 off UTC, where the original's UTC hour would be 16:30 to 17:30 and name `b` at both minutes.
    @Test func theHourIsLocalInAHalfHourZone() throws {
        let india = try #require(TimeZone(identifier: "Asia/Kolkata"))
        // Samples.now is 17:35 there: 95 minutes ago is 16:00, 35 is 17:00, 5 is 17:30.
        let projects = usage([("/srv/a", [95: 4]), ("/srv/b", [35: 1]), ("/srv/c", [5: 9])])
        #expect(caption(minutesAgo: 36, Self.steady, timeZone: india, projects: projects).hasSuffix("  ·  a"))
        #expect(caption(minutesAgo: 35, Self.steady, timeZone: india, projects: projects).hasSuffix("  ·  c"))
    }

    /// Nepal is 5:45 off UTC, where the original's UTC hour would be 16:45 to 17:45 and name `a` at both minutes.
    @Test func theHourIsLocalInAQuarterHourZone() throws {
        let nepal = try #require(TimeZone(identifier: "Asia/Kathmandu"))
        // Samples.now is 17:50 there: 65 minutes ago is 16:45, 50 is 17:00, 5 is 17:45.
        let projects = usage([("/srv/a", [65: 4]), ("/srv/b", [50: 1]), ("/srv/c", [5: 9])])
        #expect(caption(minutesAgo: 51, Self.steady, timeZone: nepal, projects: projects).hasSuffix("  ·  a"))
        #expect(caption(minutesAgo: 50, Self.steady, timeZone: nepal, projects: projects).hasSuffix("  ·  c"))
    }

    @Test func noProjectIsNamedForAnHourWithoutUsageOrBeforeTheFirstScan() {
        let unnamed = "Sat 13:35  ·  5h 40%  ·  week 50%"
        // 125 minutes ago is 12:00, an hour before the hovered one.
        #expect(caption(minutesAgo: 30, Self.steady, projects: usage([("/srv/api", [125: 4])])) == unnamed)
        #expect(caption(minutesAgo: 30, Self.steady, projects: ProjectUsage()) == unnamed)
        #expect(caption(minutesAgo: 30, Self.steady, projects: nil) == unnamed)
    }

    /// The name is the project's row's: its folder's last part, '~' for home, and the parent too when another project
    /// of the week ends the same, even one no row shows.
    @Test func theProjectIsNamedAsItsRowIs() throws {
        #expect(caption(minutesAgo: 30, Self.steady, projects: usage([(Samples.home, [35: 1])])).hasSuffix("  ·  ~"))
        let twins = usage([
            ("\(Samples.home)/work/app", [35: 1, 605: 9]), ("/srv/a", [605: 8]), ("/srv/b", [605: 7]), ("/srv/c", [605: 6]),
            ("\(Samples.home)/play/app", [605: 1]),
        ])
        let row = try #require(WidgetPresenter.make(input([], projects: twins)).projects?.rows.first)
        #expect(row.name == "work/app")
        #expect(caption(minutesAgo: 30, Self.steady, projects: twins).hasSuffix("  ·  work/app"))
    }

    /// The scan lists the week's heavier project first, and it wins a tied hour.
    @Test func aTieGoesToTheWeeksHeavierProject() {
        let tied = usage([("/srv/b", [35: 2, 605: 1]), ("/srv/a", [35: 2])])
        #expect(caption(minutesAgo: 30, Self.steady, projects: tied).hasSuffix("  ·  b"))
    }

    /// `--snapshot`'s history-hover: Thursday 15:49, in an hour the sample projects worked.
    @Test func theSampleWeekNamesTheHoveredHoursProject() throws {
        let i = input(Samples.history, projects: Samples.projects)
        let chart = try #require(WidgetPresenter.make(i).history)
        #expect(HistoryReadout.hover(x: 171, chart: chart, input: i).caption == "Thu 15:49  ·  5h 22%  ·  week 23%  ·  web")
        for p in Samples.projects.projects {
            #expect(p.quarters.count >= 8, "\(p.path)")
        }
    }

    /// Across the sample week, each minute reads the last sample at or before it, as a linear search finds it.
    @Test func everyMinuteOfTheWeekReadsItsSample() {
        let i = input(Samples.history)
        // Steps of 3 meet every offset from the 5-minute samples.
        for minute in stride(from: Self.m - 7 * 1440, through: Self.m, by: 3) {
            // A chart starting at the minute reads it exactly at its left edge.
            let caption = HistoryReadout.hover(x: 0, chart: HistoryView(label: "", start: minute, end: minute + 236), input: i).caption
            guard let s = Samples.history.last(where: { $0.minute <= minute }), minute - s.minute <= 20 else {
                #expect(caption.hasSuffix("no data"), "minute \(minute)")
                continue
            }
            #expect(caption.hasSuffix("  ·  5h \(s.session ?? -1)%  ·  week \(s.week ?? -1)%"), "minute \(minute)")
        }
    }
}
