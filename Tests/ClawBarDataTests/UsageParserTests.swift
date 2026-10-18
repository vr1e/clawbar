import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

extension UsageParser {
    /// The outcome alone, which is all most tests look at.
    static func parse(_ raw: String, now: Date, timeZone: TimeZone) -> Outcome {
        read(raw, now: now, timeZone: timeZone).outcome
    }
}

/// Every fixture is a sanitised `/usage` text; `now` is chosen next to its stamps.
@Suite struct UsageParserTests {
    /// 00:30 in Berlin on Oct 17, shortly before the fixtures' 3:29am reset.
    let now = utc("2026-10-16T22:30:00Z")

    func usage(_ fixture: String, now: Date? = nil, zone: TimeZone = berlin) -> UsageSnapshot? {
        guard case .usage(let u) = UsageParser.parse(Fixture.text("usage/\(fixture)"), now: now ?? self.now, timeZone: zone)
        else { return nil }
        return u
    }

    @Test func todaysRealShape() throws {
        let u = try #require(usage("today.txt"))
        #expect(u.sessionPercent == 50)
        // Oct 17 3:29am CEST = 01:29 UTC
        #expect(u.sessionReset == utc("2026-10-17T01:29:00Z"))
        #expect(u.weekPercent == 68)
        #expect(u.weekReset == utc("2026-10-17T03:59:00Z"))
        #expect(u.modelWeeks == [ModelWeek(name: "Fable", percent: 8, reset: utc("2026-10-17T03:59:00Z"))])
        let day = try #require(u.day)
        #expect(day.requests == 4756)
        #expect(day.sessions == 26)
        #expect(day.lines.count == 11)
        #expect(day.lines.first == "89% of your usage came from subagent-heavy sessions")
        #expect(day.lines.last == "Top MCP servers: docs-server 1%")
        let week7 = try #require(u.week7)
        #expect(week7.requests == 7589)
        #expect(week7.sessions == 96)
        #expect(week7.lines.count == 12)
        #expect(week7.lines.contains("Top subagents: helper 35%, tracker:sync 7%, builder 6%, writer 3%, planner 3%, tidy 2%, forker 2%, reviewer 1%, +1 more"))
    }

    @Test func theJSONEnvelopesResultParsesLikeTheText() throws {
        let envelope = try #require(UsageEnvelope(data: Fixture.data("usage/today.json")))
        #expect(UsageParser.parse(envelope.result ?? "", now: now, timeZone: berlin)
            == UsageParser.parse(Fixture.text("usage/today.txt"), now: now, timeZone: berlin))
    }

    @Test func anExplicitYearIsUsedAsIs() throws {
        let u = try #require(usage("year.txt"))
        // Jan 2 2027 6am CET = 05:00 UTC; Jan 5 10:15pm EST = Jan 6 03:15 UTC
        #expect(u.sessionReset == utc("2027-01-02T05:00:00Z"))
        #expect(u.weekReset == utc("2027-01-06T03:15:00Z"))
    }

    @Test func anExplicitYearWinsOverThePastThirtyDaysRule() {
        let text = "Current session: 1% used · resets Jan 2, 2026 at 6am (Europe/Berlin)"
        guard case .usage(let u) = UsageParser.parse(text, now: now, timeZone: berlin) else {
            Issue.record("no usage")
            return
        }
        #expect(u.sessionReset == utc("2026-01-02T05:00:00Z"))
    }

    @Test func aStampMoreThanThirtyDaysBackIsNextYear() {
        let text = "Current week (all models): 3% used · resets Jan 3 at 6am (Europe/Berlin)"
        guard case .usage(let u) = UsageParser.parse(text, now: utc("2026-12-30T12:00:00Z"), timeZone: berlin) else {
            Issue.record("no usage")
            return
        }
        #expect(u.weekReset == utc("2027-01-03T05:00:00Z"))
    }

    @Test func theWindowsEraCommaFormAndAMissingZone() throws {
        // Sep 16 7:30am MSK (+3) = 04:30 UTC; "Sep 21, 6am" has no zone, so the injected Berlin (CEST) applies
        let u = try #require(usage("windows-era.txt", now: utc("2026-09-16T00:00:00Z")))
        #expect(u.sessionPercent == 41)
        #expect(u.sessionReset == utc("2026-09-16T04:30:00Z"))
        #expect(u.weekPercent == 22)
        #expect(u.weekReset == utc("2026-09-21T04:00:00Z"))
        #expect(u.modelWeeks == [ModelWeek(name: "Fable", percent: 3, reset: utc("2026-09-21T04:00:00Z"))])
        #expect(u.day == UsagePeriod(requests: 298, sessions: 12, lines: [
            "45% of your usage was at >200k context",
            "12% of your usage came from subagent-heavy sessions",
            "Top MCP servers: docs-server 4%",
        ]))
    }

    @Test func aTimeOnlyStampIsItsNextOccurrence() throws {
        // 00:30 Berlin: 3:30am is still ahead today
        let before = try #require(usage("time-only.txt"))
        #expect(before.sessionReset == utc("2026-10-17T01:30:00Z"))
        // 04:00 Berlin: today's 3:30am has passed, so tomorrow's
        let after = try #require(usage("time-only.txt", now: utc("2026-10-17T02:00:00Z")))
        #expect(after.sessionReset == utc("2026-10-18T01:30:00Z"))
        #expect(after.sessionPercent == 7)
    }

    @Test func twelveAmIsMidnightAndTwelvePmIsNoon() {
        let text = """
        Current session: 5% used · resets Oct 17 at 12am (Europe/Berlin)
        Current week (all models): 6% used · resets Oct 17 at 12:15pm (Europe/Berlin)
        """
        guard case .usage(let u) = UsageParser.parse(text, now: now, timeZone: berlin) else {
            Issue.record("no usage")
            return
        }
        #expect(u.sessionReset == utc("2026-10-16T22:00:00Z"))
        #expect(u.weekReset == utc("2026-10-17T10:15:00Z"))
    }

    @Test func anUnknownZoneFallsBackToTheInjectedOne() {
        let text = "Current session: 5% used · resets Oct 17 at 3am (Mars/Base)"
        guard case .usage(let u) = UsageParser.parse(text, now: now, timeZone: TimeZone(identifier: "UTC")!) else {
            Issue.record("no usage")
            return
        }
        #expect(u.sessionReset == utc("2026-10-17T03:00:00Z"))
    }

    @Test func zeroWithNoWindowStartedIsZeroNotMissing() throws {
        let u = try #require(usage("no-reset.txt"))
        #expect(u.sessionPercent == 0)
        #expect(u.sessionReset == nil)
        #expect(u.weekPercent == 59)
        #expect(u.weekReset == utc("2026-10-22T04:00:00Z"))
    }

    @Test func singularHeadersParse() throws {
        let u = try #require(usage("singular.txt"))
        #expect(u.day == UsagePeriod(requests: 1, sessions: 1, lines: ["100% of your usage was at max effort"]))
        #expect(u.week7 == UsagePeriod(requests: 1, sessions: 1, lines: []))
    }

    @Test func everyStatLineIsKeptRawIncludingPlusMoreAndUnknownLines() throws {
        let u = try #require(usage("all-lines.txt"))
        #expect(u.day == nil)
        let w = try #require(u.week7)
        #expect(w.requests == 120)
        #expect(w.sessions == 9)
        #expect(w.lines == [
            "61% of your usage hit a >100k-token cache miss",
            "52% of your usage was at >150k context",
            "48% of your usage came from subagent-heavy sessions",
            "33% of your usage was while 4+ sessions ran in parallel",
            "27% of your usage came from sessions active for 8+ hours",
            "21% of your usage was at max effort",
            "14% of your usage came from workflows",
            "9% of your usage went to always-on context over 40k tokens",
            "5% of your usage went to tool results over 10k tokens",
            "Top skills: /notes 2%, /style 1%",
            "Top subagents: helper 35%, reviewer 7%, +3 more",
            "Top plugins: tracker 8%, release-kit 1%, +1 more",
            "Top MCP servers: docs-server 1%",
            "A brand new kind of line nobody has seen yet",
        ])
    }

    @Test func everyModelWeekButAllModelsInOrderWithOnlyDropped() throws {
        let u = try #require(usage("sonnet-only.txt"))
        let reset = utc("2026-10-22T04:00:00Z")
        #expect(u.modelWeeks == [
            ModelWeek(name: "Sonnet", percent: 23, reset: reset),
            ModelWeek(name: "Fable", percent: 8, reset: reset),
        ])
        #expect(u.weekPercent == 71)
    }

    @Test func ansiCodesAndCarriageReturnsAreStripped() throws {
        let u = try #require(usage("ansi.txt"))
        #expect(u.sessionPercent == 15)
        #expect(u.sessionReset == utc("2026-10-17T01:30:00Z"))
        #expect(u.weekPercent == 62)
        #expect(u.day == UsagePeriod(requests: 10, sessions: 2, lines: ["50% of your usage was at max effort"]))
    }

    @Test func theCostSummaryOfALoginWithoutASubscriptionIsNoLimits() {
        #expect(UsageParser.parse(Fixture.text("usage/no-limits.txt"), now: now, timeZone: berlin)
            == .noLimits(stats: UsageSnapshot()))
    }

    @Test func anEmptyOrSubscriptionAnswerWithoutLimitsIsUnavailable() {
        #expect(UsageParser.parse("", now: now, timeZone: berlin) == .unavailable)
        #expect(UsageParser.parse(Fixture.text("usage/subscription-unavailable.txt"), now: now, timeZone: berlin)
            == .unavailable)
    }

    @Test func aWeekAloneIsEnoughToCommit() {
        let text = "Current week (all models): 9% used"
        #expect(UsageParser.parse(text, now: now, timeZone: berlin) == .usage(UsageSnapshot(weekPercent: 9)))
    }

    @Test func thousandsSeparatorsInCountsAreRead() {
        let text = "Current session: 1% used\n\nLast 24h · 1,298 requests · 12 sessions\n  x\n"
        guard case .usage(let u) = UsageParser.parse(text, now: now, timeZone: berlin) else {
            Issue.record("no usage")
            return
        }
        #expect(u.day == UsagePeriod(requests: 1298, sessions: 12, lines: ["x"]))
    }

    @Test func theGuidesSampleParses() throws {
        // upstream's docs/PORTING.md: Oct 17 5:19am MSK (+3) = 02:19 UTC, Oct 19 5:59am = 02:59 UTC
        let u = try #require(usage("porting-guide.txt", now: utc("2026-10-16T12:00:00Z")))
        #expect(u.sessionPercent == 10)
        #expect(u.sessionReset == utc("2026-10-17T02:19:00Z"))
        #expect(u.weekPercent == 26)
        #expect(u.weekReset == utc("2026-10-19T02:59:00Z"))
        #expect(u.modelWeeks == [ModelWeek(name: "Fable", percent: 19, reset: utc("2026-10-19T02:59:00Z"))])
        #expect(u.day?.requests == 1043 && u.day?.sessions == 28 && u.day?.lines.count == 6)
        // The guide's "..." is kept like any unknown line.
        #expect(u.week7 == UsagePeriod(requests: 4558, sessions: 83, lines: ["78% of your usage was at >150k context", "..."]))
    }

    @Test func leapDayParsesOnlyInALeapYear() {
        #expect(UsageParser.resetDate("Feb 29, 2028 at 6am (Europe/Berlin)", now: now, timeZone: berlin) == utc("2028-02-29T05:00:00Z"))
        #expect(UsageParser.resetDate("Feb 29, 2027 at 6am (Europe/Berlin)", now: now, timeZone: berlin) == nil)
        let stamp = "Feb 29 at 6am (Europe/Berlin)"
        #expect(UsageParser.resetDate(stamp, now: utc("2028-02-25T12:00:00Z"), timeZone: berlin) == utc("2028-02-29T05:00:00Z"))
        #expect(UsageParser.resetDate(stamp, now: utc("2027-02-25T12:00:00Z"), timeZone: berlin) == nil)
    }

    @Test func aStampMinutesAgoStaysInThePast() {
        // 00:30 in Berlin: 12:25am today was five minutes ago, not a reset next year.
        #expect(UsageParser.resetDate("Oct 17 at 12:25am (Europe/Berlin)", now: now, timeZone: berlin) == utc("2026-10-16T22:25:00Z"))
    }

    @Test func aStampNoFormReadsIsReported() {
        let text = """
        Current session: 5% used · resets in 2 hr
        Current week (all models): 6% used · resets Oct 17 at 3am (Europe/Berlin)
        Current week (Sonnet only): 7% used · resets next Thursday
        """
        let (outcome, unread) = UsageParser.read(text, now: now, timeZone: berlin)
        guard case .usage(let u) = outcome else {
            Issue.record("no usage")
            return
        }
        #expect(u.sessionPercent == 5 && u.sessionReset == nil)
        #expect(u.weekReset == utc("2026-10-17T01:00:00Z"))
        #expect(unread == ["in 2 hr", "next Thursday"])
        #expect(UsageParser.read(Fixture.text("usage/today.txt"), now: now, timeZone: berlin).unreadStamps == [])
        #expect(UsageParser.read(Fixture.text("usage/no-reset.txt"), now: now, timeZone: berlin).unreadStamps == [])
    }

    @Test func aStampsShapeMasksItsDigits() {
        #expect(UsageParser.shape("Oct 17 at 3:30am (Europe/Berlin)") == "Oct ## at #:##am (Europe/Berlin)")
    }
}
