import Foundation
import Testing
import ClawBarShared

@Suite struct L10nCoverageTests {
    @Test(arguments: Lang.allCases)
    func everyKeyHasAValue(lang: Lang) {
        let missing = L10nKey.allCases.filter { L10n.table(lang)[$0] == nil }
        #expect(missing.isEmpty, "\(lang) is missing \(missing.map(\.rawValue))")
    }

    @Test func placeholdersMatchAcrossLanguages() {
        for key in L10nKey.allCases {
            guard case .text(let en)? = StringsEN.table[key], case .text(let de)? = StringsDE.table[key] else { continue }
            #expect(placeholders(en) == placeholders(de), "\(key.rawValue): \(en) vs \(de)")
        }
    }

    @Test func pluralKeysArePluralEverywhere() {
        for key in L10nKey.allCases {
            let shapes = Lang.allCases.map { lang -> Bool in
                if case .forms? = L10n.table(lang)[key] { return true }
                return false
            }
            #expect(Set(shapes).count == 1, "\(key.rawValue) is plural in one language only")
        }
        #expect(L10nKey.allCases.filter { key in
            if case .forms? = StringsEN.table[key] { return true }
            return false
        } == [.pluralSession, .pluralRequest, .pluralReply])
    }

    @Test(arguments: Lang.allCases)
    func everyNamedThingResolvesToText(lang: Lang) {
        for m in Mood.allCases { #expect(!L10n.mood(m, lang).hasPrefix("mood.")) }
        for a in ClawdAct.allCases { #expect(!L10n.act(a, lang).hasPrefix("act.")) }
        for p in SkyPhase.allCases { #expect(!L10n.phase(p, lang).hasPrefix("phase.")) }
        for h in 0 ... 6 { #expect(!L10n.health(h, lang).hasPrefix("health.")) }
        for n in 0 ... 7 { #expect(!L10n.moonName(n, lang).hasPrefix("sky.")) }
        for code in [0, 1, 2, 3, 45, 48, 51, 56, 61, 66, 71, 77, 80, 85, 95] {
            #expect(!WeatherKinds.name(code: code, lang: lang).hasPrefix("wx."))
        }
    }

    private func placeholders(_ s: String) -> [String] {
        var out: [String] = []
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out.append(String(rest[open ... close]))
            rest = rest[rest.index(after: close)...]
        }
        return out.sorted()
    }
}
