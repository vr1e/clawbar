import Foundation
import ClawBarShared

/// usage.ps1's parser for the text of `/usage`, extended for 2.1.302: ` at ` stamps, years, zones, time-only
/// stamps, singular headers and every model week.
enum UsageParser {
    enum Outcome: Sendable, Hashable {
        case usage(UsageSnapshot)
        /// Neither the session nor the week line in the `/cost` summary a login without a subscription gets.
        case noLimits(stats: UsageSnapshot)
        /// Neither line in any other answer: a subscription whose limits Claude Code could not fetch, or nothing.
        case unavailable
    }

    /// The outcome, plus every `resets …` text no stamp form reads: a new CLI format would otherwise only blank
    /// the resets.
    static func read(_ raw: String, now: Date, timeZone: TimeZone) -> (outcome: Outcome, unreadStamps: [String]) {
        let text = clean(raw)
        var unread: [String] = []
        func reset(_ stamp: String?) -> Date? {
            guard let stamp else { return nil }
            let at = resetDate(stamp, now: now, timeZone: timeZone)
            if at == nil { unread.append(stamp.trimmingCharacters(in: .whitespaces)) }
            return at
        }
        var u = UsageSnapshot()
        if let m = Rx.first(sessionLine, in: text) {
            u.sessionPercent = Int(m[1] ?? "")
            u.sessionReset = reset(m[2])
        }
        if let m = Rx.first(weekLine, in: text) {
            u.weekPercent = Int(m[1] ?? "")
            u.weekReset = reset(m[2])
        }
        for m in Rx.all(modelWeekLine, in: text) {
            guard let name = m[1]?.trimmingCharacters(in: .whitespaces), let pct = Int(m[2] ?? ""),
                  name.lowercased() != "all models"
            else { continue }
            u.modelWeeks.append(ModelWeek(name: modelName(name), percent: pct, reset: reset(m[3])))
        }
        u.day = period(text, day)
        u.week7 = period(text, week7)
        guard u.sessionPercent != nil || u.weekPercent != nil else {
            // Only a positive sign clears the numbers; anything else keeps them, as the original does.
            guard Rx.matches(costSummary, text) else { return (.unavailable, unread) }
            return (.noLimits(stats: UsageSnapshot(day: u.day, week7: u.week7)), unread)
        }
        return (.usage(u), unread)
    }

    /// A stamp with its digits masked, so the log gets one line per format, not one per window.
    static func shape(_ stamp: String) -> String {
        Rx.replace(digit, in: stamp, with: "#")
    }

    /// Without ANSI codes and carriage returns.
    static func clean(_ s: String) -> String {
        Rx.replace(ansi, in: s, with: "").replacingOccurrences(of: "\r", with: "")
    }

    /// "Oct 17 at 3:30am (Europe/Berlin)", "Sep 16, 7:30am", "Jan 2, 2027 at 6am (…)" or "3:30am (…)".
    static func resetDate(_ stamp: String, now: Date, timeZone: TimeZone) -> Date? {
        if let m = Rx.first(fullStamp, in: stamp) {
            guard let month = Months.number[(m[1] ?? "").lowercased()], let day = Int(m[2] ?? ""), (1 ... 31).contains(day),
                  let (hour, minute) = clock(m[4], m[5], m[6])
            else { return nil }
            let cal = calendar(m[7], else: timeZone)
            if let year = m[3].flatMap({ Int($0) }) {
                return date(cal, year, month, day, hour, minute)
            }
            let thisYear = cal.component(.year, from: now)
            guard let d = date(cal, thisYear, month, day, hour, minute) else { return nil }
            // Around New Year a date well in the past is next year's.
            if d < now.addingTimeInterval(-30 * 86400) { return date(cal, thisYear + 1, month, day, hour, minute) }
            return d
        }
        if let m = Rx.first(timeOnlyStamp, in: stamp) {
            guard let (hour, minute) = clock(m[1], m[2], m[3]) else { return nil }
            let cal = calendar(m[4], else: timeZone)
            let today = cal.dateComponents([.year, .month, .day], from: now)
            guard let y = today.year, let mo = today.month, let d = today.day,
                  let at = date(cal, y, mo, d, hour, minute)
            else { return nil }
            return at < now ? cal.date(byAdding: .day, value: 1, to: at) : at
        }
        return nil
    }

    // MARK: - Pieces

    /// A calendar in the stamp's named zone, or in `fallback` when it names none Foundation knows.
    private static func calendar(_ name: String?, else fallback: TimeZone) -> Calendar {
        Calendar.gregorian(in: name.flatMap { TimeZone(identifier: $0.trimmingCharacters(in: .whitespaces)) } ?? fallback)
    }

    private static func modelName(_ s: String) -> String {
        s.lowercased().hasSuffix(" only") ? String(s.dropLast(5)).trimmingCharacters(in: .whitespaces) : s
    }

    private static func period(_ text: String, _ re: NSRegularExpression) -> UsagePeriod? {
        guard let m = Rx.first(re, in: text),
              let requests = count(m[1]), let sessions = count(m[2])
        else { return nil }
        let lines = (m[3] ?? "").split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return UsagePeriod(requests: requests, sessions: sessions, lines: lines)
    }

    private static func count(_ s: String?) -> Int? {
        s.flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
    }

    /// 12am is midnight and 12pm is noon.
    private static func clock(_ h: String?, _ m: String?, _ ampm: String?) -> (Int, Int)? {
        guard let h = Int(h ?? ""), (1 ... 12).contains(h), let ampm = ampm?.lowercased() else { return nil }
        let minute = Int(m ?? "0") ?? -1
        guard (0 ... 59).contains(minute) else { return nil }
        let hour = ampm == "pm" ? (h == 12 ? 12 : h + 12) : (h == 12 ? 0 : h)
        return (hour, minute)
    }

    /// nil for dates that do not exist, like Feb 30.
    private static func date(_ cal: Calendar, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date? {
        guard let at = cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)),
              cal.component(.day, from: at) == d
        else { return nil }
        return at
    }


    private static let ansi = Rx.make(#"\x1B\[[0-?]*[ -/]*[@-~]|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)?|\x1B[@-_]"#)
    private static let sessionLine = Rx.make(#"Current session:\s*(\d+)%(?:[^\n]*?resets\s*([^\n]+))?"#)
    private static let weekLine = Rx.make(#"Current week \(all models\):\s*(\d+)%(?:[^\n]*?resets\s*([^\n]+))?"#)
    private static let modelWeekLine = Rx.make(#"Current week \(([^)\n]+)\):\s*(\d+)%(?:[^\n]*?resets\s*([^\n]+))?"#)
    private static let day = periodPattern("Last 24h")
    private static let week7 = periodPattern("Last 7d")
    private static let costSummary = Rx.make(#"(?m)^\s*Total cost:"#)
    private static let fullStamp = Rx.make(
        #"(?i)([A-Z][a-z]{2})\.?\s+(\d{1,2})(?:,\s*(\d{4}))?(?:,|\s+at)?\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)(?:\s*\(([^)]+)\))?"#
    )
    private static let timeOnlyStamp = Rx.make(#"(?i)^\s*(\d{1,2})(?::(\d{2}))?\s*([ap]m)(?:\s*\(([^)]+)\))?"#)
    private static let digit = Rx.make(#"\d"#)

    /// The header and its indented lines, up to the first blank or unindented line.
    private static func periodPattern(_ label: String) -> NSRegularExpression {
        Rx.make(
            "(?m)^" + NSRegularExpression.escapedPattern(for: label)
                + #"[^\n]*?(\d[\d,]*)\s+requests?\b[^\n]*?(\d[\d,]*)\s+sessions?\b[^\n]*(?:\n|$)((?:[ \t]+\S[^\n]*(?:\n|$))*)"#
        )
    }
}

/// `claude -p … --output-format json`: the fields the zero-token guard and the parser read.
struct UsageEnvelope: Sendable, Hashable {
    var result: String?
    var isError: Bool
    var numTurns: Int
    var costUSD: Double
    /// Every token count under `usage`, summed; the model usage's counts when those are all zero.
    var tokens: Int
    var modelUsageCount: Int

    init?(data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data), let j = obj as? [String: Any] else { return nil }
        result = j["result"] as? String
        isError = (j["is_error"] as? Bool) ?? false
        numTurns = Lenient.double(j["num_turns"]).map { Int($0) } ?? 0
        costUSD = Lenient.double(j["total_cost_usd"]) ?? 0
        let model = j["modelUsage"] as? [String: Any] ?? [:]
        modelUsageCount = model.count
        let used = Self.tokenSum(j["usage"])
        tokens = used > 0 ? used : Self.tokenSum(model)
    }

    /// The probe never reached the model: no turns, no cost, no tokens, no model usage.
    var spentNothing: Bool { numTurns == 0 && costUSD == 0 && tokens == 0 && modelUsageCount == 0 }


    private static func tokenSum(_ v: Any?, key: String = "") -> Int {
        switch v {
        case let d as [String: Any]:
            return d.reduce(0) { $0 + tokenSum($1.value, key: $1.key) }
        case let a as [Any]:
            return a.reduce(0) { $0 + tokenSum($1, key: key) }
        default:
            guard key.lowercased().contains("token"), let n = Lenient.double(v), n.isFinite else { return 0 }
            return Int(n)
        }
    }
}
