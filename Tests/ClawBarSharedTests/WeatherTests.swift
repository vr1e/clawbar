import Foundation
import Testing
import ClawBarShared

@Suite struct WeatherKindsTests {
    @Test func threeCodeGroupsScaleLightModerateHeavyWithBankersRounding() {
        // Expected counts from the original's table (data-verbatim.txt).
        #expect([51, 53, 55].map { WeatherKinds.kind(code: $0).rain } == [4, 6, 8])
        #expect([61, 63, 65].map { WeatherKinds.kind(code: $0).rain } == [7, 12, 16])
        #expect([71, 73, 75].map { WeatherKinds.kind(code: $0).snow } == [6, 10, 14])
        #expect([80, 81, 82].map { WeatherKinds.kind(code: $0).rain } == [10, 16, 22])
        #expect([95, 96, 99].map { WeatherKinds.kind(code: $0).rain } == [10, 16, 22])
    }

    @Test func twoCodeGroupsKeepTheBaseCount() {
        #expect(WeatherKinds.kind(code: 56).rain == 6)
        #expect(WeatherKinds.kind(code: 67).rain == 12)
        #expect(WeatherKinds.kind(code: 86).snow == 14)
        #expect(WeatherKinds.kind(code: 77).snow == 8)
    }

    @Test func flagsAndCover() {
        let fog = WeatherKinds.kind(code: 48)
        #expect(fog.nameKey == .wxFog && fog.fog && fog.cover == 0.7)
        let storm = WeatherKinds.kind(code: 95)
        #expect(storm.storm && storm.cover == 1.0)
        #expect(WeatherKinds.kind(code: 0).cover == 0.0)
        #expect(WeatherKinds.kind(code: 3).cover == 0.85)
    }

    @Test func unknownCodesAreHalfCoveredAndNamedByNumber() {
        let k = WeatherKinds.kind(code: 42)
        #expect(k.cover == 0.5 && k.rain == 0 && k.snow == 0 && !k.fog && !k.storm)
        #expect(WeatherKinds.name(code: 42, lang: .en) == "code 42")
        #expect(WeatherKinds.name(code: 2, lang: .en) == "partly cloudy")
    }
}

@Suite struct SunCalcTests {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

    @Test func sydneySummerMatchesTheAlmanac() {
        // Almanac: about 05:59 and 20:08 AEDT.
        let s = SunCalc.noaa(lat: -33.8688, lon: 151.2093, date: date("2026-01-15T02:00:00Z"), timeZone: zone("Australia/Sydney"))
        #expect(abs(s.sunrise - 359) < 4)
        #expect(abs(s.sunset - 1208) < 4)
    }

    @Test func theOffsetIsTakenOnTheDayItselfSoDSTShiftsTheClock() {
        let berlin = zone("Europe/Berlin")
        let before = SunCalc.noaa(lat: 52.52, lon: 13.405, date: date("2026-03-28T10:00:00Z"), timeZone: berlin)
        let after = SunCalc.noaa(lat: 52.52, lon: 13.405, date: date("2026-03-30T10:00:00Z"), timeZone: berlin)
        // Almanac: 05:51 CET, then 06:46 CEST.
        #expect(abs(before.sunrise - 351) < 4)
        #expect(abs(after.sunrise - 406) < 4)
    }

    @Test func polarDayClampsAndWrapsPastMidnight() {
        // Worked example of the original formula: c clamps to -0.999, so the "day" lasts 1419.5 min.
        let s = SunCalc.noaa(lat: 69.6492, lon: 18.9553, date: date("2026-06-21T10:00:00Z"), timeZone: zone("Europe/Oslo"))
        #expect(abs(s.sunrise - 55.9) < 0.5)
        #expect(abs(s.sunset - 35.4) < 0.5)
    }

    @Test func polarNightLeavesAShortNoon() {
        let s = SunCalc.noaa(lat: 69.6492, lon: 18.9553, date: date("2026-12-21T10:00:00Z"), timeZone: zone("Europe/Oslo"))
        #expect(abs(s.sunrise - 692.0) < 0.5)
        #expect(abs(s.sunset - 712.5) < 0.5)
    }
}
