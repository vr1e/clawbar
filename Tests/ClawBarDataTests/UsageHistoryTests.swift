import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

@Suite struct UsageHistoryTests {
    let t0 = utc("2026-10-16T22:30:00Z")
    let dir = TempDir("cb-hist")
    var m0: Int { UsageSample.minute(of: t0) }
    var url: URL { dir.file("usage-history.json") }
    static let day = 24 * 60

    func usage(_ session: Int?, _ week: Int?) -> UsageSnapshot { UsageSnapshot(sessionPercent: session, weekPercent: week) }

    func store(_ text: String? = nil, now: Date? = nil) -> UsageHistoryStore {
        if let text { dir.write("usage-history.json", text) }
        return UsageHistoryStore(url: url, now: now ?? t0)
    }

    @Test func aChangeIsRecordedAtOnce() {
        var s = store()
        let changed = [s.record(usage(34, 59), at: t0), s.record(usage(35, 59), at: t0 + 60)]
        #expect(changed == [true, true])
        #expect(s.samples == [UsageSample(minute: m0, session: 34, week: 59), UsageSample(minute: m0 + 1, session: 35, week: 59)])
    }

    @Test func anUnchangedValueIsSampledEveryFiveMinutes() {
        var s = store()
        let changed = [
            s.record(usage(34, 59), at: t0), s.record(usage(34, 59), at: t0 + 4 * 60 + 59), s.record(usage(34, 59), at: t0 + 5 * 60),
        ]
        #expect(changed == [true, false, true])
        #expect(s.samples.map(\.minute) == [m0, m0 + 5])
    }

    @Test func theFileIsCompactWithMinusOneForAMissingValue() throws {
        var s = store()
        _ = s.record(usage(nil, 59), at: t0)
        try s.save()
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"samples\":[[\(m0),-1,59]]}\n")
        #expect(store().samples == [UsageSample(minute: m0, session: nil, week: 59)])
    }

    @Test func samplesOlderThanEightDaysAreDroppedOnLoadAndOnRecord() {
        let day = Self.day
        var s = store("{\"samples\":[[\(m0 - 8 * day - 1),10,20],[\(m0 - 8 * day),11,21],[\(m0 - day),12,22]]}")
        #expect(s.samples.map(\.minute) == [m0 - 8 * day, m0 - day])
        _ = s.record(usage(13, 23), at: t0 + 60)
        #expect(s.samples.map(\.minute) == [m0 - day, m0 + 1])
    }

    @Test func malformedRowsAreSkippedAndTheRestSorted() {
        let s = store("{\"samples\":[[\(m0),1,2],\"x\",[\(m0)],[\(m0),true,2],[\(m0),null,2],[\(m0),1,2,3],[\(m0 - 1),3,4]]}")
        #expect(s.samples == [UsageSample(minute: m0 - 1, session: 3, week: 4), UsageSample(minute: m0, session: 1, week: 2)])
        #expect(store("not json").samples.isEmpty)
        #expect(store("{}").samples.isEmpty)
    }

    @Test func aClockSetBackDropsTheSamplesItHasNotReachedAgain() {
        // one from the future is dropped on load
        var s = store("{\"samples\":[[\(m0),34,59],[\(m0 + 10),35,59]]}")
        #expect(s.samples.map(\.minute) == [m0])
        let changed = [s.record(usage(35, 59), at: t0 + 600), s.record(usage(36, 60), at: t0 + 300)]
        #expect(changed == [true, true])
        #expect(s.samples.map(\.minute) == [m0, m0 + 5])
        // dropping alone is a change, though the value repeats the one before
        let dropped = s.record(usage(34, 59), at: t0 + 60)
        #expect(dropped)
        #expect(s.samples == [UsageSample(minute: m0, session: 34, week: 59)])
    }
}
