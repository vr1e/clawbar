import Foundation
import Testing
import ClawBarShared

@Suite struct L10nTests {
    @Test func placeholdersTakeTheirArguments() {
        #expect(L10n.format("{0}h {1:00}m", [4, 5]) == "4h 05m")
        #expect(L10n.format("{1} before {0}", ["b", "a"]) == "a before b")
        #expect(L10n.format("{0:000}", [7]) == "007")
    }

    @Test func aMissingArgumentLeavesThePlaceholderVisible() {
        #expect(L10n.format("resets in {0}", []) == "resets in {0}")
    }

    @Test func wholeDoublesPrintWithoutAFraction() {
        #expect(L10n.format("{0}°", [12.0]) == "12°")
        #expect(L10n.format("{0}", [2.5]) == "2.5")
    }

    @Test func bracesThatAreNotPlaceholdersStay() {
        #expect(L10n.format("{x} {0", [1]) == "{x} {0")
    }

    @Test func translatesWithArguments() {
        #expect(L10n.t(.resetIn, .en, "4h 05m") == "resets in 4h 05m")
        #expect(L10n.t(.spanH, .en, 4, 5) == "4h 05m")
    }

    @Test func countsPickTheEnglishForm() {
        #expect(L10n.count(1, .pluralSession, .en) == "1 session")
        #expect(L10n.count(2, .pluralSession, .en) == "2 sessions")
        #expect(L10n.count(0, .pluralRequest, .en) == "0 requests")
        #expect(L10n.count(1, .pluralReply, .en) == "1 reply")
    }

    @Test func namesComeFromTheirKeys() {
        #expect(L10n.mood(.wait, .en) == "waiting for you")
        #expect(L10n.act(.coinHop, .en) == "coin hop")
        #expect(L10n.health(5, .en) == "fine")
        #expect(L10n.phase(.dusk, .en) == "dusk")
    }

    @Test func outOfRangeHealthIsClampedToTheTiers() {
        #expect(L10n.health(9, .en) == "full of energy")
        #expect(L10n.health(-1, .en) == "out of strength")
    }

    // The names come from key lists, where a key listed twice would hide another.
    @Test(arguments: Lang.allCases)
    func everyMoonPhaseWeekdayAndHealthTierHasItsOwnName(lang: Lang) {
        #expect(Set((0 ... 7).map { L10n.moonName($0, lang) }).count == 8)
        #expect(Set((0 ... 6).map { L10n.weekday($0, lang) }).count == 7)
        #expect(Set((0 ... 6).map { L10n.health($0, lang) }).count == 7)
    }

    @Test func unknownComponentStatesShowRaw() {
        #expect(L10n.component("partial_outage", .en) == "partial outage")
        #expect(L10n.component("brand_new_state", .en) == "brand_new_state")
    }
}
