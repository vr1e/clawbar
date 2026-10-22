import Foundation
import ClawBarShared

/// A reply's tokens by what they cost: plain input, cache writes kept 5 minutes or 1 hour, cache reads, output.
struct TokenCounts: Sendable, Hashable {
    var input = 0
    var write5m = 0
    var write1h = 0
    var cacheRead = 0
    var output = 0

    /// The larger of each count, since a reply's later lines never count fewer.
    func merged(_ other: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: max(input, other.input), write5m: max(write5m, other.write5m), write1h: max(write1h, other.write1h),
            cacheRead: max(cacheRead, other.cacheRead), output: max(output, other.output)
        )
    }

    /// What the model read, which sets Haiku 5.5's long-prompt rate.
    var prompt: Int { input + write5m + write1h + cacheRead }
}

/// List prices as of 2026-10, in dollars per million tokens, to weigh projects against each other.
enum PriceTable {
    struct RateCard: Sendable, Hashable {
        var input: Double
        var output: Double
        var cacheRead: Double
        var write5m: Double
        var write1h: Double
        /// Fast mode's multiple, on the models it is priced for.
        var fast: Double?
        /// A prompt above this many tokens is billed at 5×.
        var longAbove: Int?

        func dollars(_ t: TokenCounts) -> Double {
            let sum = Double(t.input) * input + Double(t.write5m) * write5m + Double(t.write1h) * write1h
                + Double(t.cacheRead) * cacheRead + Double(t.output) * output
            return sum / 1_000_000
        }

        func scaled(_ k: Double) -> RateCard {
            RateCard(input: input * k, output: output * k, cacheRead: cacheRead * k, write5m: write5m * k, write1h: write1h * k)
        }
    }

    /// A model id's family and version: `claude-opus-5-5` is opus 5.5, `claude-haiku-4-5-20251001` haiku 4.5.
    struct Model: Hashable {
        var family: String
        var version: Int

        init?(_ id: String) {
            // A context suffix such as `[1m]` is not part of the version.
            let parts = id.prefix { $0 != "[" }.lowercased().split(separator: "-")
            guard let family = parts.first(where: { $0.allSatisfy(\.isLetter) && $0 != "claude" }) else { return nil }
            // Version parts are short numbers; a date suffix has 8 digits.
            let numbers = parts.filter { $0.count <= 2 && $0.allSatisfy(\.isNumber) }.compactMap { Int($0) }
            guard let major = numbers.first else { return nil }
            self.family = String(family)
            version = major * 100 + (numbers.count > 1 ? numbers[1] : 0)
        }

        init(_ family: String, _ major: Int, _ minor: Int = 0) {
            self.family = family
            version = major * 100 + minor
        }
    }

    static let cards: [Model: RateCard] = {
        let fable51 = RateCard(input: 10, output: 50, cacheRead: 0.25, write5m: 12.5, write1h: 20)
        let fable5 = RateCard(input: 10, output: 50, cacheRead: 1, write5m: 12.5, write1h: 20)
        let opus = RateCard(input: 5, output: 25, cacheRead: 0.5, write5m: 6.25, write1h: 10)
        var opus5 = opus
        opus5.fast = 2
        let sonnet5 = RateCard(input: 2, output: 10, cacheRead: 0.2, write5m: 2.5, write1h: 4)
        return [
            Model("fable", 5, 1): fable51, Model("mythos", 5, 1): fable51,
            Model("fable", 5): fable5, Model("mythos", 5): fable5,
            Model("opus", 5, 5): RateCard(input: 4, output: 20, cacheRead: 0.2, write5m: 5, write1h: 8, fast: 2),
            Model("opus", 5): opus5, Model("opus", 4, 8): opus, Model("opus", 4, 7): opus, Model("opus", 4, 6): opus,
            Model("sonnet", 5, 5): sonnet5, Model("sonnet", 5): sonnet5,
            Model("sonnet", 4, 6): RateCard(input: 3, output: 15, cacheRead: 0.3, write5m: 3.75, write1h: 6),
            Model("haiku", 5, 5): RateCard(input: 0.1, output: 0.5, cacheRead: 0.01, write5m: 0.125, write1h: 0.2, longAbove: 100_000),
            Model("haiku", 4, 5): RateCard(input: 1, output: 5, cacheRead: 0.1, write5m: 1.25, write1h: 2),
        ]
    }()

    /// The default model's card, for a family the table does not know.
    static let fallback = Model("opus", 5, 5)

    /// A reply's list price, and whether the table lists it; one that is not is priced as the nearest listed version of
    /// its family, else as the default model.
    static func price(model id: String, speed: String?, tokens: TokenCounts) -> (dollars: Double, listed: Bool) {
        var listed = true
        var card: RateCard
        if let model = Model(id), let exact = cards[model] {
            card = exact
        } else {
            listed = false
            card = cards[nearest(Model(id)) ?? fallback]!
        }
        if speed == "fast" {
            if let k = card.fast { card = card.scaled(k) } else { listed = false }
        }
        if let above = card.longAbove, tokens.prompt > above { card = card.scaled(5) }
        return (card.dollars(tokens), listed)
    }

    /// The listed version of the same family closest to `model`'s, the newer one on a tie.
    static func nearest(_ model: Model?) -> Model? {
        guard let model else { return nil }
        return cards.keys.filter { $0.family == model.family }
            .min { a, b in
                let da = abs(a.version - model.version), db = abs(b.version - model.version)
                return da != db ? da < db : a.version > b.version
            }
    }
}
