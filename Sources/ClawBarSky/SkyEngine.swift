import CoreGraphics
import Foundation
import ClawBarShared

/// sky.ps1: gradient, sun, moon, stars, clouds, fog, rain, snow and lightning, tick by tick.
public final class SkyEngine {
    private let random: any RandomSource

    /// Step-Sky recomputes the colours and bodies when this changes: about once a minute, and at once when a developer
    /// override changes the phase or the code. The minute stays a Double, so no time can trap converting it.
    private struct Key: Equatable {
        var minute: Double
        var code: Int
        var w: Double
        var h: Double
        var forcedPhase: SkyPhase?
    }

    private var tick = 0
    private var w = 0.0
    private var h = 0.0
    private var key: Key?
    private var kind = WeatherKinds.kind(code: 0)
    private var light = 0.0
    private var top = SkyArt.night.top
    private var bottom = SkyArt.night.bottom
    /// The sun's, glow's and moon's opacity: how much the clouds let through.
    private var vis = 0.0
    /// Top-left corners on the arc; nil while collapsed.
    private var sunAt: CGPoint?
    private var glowAt: CGPoint?
    private var sunColor = SkyArt.sunHigh
    private var moonAt: CGPoint?
    /// The phase is redrawn when the age in half days or the hemisphere changes.
    private var moonKey: MoonKey?
    private var moonLit: [String] = []
    private var moonDark: [String] = []
    private var lastFrame = SkyFrame(top: SkyArt.night.top, bottom: SkyArt.night.bottom, ops: [])

    private struct MoonKey: Equatable {
        var halfDays: Int
        var south: Bool
    }

    private struct Star {
        var fx: Double
        var fy: Double
        var left = 0.0
        var top = 0.0
    }

    private struct Cloud {
        let rows: [String]
        let width: Double
        /// Negative until the first layout places it.
        var x = -1.0
        var fy: Double
        let v: Double
        var fade = 0.0
    }

    private struct FogBand {
        var x: Double
        let fy: Double
    }

    /// y below −50 means not yet spawned: the first spawn spreads drops through the sky.
    private struct Drop {
        var x = 0.0
        var y = -99.0
        var v = 0.0
    }

    private struct Flake {
        var x = 0.0
        var y = -99.0
        var v = 0.0
        var ph = 0.0
    }

    private var stars: [Star]
    private var starOp = 0.0
    private var clouds: [Cloud]
    private var cloudCount = 0
    private var cloudColor = SkyArt.cloudDay
    private var fog: [FogBand]
    private var drops = Array(repeating: Drop(), count: 40)
    private var rainCount = 0
    private var flakes = Array(repeating: Flake(), count: 34)
    private var snowCount = 0
    /// Rain's sideways step per tick, which also carries the snow.
    private var slant = 0.0
    private var groundColor = SkyArt.snowNight
    /// Ticks left of a lightning flash, and this tick's flash opacity.
    private var flash = 0
    private var flashOpacity = 0.0

    /// Draws the sprites' random fractions in sky.ps1's order: stars, then clouds, then fog.
    public init(random: any RandomSource) {
        self.random = random
        stars = (0 ..< 20).map { _ in
            let fx = random.nextDouble()
            return Star(fx: fx, fy: random.nextDouble() * 0.6)
        }
        clouds = (0 ..< 9).map { i in
            let rows = SkyArt.clouds[i % SkyArt.clouds.count]
            let fy = 0.05 + 0.3 * random.nextDouble()
            return Cloud(rows: rows, width: Double(rows[0].count) * SkyArt.cloudPx, fy: fy, v: 0.7 + 0.6 * random.nextDouble())
        }
        fog = (0 ..< 3).map { i in FogBand(x: random.nextDouble(), fy: 0.42 + 0.2 * Double(i)) }
    }

    /// One tick at `size` (base units, `PlayArea.skySize`).
    public func step(size: CGSize, inputs: SkyInputs) -> SkyFrame {
        tick += 1
        let w = Double(size.width), h = Double(size.height)
        guard w > 0, h > 0, w.isFinite, h.isFinite else { return lastFrame }
        if w != self.w || h != self.h { layOut(w, h) }

        let sun = Self.drawable(inputs.sun, forced: inputs.forcedPhase != nil)
        let sr = sun.sunrise, ss = sun.sunset
        var t = Self.minutesOfDay(inputs.now, in: inputs.timeZone)
        switch inputs.forcedPhase {
        case .dawn: t = sr - 10
        case .day: t = (sr + ss) / 2
        case .dusk: t = ss + 10
        case .night: t = 0
        case nil:
            // SkyInfo keeps a sunset after midnight tomorrow; until yesterday's dusk is over, draw that.
            if ss > 1440, t < sr - 80, t + 1440 < ss + 80 { t += 1440 }
        }
        let code = inputs.weather?.code ?? 0
        let wind = inputs.weather.flatMap { $0.windKmh.isFinite ? $0.windKmh : nil } ?? 8

        let key = Key(minute: t.rounded(.toNearestOrEven), code: code, w: w, h: h, forcedPhase: inputs.forcedPhase)
        if key != self.key {
            self.key = key
            recompute(t: t, sr: sr, ss: ss, code: code, inputs: inputs)
        }

        driftClouds(wind: wind)
        if kind.fog {
            for i in fog.indices { fog[i].x = (fog[i].x + 0.0015).truncatingRemainder(dividingBy: 1.6) }
        }
        slant = min(1.2, wind / 25)
        fall()
        // Thunderstorm: now and then the sky flashes, sometimes twice in a row.
        if kind.storm, flash <= 0, random.nextInt(140) == 0 { flash = 7 }
        flashOpacity = 0
        if flash > 0 {
            flashOpacity = SkyArt.flashOpacity[flash - 1]
            flash -= 1
        }

        lastFrame = SkyFrame(top: top, bottom: bottom, ops: ops())
        return lastFrame
    }

    // MARK: Layout and recompute

    /// The size changed: lay out the static parts again.
    private func layOut(_ w: Double, _ h: Double) {
        self.w = w
        self.h = h
        key = nil
        for i in stars.indices {
            stars[i].left = (stars[i].fx * (w - 2)).rounded(.toNearestOrEven)
            stars[i].top = (2 + stars[i].fy * h).rounded(.toNearestOrEven)
        }
        for i in clouds.indices where clouds[i].x < 0 { clouds[i].x = random.nextDouble() * w }
    }

    private func recompute(t: Double, sr: Double, ss: Double, code: Int, inputs: SkyInputs) {
        kind = WeatherKinds.kind(code: code)
        let (a, b, k) = Self.segment(t, sr: sr, ss: ss)
        light = a.light + (b.light - a.light) * k
        let g = kind.cover * 0.9
        top = RGBA.dim(RGBA.mix(a.top, b.top, k), g)
        bottom = RGBA.dim(RGBA.mix(a.bottom, b.bottom, k), g)

        // Settled snow: a thin strip underfoot whenever the kind has snow.
        groundColor = RGBA.mix(SkyArt.snowNight, SkyArt.snowDay, light)
        cloudColor = RGBA.mix(SkyArt.cloudNight, SkyArt.cloudDay, light)
        if kind.rain != 0 || kind.storm { cloudColor = RGBA.mix(cloudColor, SkyArt.cloudRain, 0.55) }

        // The sun by day, from sunrise to sunset, orange near the horizon.
        vis = max(0, 1 - kind.cover * 1.15)
        let p = ss > sr ? (t - sr) / (ss - sr) : .nan
        if let at = onArc(p, half: 4.9), vis > 0 {
            sunAt = at
            glowAt = onArc(p, half: 10)
            sunColor = RGBA.mix(SkyArt.sunLow, SkyArt.sunHigh, sin(.pi * p) * 1.6)
        } else {
            sunAt = nil
            glowAt = nil
        }
        // The moon by night, from sunset to the next sunrise.
        setMoonPhase(latitude: inputs.latitude, now: inputs.now)
        let night = sr + 1440 - ss
        let q = night > 0 ? (t - ss + 1440).truncatingRemainder(dividingBy: 1440) / night : .nan
        moonAt = vis > 0 ? onArc(q, half: 4.55) : nil

        starOp = (1 - light * 2) * max(0, 1 - kind.cover * 1.4)
        // The counts are tuned for a sky about 140 wide; a wider one gets more.
        let dens = max(1, w / 140)
        cloudCount = min(clouds.count, whole(kind.cover * 5 * dens))
        rainCount = min(drops.count, whole(Double(kind.rain) * dens))
        snowCount = min(flakes.count, whole(Double(kind.snow) * dens))
    }

    /// Rain falls fast and slants with the wind; snow falls slowly. Unused ones wait above the sky.
    private func fall() {
        for i in drops.indices {
            guard i < rainCount else {
                drops[i].y = -99
                continue
            }
            if drops[i].y < -50 || drops[i].y > h {
                drops[i].x = random.nextDouble() * (w + 10) - 10
                drops[i].y = drops[i].y < -50 ? random.nextDouble() * h : -4
                drops[i].v = 3.5 + 1.5 * random.nextDouble()
            }
            drops[i].y += drops[i].v
            drops[i].x += slant
        }
        for i in flakes.indices {
            guard i < snowCount else {
                flakes[i].y = -99
                continue
            }
            if flakes[i].y < -50 || flakes[i].y > h {
                flakes[i].x = random.nextDouble() * w
                flakes[i].y = flakes[i].y < -50 ? random.nextDouble() * h : -2
                flakes[i].v = 0.3 + 0.35 * random.nextDouble()
                flakes[i].ph = random.nextDouble() * 6.28
            }
            flakes[i].y += flakes[i].v
        }
    }

    /// Clouds drift with the wind, always to the right; extra ones fade out, needed ones fade in.
    private func driftClouds(wind: Double) {
        let drift = 0.04 + wind / 350
        for i in clouds.indices {
            let want = i < cloudCount ? 1.0 : 0.0
            clouds[i].fade += max(-0.03, min(0.03, want - clouds[i].fade))
            guard clouds[i].fade > 0 else { continue }
            clouds[i].x += drift * clouds[i].v
            if clouds[i].x > w {
                clouds[i].x = -clouds[i].width
                clouds[i].fy = 0.05 + 0.3 * random.nextDouble()
            }
        }
    }


    private func setMoonPhase(latitude: Double, now: Date) {
        let age = Moon.age(at: now)
        let key = MoonKey(halfDays: Int((age * 2).rounded(.toNearestOrEven)), south: latitude < 0)
        guard key != moonKey else { return }
        moonKey = key
        (moonLit, moonDark) = Self.moonRows(age: age, south: key.south)
    }

    /// A 7 × 7 disk; a pixel is lit on the bright side of the terminator u = cos θ·√(1 − v²).
    private static func moonRows(age: Double, south: Bool) -> (lit: [String], dark: [String]) {
        let th = 2 * Double.pi * age / Moon.synodicMonth
        let k = cos(th)
        let n = 7, r = Double(n) / 2
        var lit: [String] = [], dark: [String] = []
        for y in 0 ..< n {
            var a = "", b = ""
            for x in 0 ..< n {
                var u = (Double(x) + 0.5 - r) / r
                let v = (Double(y) + 0.5 - r) / r
                // In the southern hemisphere the waxing moon is lit on the left.
                if south { u = -u }
                let inside = u * u + v * v <= 1.05
                let t = k * max(0, 1 - v * v).squareRoot()
                let on = inside && (th < .pi ? u > t : u < -t)
                a.append(on ? "#" : ".")
                b.append(inside && !on ? "#" : ".")
            }
            lit.append(a)
            dark.append(b)
        }
        return (lit, dark)
    }

    /// Set-OnArc: where a body of half-size `half` sits at `p` (0...1 from horizon to horizon); nil off the arc.
    /// The horizon is 3 below the bottom edge, so bodies rise from behind the ground.
    private func onArc(_ p: Double, half: Double) -> CGPoint? {
        guard p >= -0.06, p <= 1.06 else { return nil }
        let alt = sin(.pi * p)
        return CGPoint(x: 7 + p * (w - 14) - half, y: h + 3 - alt * (h - 12) - half)
    }

    // MARK: Frame

    /// The visible sprites in sky.ps1's z-order.
    private func ops() -> [DrawOp] {
        var ops: [DrawOp] = []
        if starOp > 0 {
            for (i, star) in stars.enumerated() {
                let twinkle = 0.55 + 0.45 * sin(Double(tick) / 7 + Double(i) * 1.7)
                ops.append(.rects([CGRect(x: star.left, y: star.top, width: 1.2, height: 1.2)], SkyArt.star, opacity: starOp * twinkle))
            }
        }
        if let moonAt {
            let px = SkyArt.moonPx
            for (rows, color) in [(moonDark, SkyArt.moonDark), (moonLit, SkyArt.moonLit)] {
                let rects = PixelArt.rects(rows, value: "#", px: px, py: px, origin: moonAt)
                if !rects.isEmpty { ops.append(.rects(rects, color, opacity: vis)) }
            }
        }
        if let glowAt {
            ops.append(.radialGlow(
                CGRect(origin: glowAt, size: CGSize(width: 20, height: 20)),
                inner: SkyArt.glowInner, outer: SkyArt.glowOuter, opacity: vis
            ))
        }
        if let sunAt {
            let px = SkyArt.sunPx
            ops.append(.rects(PixelArt.rects(SkyArt.sun, value: "#", px: px, py: px, origin: sunAt), sunColor, opacity: vis))
        }
        for cloud in clouds where cloud.fade > 0 {
            let origin = CGPoint(x: cloud.x.rounded(.toNearestOrEven), y: (cloud.fy * h).rounded(.toNearestOrEven))
            let px = SkyArt.cloudPx
            ops.append(.rects(PixelArt.rects(cloud.rows, value: "#", px: px, py: px, origin: origin), cloudColor, opacity: 0.65 * cloud.fade))
        }
        if kind.fog {
            for band in fog {
                let rect = CGRect(x: (band.x - 0.6) * w, y: band.fy * h, width: w * 0.6, height: 3)
                ops.append(.hGradient(rect, stops: SkyArt.fogStops, opacity: 0.14 + 0.05 * sin(Double(tick) / 20 + band.fy * 10)))
            }
        }
        let rain = drops.prefix(rainCount).map { CGRect(x: $0.x, y: $0.y, width: 1, height: 3.5) }
        if !rain.isEmpty { ops.append(.rects(rain, SkyArt.drop, opacity: 1)) }
        let snow = flakes.prefix(snowCount).map { f in
            CGRect(x: f.x + 1.5 * sin(Double(tick) / 9 + f.ph) + slant * f.y / 4, y: f.y, width: 1.6, height: 1.6)
        }
        if !snow.isEmpty { ops.append(.rects(snow, SkyArt.flake, opacity: 1)) }
        if kind.snow > 0 { ops.append(.rects([CGRect(x: 0, y: h - 1.5, width: w, height: 1.5)], groundColor, opacity: 1)) }
        if flashOpacity > 0 { ops.append(.rects([CGRect(x: 0, y: 0, width: w, height: h)], SkyArt.flash, opacity: flashOpacity)) }
        return ops
    }

    /// The palette segment around sunrise or sunset that holds `t`; night outside them all.
    private static func segment(_ t: Double, sr: Double, ss: Double) -> (SkyArt.Palette, SkyArt.Palette, Double) {
        let stops = [
            (sr - 80, SkyArt.night), (sr - 10, SkyArt.dawn), (sr + 70, SkyArt.day),
            (ss - 70, SkyArt.day), (ss + 10, SkyArt.dusk), (ss + 80, SkyArt.night),
        ]
        for i in 0 ..< stops.count - 1 where t >= stops[i].0 && t < stops[i + 1].0 {
            return (stops[i].1, stops[i + 1].1, (t - stops[i].0) / (stops[i + 1].0 - stops[i].0))
        }
        return (SkyArt.night, SkyArt.night, 0)
    }

    // MARK: Time

    /// (Get-Date).TimeOfDay.TotalMinutes, on the wall clock of `zone`.
    private static func minutesOfDay(_ now: Date, in zone: TimeZone) -> Double {
        let local = now.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: now))
        let s = local.truncatingRemainder(dividingBy: 86_400)
        return (s < 0 ? s + 86_400 : s) / 60
    }

    /// Sun times the step can use: unusable ones are 07:00/19:00, and so are polar ones under a developer phase,
    /// whose dawn, day, dusk and night need a sunrise today and a night.
    private static func drawable(_ sun: SunTimes, forced: Bool) -> SunTimes {
        let usable = abs(sun.sunrise) <= 4 * 1440 && abs(sun.sunset) <= 4 * 1440
        let dayAndNight = sun.sunrise >= 0 && sun.sunset > sun.sunrise && sun.sunset - sun.sunrise < 1440
        return usable && (dayAndNight || !forced) ? sun : .fallback
    }
}
