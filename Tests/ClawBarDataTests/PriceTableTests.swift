import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

// Expected values are the list prices the table cites (2026-10), in dollars per million tokens.
@Suite struct PriceTableTests {
    func price(_ model: String, speed: String? = nil, _ tokens: TokenCounts) -> (dollars: Double, listed: Bool) {
        PriceTable.price(model: model, speed: speed, tokens: tokens)
    }

    /// Dollars per million of each kind: input, 5-minute writes, 1-hour writes, cache reads, output. Priced on 100K,
    /// which stays under Haiku 5.5's long-prompt rate.
    func card(_ model: String, speed: String? = nil) -> [Double] {
        [
            TokenCounts(input: 100_000), TokenCounts(write5m: 100_000), TokenCounts(write1h: 100_000),
            TokenCounts(cacheRead: 100_000), TokenCounts(output: 100_000),
        ].map { price(model, speed: speed, $0).dollars * 10 }
    }

    func same(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 } }

    @Test func everyListedModelHasItsCard() {
        let expected: [(String, [Double])] = [
            ("claude-fable-5-1", [10, 12.5, 20, 0.25, 50]), ("claude-mythos-5-1", [10, 12.5, 20, 0.25, 50]),
            ("claude-fable-5", [10, 12.5, 20, 1, 50]), ("claude-mythos-5", [10, 12.5, 20, 1, 50]),
            ("claude-opus-5-5", [4, 5, 8, 0.2, 20]), ("claude-opus-5", [5, 6.25, 10, 0.5, 25]),
            ("claude-opus-4-8", [5, 6.25, 10, 0.5, 25]), ("claude-opus-4-7", [5, 6.25, 10, 0.5, 25]),
            ("claude-opus-4-6", [5, 6.25, 10, 0.5, 25]), ("claude-sonnet-5-5", [2, 2.5, 4, 0.2, 10]),
            ("claude-sonnet-5", [2, 2.5, 4, 0.2, 10]), ("claude-sonnet-4-6", [3, 3.75, 6, 0.3, 15]),
            ("claude-haiku-5-5", [0.1, 0.125, 0.2, 0.01, 0.5]), ("claude-haiku-4-5-20251001", [1, 1.25, 2, 0.1, 5]),
            ("claude-opus-5-5[1m]", [4, 5, 8, 0.2, 20]),
        ]
        for (model, rates) in expected {
            let got = card(model)
            #expect(same(got, rates), "\(model): \(got)")
            #expect(price(model, TokenCounts(input: 1)).listed, "\(model)")
        }
    }

    @Test func aLongHaikuPromptCostsFiveTimesAsMuch() {
        let short = TokenCounts(input: 40_000, write5m: 30_000, cacheRead: 30_000, output: 1_000)
        var long = short
        long.input += 1
        #expect(abs(price("claude-haiku-5-5", short).dollars - 0.00855) < 1e-12)
        #expect(abs(price("claude-haiku-5-5", long).dollars - 5 * 0.0085501) < 1e-12)
        // Only Haiku 5.5 has the long-prompt rate.
        #expect(abs(price("claude-haiku-4-5", long).dollars - 0.085501) < 1e-12)
    }

    @Test func fastModeDoublesOpus55AndOpus5AndLeavesOthersUnpriced() {
        #expect(same(card("claude-opus-5-5", speed: "fast"), [8, 10, 16, 0.4, 40]))
        #expect(same(card("claude-opus-5", speed: "fast"), [10, 12.5, 20, 1, 50]))
        #expect(price("claude-opus-5-5", speed: "fast", TokenCounts(input: 1)).listed)
        // Opus 4.8's fast price is not published: its own card, marked unpriced.
        let fast48 = price("claude-opus-4-8", speed: "fast", TokenCounts(input: 1_000_000))
        #expect(fast48.dollars == 5 && !fast48.listed)
        #expect(card("claude-opus-5-5", speed: "standard") == card("claude-opus-5-5"))
    }

    @Test func anUnlistedModelTakesTheNearestCardOfItsFamilyAndIsMarked() {
        // A newer Opus than any listed: the newest Opus.
        #expect(card("claude-opus-6") == card("claude-opus-5-5"))
        // An older Sonnet: the closest version, not the newest.
        #expect(card("claude-sonnet-4-5-20250929") == card("claude-sonnet-4-6"))
        #expect(card("claude-3-5-sonnet-20241022") == card("claude-sonnet-4-6"))
        // Between two listed versions, the closer one.
        #expect(card("claude-opus-5-2") == card("claude-opus-5"))
        // A family the table does not know: the default model's card.
        #expect(card("claude-quill-1") == card("claude-opus-5-5"))
        #expect(card("gpt-x") == card("claude-opus-5-5"))
        for model in ["claude-opus-6", "claude-sonnet-4-5", "claude-quill-1", "gpt-x"] {
            #expect(!price(model, TokenCounts(input: 1)).listed, "\(model)")
        }
    }

    @Test func modelIdsReadAsFamilyAndVersion() {
        #expect(PriceTable.Model("claude-opus-5-5") == PriceTable.Model("opus", 5, 5))
        #expect(PriceTable.Model("claude-haiku-4-5-20251001") == PriceTable.Model("haiku", 4, 5))
        #expect(PriceTable.Model("claude-fable-5") == PriceTable.Model("fable", 5))
        #expect(PriceTable.Model("<synthetic>") == nil)
        #expect(PriceTable.Model("claude-opus") == nil)
    }
}
