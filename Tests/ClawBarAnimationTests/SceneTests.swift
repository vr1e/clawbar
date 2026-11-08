import CoreGraphics
import Foundation
import Testing
import ClawBarAnimation
import ClawBarShared

/// The theme's scene inside the animation tick: in the sky's place, at a steady pace, with or without Clawd.
@Suite struct SceneTests {
    static let card = CGSize(width: 260, height: 220)
    static let christmas = Config(theme: .fixed(.christmas))

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
        // Samples.now is in October: Halloween, whose scene is not ported yet.
        #expect(ticks(christmasEngine(Config(theme: .bySeason)), 2).allSatisfy { $0.scene == nil })
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
}
