import Foundation
import ClawBarShared

/// history.ps1 Show-HistPoint: the time under the pointer on the 7-day chart and both limits at that moment.
public enum HistoryReadout {
    /// The cursor `x` base units into `chart`, read from the samples the chart drew.
    public static func hover(x: Double, chart: HistoryView, input: PresenterInput) -> HistoryHover {
        let x = min(HistoryView.width, max(0, x))
        let minute = HistoryChart.Box(start: chart.start, end: chart.end).minute(at: x)
        return HistoryHover(x: x, caption: caption(minute: minute, input: input))
    }

    /// `Sat 14:20  ·  5h 34%  ·  week 61%` from the last sample at or before the minute, or `no data` after a gap.
    static func caption(minute: Int, input: PresenterInput) -> String {
        let lang = input.config.lang
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.timeZone
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: UsageSample(minute: minute).date)
        var parts = [L10n.weekday((c.weekday ?? 1) - 1, lang) + String(format: " %02d:%02d", c.hour ?? 0, c.minute ?? 0)]
        let gap = HistoryChart.gapMinutes(usageInterval: input.config.usageIntervalSeconds)
        if let s = last(atOrBefore: minute, in: input.data.history), Double(minute - s.minute) <= gap {
            if let v = s.session { parts.append("\(L10n.t(.histSession, lang)) \(v)%") }
            if let v = s.week { parts.append("\(L10n.t(.histWeek, lang)) \(v)%") }
        } else {
            parts.append(L10n.t(.noData, lang))
        }
        return parts.joined(separator: "  ·  ")
    }

    /// Samples are in time order, so a binary search finds it at pointer rate.
    static func last(atOrBefore minute: Int, in samples: [UsageSample]) -> UsageSample? {
        var lo = 0, hi = samples.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].minute <= minute { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? samples[lo - 1] : nil
    }
}
