import Foundation

public enum L10nValue: Sendable, Equatable {
    case text(String)
    /// Plural forms: one, other.
    case forms([String])
}

/// Runtime-switchable strings: the language comes with every call, never from the system locale.
public enum L10n {
    public static func table(_ lang: Lang) -> [L10nKey: L10nValue] {
        switch lang {
        case .en: StringsEN.table
        case .de: StringsDE.table
        }
    }

    /// The value in `lang`, else English.
    public static func value(_ k: L10nKey, _ lang: Lang) -> L10nValue? {
        table(lang)[k] ?? StringsEN.table[k]
    }

    /// The translated text with `{n}` / `{n:00}` placeholders filled; the raw key when no table has it.
    public static func t(_ k: L10nKey, _ lang: Lang, _ args: Any...) -> String {
        switch value(k, lang) {
        case .text(let s): format(s, args)
        case .forms(let f): format(f.last ?? k.rawValue, args)
        case nil: k.rawValue
        }
    }

    /// `"<n> <form>"`, e.g. "1 session", "3 sessions".
    public static func count(_ n: Int, _ k: L10nKey, _ lang: Lang) -> String {
        "\(n) \(form(n, k, lang))"
    }

    public static func form(_ n: Int, _ k: L10nKey, _ lang: Lang) -> String {
        switch value(k, lang) {
        case .forms(let f): pluralForm(n, f)
        case .text(let s): s
        case nil: k.rawValue
        }
    }

    public static func pluralForm(_ n: Int, _ forms: [String]) -> String {
        forms.count == 2 ? (n == 1 ? forms[0] : forms[1]) : forms.last ?? ""
    }

    public static func mood(_ m: Mood, _ lang: Lang) -> String { named("mood.\(m.rawValue)", lang) }
    public static func act(_ a: ClawdAct, _ lang: Lang) -> String { named("act.\(a.rawValue)", lang) }
    public static func phase(_ p: SkyPhase, _ lang: Lang) -> String { named("phase.\(p.rawValue)", lang) }

    /// The moon's name for 0...7, from the new moon round to the waning crescent.
    public static func moonName(_ n: Int, _ lang: Lang) -> String { named("sky.moonNames.\(n)", lang) }

    /// The health tier name for 0...6 halves; values outside are clamped.
    public static func health(_ halves: Int, _ lang: Lang) -> String {
        named("health.\(min(6, max(0, halves)))", lang)
    }

    /// A Statuspage component state; unknown states show raw, as in the original.
    public static func component(_ state: String, _ lang: Lang) -> String {
        guard let k = L10nKey(rawValue: "comp.\(state)") else { return state }
        return t(k, lang)
    }

    private static func named(_ raw: String, _ lang: Lang) -> String {
        guard let k = L10nKey(rawValue: raw) else { return raw }
        return t(k, lang)
    }

    /// The .NET composite format subset the strings use: `{0}`, and `{1:00}` for zero padding.
    public static func format(_ template: String, _ args: [Any]) -> String {
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

    private static func render(_ arg: Any, pad: Int) -> String {
        let s: String
        switch arg {
        case let v as Int: s = String(v)
        case let v as Int32: s = String(v)
        case let v as Int64: s = String(v)
        case let v as UInt8: s = String(v)
        case let v as Double:
            if pad > 0 || (v.rounded() == v && abs(v) < 1e15) {
                s = String(Int(v.rounded(.toNearestOrEven)))
            } else {
                s = String(v)
            }
        case let v as String: s = v
        default: s = String(describing: arg)
        }
        guard pad > s.count, let first = s.first, first != "-" else { return s }
        return String(repeating: "0", count: pad - s.count) + s
    }
}
