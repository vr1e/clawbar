import CoreGraphics
import Foundation
import Testing
import ClawBarCard
import ClawBarPresenter
import ClawBarShared

private let t0 = Samples.now
private let laidOut = CardMeasure(
    numberWidth: 32, cardSize: CGSize(width: 524, height: 444), percentRow: CGRect(x: 26, y: 62, width: 472, height: 80), scale: 2
)

private func input(_ edit: (inout Config, inout DataSnapshot) -> Void = { _, _ in }) -> PresenterInput {
    var config = Config(), data = DataSnapshot.sample
    edit(&config, &data)
    return PresenterInput(config: config, now: t0, timeZone: Samples.timeZone, data: data, homeDirectory: Samples.home)
}

private func engine(_ input: PresenterInput, seed: UInt64 = 7) -> CardEngine {
    let engine = CardEngine(random: SeededRandomSource(seed: seed), config: input.config, skins: .builtIn, now: t0)
    engine.present(input, skins: .builtIn)
    return engine
}

/// The virtual clock, as snapshot mode runs it: each tick a cadence after the last.
@discardableResult
private func run(_ engine: CardEngine, ticks: Int, measure: CardMeasure = laidOut) -> Date {
    var now = t0
    for _ in 0 ..< ticks {
        engine.step(now: now, timeZone: Samples.timeZone, measure: measure)
        guard let ms = engine.tickMilliseconds else { break }
        now = now.addingTimeInterval(Double(ms) / 1000)
    }
    return now
}

private let withChart = input {
    $0.expanded = true
    $0.showHistory = true
    $1.history = Samples.history
    $1.projects = Samples.projects
}

@Suite struct CardEngineTests {
    @Test func theCardShowsThePresentersViewState() {
        let input = input()
        let card = engine(input)
        #expect(card.presented == WidgetPresenter.make(input))
        #expect(card.shown == card.presented)
        #expect(card.mascotVisible && card.skyVisible && card.tickMilliseconds != nil)
        run(card, ticks: 20)
        #expect(card.shown == card.presented)
        #expect(!card.frame.clawd.spriteRect.isEmpty)
    }

    @Test func nothingMovesWithClawdHiddenAndNoScene() {
        let card = engine(input { c, _ in c.showMascot = false })
        #expect(!card.mascotVisible && !card.skyVisible && card.tickMilliseconds == nil)
    }

    @Test func theHaywireScramblesWhatTheCardDrawsAndNothingElse() throws {
        let input = input { c, _ in c.theme = .fixed(.cyberpunk) }
        let card = engine(input)
        // The picture of `scene-cyberpunk-relic`: played from its start so step 60 is the last tick.
        for i in 0 ..< 61 {
            if i == 0 { card.play(.relic) }
            card.step(now: t0.addingTimeInterval(Double(i) * 0.09), timeZone: Samples.timeZone, measure: laidOut)
        }
        let haywire = try #require(card.frame.scene?.secret?.haywire)
        #expect(card.presented == WidgetPresenter.make(input))
        #expect(card.shown == Haywire.scramble(card.presented, haywire))
        #expect(card.shown != card.presented)
        #expect(card.shown.trayText == card.presented.trayText && card.shown.parts == card.presented.parts)

        // New data under a running haywire is scrambled too.
        var fresh = input
        fresh.data.usage?.sessionPercent = 77
        card.present(fresh, skins: .builtIn)
        #expect(card.presented.pctText == WidgetPresenter.make(fresh).pctText)
        #expect(card.shown == Haywire.scramble(card.presented, card.frame.scene?.secret?.haywire))

        // Hiding the widget ends the secret at once.
        card.hide()
        #expect(card.frame.scene?.secret == nil)
        #expect(card.shown == card.presented)
    }

    @Test func leavingTheThemeEndsTheHaywire() {
        let card = engine(input { c, _ in c.theme = .fixed(.cyberpunk) })
        card.play(.relic, at: 60)
        run(card, ticks: 1)
        #expect(card.shown != card.presented)
        card.present(input(), skins: .builtIn)
        #expect(card.shown == card.presented)
    }

    @Test func theReadoutFollowsThePointerOverThePresentedChart() throws {
        let card = engine(withChart)
        #expect(card.historyHover == nil)
        card.hover(chartX: 171)
        let chart = try #require(card.presented.history)
        #expect(card.historyHover == HistoryReadout.hover(x: 171, chart: chart, input: withChart))
        card.hover(chartX: nil)
        #expect(card.historyHover == nil)
    }

    @Test func theReadoutGoesWithTheChartAndComesBackWithIt() {
        let card = engine(withChart)
        card.hover(chartX: 171)
        var closed = withChart
        closed.config.showHistory = false
        card.present(closed, skins: .builtIn)
        #expect(card.presented.history == nil && card.historyHover == nil)
        card.present(withChart, skins: .builtIn)
        #expect(card.historyHover != nil)
    }

    @Test func theSameSeedAndClockGiveTheSameCard() {
        let a = engine(input()), b = engine(input()), c = engine(input(), seed: 8)
        run(a, ticks: 40)
        run(b, ticks: 40)
        run(c, ticks: 40)
        #expect(a.frame == b.frame)
        #expect(a.frame != c.frame)
    }

    @Test func aSceneCoversTheCardAsMeasured() throws {
        let card = engine(input { c, _ in c.theme = .fixed(.christmas) })
        run(card, ticks: 3)
        let laid = try #require(card.frame.scene)
        let bare = engine(input { c, _ in c.theme = .fixed(.christmas) })
        run(bare, ticks: 3, measure: CardMeasure(numberWidth: 32))
        // Before the first layout the scene has no card to cover.
        #expect(bare.frame.scene != laid)
    }
}

@Suite struct CardMeasureTests {
    @Test func theBackdropIsTheCardInsideItsRimInBaseUnits() {
        #expect(laidOut.backdropSize == CGSize(width: 260, height: 220))
        #expect(laidOut.skyOrigin == CGPoint(x: 12, y: 30))
    }

    @Test func nothingIsMeasuredBeforeTheFirstLayout() {
        let m = CardMeasure(numberWidth: 0)
        #expect(m.backdropSize == .zero && m.skyOrigin == .zero)
    }

    @Test func thePointerIsReadFromThePlayAreasLeftEnd() {
        // The row at 26, then the number's 32 and the 10 of margin, all at scale 2.
        #expect(laidOut.mouseX(cardX: 26 + 2 * 42 + 20) == 10)
        // Before the first layout the row sits at the content's inset.
        #expect(CardMeasure(numberWidth: 32, scale: 2).mouseX(cardX: 26 + 2 * 42 + 20) == 10)
    }
}
