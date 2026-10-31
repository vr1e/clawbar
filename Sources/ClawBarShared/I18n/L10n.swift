import Foundation

/// One key's English and German; built only through `text` and `plural`, so a key is plural in both or in neither.
public struct L10nStrings: Sendable, Equatable {
    public let en: L10nValue
    public let de: L10nValue

    private init(en: L10nValue, de: L10nValue) {
        self.en = en
        self.de = de
    }

    static func text(en: String, de: String) -> L10nStrings { L10nStrings(en: .text(en), de: .text(de)) }

    static func plural(en: (one: String, other: String), de: (one: String, other: String)) -> L10nStrings {
        L10nStrings(en: .forms(one: en.one, other: en.other), de: .forms(one: de.one, other: de.other))
    }
}

public enum L10nValue: Sendable, Equatable {
    case text(String)
    case forms(one: String, other: String)
}

/// What a `{n}` placeholder can show; an optional is no argument, so it never renders as "Optional(…)".
public protocol L10nArg {
    /// The text before zero padding; `pad` is the `{n:00}` width.
    func l10nText(pad: Int) -> String
}

extension Int: L10nArg {
    public func l10nText(pad: Int) -> String { String(self) }
}

extension Double: L10nArg {
    // A padded or whole value shows without a fraction, as .NET's `{0:00}` and `{0}` do.
    public func l10nText(pad: Int) -> String {
        pad > 0 || (rounded() == self && abs(self) < 1e15) ? String(Int(rounded(.toNearestOrEven))) : String(self)
    }
}

extension String: L10nArg {
    public func l10nText(pad: Int) -> String { self }
}

/// Runtime-switchable strings: the language comes with every call, never from the system locale.
public enum L10n {
    public static func value(_ k: L10nKey, _ lang: Lang) -> L10nValue {
        switch lang {
        case .en: k.strings.en
        case .de: k.strings.de
        }
    }

    /// The translated text with `{n}` / `{n:00}` placeholders filled.
    public static func t(_ k: L10nKey, _ lang: Lang, _ args: any L10nArg...) -> String {
        switch value(k, lang) {
        case .text(let s): format(s, args)
        case .forms(_, let other): format(other, args)
        }
    }

    /// `"<n> <form>"`, e.g. "1 session", "3 sessions".
    public static func count(_ n: Int, _ k: L10nKey, _ lang: Lang) -> String {
        "\(n) \(form(n, k, lang))"
    }

    public static func form(_ n: Int, _ k: L10nKey, _ lang: Lang) -> String {
        switch value(k, lang) {
        case .forms(let one, let other): n == 1 ? one : other
        case .text(let s): s
        }
    }

    public static func mood(_ m: Mood, _ lang: Lang) -> String {
        let k: L10nKey = switch m {
        case .sleep: .moodSleep
        case .doze: .moodDoze
        case .idle: .moodIdle
        case .work: .moodWork
        case .wait: .moodWait
        case .dead: .moodDead
        }
        return t(k, lang)
    }

    public static func act(_ a: ClawdAct, _ lang: Lang) -> String {
        let k: L10nKey = switch a {
        case .jump: .actJump
        case .look: .actLook
        case .celebrate: .actCelebrate
        case .skip: .actSkip
        case .spin: .actSpin
        case .peekaboo: .actPeekaboo
        case .drop: .actDrop
        case .waddle: .actWaddle
        case .peek: .actPeek
        case .wink: .actWink
        case .boop: .actBoop
        case .tap: .actTap
        case .sneeze: .actSneeze
        case .turn: .actTurn
        case .coinHop: .actCoinHop
        case .wave: .actWave
        case .stretch: .actStretch
        case .yawn: .actYawn
        case .stumble: .actStumble
        case .soul: .actSoul
        case .burrow: .actBurrow
        case .unburrow: .actUnburrow
        case .stir: .actStir
        }
        return t(k, lang)
    }

    public static func phase(_ p: SkyPhase, _ lang: Lang) -> String {
        let k: L10nKey = switch p {
        case .dawn: .phaseDawn
        case .day: .phaseDay
        case .dusk: .phaseDusk
        case .night: .phaseNight
        }
        return t(k, lang)
    }

    /// The moon's name for 0...7, from the new moon round to the waning crescent.
    public static func moonName(_ n: Int, _ lang: Lang) -> String { t(nearest(moonNames, n), lang) }

    /// The short weekday name for 0...6, from Sunday.
    public static func weekday(_ n: Int, _ lang: Lang) -> String { t(nearest(weekdays, n), lang) }

    /// The health tier name for 0...6 halves; values outside are clamped.
    public static func health(_ halves: Int, _ lang: Lang) -> String { t(nearest(healthTiers, halves), lang) }

    private static let moonNames: [L10nKey] = [
        .skyMoonName0, .skyMoonName1, .skyMoonName2, .skyMoonName3,
        .skyMoonName4, .skyMoonName5, .skyMoonName6, .skyMoonName7,
    ]
    private static let weekdays: [L10nKey] = [.wd0, .wd1, .wd2, .wd3, .wd4, .wd5, .wd6]
    private static let healthTiers: [L10nKey] = [.health0, .health1, .health2, .health3, .health4, .health5, .health6]

    /// An index past either end takes the nearest name rather than trapping.
    private static func nearest(_ keys: [L10nKey], _ i: Int) -> L10nKey { keys[min(keys.count - 1, max(0, i))] }

    /// A Statuspage component state; unknown states show raw, as in the original.
    public static func component(_ state: String, _ lang: Lang) -> String {
        guard let k = L10nKey(rawValue: "comp.\(state)") else { return state }
        return t(k, lang)
    }

    /// The .NET composite format subset the strings use: `{0}`, and `{1:00}` for zero padding.
    public static func format(_ template: String, _ args: [any L10nArg]) -> String {
        guard template.contains("{") else { return template }
        var out = ""
        var i = template.startIndex
        while i < template.endIndex {
            let c = template[i]
            guard c == "{", let close = template[i...].firstIndex(of: "}") else {
                out.append(c)
                i = template.index(after: i)
                continue
            }
            let inner = template[template.index(after: i) ..< close]
            let parts = inner.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let spec = parts.count == 2 ? String(parts[1]) : ""
            guard let n = Int(parts[0]), n >= 0, spec.allSatisfy({ $0 == "0" }) else {
                out.append(c)
                i = template.index(after: i)
                continue
            }
            if n < args.count {
                out += render(args[n], pad: spec.count)
            } else {
                out += template[i ... close]
            }
            i = template.index(after: close)
        }
        return out
    }

    private static func render(_ arg: any L10nArg, pad: Int) -> String {
        let s = arg.l10nText(pad: pad)
        guard pad > s.count, let first = s.first, first != "-" else { return s }
        return String(repeating: "0", count: pad - s.count) + s
    }
}
