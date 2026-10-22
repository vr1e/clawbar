import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

// Expected values follow history.ps1 Draw-HistoryChart in a 236 × 44 box, with ClawBar's gap and window end.
@Suite struct HistoryChartTests {
    /// Samples.now's minute: Saturday 2026-10-17 14:05 in Berlin.
    static let m = UsageSample.minute(of: Samples.now)
    static let chartOn = Config(expanded: true, showHistory: true)

    private func chart(
        _ history: [UsageSample], issue: UsageIssue? = nil, config: Config = chartOn, lang: Lang = .en, now: Date = Samples.now
    ) throws -> HistoryView {
        let data = sample(data: {
            $0.history = history
            $0.usageIssue = issue
        })
        return try #require(render(data, config: config, lang: lang, now: now).history)
    }

    private func y(_ percent: Double) -> Double { 1 + 42 * (1 - percent / 100) }

    @Test func theChartShowsOnlyWithItsSwitchAndTheDetailsOpen() {
        let d = sample(data: { $0.history = Samples.history })
        #expect(render(d, config: Self.chartOn).history != nil)
        #expect(render(d, config: Config(expanded: true)).history == nil)
        #expect(render(d, config: Config(expanded: false, showHistory: true)).history == nil)
        #expect(render(d, config: Config(expanded: true, showStats: false, showHistory: true)).history != nil)
    }

    @Test func theWeekRunsFromLeftToRightEdgeAndLoneSamplesAreStubs() throws {
        let h = try chart([UsageSample(minute: Self.m - 7 * 1440, session: 10, week: 50), UsageSample(minute: Self.m, session: 20, week: 50)])
        // A week apart is a gap, so each sample stands alone; the newest stubs leftwards to stay inside the clip.
        #expect(h.sessionRuns == [
            [ChartPoint(x: 0, y: y(10)), ChartPoint(x: 1, y: y(10))],
            [ChartPoint(x: 235, y: y(20)), ChartPoint(x: 236, y: y(20))],
        ])
        #expect(h.weekRuns.count == 2)
    }

    @Test func percentagesAreClampedToTheBox() throws {
        let h = try chart([
            UsageSample(minute: Self.m - 10, session: 0), UsageSample(minute: Self.m - 5, session: 100), UsageSample(minute: Self.m, session: 150),
        ])
        #expect(h.sessionRuns.first?.map(\.y) == [43, 1, 1])
        #expect(h.weekRuns.isEmpty)
    }

    @Test func aGapOfTwentyMinutesStillJoinsAtTheDefaultInterval() throws {
        let joined = try chart([UsageSample(minute: Self.m - 40, session: 5), UsageSample(minute: Self.m - 20, session: 6), UsageSample(minute: Self.m, session: 7)])
        #expect(joined.sessionRuns.map(\.count) == [3])
        let broken = try chart([UsageSample(minute: Self.m - 41, session: 5), UsageSample(minute: Self.m - 20, session: 6), UsageSample(minute: Self.m, session: 7)])
        #expect(broken.sessionRuns.map(\.count) == [2, 2])
    }

    @Test func anHourlyProbeStretchesTheGapToThreeIntervalsAndThirtySeconds() throws {
        var config = Self.chartOn
        config.usageIntervalSeconds = 3600
        let joined = try chart([UsageSample(minute: Self.m - 360, session: 5), UsageSample(minute: Self.m - 180, session: 6), UsageSample(minute: Self.m, session: 7)], config: config)
        #expect(joined.sessionRuns.map(\.count) == [3])
        let broken = try chart([UsageSample(minute: Self.m - 361, session: 5), UsageSample(minute: Self.m - 180, session: 6), UsageSample(minute: Self.m, session: 7)], config: config)
        #expect(broken.sessionRuns.map(\.count) == [2, 2])
    }

    @Test func aMissingValueBreaksOnlyItsOwnLine() throws {
        let h = try chart([
            UsageSample(minute: Self.m - 10, session: 30, week: 50),
            UsageSample(minute: Self.m - 5, session: nil, week: 51),
            UsageSample(minute: Self.m, session: 32, week: 52),
        ])
        #expect(h.sessionRuns.map(\.count) == [2, 2])
        #expect(h.weekRuns.map(\.count) == [3])
    }

    @Test func theSampleWeekEndsAtTheRightEdgeOnTheSamplesNumbers() throws {
        let h = try chart(Samples.history)
        #expect(h.sessionRuns.last?.last == ChartPoint(x: 236, y: y(34)))
        #expect(h.weekRuns.last?.last == ChartPoint(x: 236, y: y(59)))
        // The Tuesday-night sleep is the one gap.
        #expect(h.sessionRuns.count == 2 && h.weekRuns.count == 2)
        #expect(h.legend == [ChartLegendItem(text: "5h", color: Palette.ok), ChartLegendItem(text: "week", color: Palette.weekBar)])
        #expect(h.caption.isEmpty)
    }

    @Test func samplesFromAfterNowAreLeftOut() throws {
        let h = try chart([UsageSample(minute: Self.m - 5, session: 30), UsageSample(minute: Self.m + 30, session: 90)])
        #expect(h.sessionRuns == [[ChartPoint(x: 235, y: y(30)), ChartPoint(x: 236, y: y(30))]])
    }

    @Test func betweenSamplesTheChartStandsStillForTenMinutes() throws {
        // 12:05:00 UTC; the newest sample is from 11:58, so the week ends at 12:00 until 12:10.
        let history = [UsageSample(minute: Self.m - 12, session: 30), UsageSample(minute: Self.m - 7, session: 31)]
        let first = try chart(history)
        #expect(try chart(history, now: Samples.now.plus(seconds: 2)) == first)
        #expect(try chart(history, now: Samples.now.plus(minutes: 4, seconds: 59)) == first)
        #expect(try chart(history, now: Samples.now.plus(minutes: 5)) != first)
    }

    @Test func theDaysFollowBerlinsCalendarAcrossTheFallBack() throws {
        // Wednesday 2026-10-28 13:00 CET: the week holds Sunday the 25th, 25 hours long.
        let h = try chart([], now: utc("2026-10-28T12:00:00Z"))
        let midnights = ["2026-10-21T22:00:00Z", "2026-10-22T22:00:00Z", "2026-10-23T22:00:00Z", "2026-10-24T22:00:00Z",
                         "2026-10-25T23:00:00Z", "2026-10-26T23:00:00Z", "2026-10-27T23:00:00Z"]
        let start = UsageSample.minute(of: utc("2026-10-21T12:00:00Z"))
        #expect(h.dayTicks == midnights.map { 236 * Double(UsageSample.minute(of: utc($0)) - start) / 10080 })
        #expect(h.days.map(\.text) == ["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"])
        #expect(h.days.first?.from == 0 && h.days.last?.to == 236)
        #expect(zip(h.days.dropFirst(), h.dayTicks).allSatisfy { $0.from == $1 })
        let german = try chart([], lang: .de, now: utc("2026-10-28T12:00:00Z"))
        #expect(german.days.map(\.text) == ["Mi.", "Do.", "Fr.", "Sa.", "So.", "Mo.", "Di.", "Mi."])
    }

    @Test func aSlotNarrowerThanFourteenGetsNoWeekday() throws {
        // Saturday 14:00 to midnight is 600 minutes, 14.05 wide; from 14:05 it is 13.93.
        #expect(try chart([]).days.first?.text == "Sat")
        let h = try chart([UsageSample(minute: Self.m, session: 34)])
        #expect(h.days.first?.text == "Sun")
        #expect(h.days.count == 7 && h.dayTicks.count == 7)
    }

    @Test func anEmptyWeekSaysTheHistoryStartsNow() throws {
        let h = try chart([])
        #expect(h.caption == "the history starts now" && h.legend.isEmpty)
        #expect(h.sessionRuns.isEmpty && h.weekRuns.isEmpty)
        #expect(try chart([], lang: .de).caption == "der Verlauf beginnt jetzt")
        // Samples older than the week, which the store keeps for a day longer, do not count.
        #expect(try chart([UsageSample(minute: Self.m - 7 * 1440 - 60, session: 40)]).caption == "the history starts now")
    }

    @Test func withoutClaudeOrPlanLimitsAnEmptyWeekSaysNoData() throws {
        #expect(try chart([], issue: .noLimits).caption == "no data")
        #expect(try chart([], issue: .claudeNotFound, lang: .de).caption == "keine Daten")
        #expect(try chart([], issue: .timedOut).caption == "the history starts now")
        // Older samples still draw, with the legend.
        let h = try chart([UsageSample(minute: Self.m - 60, session: 40)], issue: .noLimits)
        #expect(h.caption.isEmpty && h.legend.count == 2 && h.sessionRuns.count == 1)
    }

    @Test func theLabelAndLegendInGerman() throws {
        let h = try chart(Samples.history, lang: .de)
        #expect(h.label == "LIMITS · 7 TAGE")
        #expect(h.legend.map(\.text) == ["5 Std.", "Woche"])
        #expect(try chart([]).label == "LIMITS · 7 DAYS")
    }
}
