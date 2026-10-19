import Foundation
import Testing
import ClawBarShared
import ClawBarSky

/// weather.ps1 Update-SkyTip. English literals are the original's strings (visuals-verbatim K).
@Suite struct TooltipTests {
    let now = Samples.now
    let sample = DataSnapshot.sample
    let sun = SunTimes(sunrise: 441, sunset: 1079)
    /// The moon line at `Samples.now`, 2026-10-17 12:05 UTC, 6.3 days after the new moon.
    let moon = "\nmoon: first quarter, 39% lit"

    private func weather(temp: Double = 14.6, wind: Double = 11.2, code: Int = 2, hoursOld: Double = 0.1) -> WeatherSnapshot {
        WeatherSnapshot(code: code, tempC: temp, windKmh: wind, at: now.addingTimeInterval(-hoursOld * 3600))
    }

    private func tip(
        _ w: WeatherSnapshot?, place: Place? = nil, sun: SunTimes? = nil, now: Date? = nil, dev: SkyDevState = SkyDevState(), lang: Lang = .en
    ) -> String {
        SkyInfo.tooltip(w, place: place, sun: sun ?? self.sun, now: now ?? self.now, dev: dev, lang: lang)
    }

    @Test func liveWeatherShowsCityTemperatureKindWindAndSun() {
        let (sun, _) = SkyInfo.sunTimes(sample.weather, place: sample.place, now: now, localZone: Zones.utc)
        let text = SkyInfo.tooltip(sample.weather, place: sample.place, sun: sun, now: now, dev: SkyDevState(), lang: .en)
        #expect(text == "Berlin · +15°, partly cloudy\nwind 3 m/s\nsunrise 07:21 · sunset 17:59\(moon)")
    }

    @Test func configuredCoordinatesHaveNoCity() {
        #expect(tip(weather(), place: Place(lat: 52.52, lon: 13.405)) == "+15°, partly cloudy\nwind 3 m/s\nsunrise 07:21 · sunset 17:59\(moon)")
        #expect(tip(weather(), place: Place(lat: 52.52, lon: 13.405, city: "")).hasPrefix("+15°"))
    }

    @Test(arguments: [(0.5, "0°"), (1.5, "+2°"), (2.5, "+2°"), (-0.4, "0°"), (-3.5, "-4°"), (-12.2, "-12°")])
    func temperatureRoundsHalfToEvenAndOnlyAboveZeroGetsAPlus(temp: Double, shown: String) {
        #expect(tip(weather(temp: temp)).hasPrefix("\(shown), partly cloudy\n"))
    }

    @Test(arguments: [(9.0, 2), (12.6, 4), (11.2, 3), (0.0, 0)])
    func windIsMetresPerSecondRoundedHalfToEven(kmh: Double, ms: Int) {
        #expect(tip(weather(wind: kmh)).components(separatedBy: "\n").dropFirst().first == "wind \(ms) m/s")
    }

    @Test func staleOrMissingWeatherHasNoData() {
        #expect(tip(weather(hoursOld: 3)) == "weather: no data\nsunrise 07:21 · sunset 17:59\(moon)")
        #expect(tip(nil, sun: .fallback) == "weather: no data\nsunrise 07:00 · sunset 19:00\(moon)")
    }

    @Test func developerOverridesReplaceTheWeatherLines() {
        #expect(tip(weather(), dev: SkyDevState(phase: .night)) == "dev · night\nsunrise 07:21 · sunset 17:59\(moon)")
        #expect(tip(nil, dev: SkyDevState(weatherCode: 95)) == "dev · thunderstorm\nsunrise 07:21 · sunset 17:59\(moon)")
        #expect(tip(weather(), dev: SkyDevState(phase: .dusk, weatherCode: 63)) == "dev · dusk, rain\nsunrise 07:21 · sunset 17:59\(moon)")
        #expect(tip(nil, dev: SkyDevState(weatherCode: 42)) == "dev · code 42\nsunrise 07:21 · sunset 17:59\(moon)")
    }

    @Test(arguments: [(441.7, "07:21"), (0, "00:00"), (1439.999, "23:59"), (59.999_99, "00:59"), (59.999_999_999, "01:00"), (1444.025, "00:04")])
    func sunTimesPrintLikeTimeSpanHoursAndMinutes(minutes: Double, shown: String) {
        // TimeSpan.FromMinutes rounds to the millisecond; 'hh' drops whole days, so a sunset tomorrow shows its clock time.
        #expect(tip(nil, sun: SunTimes(sunrise: minutes, sunset: 1200)).hasSuffix("sunrise \(shown) · sunset 20:00\(moon)"))
    }

    @Test func polarSunTimesHaveNoSunriseOrSunset() {
        let tromso = Place(lat: 69.6492, lon: 18.9553, city: "Tromsø", timeZoneID: "Europe/Oslo")
        for (date, moon) in [(local(2026, 6, 21, 0, 30, in: Zones.oslo), "first quarter, 40%"), (local(2026, 12, 21, 12, 0, in: Zones.oslo), "waxing gibbous, 90%")] {
            let sun = SkyInfo.sunTimes(nil, place: tromso, now: date, localZone: Zones.utc).0
            #expect(SkyInfo.tooltip(nil, place: tromso, sun: sun, now: date, dev: SkyDevState(), lang: .en) == "weather: no data\nsunrise — · sunset —\nmoon: \(moon) lit")
        }
    }

    @Test func germanUsesTheGermanStringsAroundTheSameNumbers() {
        // The German wording belongs to the strings table; the numbers, city, sign and dev prefix are this module's.
        let deMoon = "\n" + L10n.t(.skyMoon, .de, L10n.moonName(2, .de), 39)
        let de = SkyInfo.tooltip(sample.weather, place: sample.place, sun: sun, now: now, dev: SkyDevState(), lang: .de)
        #expect(de == "Berlin · +15°, \(WeatherKinds.name(code: 2, lang: .de))\n\(L10n.t(.skyWind, .de, 3))\n\(L10n.t(.skySun, .de, "07:21", "17:59"))\(deMoon)")
        let dev = tip(nil, dev: SkyDevState(phase: .dawn, weatherCode: 73), lang: .de)
        #expect(dev == "dev · \(L10n.phase(.dawn, .de)), \(WeatherKinds.name(code: 73, lang: .de))\n\(L10n.t(.skySun, .de, "07:21", "17:59"))\(deMoon)")
        #expect(tip(nil, lang: .de) == "\(L10n.t(.skyNoData, .de))\n\(L10n.t(.skySun, .de, "07:21", "17:59"))\(deMoon)")
    }

    @Test func theMoonLineNamesThePhaseAndHowMuchIsLitAtTheEclipses() {
        // The solar eclipse of 2024-04-08 18:21 UTC and the lunar eclipse of 2025-03-14 06:55 UTC.
        #expect(tip(nil, now: local(2024, 4, 8, 18, 21, in: Zones.utc)).hasSuffix("\nmoon: new moon, 0% lit"))
        #expect(tip(nil, now: local(2025, 3, 14, 6, 55, in: Zones.utc)).hasSuffix("\nmoon: full moon, 100% lit"))
        #expect(tip(nil, now: local(2025, 3, 14, 6, 55, in: Zones.utc), lang: .de).hasSuffix("\nMond: Vollmond, 100 % beleuchtet"))
    }
}
