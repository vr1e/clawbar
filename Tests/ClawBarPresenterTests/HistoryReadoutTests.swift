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

    private func input(_ history: [UsageSample], lang: Lang = .en, interval: Int = 60, timeZone: TimeZone = Samples.timeZone) -> PresenterInput {
        var config = Config(expanded: true, showHistory: true)
        config.language = lang.rawValue
        config.usageIntervalSeconds = interval
        return PresenterInput(config: config, now: Samples.now, timeZone: timeZone, data: sample(data: { $0.history = history }))
    }

    private func caption(minutesAgo n: Int, _ history: [UsageSample], interval: Int = 60) -> String {
        HistoryReadout.hover(x: Double(236 - n), chart: Self.minuteChart, input: input(history, interval: interval)).caption
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
        #expect(hover(0.5).caption.hasPrefix("Sat 10:09"))
        #expect(hover(1.5).caption.hasPrefix("Sat 10:11"))
        #expect(hover(2.5).caption.hasPrefix("Sat 10:11"))
    }

    @Test func theTimeIsTheInputZones() {
        let hover = HistoryReadout.hover(x: 236, chart: Self.minuteChart, input: input([], timeZone: .gmt))
        #expect(hover.caption == "Sat 12:05  ·  no data")
    }

    /// Across the sample week, each x reads the last sample at or before its minute, as a linear search finds it.
    @Test func everyPointOfTheWeekReadsItsSample() throws {
        let i = input(Samples.history)
        let chart = try #require(WidgetPresenter.make(i).history)
        for x in stride(from: 0.0, through: 236, by: 0.37) {
            let minute = chart.start + Int((Double(chart.end - chart.start) * x / 236).rounded(.toNearestOrEven))
            let caption = HistoryReadout.hover(x: x, chart: chart, input: i).caption
            guard let s = Samples.history.last(where: { $0.minute <= minute }), minute - s.minute <= 20 else {
                #expect(caption.hasSuffix("no data"), "x \(x)")
                continue
            }
            #expect(caption.hasSuffix("  ·  5h \(s.session ?? -1)%  ·  week \(s.week ?? -1)%"), "x \(x)")
        }
    }
}
