import Foundation
import ClawBarShared

/// The sky's inputs and tooltip from the weather data (weather.ps1's sky helpers).
public enum SkyInfo {
    /// A forced code with a 12 km/h wind, else live weather younger than 3 h, else nil.
    public static func skyWeather(_ weather: WeatherSnapshot?, now: Date, dev: SkyDevState) -> SkyWeather? {
        if let code = dev.weatherCode { return SkyWeather(code: code, windKmh: 12) }
        guard let live = fresh(weather, now: now) else { return nil }
        return SkyWeather(code: live.code, windKmh: live.windKmh)
    }

    /// The sun times and the zone they are in: Open-Meteo's, else NOAA for the place, else 07:00/19:00.
    /// The zone is the location's (Open-Meteo, then the IP lookup), else `localZone`. Sunrise is always before sunset:
    /// a sunset after midnight comes out past 1440, a polar day starts before today and ends after it, and a polar
    /// night lies wholly before today. Pass the result to `SkyInputs.sun` and `tooltip` unchanged.
    public static func sunTimes(_ weather: WeatherSnapshot?, place: Place?, now: Date, localZone: TimeZone) -> (SunTimes, TimeZone) {
        let zone = [weather?.timeZoneID, place?.timeZoneID].lazy
            .compactMap { $0.flatMap(TimeZone.init(identifier:)) }.first ?? localZone
        let noaa = place.map { SunCalc.noaa(lat: $0.lat, lon: $0.lon, date: now, timeZone: zone) }
        if let sr = weather?.sunriseMin, let ss = weather?.sunsetMin, sr.isFinite, ss.isFinite {
            return (ordered(SunTimes(sunrise: sr, sunset: ss), noaa: noaa), zone)
        }
        if let noaa { return (ordered(noaa, noaa: noaa), zone) }
        return (.fallback, zone)
    }

    /// For the moon's hemisphere: the place's latitude, else 50.
    public static func latitude(place: Place?) -> Double { place?.lat ?? 50 }

    /// One tick's inputs from the latest data and the developer overrides; the tooltip shows the same `sun`.
    public static func inputs(
        _ weather: WeatherSnapshot?, place: Place?, now: Date, localZone: TimeZone, dev: SkyDevState
    ) -> SkyInputs {
        let (sun, zone) = sunTimes(weather, place: place, now: now, localZone: localZone)
        return SkyInputs(
            now: now, timeZone: zone, sun: sun, weather: skyWeather(weather, now: now, dev: dev),
            latitude: latitude(place: place), forcedPhase: dev.phase
        )
    }

    /// Update-SkyTip: the developer override, else the live weather and its wind, else no data; then the sun times
    /// from `sunTimes`, as HH:mm, or dashes on a polar day or night; last the moon's phase, day and night.
    public static func tooltip(_ weather: WeatherSnapshot?, place: Place?, sun: SunTimes, now: Date, dev: SkyDevState, lang: Lang) -> String {
        var lines: [String] = []
        if dev.isForced {
            let what = [dev.phase.map { L10n.phase($0, lang) }, dev.weatherCode.map { WeatherKinds.name(code: $0, lang: lang) }]
            lines.append("dev · " + what.compactMap { $0 }.joined(separator: ", "))
        } else if let live = fresh(weather, now: now) {
            let temp = whole(live.tempC)
            var line = "\(temp > 0 ? "+" : "")\(temp)°, \(WeatherKinds.name(code: live.code, lang: lang))"
            if let city = place?.city, !city.isEmpty { line = "\(city) · \(line)" }
            lines.append(line)
            lines.append(L10n.t(.skyWind, lang, whole(live.windKmh / 3.6)))
        } else {
            lines.append(L10n.t(.skyNoData, lang))
        }
        // A sunrise before today is how sunTimes marks a polar day or night: no sunrise or sunset to show.
        let polar = !(sun.sunrise >= 0)
        lines.append(L10n.t(.skySun, lang, polar ? "—" : clock(sun.sunrise), polar ? "—" : clock(sun.sunset)))
        let moon = Moon.info(at: now)
        lines.append(L10n.t(.skyMoon, lang, L10n.moonName(moon.name, lang), moon.lit))
        return lines.joined(separator: "\n")
    }

    /// Live weather is drawn and described for three hours after it arrived.
    private static func fresh(_ weather: WeatherSnapshot?, now: Date) -> WeatherSnapshot? {
        guard let weather, now.timeIntervalSince(weather.at) < 3 * 3600 else { return nil }
        return weather
    }


    /// TimeSpan.FromMinutes(m).ToString("hh\\:mm"): rounded to the millisecond, whole days dropped.
    private static func clock(_ minutes: Double) -> String {
        let ms = (minutes * 60_000 + 0.5).rounded(.down)
        guard ms.isFinite, ms >= 0, ms < 1e15 else { return "—" }
        let total = Int(ms) / 60_000
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(two(total / 60 % 24)):\(two(total % 60))"
    }

    // MARK: Sunrise before sunset

    /// SunCalc clamps the hour angle's cosine to ±0.999, so its polar days last exactly this long (1419.5 min)
    /// and the days of its polar nights this short (20.5 min).
    private static let clampedPolarDay = 8 * acos(-0.999) * 180 / .pi
    private static let clampedPolarNight = 8 * acos(0.999) * 180 / .pi

    /// Step-Sky needs sunrise < sunset, and the wrapped clock times of the sources cross at high latitudes.
    /// NOAA for the place tells polar day from polar night, which Open-Meteo reports alike as 00:00–00:00.
    private static func ordered(_ s: SunTimes, noaa: SunTimes?) -> SunTimes {
        if let noaa {
            let length = dayLength(noaa)
            if length > clampedPolarDay - 0.01 { return .polarDay }
            if length < clampedPolarNight + 0.01 { return .polarNight }
            if s.sunrise == s.sunset { return length > 720 ? .polarDay : .polarNight }
        } else if s.sunrise == s.sunset {
            return .fallback
        }
        // The sun sets after midnight: keep that sunset tomorrow.
        if s.sunset < s.sunrise { return SunTimes(sunrise: s.sunrise, sunset: s.sunset + 1440) }
        if s.sunset - s.sunrise >= 1440 { return .polarDay }
        return s
    }

    /// From sunrise to sunset on a 24-hour clock.
    private static func dayLength(_ s: SunTimes) -> Double {
        let d = (s.sunset - s.sunrise).truncatingRemainder(dividingBy: 1440)
        return d < 0 ? d + 1440 : d
    }
}

extension SunTimes {
    /// The sun never sets: it rose a twilight before this midnight and sets a twilight after the next one,
    /// so all of today draws as full day, with the sun low at midnight and no night for the moon.
    fileprivate static let polarDay = SunTimes(sunrise: -80, sunset: 1440 + 80)
    /// The sun never rises: a one-minute day a day ago, so today draws as night, with the moon's arc spanning it.
    fileprivate static let polarNight = SunTimes(sunrise: -1441, sunset: -1440)
}
