import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

@Suite struct UsageHistoryTests {
    let t0 = utc("2026-10-16T22:30:00Z")
    let dir = TempDir("cb-hist")
    var m0: Int { UsageSample.minute(of: t0) }
    var url: URL { dir.file("usage-history.json") }

    func record(_ session: Int?, _ week: Int?, at date: Date, into s: inout [UsageSample]) -> Bool {
        UsageHistoryStore.record(UsageSnapshot(sessionPercent: session, weekPercent: week), at: date, into: &s)
    }

    func load(_ text: String? = nil) -> [UsageSample] {
        if let text { dir.write("usage-history.json", text) }
        return UsageHistoryStore(url: url).load(now: t0)
    }

    @Test func aChangeIsRecordedAtOnce() {
        var s: [UsageSample] = []
        let changed = [record(34, 59, at: t0, into: &s), record(35, 59, at: t0 + 60, into: &s)]
        #expect(changed == [true, true])
        #expect(s == [UsageSample(minute: m0, session: 34, week: 59), UsageSample(minute: m0 + 1, session: 35, week: 59)])
    }

    @Test func anUnchangedValueIsSampledEveryFiveMinutes() {
        var s: [UsageSample] = []
        let changed = [
            record(34, 59, at: t0, into: &s), record(34, 59, at: t0 + 4 * 60 + 59, into: &s),
            record(34, 59, at: t0 + 5 * 60, into: &s),
        ]
        #expect(changed == [true, false, true])
        #expect(s.map(\.minute) == [m0, m0 + 5])
    }

    @Test func theFileIsCompactWithMinusOneForAMissingValue() throws {
        let samples = [UsageSample(minute: m0, session: nil, week: 59)]
        try UsageHistoryStore(url: url).save(samples)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"samples\":[[\(m0),-1,59]]}\n")
        #expect(load() == samples)
    }

    @Test func samplesOlderThanEightDaysAreDroppedOnLoadAndOnRecord() {
        let day = 24 * 60
        var s = load("{\"samples\":[[\(m0 - 8 * day - 1),10,20],[\(m0 - 8 * day),11,21],[\(m0),12,22]]}")
        #expect(s.map(\.minute) == [m0 - 8 * day, m0])
        // aging out alone needs no save, since loading drops them too
        let changed = record(12, 22, at: t0 + 60, into: &s)
        #expect(!changed)
        #expect(s.map(\.minute) == [m0])
    }

    @Test func malformedRowsAreSkippedAndTheRestSorted() {
        let s = load("{\"samples\":[[\(m0),1,2],\"x\",[\(m0)],[\(m0),true,2],[\(m0),null,2],[\(m0),1,2,3],[\(m0 - 1),3,4]]}")
        #expect(s == [UsageSample(minute: m0 - 1, session: 3, week: 4), UsageSample(minute: m0, session: 1, week: 2)])
        #expect(load("not json").isEmpty)
        #expect(load("{}").isEmpty)
    }

    @Test func aClockSetBackDropsTheSamplesItHasNotReachedAgain() {
        // one from the future is dropped on load
        var s = load("{\"samples\":[[\(m0),34,59],[\(m0 + 10),35,59]]}")
        #expect(s.map(\.minute) == [m0])
        let changed = [record(35, 59, at: t0 + 600, into: &s), record(36, 60, at: t0 + 300, into: &s)]
        #expect(changed == [true, true])
        #expect(s.map(\.minute) == [m0, m0 + 5])
        // dropping alone needs a save, though the value repeats the one before
        let dropped = record(34, 59, at: t0 + 60, into: &s)
        #expect(dropped)
        #expect(s == [UsageSample(minute: m0, session: 34, week: 59)])
    }
}
