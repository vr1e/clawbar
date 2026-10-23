import CoreGraphics
import Foundation
import Testing
import ClawBarShared
import ClawBarSky

/// The engine alone through the `weather` recording's four skies: day 63, night 73, dusk 95 and dawn 2, each a
/// developer override the key picks up on its first tick, 100 ticks of 90 ms each over the sample's weather.
@Suite struct DeterminismTests {
    static let skies: [(SkyPhase, Int)] = [(.day, 63), (.night, 73), (.dusk, 95), (.dawn, 2)]

    private func play(seed: UInt64, ticksPerSky: Int = 100) -> [SkyFrame] {
        let sky = SkyEngine(random: SeededRandomSource(seed: seed))
        let data = DataSnapshot.sample
        var now = Samples.now
        var frames: [SkyFrame] = []
        for (phase, code) in Self.skies {
            let dev = SkyDevState(phase: phase, weatherCode: code)
            for _ in 0 ..< ticksPerSky {
                let input = SkyInfo.inputs(data.weather, place: data.place, now: now, localZone: Zones.utc, dev: dev)
                frames.append(sky.step(size: skySize, inputs: input))
                now = now.addingTimeInterval(0.09)
            }
        }
        return frames
    }

    @Test func aSeedReplaysTheSameFramesTickForTick() {
        let a = play(seed: 42), b = play(seed: 42)
        #expect(a.count == 400)
        #expect(a == b)
        #expect(a != play(seed: 43))
    }

    @Test func eachSkySettlesIntoItsWeather() throws {
        let frames = play(seed: 42)
        // Day, rain: 20 drops, 8 clouds faded in, the sun hidden by 0.9 cover.
        let day = Sprites(frames[99])
        #expect(day.drops?.rects.count == 20 && day.clouds.count == 8 && day.sun == nil)
        #expect(day.clouds.allSatisfy { near($0.opacity, 0.65) })
        // Night, snow: 17 flakes, 7 clouds, the strip in the night snow colour, no rain.
        let night = Sprites(frames[199])
        #expect(night.flakes?.rects.count == 17 && night.clouds.count == 7 && night.drops == nil)
        #expect(night.ground?.color == RGBA("#50A1A8B5"))
        // Dusk, storm: 17 drops under 8 clouds, no snow strip.
        let dusk = Sprites(frames[299])
        #expect(dusk.drops?.rects.count == 17 && dusk.clouds.count == 8 && dusk.ground == nil)
        // Dawn, partly cloudy: 4 clouds and the sun just below the horizon (p = −10/638).
        let dawn = Sprites(frames[399])
        #expect(dawn.clouds.count == 4 && dawn.drops == nil && dawn.flakes == nil)
        let sun = try #require(dawn.sun)
        #expect(sun.color == RGBA("#FFFB923C") && near(sun.opacity, 0.425, 1e-12))
        #expect(frames[399].top == RGBA.dim(RGBA("#00404E8A"), 0.45))
    }

    @Test func dropsAndFlakesKeepMovingEveryTick() {
        let frames = play(seed: 7)
        let rain = frames[0 ..< 100].map { Sprites($0).drops?.rects ?? [] }
        #expect(zip(rain, rain.dropFirst()).allSatisfy { $0 != $1 })
        let snow = frames[100 ..< 200].map { Sprites($0).flakes?.rects ?? [] }
        #expect(zip(snow, snow.dropFirst()).allSatisfy { $0 != $1 })
    }
}

/// Inputs the original never produced, or produced and crashed on: the step must still draw.
@Suite struct RobustnessTests {
    private func survive(_ input: SkyInputs, size: CGSize = skySize, ticks: Int = 300) -> SkyFrame {
        let sky = SkyEngine(random: SeededRandomSource(seed: 9))
        var frame = SkyFrame.empty
        for _ in 0 ..< ticks { frame = sky.step(size: size, inputs: input) }
        return frame
    }

    @Test(arguments: [
        SunTimes(sunrise: 600, sunset: 600),  // no day: ss − sr = 0
        SunTimes(sunrise: 1000, sunset: 200),  // crossed
        SunTimes(sunrise: 0, sunset: 1440),  // no night: sr + 1440 − ss = 0
        SunTimes(sunrise: -500, sunset: 2500),  // longer than a day
        SunTimes(sunrise: .nan, sunset: 1140),
        SunTimes(sunrise: 420, sunset: .infinity),
        SunTimes(sunrise: 1e300, sunset: -1e300),
        SunTimes(sunrise: 1e19, sunset: 1e19 + 1000),  // a "day" a forced phase would accept, beyond Int
    ])
    func oddSunTimesNeverTrap(sun: SunTimes) {
        for phase in [nil] + SkyPhase.allCases.map(Optional.some) {
            let frame = survive(inputs(utcDay(700), sun: sun, weather: SkyWeather(code: 95, windKmh: 30), phase: phase), ticks: 20)
            #expect(frame.ops.allSatisfy { op in
                if case .rects(let rects, _, let opacity) = op { return rects.allSatisfy { $0.minX.isFinite && $0.minY.isFinite } && opacity.isFinite }
                return true
            })
        }
    }

    @Test func unusableSunTimesDrawLikeSevenToNineteen() {
        let odd = survive(inputs(utcDay(450), sun: SunTimes(sunrise: .nan, sunset: 1140)), ticks: 1)
        #expect(odd.top == RGBA("#00456DAA"))
    }

    @Test func oddWeatherAndPlacesNeverTrap() {
        _ = survive(inputs(utcDay(60), weather: SkyWeather(code: 42, windKmh: .nan), latitude: .nan))
        _ = survive(inputs(utcDay(60), weather: SkyWeather(code: -1, windKmh: -500), latitude: -90))
        _ = survive(inputs(Date.distantFuture, zone: Zones.tokyo))
        _ = survive(inputs(Date.distantPast, zone: Zones.reykjavik))
        _ = survive(inputs(utcDay(60), weather: SkyWeather(code: 82, windKmh: 1e9)), size: CGSize(width: 2, height: 1))
    }

    @Test func emptyOrBrokenSizesAreSkipped() {
        for size in [CGSize(width: -10, height: 43), CGSize(width: CGFloat.nan, height: 43), CGSize(width: 236, height: CGFloat.infinity)] {
            #expect(survive(inputs(utcDay(780)), size: size, ticks: 3) == SkyFrame(top: RGBA("#00304A8C"), bottom: RGBA("#1A304A8C"), ops: []))
        }
    }

    @Test func skyInfoCopesWithBrokenWeather() {
        let broken = WeatherSnapshot(code: 2, tempC: .nan, windKmh: .infinity, sunriseMin: .nan, sunsetMin: 1079, at: Samples.now)
        let place = Place(lat: 52.52, lon: 13.405, city: "Berlin", timeZoneID: "Europe/Berlin")
        let (sun, _) = SkyInfo.sunTimes(broken, place: place, now: Samples.now, localZone: Zones.utc)
        #expect(sun.sunrise < sun.sunset && sun.sunrise.isFinite)
        let text = SkyInfo.tooltip(broken, place: place, sun: SunTimes(sunrise: .nan, sunset: .nan), now: Samples.now, dev: SkyDevState(), lang: .en)
        #expect(text == "Berlin · 0°, partly cloudy\nwind 0 m/s\nsunrise — · sunset —\nmoon: first quarter, 39% lit")
    }
}
