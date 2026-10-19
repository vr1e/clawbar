import Foundation
import ClawBarShared

/// The usage samples in usage-history.json: one per change, else one every 5 minutes, kept for 8 days.
struct UsageHistoryStore: Sendable {
    let url: URL
    private(set) var samples: [UsageSample]

    static let keepMinutes = 8 * 24 * 60
    /// An unchanged value is sampled this often.
    static let stepMinutes = 5

    /// Lenient: a malformed row is skipped, and a missing or unreadable file is an empty history.
    init(url: URL, now: Date) {
        self.url = url
        let rows = JSONFile.object(at: url)?["samples"] as? [Any] ?? []
        samples = rows.compactMap(Self.sample).sorted { $0.minute < $1.minute }
        trim(now: UsageSample.minute(of: now))
    }

    /// Adds a sample unless both values equal the last one's and less than 5 minutes passed; true when the samples changed.
    mutating func record(_ u: UsageSnapshot, at date: Date) -> Bool {
        let now = UsageSample.minute(of: date)
        let before = samples
        trim(now: now)
        let sample = UsageSample(minute: now, session: u.sessionPercent, week: u.weekPercent)
        let repeats = samples.last.map {
            $0.session == sample.session && $0.week == sample.week && now - $0.minute < Self.stepMinutes
        } ?? false
        if !repeats { samples.append(sample) }
        return samples != before
    }

    /// Compact, since a busy week is thousands of rows; atomic, so a torn write never empties the history.
    func save() throws {
        let rows = samples.map { [$0.minute, $0.session ?? -1, $0.week ?? -1] }
        try JSONFile.write(["samples": rows], to: url, pretty: false)
    }

    /// Drops samples older than 8 days, and those after a clock set back.
    private mutating func trim(now: Int) {
        samples.removeAll { $0.minute < now - Self.keepMinutes || $0.minute > now }
    }

    /// `[minute, session, week]`, with -1 for a value /usage did not show.
    private static func sample(_ row: Any) -> UsageSample? {
        guard let r = row as? [Any], r.count == 3,
              let minute = Lenient.int(r[0]), let session = Lenient.int(r[1]), let week = Lenient.int(r[2])
        else { return nil }
        return UsageSample(minute: minute, session: session < 0 ? nil : session, week: week < 0 ? nil : week)
    }
}
