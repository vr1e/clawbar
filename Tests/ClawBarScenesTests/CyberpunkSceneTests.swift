import CoreGraphics
import Foundation
import Testing
import ClawBarScenes
import ClawBarShared

/// cyberpunk.ps1's scene: the glow, the rain, the glitches, the searchlights, the skyline with its beacon, the flying
/// cars and the neon signs.
@Suite struct CyberpunkSceneTests {
    static let farWall = RGBA("#FF1E1436"), nearWall = RGBA("#FF0B0716"), beacon = RGBA("#FFFF003C")
    static let carBody = RGBA("#FF3B3656"), roofSign = RGBA("#FF00F0FF"), sideSign = RGBA("#FFFF2A6D")
    static let bars = ["#66FF003C", "#5500F0FF", "#4DFF003C", "#4400F0FF", "#33FCEE0A"].map(RGBA.init)

    private func run(_ steps: Int, sky: Bool = true) -> [SceneFrame] {
        runScene(.cyberpunk, steps, sky: sky)
    }

    /// The rain's streaks in their order, after the glows.
    private func drops(_ f: SceneFrame) -> [CGRect] {
        f.backdrop.dropFirst(3).prefix(36).flatMap { op -> [CGRect] in if case let .rects(r, _, _) = op { r } else { [] } }
    }

    private func hasBars(_ f: SceneFrame) -> Bool {
        f.backdrop.contains { if case let .rects(_, c, _) = $0 { Self.bars.contains(c) } else { false } }
    }

    /// Where each searchlight's tip, its picture's origin, lands, and how far it turns.
    private func beams(_ f: SceneFrame) -> [(tip: CGPoint, degrees: Double)] {
        f.backdrop.compactMap { op in
            guard case let .group(c, t, _, _) = op, case .polygon = c.first else { return nil }
            return (CGPoint(x: t.tx, y: t.ty), atan2(t.b, t.a) * 180 / .pi)
        }
    }

    /// The skyline's shift: a glitch wraps each half of it in a group moved sideways.
    private func shift(_ f: SceneFrame) -> Double {
        if case let .group(_, t, _, _)? = f.sky.first { t.tx } else { 0 }
    }

    /// The sky's ops with the glitch's groups opened up, each child moved by the shift.
    private func flat(_ f: SceneFrame) -> [DrawOp] {
        f.sky.flatMap { op -> [DrawOp] in
            guard case let .group(c, t, 1, nil) = op, t.ty == 0, c.count > 2 else { return [op] }
            return c.map { child in
                guard case let .rects(r, color, o) = child else { return child }
                return .rects(r.map { $0.offsetBy(dx: t.tx, dy: 0) }, color, opacity: o)
            }
        }
    }

    @Test func theCitysGlowDriftsAlongTheBottom() {
        let f = run(1)[0]
        let glows = f.backdrop.prefix(3).compactMap { if case let .radialGlow(r, _, _, o) = $0 { (r, o) } else { nil } }
        #expect(zip(glows.map(\.0.width), [208.0, 260, 312]).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(glows.map(\.0.height) == [90, 110, 130])
        // Each reaches half its height below the card.
        #expect(glows.allSatisfy { abs($0.0.maxY - (220 + $0.0.height / 2)) < 1e-9 && (0.5 ... 1).contains($0.1) })
    }

    @Test func theRainFallsFastAndComesBackFromAbove() {
        let frames = run(200)
        #expect(frames.allSatisfy { drops($0).count == 36 && drops($0).allSatisfy { $0.width == 1 && (6 ... 12).contains($0.height) } })
        // The first step scatters the drops down the card.
        #expect(drops(frames[0]).filter { $0.minY > 110 }.count > 5)
        var respawned = 0
        for (a, b) in zip(frames, frames.dropFirst()) {
            for (before, after) in zip(drops(a), drops(b)) {
                let fall = after.minY - before.minY
                if (4.5 ... 9.5).contains(fall), after.minX == before.minX { continue }
                // Below the card, a drop starts again above it.
                #expect(before.minY > 220 - 10 && (-52 ... 3).contains(after.minY))
                respawned += 1
            }
        }
        #expect(respawned > 36)
    }

    @Test func aGlitchTearsAcrossNowAndThenAndJerksTheSkylineAside() {
        let frames = run(1_600)
        let torn = frames.indices.filter { hasBars(frames[$0]) }
        // The first after 150 steps, six steps of bars; the seventh puts the skyline back.
        #expect(Array(torn.prefix(6)) == Array(149 ... 154))
        #expect(frames[149 ... 154].allSatisfy { abs(shift($0)) == 2 })
        #expect(shift(frames[155]) == 0 && shift(frames[148]) == 0)
        // Then 250 to 699 steps until the next.
        let next = torn.dropFirst(6).first
        #expect(next.map { (155 + 250 ... 155 + 699).contains($0) } == true)
        #expect(frames.allSatisfy { abs(shift($0)) == 2 || shift($0) == 0 })
    }

    @Test func searchlightsSweepUpFromTheTowersTop() {
        let frames = run(400)
        let all = frames.map(beams)
        #expect(all.allSatisfy { $0.count == 2 })
        // The antenna's column, half a pixel in, on the skyline's top row; aside with the skyline in a glitch.
        let x = sceneSkyRow.minX + 96 * 1.6 + 0.8, y = sceneSkyRow.minY + 1
        #expect(zip(frames, all).allSatisfy { f, b in b.allSatisfy { abs($0.tip.x - x - shift(f)) < 1e-9 && abs($0.tip.y - y) < 1e-9 } })
        let turns = all.flatMap { $0.map(\.degrees) }
        #expect(turns.allSatisfy { abs($0) <= 38 + 1e-9 } && turns.contains { $0 > 30 } && turns.contains { $0 < -30 })
    }

    @Test func theSkylineRisesAlongTheRowWithItsBeaconBlinking() {
        let frames = run(28)
        let f = frames[0]
        // 26 rows from the row's top rounded: 1, so it ends 0.4 short of the floor line, as upstream's does.
        #expect(rects(f.sky, Self.farWall).map(\.maxY).max().map { abs($0 - 42.6) < 1e-9 } == true)
        #expect(rects(f.sky, Self.nearWall).map(\.maxY).max().map { abs($0 - 42.6) < 1e-9 } == true)
        // The antenna reaches the skyline's top row.
        #expect(rects(f.sky, Self.farWall).contains { abs($0.minX - 96 * 1.6) < 1e-9 && $0.minY == 1 })
        // On for the first 4 of every 14 steps, counted from the scene's first.
        let on = frames.indices.filter { !rects(flat(frames[$0]), Self.beacon).filter { $0.width == 1.6 && $0.height == 1.6 }.isEmpty }
        #expect(on == [0, 1, 2, 13, 14, 15, 16, 27])
    }

    @Test func windowsDimNowAndThen() {
        let opacities = run(600).flatMap { f in
            f.sky.compactMap { if case let .rects(_, c, o) = $0, c != Self.farWall, c != Self.nearWall, c != Self.beacon { o } else { nil } }
        }
        #expect(opacities.allSatisfy { (0.15 ... 1).contains($0) })
        #expect(opacities.contains { $0 < 0.5 } && opacities.contains(1))
    }

    @Test func carsFlyAcrossBetweenTheTowers() {
        let frames = run(2_000)
        let big = frames.map { groups($0.sky, Self.carBody).first { $0.opacity == 1 }?.transform.tx }
        let small = frames.map { groups($0.sky, Self.carBody).first { $0.opacity == 0.75 }?.transform.tx }
        // The big one heads right, the small one left, each crossing the whole row.
        func crossings(_ xs: [Double?], from: Double, to: Double) -> Int {
            var count = 0, entered = false
            for x in xs {
                guard let x else { entered = false; continue }
                if !entered, (from - 20 ... from + 1).contains(x) { entered = true }
                if entered, abs(x - to) < 2 { count += 1; entered = false }
            }
            return count
        }
        #expect(crossings(big, from: -16, to: 235) >= 1)
        #expect(crossings(small, from: 236, to: -5) >= 1)
        // Each moves its own pace along.
        let steps = zip(big, big.dropFirst()).compactMap { a, b in a.flatMap { a in b.map { $0 - a } } }
        #expect(steps.allSatisfy { (-0.5 ... 2).contains($0) })
    }

    @Test func signsStutterNowAndThen() {
        let frames = run(2_000)
        for color in [Self.roofSign, Self.sideSign] {
            let shown = frames.map { flat($0) }.compactMap { groups($0, color).first }
            #expect(shown.count == 2_000)
            let dark = shown.indices.filter { shown[$0].opacity == 0.12 }
            #expect(!dark.isEmpty)
            #expect(shown.allSatisfy { $0.opacity == 0.12 || (0.7 ... 1).contains($0.opacity) })
            // A stutter's pattern: off, on, off, off, on, off, then on.
            if let first = dark.first {
                #expect(Array(dark.prefix(4)) == [first, first + 2, first + 3, first + 5])
            }
        }
    }

    @Test func theSkyLayerAndSearchlightsWaitWhileTheSkyRowIsHidden() {
        #expect(run(50, sky: false).allSatisfy { $0.sky.isEmpty && beams($0).isEmpty && !$0.backdrop.isEmpty })
    }

    // MARK: The 20:77 secret

    private func evening(hour: Int = 21, minute: Int = 17) throws -> Date {
        try #require(Calendar.gregorian(in: Samples.timeZone).date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour, minute: minute)))
    }

    private func relicStarts(at minute: Date, asleep: Bool = true, zone: TimeZone = Samples.timeZone) -> [Date] {
        secretStarts(.cyberpunk, around: minute, seed: 3, zone: zone, asleep: asleep)
    }

    /// The secret from its first step, `steps` long; a step that draws nothing is nil.
    private func relic(_ steps: Int = 112, from step: Int = 0, size: CGSize = sceneCard, sky: Bool = true, lang: Lang = .en) -> [SceneFrame] {
        var clock = SceneClock(.cyberpunk, seed: 3)
        _ = clock.step()
        clock.engine.play(.relic, at: step)
        return (0 ..< steps).map { _ in clock.step(size: size, sky: sky, lang: lang) }
    }

    @Test func twentySeventySevenStrikesOnceAnEveningWhileClawdSleeps() throws {
        let starts = relicStarts(at: try evening())
        #expect(starts.count == 1)
        #expect(starts.allSatisfy { Calendar.gregorian(in: Samples.timeZone).dateComponents([.hour, .minute], from: $0) == DateComponents(hour: 21, minute: 17) })
        #expect(relicStarts(at: try evening(), asleep: false).isEmpty)
        #expect(relicStarts(at: try evening(hour: 20)).isEmpty)
        // 21:17 in Berlin is 20:17 in UTC.
        #expect(relicStarts(at: try evening(), zone: .gmt).isEmpty)
    }

    @Test func theNextEveningStrikesAgain() throws {
        var clock = SceneClock(.cyberpunk, seed: 3, from: try evening().addingTimeInterval(-10))
        var starts = 0
        for night in 0 ..< 3 {
            clock.now = try evening().addingTimeInterval(Double(night) * 86_400 - 10)
            var on = false
            for _ in 0 ..< 900 {
                let playing = clock.step(asleep: true).secret != nil
                if playing, !on { starts += 1 }
                on = playing
            }
        }
        #expect(starts == 3)
    }

    @Test func theCardFlushesRedWithBarsTornThickestInTheStorms() {
        let s = relic().map(\.secret)
        let tint = RGBA("#FFFF003C")
        func tintOpacity(_ f: SceneSecretFrame?) -> Double? {
            if case let .rects(r, c, o)? = f?.overlay.first, c == tint, r == [CGRect(origin: .zero, size: sceneCard)] { o } else { nil }
        }
        #expect(tintOpacity(s[0]) == 0 && tintOpacity(s[1]) == 0.12)
        #expect(s[15 ..< 98].allSatisfy { (0.03 ... 0.11).contains(tintOpacity($0) ?? -1) })
        // Every bar in the storms, one in five between them.
        #expect(s[0 ..< 15].allSatisfy { $0?.overlay.count == 7 } && s[98 ..< 109].allSatisfy { $0?.overlay.count == 7 })
        let calm = s[15 ..< 98].map { ($0?.overlay.count ?? 0) - 1 }.reduce(0, +)
        #expect((60 ... 140).contains(calm))
    }

    @Test func theStormShakesTheSkylineAndTheSearchlightsWithIt() {
        let frames = relic()
        #expect(frames[0 ..< 15].allSatisfy { abs(shift($0)) == 3 } && frames[98 ..< 109].allSatisfy { abs(shift($0)) == 3 })
        #expect(frames[15 ..< 98].allSatisfy { shift($0) == 0 })
        // The same step moves both, as upstream's relic steps before the searchlights.
        let x = sceneSkyRow.minX + 96 * 1.6 + 0.8
        #expect(frames[0 ..< 15].allSatisfy { f in beams(f).allSatisfy { abs($0.tip.x - x - shift(f)) < 1e-9 } })
        #expect(shift(frames[109]) == 0)
    }

    @Test func theCardGoesHaywireEveryOtherStepAndCalmsBeforeTheEnd() {
        let s = relic().map { $0.secret?.haywire }
        #expect(s[0]?.strength == 0.6 && s[1] == s[0] && s[2] != s[1])
        #expect(s[20]?.strength == 0.2 && s[21] == s[20])
        #expect(s[100]?.strength == 0.6)
        #expect(s[105] != nil && s[106 ..< 112].allSatisfy { $0 == nil })
    }

    @Test func theErrorBoxTypesTheQuoteUnderTheSkyRow() throws {
        let s = relic().map { $0.secret?.errorBox }
        // Hidden in the storms and on every 17th step.
        let shown = s.indices.filter { s[$0] != nil }
        #expect(shown == Array(15 ..< 98).filter { $0 % 17 != 0 })
        let box = try #require(s[30])
        #expect(box.origin == CGPoint(x: 16, y: (sceneSkyRow.maxY + 8).rounded(.toNearestOrEven)) && box.width == 260 - 32)
        #expect(box.header == "RELIC: MALFUNCTION")
        // 1.4 characters a step from step 18, the cursor blinking while it types.
        #expect(s[20]?.quote == "Wak_" && s[22]?.quote == "Wake u")
        #expect(s[30]?.quote == "Wake up, Samurai." && s[60]?.quote == "Wake up, Samurai. We have a city to vibecode.")
        #expect(s.compactMap { $0?.redShift }.allSatisfy { [-1.5, -3, -4.5, -6].contains($0) })
        #expect(s.compactMap { $0?.cyanShift }.allSatisfy { [1.5, 3, 4.5, 6].contains($0) })
        #expect(s.compactMap { $0?.redShift }.contains { $0 != -1.5 })
    }

    @Test func theErrorBoxSitsHigherWithoutTheSkyRowAndSpeaksTheLanguage() {
        let box = relic(1, from: 30, sky: false, lang: .de)[0].secret?.errorBox
        #expect(box?.origin == CGPoint(x: 16, y: 88) && box?.header == "RELIKT: FEHLFUNKTION")
        #expect(relic(1, from: 30, size: CGSize(width: 100, height: 220))[0].secret?.errorBox?.width == 80)
    }

    @Test func clawdWakesFlickersIntoTheNetrunnerWavesAndGoesBackToSleep() {
        let s = relic().map { $0.secret }
        #expect(s[12]?.cues == [.jack(false), .wake])
        #expect(s[55]?.cues == [.jack(true), .act(.wave)])
        // On for three steps, off for three, from step 20; steady from 48 to the last 15.
        let jacked = s.indices.filter { s[$0]?.cues.contains(.jack(true)) == true }
        #expect(jacked == [20, 24, 25, 26, 30, 31, 32, 36, 37, 38, 42, 43, 44] + Array(48 ..< 95))
        // The last step draws nothing and puts him back to sleep.
        #expect(s[109] == SceneSecretFrame(overlay: [], cues: [.letSleep]))
        #expect(s[110 ..< 112].allSatisfy { $0 == nil })
    }
}
