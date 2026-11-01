import Foundation
import ClawBarShared

/// format.ps1 Format-ResetClock: the clock time a reset falls at, in the input's zone.
public enum ResetClock {
    /// `16:10` today, `tomorrow 00:30`, `Thu 06:00` within the week, `Thu 29 06:00` from a week out.
    public static func text(_ reset: Date, now: Date, timeZone: TimeZone, lang: Lang) -> String {
        let calendar = Calendar.gregorian(in: timeZone)
        // Calendar days, not 24-hour steps, so a DST change or a reset just past midnight lands on the right day.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: reset))
            .day ?? 0
        let c = calendar.dateComponents([.weekday, .day, .hour, .minute], from: reset)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        let weekday = L10n.weekday((c.weekday ?? 1) - 1, lang)
        switch days {
        case ...0: return time
        case 1: return L10n.t(.clockTomorrow, lang, time)
        case 2 ... 6: return "\(weekday) \(time)"
        // A week out the weekday alone would read as today's.
        default: return L10n.t(.clockDate, lang, weekday, c.day ?? 1, time)
        }
    }
}
