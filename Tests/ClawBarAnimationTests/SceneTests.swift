import CoreGraphics
import Foundation
import Testing
import ClawBarAnimation
import ClawBarShared

/// The theme's scene inside the animation tick: in the sky's place, at a steady pace, with or without Clawd.
@Suite struct SceneTests {
    static let card = CGSize(width: 260, height: 220)
    static let christmas = Config(theme: .fixed(.christmas))

    @discardableResult
    private func ticks(_ e: AnimationEngine, _ n: Int, every ms: Double = 90, from start: Date = t0) -> [AnimationFrame] {
        (0 ..< n).map { i in e.step(inputs(now: start.addingTimeInterval(Double(i) * ms / 1000), backdrop: Self.card)) }
    }

    private func christmasEngine(_ config: Config = christmas) -> AnimationEngine {
        let e = settled()
        e.apply(data(sessions: 1), config: config, skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        return e
    }

    @Test func aSceneTakesTheSkysPlaceAndTheSkyWaits() {
        let frames = ticks(christmasEngine(), 20)
        #expect(frames.allSatisfy { $0.scene != nil && $0.sky == .empty })
        #expect(ticks(settled(), 3).allSatisfy { $0.scene == nil })
    }

    @Test func theWeatherSkyResumesWhereTheSceneFoundIt() {
        // Rain, so the weather's sky changes on every tick it steps.
        let e = settled()
        e.perform(.skyWeather(63))
        e.apply(data(sessions: 1), config: Config(), skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        let sky = ticks(e, 30).last?.sky
        e.apply(data(sessions: 1), config: Self.christmas, skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        #expect(ticks(e, 30, from: t0.addingTimeInterval(3)).allSatisfy { $0.sky == sky })
        e.apply(data(sessions: 1), config: Config(), skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        #expect(ticks(e, 30, from: t0.addingTimeInterval(6)).contains { $0.sky != sky })
    }

    @Test func bySeasonFindsTheSceneOnTheDay() throws {
        // Samples.now is in October: Halloween, with its bats.
        let bat = RGBA("#FF7353A0")
        #expect(ticks(christmasEngine(Config(theme: .bySeason)), 2).allSatisfy {
            $0.scene?.backdrop.contains { if case let .rects(_, c, _) = $0 { c == bat } else { false } } == true
        })
        let december = try #require(Calendar.gregorian(in: Samples.timeZone).date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 12)))
        #expect(ticks(christmasEngine(Config(theme: .bySeason)), 2, from: december).allSatisfy { $0.scene != nil })
    }

    @Test func withClawdHiddenTheSceneStillMoves() {
        let e = christmasEngine(Config(theme: .fixed(.christmas), showMascot: false))
        #expect(e.tickMilliseconds == 90)
        let frames = ticks(e, 4)
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.scene != $1.scene })
        #expect(frames.allSatisfy { $0.clawd == .empty && $0.scene?.sky.isEmpty == true })
        // Without a scene there is nothing to move.
        e.apply(data(sessions: 1), config: Config(showMascot: false), skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        #expect(e.tickMilliseconds == nil)
        #expect(e.frame.scene == nil)
    }

    @Test func switchingBackResumesTheScene() {
        let e = christmasEngine()
        let red = RGBA("#FFEF4444")
        func sleighX(_ f: AnimationFrame) -> Double? {
            f.scene?.sky.flatMap { op -> [CGRect] in
                guard case let .rects(r, c, _) = op, c == red else { return [] }
                return r
            }.map { Double($0.minX) }.min()
        }
        let x = ticks(e, 140).last.flatMap(sleighX)
        e.apply(data(sessions: 1), config: Config(), skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        #expect(e.frame.scene == nil)
        e.apply(data(sessions: 1), config: Self.christmas, skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        let resumed = ticks(e, 1, from: t0.addingTimeInterval(20)).last.flatMap(sleighX)
        #expect(x != nil && resumed != nil && resumed! > x!)
    }

    @Test func aThemeSwitchShowsTheOtherThemesScene() {
        let e = christmasEngine()
        let shipGrey = RGBA("#FF94A3B8")
        func hasShip(_ f: AnimationFrame) -> Bool {
            f.scene?.sky.contains { if case let .rects(_, c, _) = $0 { c == shipGrey } else { false } } == true
        }
        #expect(ticks(e, 3).allSatisfy { $0.scene != nil && !hasShip($0) })
        e.apply(data(sessions: 1), config: Config(theme: .fixed(.space)), skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        #expect(ticks(e, 3, from: t0.addingTimeInterval(1)).allSatisfy(hasShip))
    }

    @Test func theSearchlightsRiseFromWhereTheCardPutsTheSkyRow() {
        let e = christmasEngine(Config(theme: .fixed(.cyberpunk)))
        // Each cone's tip is its picture's origin, so the group's move is where it lands on the card.
        func tips(_ origin: CGPoint, at i: Int) -> [CGPoint] {
            let f = e.step(inputs(now: t0.addingTimeInterval(Double(i) * 0.09), backdrop: Self.card, skyOrigin: origin))
            return f.scene?.backdrop.compactMap { op -> CGPoint? in
                guard case let .group(c, t, _, _) = op, case .polygon = c.first else { return nil }
                return CGPoint(x: t.tx, y: t.ty)
            } ?? []
        }
        let high = tips(CGPoint(x: 12, y: 30), at: 0), low = tips(CGPoint(x: 12, y: 60), at: 1)
        #expect(high.count == 2 && low.count == 2)
        #expect(zip(high, low).allSatisfy { abs($1.y - $0.y - 30) < 1e-9 && abs($1.x - $0.x) < 1e-9 })
    }

    // MARK: Halloween's scare

    private func scaredEngine(_ config: Config = Config(theme: .fixed(.halloween))) -> AnimationEngine {
        let e = christmasEngine(config)
        ticks(e, 2)
        e.play(.scare)
        return e
    }

    @Test func theScareMakesClawdJumpAsTheLightsComeBack() {
        let e = scaredEngine()
        // The developer caption names his act.
        e.perform(.sweat(true))
        let frames = ticks(e, 63, from: t0.addingTimeInterval(1))
        #expect(frames[60].scene?.secret?.cues == [.act(.jump)])
        #expect(frames[59].clawd.devCaption != "dev · jump")
        #expect(frames[61].clawd.devCaption == "dev · jump")
    }

    @Test func withClawdHiddenTheScarePlaysWithoutHisJump() {
        let e = scaredEngine(Config(theme: .fixed(.halloween), showMascot: false))
        let frames = ticks(e, 63, from: t0.addingTimeInterval(1))
        #expect(frames[30].scene?.secret != nil)
        #expect(frames.allSatisfy { $0.clawd == .empty })
    }

    /// A scare 20 steps in, ended by `end`: the lights are back at once and stay back.
    private func expectLightsBack(after end: (AnimationEngine) -> Void) {
        let e = scaredEngine()
        #expect(ticks(e, 20, from: t0.addingTimeInterval(1)).last?.scene?.secret != nil)
        end(e)
        #expect(e.frame.scene?.secret == nil)
        #expect(ticks(e, 60, from: t0.addingTimeInterval(4)).allSatisfy { $0.scene?.secret == nil })
    }

    @Test func aThemeSwitchPutsTheLightsBack() {
        expectLightsBack { e in
            e.apply(data(sessions: 1), config: Self.christmas, skins: .builtIn, now: t0, timeZone: Samples.timeZone)
            e.apply(data(sessions: 1), config: Config(theme: .fixed(.halloween)), skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        }
    }

    @Test func hidingTheWidgetPutsTheLightsBack() {
        expectLightsBack { $0.endSecret() }
    }

    // MARK: Cyberpunk's 20:77 secret

    static let cyberpunk = Config(theme: .fixed(.cyberpunk))
    static let gear = SkinCatalog.builtIn.skin(for: BuiltInSkin.netrunner.rawValue).layers.first?.color

    private func evening() throws -> Date {
        try #require(Calendar.gregorian(in: Samples.timeZone).date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 21, minute: 17)))
    }

    private func jacked(_ f: AnimationFrame) -> Bool {
        f.clawd.ops.contains { if case let .rects(_, c, _) = $0 { c == Self.gear } else { false } }
    }

    /// An engine on the Cyberpunk theme with Clawd asleep, as no session runs.
    private func asleepEngine(_ config: Config = cyberpunk) -> AnimationEngine {
        let e = settled()
        e.apply(data(sessions: 0), config: config, skins: .builtIn, now: t0, timeZone: Samples.timeZone)
        return e
    }

    @Test func at2077ClawdWakesJacksInWavesAndSleepsAgain() throws {
        let e = asleepEngine()
        let frames = ticks(e, 400, from: try evening().addingTimeInterval(-5))
        let start = try #require(frames.firstIndex { $0.scene?.secret != nil })
        // The wake forces idle, which the developer caption names.
        #expect(frames[start + 11].clawd.devCaption.isEmpty)
        #expect(!frames[start + 13].clawd.devCaption.isEmpty)
        #expect(frames[start + 61 ..< start + 94].allSatisfy(jacked))
        #expect(frames[start + 56 ..< start + 70].contains { $0.clawd.devCaption.hasSuffix("wave") })
        // Himself and asleep again once it is over.
        #expect(frames[start + 111 ..< 400].allSatisfy { !jacked($0) && $0.clawd.devCaption.isEmpty && $0.scene?.secret == nil })
    }

    @Test func withClawdHiddenTwentySeventySevenNeverStrikes() throws {
        let e = asleepEngine(Config(theme: .fixed(.cyberpunk), showMascot: false))
        #expect(ticks(e, 400, from: try evening().addingTimeInterval(-5)).allSatisfy { $0.scene?.secret == nil })
    }

    @Test func endingTheSecretPutsClawdBack() {
        let e = asleepEngine()
        ticks(e, 2)
        e.play(.relic)
        let frames = ticks(e, 60, from: t0.addingTimeInterval(1))
        #expect(jacked(frames[59]) && !frames[59].clawd.devCaption.isEmpty)
        e.endSecret()
        let after = ticks(e, 2, from: t0.addingTimeInterval(7))
        #expect(after.allSatisfy { !jacked($0) && $0.clawd.devCaption.isEmpty && $0.scene?.secret == nil })
    }
}
