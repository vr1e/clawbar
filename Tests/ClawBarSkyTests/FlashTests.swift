import CoreGraphics
import Foundation
import Testing
import ClawBarShared
import ClawBarSky

/// Thunderstorm flashes: a 1-in-140 roll each idle tick starts flash = 7, which plays the table
/// [0, 0.18, 0.05, 0, 0.25, 0.1, 0.04] backwards from index 6.
@Suite struct FlashTests {
    private let storm = inputs(utcDay(780), weather: SkyWeather(code: 95, windKmh: 12))

    private func flashes(_ random: ScriptedRandom, _ input: SkyInputs, ticks: Int) -> [Double] {
        let sky = SkyEngine(random: random)
        return (0 ..< ticks).map { _ in Sprites(sky.step(size: skySize, inputs: input)).flash?.opacity ?? 0 }
    }

    @Test func aStrikeIsADoubleFlashOverSevenTicks() throws {
        // Every roll hits, so a new strike follows right after.
        let seen = flashes(ScriptedRandom(restInt: 0), storm, ticks: 14)
        #expect(seen == [0.04, 0.1, 0.25, 0, 0.05, 0.18, 0, 0.04, 0.1, 0.25, 0, 0.05, 0.18, 0])
        let frame = SkyEngine(random: ScriptedRandom(restInt: 0)).step(size: skySize, inputs: storm)
        let flash = try #require(Sprites(frame).flash)
        #expect(flash.rects == [CGRect(x: 0, y: 0, width: 236, height: 43)] && flash.color == RGBA("#FFF8FAFC"))
    }

    @Test func aMissedRollIsNoFlash() {
        let random = ScriptedRandom(restInt: 1)
        #expect(flashes(random, storm, ticks: 300).allSatisfy { $0 == 0 })
        #expect(random.intDraws == 300)
    }

    @Test func theDiceRollOnlyInAStormAndNotWhileAFlashPlays() {
        let calm = ScriptedRandom(restInt: 0)
        #expect(flashes(calm, inputs(utcDay(780), weather: SkyWeather(code: 63, windKmh: 12)), ticks: 50).allSatisfy { $0 == 0 })
        #expect(calm.intDraws == 0)
        let striking = ScriptedRandom(ints: [0], restInt: 1)
        _ = flashes(striking, storm, ticks: 8)
        // Tick 1 strikes; ticks 2 to 7 play the flash without rolling; tick 8 rolls again.
        #expect(striking.intDraws == 2)
    }
}

/// When Step-Sky recomputes, and what a frame holds.
@Suite struct FrameTests {
    @Test func withinOneMinuteNewSunTimesWaitForTheNextRecompute() {
        // 10:00 with sunrise 07:00 is day; with sunrise 11:40 it would be night.
        let sky = SkyEngine(random: SeededRandomSource(seed: 3))
        let now = utcDay(600)
        #expect(sky.step(size: skySize, inputs: inputs(now)).top == RGBA("#004A8CCB"))
        let night = SunTimes(sunrise: 700, sunset: 1140)
        #expect(sky.step(size: skySize, inputs: inputs(now, sun: night)).top == RGBA("#004A8CCB"))
        #expect(sky.step(size: skySize, inputs: inputs(utcDay(601), sun: night)).top == RGBA("#00304A8C"))
    }

    @Test func aForcedPhaseRecomputesAtOnceEvenWhenTheMinuteStays() {
        // A polar day at 00:00 is day by the clock; forced to night at the same minute, the fallback sun times make it night.
        let sky = SkyEngine(random: SeededRandomSource(seed: 3))
        let polar = SunTimes(sunrise: -80, sunset: 1520)
        #expect(sky.step(size: skySize, inputs: inputs(utcDay(0), sun: polar)).top == RGBA("#004A8CCB"))
        #expect(sky.step(size: skySize, inputs: inputs(utcDay(0), sun: polar, phase: .night)).top == RGBA("#00304A8C"))
        #expect(sky.step(size: skySize, inputs: inputs(utcDay(0), sun: polar)).top == RGBA("#004A8CCB"))
    }

    @Test func theMinuteInTheKeyRoundsHalfToEven() {
        let sky = SkyEngine(random: SeededRandomSource(seed: 3))
        _ = sky.step(size: skySize, inputs: inputs(utcDay(600)))
        let night = SunTimes(sunrise: 700, sunset: 1140)
        // 600.5 rounds to 600: same key. 601.5 rounds to 602: recompute.
        #expect(sky.step(size: skySize, inputs: inputs(utcDay(600.5), sun: night)).top == RGBA("#004A8CCB"))
        #expect(sky.step(size: skySize, inputs: inputs(utcDay(601.5), sun: night)).top == RGBA("#00304A8C"))
    }

    @Test func aNewWeatherCodeOrSizeRecomputesAtOnce() {
        let sky = SkyEngine(random: SeededRandomSource(seed: 3))
        _ = sky.step(size: skySize, inputs: inputs(utcDay(780)))
        #expect(sky.step(size: skySize, inputs: inputs(utcDay(780), weather: SkyWeather(code: 3, windKmh: 8))).top == RGBA("#00586470"))
        let night = inputs(utcDay(780), sun: SunTimes(sunrise: 900, sunset: 1140), weather: SkyWeather(code: 3, windKmh: 8))
        #expect(sky.step(size: CGSize(width: 200, height: 43), inputs: night).top != RGBA("#00586470"))
    }

    @Test func anEmptySizeSkipsTheTickAndKeepsTheLastFrame() {
        let sky = SkyEngine(random: SeededRandomSource(seed: 3))
        let blank = sky.step(size: .zero, inputs: inputs(utcDay(780)))
        #expect(blank == SkyFrame(top: RGBA("#00304A8C"), bottom: RGBA("#1A304A8C"), ops: []))
        let frame = sky.step(size: skySize, inputs: inputs(utcDay(780), weather: SkyWeather(code: 2, windKmh: 8)))
        #expect(sky.step(size: CGSize(width: 236, height: 0), inputs: inputs(utcDay(60))) == frame)
    }

    @Test func spritesComeInSkyPs1sZOrder() {
        let rank = ["stars", "moonDark", "moonLit", "glow", "sun", "clouds", "fog", "rain", "snow", "ground", "flash"]
        let scenes: [SkyInputs] = [
            // 06:40, mostly clear: stars, both moon parts, glow, sun and clouds at once.
            inputs(utcDay(400), weather: SkyWeather(code: 1, windKmh: 8)),
            inputs(utcDay(60), weather: SkyWeather(code: 45, windKmh: 8)),
            inputs(utcDay(780), weather: SkyWeather(code: 73, windKmh: 8)),
            inputs(utcDay(780), weather: SkyWeather(code: 95, windKmh: 8)),
        ]
        for scene in scenes {
            let order = Sprites(SkyEngine(random: ScriptedRandom(restInt: 0)).step(size: skySize, inputs: scene)).order
            let ranks = order.map { rank.firstIndex(of: $0) ?? -1 }
            #expect(!ranks.contains(-1) && ranks == ranks.sorted(), "\(order)")
        }
        let first = Set(Sprites(SkyEngine(random: ScriptedRandom(restInt: 0)).step(size: skySize, inputs: scenes[0])).order)
        #expect(first == ["stars", "moonDark", "moonLit", "glow", "sun", "clouds"])
    }
}
