import Foundation
import ClawBarShared

/// history.ps1 Draw-HistoryChart and Set-HistLegend: the last 7 days of samples laid out in the chart's box.
enum HistoryChart {
    static let windowMinutes = 7 * 1440
    /// The week's end moves in these steps between samples, so the 2-second renders stay equal (the original's redraw key).
    static let stepMinutes = 10
    /// A weekday shows only in a slot at least this wide.
    static let minDayWidth = 14.0

    static func view(_ data: DataSnapshot, config: Config, now date: Date, timeZone: TimeZone) -> HistoryView {
        let lang = config.lang
        let now = UsageSample.minute(of: date)
        // Samples after now come from a clock set back; the next recording drops them.
        let samples = data.history.prefix { $0.minute <= now }
        // Ending at the newest sample keeps it at the right edge instead of up to 10 minutes past it.
        let end = max(now - now % stepMinutes, samples.last?.minute ?? 0)
        let box = Box(start: end - windowMinutes, end: end)
        let week = samples.drop { $0.minute < box.start }
        let gap = gapMinutes(usageInterval: config.usageIntervalSeconds)
        // Without claude or plan limits no sample is coming, so "starts now" would mislead.
        let empty: L10nKey = data.usageIssue?.voidsLimits == true ? .noData : .histEmpty
        return HistoryView(
            label: L10n.t(.uiHist, lang),
            sessionName: L10n.t(.histSession, lang),
            weekName: L10n.t(.histWeek, lang),
            sessionRuns: runs(week, \.session, box, gap: gap),
            weekRuns: runs(week, \.week, box, gap: gap),
            days: days(box, timeZone: timeZone, lang: lang),
            caption: week.isEmpty ? L10n.t(empty, lang) : "",
            start: box.start,
            end: box.end
        )
    }

    /// The original breaks a line after 20 minutes without a sample; a long probe interval stretches that as staleness
    /// does, or every sample would be a stub.
    static func gapMinutes(usageInterval: Int) -> Double { max(20, DataSnapshot.staleAfter(interval: usageInterval) / 60) }

    /// Unix minutes to the chart's box.
    struct Box {
        let start: Int
        let end: Int

        func x(_ minute: Int) -> Double { HistoryView.width * Double(minute - start) / Double(end - start) }
    }

    /// 1 unit of room above 100% and below 0%, so the stroke is not cut.
    static func y(_ percent: Int) -> Double { 1 + (HistoryView.height - 2) * (1 - Double(min(100, max(0, percent))) / 100) }

    /// One series cut into runs at a missing value or a gap.
    static func runs(_ samples: ArraySlice<UsageSample>, _ value: KeyPath<UsageSample, Int?>, _ box: Box, gap: Double) -> [[CGPoint]] {
        var out: [[CGPoint]] = [[]]
        var previous: Int?
        for s in samples {
            let v = s[keyPath: value]
            if v == nil || previous.map({ Double(s.minute - $0) > gap }) == true { out.append([]) }
            previous = s.minute
            if let v { out[out.count - 1].append(CGPoint(x: box.x(s.minute), y: y(v))) }
        }
        return out.filter { !$0.isEmpty }.map(stub)
    }

    /// A lone sample becomes a 1-wide stub, leftwards at the right edge or the clip would hide it.
    static func stub(_ run: [CGPoint]) -> [CGPoint] {
        guard run.count == 1, let p = run.first else { return run }
        return p.x + 1 <= HistoryView.width ? [p, CGPoint(x: p.x + 1, y: p.y)] : [CGPoint(x: p.x - 1, y: p.y), p]
    }

    /// Each local day the box touches, between its midnights; calendar days, so DST days are 23 or 25 hours.
    static func days(_ box: Box, timeZone: TimeZone, lang: Lang) -> [ChartDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var days: [ChartDay] = []
        var day = calendar.dateInterval(of: .day, for: UsageSample(minute: box.start).date)!
        var from = 0.0
        repeat {
            let minute = UsageSample.minute(of: day.end)
            let to = minute < box.end ? box.x(minute) : HistoryView.width
            let weekday = calendar.component(.weekday, from: day.start)
            days.append(ChartDay(text: to - from >= minDayWidth ? L10n.weekday(weekday - 1, lang) : "", from: from, to: to))
            from = to
            day = calendar.dateInterval(of: .day, for: day.end)!
        } while from < HistoryView.width
        return days
    }
}
