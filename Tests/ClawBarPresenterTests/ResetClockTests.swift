import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

// Expected values follow format.ps1 Format-ResetClock, counted in calendar days of the input's zone.
@Suite struct ResetClockTests {
    private func clock(_ reset: Date, from now: Date = Samples.now, _ lang: Lang = .en, zone: TimeZone = Samples.timeZone) -> String {
        ResetClock.text(reset, now: now, timeZone: zone, lang: lang)
    }

    @Test func todayIsTheTimeAlone() {
        #expect(clock(Samples.now.plus(hours: 2, minutes: 5)) == "16:10")
        #expect(clock(Samples.now.plus(seconds: 1)) == "14:05")
        #expect(clock(utc("2026-10-17T21:59:00Z")) == "23:59")
    }

    @Test func theNextCalendarDayIsTomorrowHoweverManyHoursAway() {
        #expect(clock(utc("2026-10-17T22:00:00Z")) == "tomorrow 00:00")
        #expect(clock(utc("2026-10-17T22:30:00Z"), .de) == "morgen 00:30")
        // Sat 23:59 to Sun 00:00, and Sat 00:10 to Sun 23:50, 47 h 40 min away.
        #expect(clock(utc("2026-10-17T22:00:00Z"), from: utc("2026-10-17T21:59:00Z")) == "tomorrow 00:00")
        #expect(clock(utc("2026-10-18T21:50:00Z"), from: utc("2026-10-16T22:10:00Z")) == "tomorrow 23:50")
    }

    @Test func theFallBackDayStillCountsAsOne() {
        // Sat 12:00 CEST to Sun 23:30 CET: 36 h 30 min, and 2 by seconds since midnight.
        #expect(clock(utc("2026-10-25T22:30:00Z"), from: utc("2026-10-24T10:00:00Z")) == "tomorrow 23:30")
    }

    @Test func withinTheWeekTheWeekday() {
        #expect(clock(DataSnapshot.sample.usage!.weekReset!) == "Thu 06:00")
        #expect(clock(DataSnapshot.sample.usage!.weekReset!, .de) == "Do. 06:00")
        #expect(clock(Samples.now.plus(days: 2)) == "Mon 14:05")
        #expect(clock(Samples.now.plus(days: 6), .de) == "Fr. 14:05")
        // From Wednesday, a Sunday reset.
        #expect(clock(utc("2026-10-25T11:00:00Z"), from: utc("2026-10-21T10:00:00Z")) == "Sun 12:00")
    }

    @Test func aWeekOrMoreOutAddsTheDayOfTheMonth() {
        // A weekly window that began Thu 06:01 resets next Thursday: "Thu 06:00" alone would read as this morning.
        #expect(clock(utc("2026-10-29T05:00:00Z"), from: utc("2026-10-22T04:01:00Z")) == "Thu 29 06:00")
        #expect(clock(utc("2026-10-29T05:00:00Z"), from: utc("2026-10-22T04:01:00Z"), .de) == "Do. 29. 06:00")
        // 168 h across the spring change land 8 calendar days out, past midnight.
        #expect(clock(utc("2026-03-28T22:30:00Z").plus(hours: 168), from: utc("2026-03-28T22:30:00Z")) == "Sun 5 00:30")
    }

    @Test func theClockFollowsTheInputZone() {
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(clock(Samples.now.plus(hours: 2, minutes: 5), zone: newYork) == "10:10")
        #expect(clock(DataSnapshot.sample.usage!.weekReset!, zone: newYork) == "Thu 00:00")
    }
}
