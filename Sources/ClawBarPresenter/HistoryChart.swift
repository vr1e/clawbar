import Foundation
import ClawBarShared

/// history.ps1 Draw-HistoryChart and Set-HistLegend: the last 7 days of samples laid out in the chart's box.
enum HistoryChart {
    static let windowMinutes = 7 * 1440
    /// The week's end moves in these steps between samples, so the 2-second renders stay equal (the original's redraw key).
    static let stepMinutes = 10
    /// A weekday shows only in a slot at least this wide.
    static let minDayWidth = 14.0

    static func view(_ input: PresenterInput, config: Config, lang: Lang) -> HistoryView {
        let now = UsageSample.minute(of: input.now)
        // Samples after now come from a clock set back; the next recording drops them.
        let samples = input.data.history.filter { $0.minute <= now }
        // Ending at the newest sample keeps it at the right edge instead of up to 10 minutes past it.
        let end = max(now - now % stepMinutes, samples.last?.minute ?? 0)
        let start = end - windowMinutes
        let week = samples.filter { $0.minute >= start }
        let box = Box(start: start, end: end)
        let gap = gapMinutes(usageInterval: config.usageIntervalSeconds)
        let (ticks, days) = dayMarks(box, timeZone: input.timeZone, lang: lang)
        var v = HistoryView(
            label: L10n.t(.uiHist, lang),
            sessionRuns: runs(week, \.session, box, gap: gap),
            weekRuns: runs(week, \.week, box, gap: gap),
            dayTicks: ticks,
            days: days
        )
        if week.isEmpty {
            // Without claude, or under a login without a subscription, no sample is coming, so "starts now" would mislead.
            let issue = input.data.usageIssue
            v.caption = L10n.t(issue == .claudeNotFound || issue == .noLimits ? .noData : .histEmpty, lang)
        } else {
            v.legend = [
                ChartLegendItem(text: L10n.t(.histSession, lang), color: Palette.ok),
                ChartLegendItem(text: L10n.t(.histWeek, lang), color: Palette.weekBar),
            ]
        }
        return v
    }

    /// The original breaks a line after 20 minutes without a sample; a long probe interval stretches that as staleness
    /// does, or every sample would be a stub.
    static func gapMinutes(usageInterval: Int) -> Double { max(20, Double(3 * usageInterval + 30) / 60) }

    /// Unix minutes to the chart's box.
    struct Box {
        let start: Int
        let end: Int

        func x(_ minute: Int) -> Double { HistoryView.width * Double(minute - start) / Double(end - start) }

        /// 1 unit of room above 100% and below 0%, so the stroke is not cut.
        func y(_ percent: Int) -> Double {
            1 + (HistoryView.height - 2) * (1 - Double(min(100, max(0, percent))) / 100)
        }
    }

    /// One series cut into runs at a missing value or a gap.
    static func runs(_ samples: [UsageSample], _ value: KeyPath<UsageSample, Int?>, _ box: Box, gap: Double) -> [[ChartPoint]] {
        var out: [[ChartPoint]] = []
        var run: [ChartPoint] = []
        func flush() {
            if run.count == 1 {
                // A lone sample at the right edge stubs leftwards, or the clip would hide it.
                let p = run[0]
                run = p.x + 1 <= HistoryView.width ? [p, ChartPoint(x: p.x + 1, y: p.y)] : [ChartPoint(x: p.x - 1, y: p.y), p]
            }
            if !run.isEmpty { out.append(run) }
            run = []
        }
        var previous: Int?
        for s in samples {
            let v = s[keyPath: value]
            if v == nil || previous.map({ Double(s.minute - $0) > gap }) == true { flush() }
            previous = s.minute
            if let v { run.append(ChartPoint(x: box.x(s.minute), y: box.y(v))) }
        }
        flush()
        return out
    }

    /// A tick at each local midnight, and under each day its weekday; calendar days, so DST days are 23 or 25 hours.
    static func dayMarks(_ box: Box, timeZone: TimeZone, lang: Lang) -> (ticks: [Double], days: [ChartDay]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func date(_ minute: Int) -> Date { UsageSample(minute: minute).date }
        func nextMidnight(after d: Date) -> Date {
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: d))!)
        }
        var ticks: [Double] = [], days: [ChartDay] = []
        var midnight = nextMidnight(after: date(box.start))
        var from = 0.0
        while true {
            let minute = UsageSample.minute(of: midnight)
            let to = minute < box.end ? box.x(minute) : HistoryView.width
            if to - from >= minDayWidth {
                // The slot holds the day that ends at its midnight.
                let weekday = calendar.component(.weekday, from: midnight.addingTimeInterval(-1))
                days.append(ChartDay(text: L10n.weekday(weekday - 1, lang), from: from, to: to))
            }
            if minute >= box.end { break }
            ticks.append(to)
            from = to
            midnight = nextMidnight(after: midnight)
        }
        return (ticks, days)
    }
}
