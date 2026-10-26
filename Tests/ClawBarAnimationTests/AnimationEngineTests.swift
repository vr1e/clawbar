import CoreGraphics
import Foundation
import Testing
import ClawBarAnimation
import ClawBarClawd
import ClawBarShared
import ClawBarSky

/// The rules between Clawd and the sky, as mascot-menu.ps1's timer and Sync-Mascot keep them.
@Suite struct AnimationEngineTests {
    static let dayTop = RGBA("#004A8CCB")
    static let nightTop = RGBA("#00304A8C")
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    @Test func clawdStepsBeforeTheSkyOnOneGenerator() {
        // The two engines by hand on one seeded source, in the original's order: the entrance act, then the sky's
        // sprites. Auto ends the act and rain makes the sky draw every tick, so a reversed order would show.
        let random = SeededRandomSource(seed: 5)
        let clawd = ClawdEngine(random: random, now: t0)
        let sky = SkyEngine(random: random)
        let busy = data(busy: 1, sessions: 1, pct: 40, place: DataSnapshot.sample.place)
        clawd.apply(ClawdDataInput(busy, critPercent: 85), now: t0)
        clawd.perform(.auto)
        let engine = engine(seed: 5)
        engine.apply(busy, config: Config(), now: t0)
        engine.perform(.auto)
        engine.perform(.skyWeather(63))
        var now = t0
        for _ in 0 ..< 40 {
            let expected = AnimationFrame(
                clawd: clawd.step(ClawdStepEnv(areaWidth: PlayArea.width(numberWidth: 32), mouseOverWindow: false, mouseX: nil, now: now, lang: .en)),
                sky: sky.step(size: PlayArea.skySize, inputs: SkyInfo.inputs(
                    nil, place: busy.place, now: now, localZone: Samples.timeZone, dev: SkyDevState(weatherCode: 63)
                ))
            )
            #expect(engine.step(inputs(now: now)) == expected)
            #expect(engine.frame == expected)
            now = now.addingTimeInterval(Double(clawd.tickMilliseconds) / 1000)
        }
    }

    @Test func dataWaitsForTheFirstRegistryRead() {
        // Before the registry's first read an empty session list means nothing; after it, no session puts him to bed.
        let waiting = settled()
        waiting.apply(data(sessions: 0, read: false), config: Config(), now: t0)
        let idle = (0 ..< 40).map { _ in FrameView(waiting.step(inputs()).clawd) }
        #expect(idle.allSatisfy { !$0.z })

        let read = settled()
        read.apply(data(sessions: 0, read: true), config: Config(), now: t0)
        let asleep = (0 ..< 40).map { _ in FrameView(read.step(inputs()).clawd) }
        // The 30-tick burrow, then the 'z'.
        #expect(!asleep[29].z && asleep[30].z)
    }

    @Test func hidingClawdForgetsTheHeartsAndStopsTheTicks() {
        let engine = settled()
        engine.apply(data(sessions: 1, pct: 50), config: Config(), now: t0)
        let shown = engine.step(inputs())
        #expect(shown.clawd.hearts == HeartsFrame(visible: true, shownHalves: 3, tooltip: "tired · 50% of the session limit left"))
        #expect(engine.tickMilliseconds != nil && engine.mascotVisible && engine.skyVisible)

        engine.apply(data(sessions: 1, pct: 50), config: Config(showMascot: false), now: t0)
        #expect(engine.frame.clawd == .empty && !engine.frame.clawd.hearts.visible)
        // The sky's last frame stays; no view draws it while Clawd is hidden.
        #expect(engine.frame.sky == shown.sky)
        #expect(engine.tickMilliseconds == nil && !engine.mascotVisible && !engine.skyVisible)
        #expect(engine.step(inputs()) == engine.frame)

        // Shown again with fewer halves: a new value, not a loss, so no blink of the old one.
        engine.apply(data(sessions: 1, pct: 90), config: Config(), now: t0)
        #expect(engine.tickMilliseconds == 90)
        let back = (0 ..< 4).map { _ in engine.step(inputs()).clawd.hearts.shownHalves }
        #expect(back == [1, 1, 1, 1])
    }

    @Test func theSkyFollowsClawdsCadenceDuringASequence() {
        // Waiting for you, so that no random hop or act of his own gets in the way of the cadence.
        let engine = engine()
        engine.apply(data(waiting: 1, pct: 10), config: Config(), now: t0)
        engine.perform(.auto)
        engine.step(inputs())
        #expect(engine.tickMilliseconds == 90)
        // Rain, so that every tick of the sky draws differently.
        engine.perform(.skyWeather(63))
        engine.perform(.act(.spin))
        var skies: [SkyFrame] = []
        var cadences: [Int?] = []
        for _ in 0 ..< 3 {
            skies.append(engine.step(inputs()).sky)
            cadences.append(engine.tickMilliseconds)
        }
        // A Claude Code sequence runs at 60 ms, and the sky moves on every one of its ticks.
        #expect(cadences == [60, 60, 60])
        #expect(skies[0] != skies[1] && skies[1] != skies[2])
        for _ in 0 ..< 60 { engine.step(inputs()) }
        #expect(engine.tickMilliseconds == 90)
    }

    @Test func anOverrideShowsOnTheNextTickAndAutoReturnsToTheClock() {
        // 14:05 in Berlin with no weather: a clear day by the fallback sun times.
        let engine = engine()
        engine.apply(data(sessions: 1), config: Config(), now: t0)
        #expect(engine.step(inputs()).sky.top == Self.dayTop)
        engine.perform(.skyPhase(.night))
        #expect(engine.step(inputs()).sky.top == Self.nightTop)
        engine.perform(.skyWeather(73))
        let snowing = engine.step(inputs()).sky
        #expect(Sprites(snowing).ground != nil && Sprites(snowing).flakes != nil)
        let checked = skyMenu(engine)?.children.filter(\.checked).map(\.title)
        #expect(checked == ["night", "snow"])
        #expect(engine.skyTooltip(now: t0, timeZone: Samples.timeZone).hasPrefix("dev · night, snow\n"))

        engine.perform(.auto)
        let clear = engine.step(inputs()).sky
        #expect(clear.top == Self.dayTop && Sprites(clear).ground == nil)
        #expect(skyMenu(engine)?.children.filter(\.checked).map(\.title) == ["by the clock", "live weather"])
        #expect(engine.skyTooltip(now: t0, timeZone: Samples.timeZone).hasPrefix("weather: no data\nsunrise 07:00 · sunset 19:00\n"))
    }

    @Test func aHiddenSkyIsNotSteppedAndKeepsItsLastFrame() {
        // The sky by hand on the same seed, stepped only while shown: a hidden step would draw from the shared
        // generator and move Clawd's frames too.
        let random = SeededRandomSource(seed: 2026)
        let clawd = ClawdEngine(random: random, now: t0)
        let sky = SkyEngine(random: random)
        clawd.perform(.auto)
        let oneSession = data(sessions: 1)
        let env = ClawdStepEnv(areaWidth: PlayArea.width(numberWidth: 32), mouseOverWindow: false, mouseX: nil, now: t0, lang: .en)
        let rain = SkyInfo.inputs(nil, place: nil, now: t0, localZone: Samples.timeZone, dev: SkyDevState(weatherCode: 63))
        let engine = settled()
        engine.perform(.skyWeather(63))
        var last = SkyFrame.empty
        for shown in [true, false, true] {
            engine.apply(oneSession, config: Config(showSky: shown), now: t0)
            clawd.apply(ClawdDataInput(oneSession, critPercent: 85), now: t0)
            let c = clawd.step(env)
            if shown { last = sky.step(size: PlayArea.skySize, inputs: rain) }
            #expect(engine.step(inputs()) == AnimationFrame(clawd: c, sky: last))
            #expect(engine.skyVisible == shown && engine.mascotVisible && engine.tickMilliseconds == 90)
            #expect(skyMenu(engine)?.enabled == shown)
        }
    }

    @Test func theLanguageAndTheCritPercentArriveWithTheData() {
        // Built in English, switched to German by a data tick, as a reloaded config.json reaches the engine.
        let german = engine()
        german.apply(data(sessions: 1, pct: 50), config: Config(language: "de"), now: t0)
        #expect(german.step(inputs()).clawd.hearts.tooltip == "müde · 50% des Sitzungslimits übrig")
        #expect(german.developerMenu()[2].title == "Automatisch (Live-Daten)")
        #expect(german.skyTooltip(now: t0, timeZone: Samples.timeZone).hasPrefix("Wetter: keine Daten\n"))

        // 50% leaves three halves, a tier that does not sweat by itself: only critPercent makes him.
        func sweats(critPercent: Int) -> Bool {
            let engine = settled()
            engine.apply(data(sessions: 1, pct: 50), config: Config(critPercent: critPercent), now: t0)
            return (0 ..< 5).contains { _ in !FrameView(engine.step(inputs()).clawd).sweat.isEmpty }
        }
        #expect(sweats(critPercent: 50) && !sweats(critPercent: 85))
    }

    @Test func theZoneInputReachesTheSkyAndItsTooltip() {
        // No weather or place: 21:05 in Tokyo is night by the fallback sun times, where Berlin's 14:05 is day.
        let plain = engine()
        plain.apply(data(sessions: 1), config: Config(), now: t0)
        #expect(plain.step(inputs(zone: Self.tokyo)).sky.top == Self.nightTop)
        // Configured coordinates carry no zone, so NOAA's sun times are on the given zone's clock.
        let placed = engine()
        placed.apply(data(sessions: 1, place: Place(lat: 52.52, lon: 13.405)), config: Config(), now: t0)
        #expect(placed.skyTooltip(now: t0, timeZone: Samples.timeZone).hasPrefix("weather: no data\nsunrise 07:34 · sunset 18:08\n"))
        #expect(placed.skyTooltip(now: t0, timeZone: Self.tokyo).hasPrefix("weather: no data\nsunrise 14:34 · sunset 01:08\n"))
    }

    @Test func thePlaceReachesTheSkyAndItsTooltip() {
        let berlin = engine()
        berlin.apply(data(sessions: 1, weather: DataSnapshot.sample.weather, place: DataSnapshot.sample.place), config: Config(), now: t0)
        #expect(berlin.skyTooltip(now: t0, timeZone: Samples.timeZone).hasPrefix("Berlin · "))
        // A place with its own zone: 23:05 in Sydney is night, whatever the Mac's zone says.
        let sydney = engine()
        sydney.apply(data(sessions: 1, place: Place(lat: -33.87, lon: 151.21, city: "Sydney", timeZoneID: "Australia/Sydney")), config: Config(), now: t0)
        #expect(sydney.step(inputs()).sky.top == Self.nightTop)
    }

    @Test func thePointerReachesClawd() {
        // Waiting for you with the pointer far to his right, he looks right: his eyes sit further right than when it is left.
        func eyesX(mouseX: Double) -> Double {
            let engine = settled(seed: 3)
            engine.apply(data(waiting: 1), config: Config(), now: t0)
            return Double(FrameView(engine.step(inputs(over: true, mouseX: mouseX)).clawd).eyes.map(\.minX).min() ?? .nan)
        }
        #expect(eyesX(mouseX: 190) > eyesX(mouseX: 0))
    }

    @Test func thePointerOverTheWindowKeepsHimFromDozing() {
        // Ten minutes of silence doze him off; a pointer over the window counts as company, even without an x.
        func dozes(over: Bool) -> Bool {
            let engine = settled()
            engine.apply(data(sessions: 1), config: Config(), now: t0)
            return (0 ..< 10).contains { _ in FrameView(engine.step(inputs(now: t0 + 600, over: over)).clawd).z }
        }
        #expect(dozes(over: false) && !dozes(over: true))
    }
}
