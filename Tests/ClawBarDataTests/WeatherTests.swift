import Foundation
import os
import Testing
import ClawBarShared
@testable import ClawBarData

struct HTTPFailure: Error {}

/// Answers by host from a table the test can change; records every request.
final class FakeHTTP: HTTPFetching {
    private let state = OSAllocatedUnfairLock<(answers: [String: Data?], urls: [URL])>(initialState: ([:], []))
    /// Between recording a request and answering it.
    private let latency: Duration

    init(_ answers: [String: Data?] = [:], latency: Duration = .zero) {
        self.latency = latency
        state.withLock { $0.answers = answers }
    }

    /// nil data makes that host fail.
    func answer(_ host: String, _ data: Data?) { state.withLock { $0.answers[host] = data } }

    var urls: [URL] { state.withLock { $0.urls } }
    func count(_ host: String) -> Int { urls.filter { $0.host == host }.count }

    func get(_ url: URL, timeout: TimeInterval) async throws -> Data {
        let answer = state.withLock { s -> Data?? in
            s.urls.append(url)
            return s.answers[url.host ?? ""]
        }
        if latency > .zero { try await Task.sleep(for: latency) }
        guard case .some(.some(let data)) = answer else { throw HTTPFailure() }
        return data
    }
}

@Suite struct WeatherParsingTests {
    let now = utc("2026-10-16T22:30:00Z")

    @Test func openMeteoGivesCodeTemperatureWindSunTimesAndZone() {
        #expect(WeatherService.parseOpenMeteo(Fixture.data("weather/open-meteo.json"), now: now) == WeatherSnapshot(
            code: 61, tempC: 14.6, windKmh: 11.2, sunriseMin: 441, sunsetMin: 1083, timeZoneID: "Europe/Berlin", at: now
        ))
        #expect(WeatherService.parseOpenMeteo(Data(#"{"error": true, "reason": "x"}"#.utf8), now: now) == nil)
    }

    @Test func metNoGivesTheCodeFromItsSymbolAndWindInKmh() {
        let wx = WeatherService.parseMetNo(Fixture.data("weather/met-no.json"), now: now)
        #expect(wx?.code == 80)
        #expect(wx?.tempC == 12.3)
        #expect(wx.map { abs($0.windKmh - 16.2) < 1e-9 } == true)
        #expect(wx?.sunriseMin == nil && wx?.sunsetMin == nil && wx?.timeZoneID == nil)
        #expect(WeatherService.parseMetNo(Data(#"{"properties": {"timeseries": []}}"#.utf8), now: now) == nil)
    }

    @Test func metNoSymbolsMapToWMOCodes() {
        let table: [(String, Int)] = [
            ("clearsky_day", 0), ("fair_night", 1), ("partlycloudy_polartwilight", 2), ("cloudy", 3), ("fog", 45),
            ("lightrain", 61), ("rain", 63), ("heavyrain", 65),
            ("lightrainshowers_day", 80), ("rainshowers_day", 81), ("heavyrainshowers_night", 82),
            ("lightsnow", 71), ("snow", 73), ("heavysnow", 75),
            ("lightsnowshowers_day", 85), ("snowshowers_day", 85), ("heavysnowshowers_day", 86),
            ("lightsleet", 66), ("sleetshowers_day", 66), ("heavysleet", 67),
            ("rainandthunder", 95), ("heavysleetshowersandthunder_day", 95), ("lightssnowshowersandthunder_day", 95),
            ("CloudY", 3), ("", 3), ("something_new", 3),
        ]
        for (symbol, code) in table { #expect(WeatherService.metNoCode(symbol) == code, "\(symbol)") }
    }

    @Test func ipwhoGivesThePlaceCityAndZone() {
        #expect(WeatherService.parseGeo(Fixture.data("weather/ipwho.json"))
            == Place(lat: 10.5, lon: 20.25, city: "Exampleville", timeZoneID: "Europe/Berlin"))
        #expect(WeatherService.parseGeo(Data(#"{"success": false, "message": "limit"}"#.utf8)) == nil)
    }

    @Test func requestURLs() {
        let p = Place(lat: 48.20849, lon: 16.37208)
        #expect(WeatherService.openMeteoURL(p).absoluteString == "https://api.open-meteo.com/v1/forecast?latitude=48.20849&longitude=16.37208"
            + "&current=weather_code,temperature_2m,wind_speed_10m&daily=sunrise,sunset&timezone=auto&forecast_days=1")
        #expect(WeatherService.openMeteoURL(Place(lat: 48, lon: -0.00001)).absoluteString.contains("latitude=48&longitude=-0.00001&"))
        #expect(WeatherService.metNoURL(p).absoluteString
            == "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=48.2085&lon=16.3721")
        #expect(WeatherService.geoURL(.de).absoluteString == "https://ipwho.is/?lang=de")
    }

    @Test func requestsCarryTheUserAgentAndTheTimeout() {
        let r = URLSessionHTTP.request(URL(string: "https://api.met.no/x")!, timeout: 15)
        #expect(r.value(forHTTPHeaderField: "User-Agent") == AppInfo.userAgent)
        #expect(r.timeoutInterval == 15)
    }
}

@MainActor
@Suite struct WeatherServiceTests {
    let t0 = utc("2026-10-16T22:30:00Z")

    func config(lat: Double? = nil, lon: Double? = nil, mascot: Bool = true, sky: Bool = true) -> Config {
        var c = Config()
        c.weatherLat = lat
        c.weatherLon = lon
        c.showMascot = mascot
        c.showSky = sky
        return c
    }

    /// Answers late, so a test that ticks as soon as a request goes out fails every time, not only under load.
    func lateHTTP(_ answers: [String: Data?] = [:]) -> FakeHTTP { FakeHTTP(answers, latency: .milliseconds(20)) }

    func service(_ http: FakeHTTP) -> WeatherService {
        WeatherService(http: http, clock: { [t0] in t0 }, log: { _ in })
    }

    @Test func configuredCoordinatesNeedNoIPLookup() async {
        let http = lateHTTP(["api.open-meteo.com": Fixture.data("weather/open-meteo.json")])
        let wx = service(http)
        wx.tick(now: t0, config: config(lat: 10.5, lon: 20.25))
        #expect(await eventually { wx.weather != nil })
        #expect(wx.weather?.code == 61)
        #expect(wx.place == Place(lat: 10.5, lon: 20.25))
        #expect(http.count("ipwho.is") == 0)
    }

    @Test func withoutCoordinatesTheIPLocationComesFirstThenTheWeatherAtOnce() async {
        let http = lateHTTP([
            "ipwho.is": Fixture.data("weather/ipwho.json"),
            "api.open-meteo.com": Fixture.data("weather/open-meteo.json"),
        ])
        let wx = service(http)
        wx.tick(now: t0, config: config())
        #expect(await eventually { wx.weather != nil })
        #expect(wx.place == Place(lat: 10.5, lon: 20.25, city: "Exampleville", timeZoneID: "Europe/Berlin"))
        #expect(http.urls.map(\.host) == ["ipwho.is", "api.open-meteo.com"])
        #expect(http.urls.last?.query?.contains("latitude=10.5&longitude=20.25") == true)
    }

    @Test func aFailedIPLookupIsRetriedAtMostEveryTenMinutes() async {
        let http = lateHTTP()
        let wx = service(http)
        let failures = Counter()
        wx.log = { _ in failures.value += 1 }
        wx.tick(now: t0, config: config())
        #expect(await eventually { failures.value == 1 })
        #expect(http.count("ipwho.is") == 1)
        wx.tick(now: t0 + 60, config: config())
        wx.tick(now: t0 + 599, config: config())
        await settle()
        #expect(http.count("ipwho.is") == 1)
        wx.tick(now: t0 + 600, config: config())
        #expect(await eventually { http.count("ipwho.is") == 2 })
    }

    @Test func openMeteoFailingFallsBackToMetNoAtOnceAndIsRetriedHourly() async {
        let http = lateHTTP(["api.met.no": Fixture.data("weather/met-no.json")])
        let wx = service(http)
        let updates = Counter()
        wx.onUpdate = { updates.value += 1 }
        let c = config(lat: 10.5, lon: 20.25)
        wx.tick(now: t0, config: c)
        #expect(await eventually { wx.weather?.code == 80 })
        #expect(http.urls.map(\.host) == ["api.open-meteo.com", "api.met.no"])

        // within the hour the next fetches stay with met.no
        wx.tick(now: t0 + 900, config: c)
        // the update, not the request, ends the fetch; a tick while it runs is dropped
        #expect(await eventually { updates.value == 2 })
        #expect(http.count("api.met.no") == 2)
        #expect(http.count("api.open-meteo.com") == 1)

        // an hour after the fallback Open-Meteo gets another chance, and wins
        http.answer("api.open-meteo.com", Fixture.data("weather/open-meteo.json"))
        wx.tick(now: t0 + 3600, config: c)
        #expect(await eventually { wx.weather?.code == 61 })
        #expect(http.count("api.open-meteo.com") == 2)
        wx.tick(now: t0 + 4500, config: c)
        #expect(await eventually { http.count("api.open-meteo.com") == 3 })
        #expect(http.count("api.met.no") == 2)
    }

    @Test func theIntervalCountsFromTheLastAttempt() async {
        let http = lateHTTP(["api.open-meteo.com": Fixture.data("weather/open-meteo.json")])
        let wx = service(http)
        let c = config(lat: 10.5, lon: 20.25)
        wx.tick(now: t0, config: c)
        #expect(await eventually { wx.weather != nil })
        wx.tick(now: t0 + 899, config: c)
        await settle()
        #expect(http.urls.count == 1)
        wx.tick(now: t0 + 900, config: c)
        #expect(await eventually { http.urls.count == 2 })
    }

    @Test func editedCoordinatesRefetchAtOnce() async {
        let http = lateHTTP(["api.open-meteo.com": Fixture.data("weather/open-meteo.json")])
        let wx = service(http)
        wx.tick(now: t0, config: config(lat: 10.5, lon: 20.25))
        #expect(await eventually { wx.weather != nil })
        wx.tick(now: t0 + 10, config: config(lat: 11.5, lon: 20.25))
        #expect(await eventually { http.urls.count == 2 })
        #expect(http.urls.last?.query?.contains("latitude=11.5&") == true)
        #expect(wx.place == Place(lat: 11.5, lon: 20.25))
    }

    @Test func nothingIsFetchedUnlessTheMascotAndTheSkyShow() async {
        let http = FakeHTTP(["api.open-meteo.com": Fixture.data("weather/open-meteo.json")])
        let wx = service(http)
        wx.tick(now: t0, config: config(lat: 10.5, lon: 20.25, sky: false))
        wx.tick(now: t0 + 1000, config: config(lat: 10.5, lon: 20.25, mascot: false))
        await settle()
        #expect(http.urls.isEmpty)
    }
}
