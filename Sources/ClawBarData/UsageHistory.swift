import Foundation
import ClawBarShared

/// The usage samples in usage-history.json: one per change, else one every 5 minutes, kept for 8 days.
struct UsageHistoryStore: Sendable {
    let url: URL

    static let keepMinutes = 8 * 24 * 60
    /// An unchanged value is sampled this often.
    static let stepMinutes = 5

    /// Lenient: a malformed row is skipped, and a missing or unreadable file is an empty history.
    func load(now: Date) -> [UsageSample] {
        let rows = JSONFile.object(at: url)?["samples"] as? [Any] ?? []
        var samples = rows.compactMap(Self.sample).sorted { $0.minute < $1.minute }
        Self.trim(&samples, now: UsageSample.minute(of: now))
        return samples
    }

    /// Compact, since a busy week is thousands of rows; atomic, so a torn write never empties the history.
    func save(_ samples: [UsageSample]) throws {
        let rows = samples.map { [$0.minute, $0.session ?? -1, $0.week ?? -1] }
        try JSONFile.write(["samples": rows], to: url, pretty: false)
    }

    /// Adds a sample unless both values equal the last one's and less than 5 minutes passed. True when the file needs
    /// saving; samples that only aged out can wait, since loading drops them too.
    static func record(_ u: UsageSnapshot, at date: Date, into samples: inout [UsageSample]) -> Bool {
        let now = UsageSample.minute(of: date)
        let setBack = trim(&samples, now: now)
        if let last = samples.last, last.session == u.sessionPercent, last.week == u.weekPercent,
           now - last.minute < stepMinutes {
            return setBack
        }
        samples.append(UsageSample(minute: now, session: u.sessionPercent, week: u.weekPercent))
        return true
    }

    /// Drops samples older than 8 days, and those after a clock set back; true when it dropped any of the latter.
    @discardableResult
    private static func trim(_ samples: inout [UsageSample], now: Int) -> Bool {
        let setBack = samples.contains { $0.minute > now }
        samples.removeAll { $0.minute < now - keepMinutes || $0.minute > now }
        return setBack
    }

    /// `[minute, session, week]`, with -1 for a value /usage did not show.
    private static func sample(_ row: Any) -> UsageSample? {
        guard let r = row as? [Any], r.count == 3,
              let minute = Lenient.int(r[0]), let session = Lenient.int(r[1]), let week = Lenient.int(r[2])
        else { return nil }
        return UsageSample(minute: minute, session: session < 0 ? nil : session, week: week < 0 ? nil : week)
    }
}
