import Testing
@testable import ClawBarPresenter
import ClawBarShared

/// cyberpunk.ps1's Set-RelicHaywire on the view state: digits jump, captions crumble, bars twitch, the rest stays.
@Suite struct HaywireTests {
    static let sample = WidgetViewState.sample

    private func scrambled(_ v: WidgetViewState = sample, strength p: Double, seed: UInt64 = 1) -> WidgetViewState {
        Haywire.scramble(v, strength: p, random: SeededRandomSource(seed: seed))
    }

    @Test func numbersJumpWhileTheRestHoldsWithoutStrength() {
        let v = scrambled(strength: 0)
        for (a, b) in [(Self.sample.pctText, v.pctText), (Self.sample.resetText, v.resetText), (Self.sample.stampText, v.stampText)] {
            #expect(a.count == b.count)
            #expect(zip(a, b).allSatisfy { $0.isNumber ? $1.isNumber : $0 == $1 })
        }
        #expect(v.stampText != Self.sample.stampText)
    }

    @Test func atFullStrengthEveryCharacterButASpaceIsJunk() {
        let a = Self.sample.statusText, b = scrambled(strength: 1).statusText
        #expect(a.count == b.count)
        #expect(zip(a, b).allSatisfy { $0.isWhitespace ? $0 == $1 : Haywire.junk.contains($1) || $1.isNumber })
    }

    @Test func theLegendTheMenuBarItemAndTheTooltipsStay() {
        var v = Self.sample
        v.history = HistoryView(label: "LIMITS", sessionName: "session", weekName: "week", days: [ChartDay(text: "Mo", from: 0, to: 30)])
        let s = scrambled(v, strength: 1)
        #expect(s.history?.sessionName == "session" && s.history?.weekName == "week")
        #expect(s.history?.label != "LIMITS" && s.history?.days.first?.text != "Mo")
        #expect(s.trayText == v.trayText && s.trayTooltip == v.trayTooltip && s.gameCaption == v.gameCaption && s.parts == v.parts)
    }

    @Test func theBarsJump() {
        let s = scrambled(strength: 0)
        let fractions = [s.mainFraction, s.otherLimit.fraction] + s.modelWeeks.map(\.fraction)
        let before = [Self.sample.mainFraction, Self.sample.otherLimit.fraction] + Self.sample.modelWeeks.map(\.fraction)
        #expect(fractions.allSatisfy { (0 ..< 1).contains($0) } && fractions != before)
    }

    @Test func theSameSeedGivesTheSameScramble() {
        #expect(scrambled(strength: 0.6, seed: 9) == scrambled(strength: 0.6, seed: 9))
        #expect(scrambled(strength: 0.6, seed: 9) != scrambled(strength: 0.6, seed: 10))
    }
}
