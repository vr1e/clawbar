import Foundation

/// sky.ps1 Get-MoonAge and Get-MoonInfo: the moon's phase from how far it is from the Sun along the ecliptic.
enum Moon {
    static let synodicMonth = 29.530588853
    /// J2000.0, 2000-01-01 12:00 UTC.
    private static let j2000 = Date(timeIntervalSince1970: 946_728_000)

    /// Days since the new moon, 0 ..< synodicMonth, from the elongation with the main periodic terms (within about an hour).
    static func age(at now: Date) -> Double {
        let d = now.timeIntervalSince(j2000) / 86_400
        let rad = Double.pi / 180
        let g = (357.528 + 0.9856003 * d) * rad
        let meanSun = 280.460 + 0.9856474 * d
        let sun = meanSun + 1.915 * sin(g) + 0.020 * sin(2 * g)
        let lm = 218.316 + 13.176396 * d
        let mm = (134.963 + 13.064993 * d) * rad
        let dd = (lm - meanSun) * rad
        // Upstream subtracts the evection and the last two terms; the lunar series adds them, which cuts ~6 h to ~1 h.
        let moon = lm + 6.289 * sin(mm) + 1.274 * sin(2 * dd - mm) + 0.658 * sin(2 * dd) - 0.186 * sin(g)
            + 0.059 * sin(2 * dd - 2 * mm) + 0.057 * sin(2 * dd - mm - g)
        let e = ((moon - sun).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return e / 360 * synodicMonth
    }

    /// One of eight names, 0 the new moon round to 7 the waning crescent, and the percentage lit.
    static func info(at now: Date) -> (name: Int, lit: Int) {
        let f = age(at: now) / synodicMonth
        let name = Int((f * 8 + 0.5).rounded(.down)) % 8
        let lit = Int(((1 - cos(2 * .pi * f)) / 2 * 100).rounded(.toNearestOrEven))
        return (name, lit)
    }
}
