import CoreGraphics
import Foundation
import Testing
import ClawBarShared
@testable import ClawBarSky

/// Get-MoonAge, Set-MoonPhase and the moon's night arc. Pixel maps are worked out by hand from the terminator rule:
/// on a 7 × 7 grid, u = (x + 0.5 − 3.5)/3.5 (negated in the south), lit iff u > cos θ·√(1 − v²) while waxing
/// (θ < π) and u < −cos θ·√(1 − v²) while waning.
@Suite struct MoonTests {
    /// The new moon of the solar eclipse, 2024-04-08 18:21 UTC.
    static let epoch = Date(timeIntervalSince1970: 1_712_600_460)
    /// The full moon of the lunar eclipse, 2025-03-14 06:55 UTC.
    static let full = Date(timeIntervalSince1970: 1_741_935_300)
    static let disk = ["..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###.."]
    static let none = Array(repeating: ".......", count: 7)
    /// Lit on the right three columns (age 7.36: cos θ = 0.005, so u = 0 stays dark).
    static let right = ["....#..", "....##.", "....###", "....###", "....###", "....##.", "....#.."]
    static let left = ["..#....", ".##....", "###....", "###....", "###....", ".##....", "..#...."]

    /// The moon at a forced midnight with sunrise 07:00 and sunset 19:00: q = 300/720 on the arc.
    static let origin = CGPoint(x: 7 + 300.0 / 720 * 222 - 4.55, y: 46 - sin(.pi * 300 / 720) * 31 - 4.55)

    private func moon(at now: Date, latitude: Double = 50) -> (lit: [String], dark: [String]) {
        let sprites = Sprites(firstFrame(inputs(now, latitude: latitude, phase: .night)))
        let lit = sprites.moonLit.map { pixelRows($0.rects, px: 1.3, origin: Self.origin, columns: 7, rows: 7) } ?? Self.none
        let dark = sprites.moonDark.map { pixelRows($0.rects, px: 1.3, origin: Self.origin, columns: 7, rows: 7) } ?? Self.none
        return (lit, dark)
    }

    private func days(_ d: Double) -> Date { Self.epoch.addingTimeInterval(d * 86_400) }

    @Test func theEpochIsANewMoonAllDark() {
        let m = moon(at: Self.epoch)
        #expect(m.lit == Self.none)
        #expect(m.dark == Self.disk)
    }

    @Test func theLunarEclipseIsAFullMoonAllLit() {
        let m = moon(at: Self.full)
        #expect(m.lit == Self.disk)
        #expect(m.dark == Self.none)
    }

    @Test func waxingIsLitOnTheRightAndWaningOnTheLeft() {
        let waxing = moon(at: days(7))
        #expect(waxing.lit == Self.right)
        #expect(waxing.dark == ["..##...", ".###...", "####...", "####...", "####...", ".###...", "..##..."])
        let waning = moon(at: days(23))
        #expect(waning.lit == Self.left)
        #expect(waning.dark == ["...##..", "...###.", "...####", "...####", "...####", "...###.", "...##.."])
    }

    @Test func theSouthernHemisphereSeesItMirrored() {
        #expect(moon(at: days(7), latitude: -33.87).lit == Self.left)
        #expect(moon(at: days(23), latitude: -33.87).lit == Self.right)
    }

    @Test func phasesFollowTheRealMoonEitherSideOfTheEpoch() {
        // Six days before the epoch the age is 22.8: waning, past the last quarter.
        #expect(moon(at: days(-6)).lit == Self.left)
        // The full moon of 2026-10-26 04:12 UTC.
        #expect(moon(at: local(2026, 10, 26, 4, 12, in: Zones.utc)).lit == Self.disk)
    }

    /// The elongation with upstream's three signs fixed stays within ~1.1 h; the mean month was up to ~23 h off.
    @Test(arguments: [
        (epoch, 0.0),
        (full, 29.530588853 / 2),
        (Date(timeIntervalSince1970: 947_182_440), 0.0),  // the new moon of 2000-01-06 18:14 UTC
        (local(2026, 10, 26, 4, 12, in: Zones.utc), 29.530588853 / 2),
    ])
    func theAgeIsWithinAnHourAndAHalfAtKnownPhases(at: Date, age: Double) {
        let p = Moon.synodicMonth
        let off = (Moon.age(at: at) - age + p * 1.5).truncatingRemainder(dividingBy: p) - p / 2
        #expect(abs(off) * 24 < 1.5, "\(off * 24) h")
    }

    @Test func theNameAndLitPercentRoundAsUpstreamDoes() {
        #expect(Moon.info(at: Self.epoch) == (name: 0, lit: 0))
        #expect(Moon.info(at: Self.full) == (name: 4, lit: 100))
        // 7.36 days in: f·8 + 0.5 = 2.49, so first quarter, and (1 − cos 2πf)/2 = 0.498.
        #expect(Moon.info(at: days(7)) == (name: 2, lit: 50))
    }

    @Test func theMoonCrossesTheNightArcFromSunsetToSunrise() throws {
        // Real clock at 01:00 UTC: q = ((60 − 1140 + 1440) mod 1440)/(420 + 1440 − 1140) = 0.5, the zenith.
        let sprites = Sprites(firstFrame(inputs(utcDay(60), weather: SkyWeather(code: 2, windKmh: 10))))
        let dark = try #require(sprites.moonDark ?? sprites.moonLit)
        #expect(near(topLeft(dark.rects).y, 46 - 31 - 4.55, 1.3 + 1e-9))
        #expect(near(dark.opacity, 0.425, 1e-12))
        // By day q = 1.5: no moon. Rain clouds hide it at night.
        #expect(Sprites(firstFrame(inputs(utcDay(780)))).moonDark == nil)
        let rainy = Sprites(firstFrame(inputs(utcDay(60), weather: SkyWeather(code: 63, windKmh: 10))))
        #expect(rainy.moonDark == nil && rainy.moonLit == nil)
    }

    @Test func theDarkPartIsDrawnUnderTheLitPart() {
        let order = Sprites(firstFrame(inputs(days(7), phase: .night))).order
        #expect(order.filter { $0.hasPrefix("moon") } == ["moonDark", "moonLit"])
    }
}
