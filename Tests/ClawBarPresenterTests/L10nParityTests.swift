import Foundation
import Testing
import ClawBarShared

@Suite struct L10nParityTests {
    /// Keys whose German is, correctly, the English: pure formats, a unit symbol and a proper name.
    static let sameInBothLanguages: Set<L10nKey> = [.period, .spanD, .statMcp, .histSession, .setShowMascot, .gameTitle]

    @Test(arguments: L10nKey.allCases)
    func placeholdersMatch(key: L10nKey) {
        #expect(placeholders(key.strings.en) == placeholders(key.strings.de), "\(key.rawValue)")
    }

    @Test(arguments: L10nKey.allCases)
    func germanIsNotEnglish(key: L10nKey) {
        let s = key.strings
        if Self.sameInBothLanguages.contains(key) {
            #expect(s.en == s.de, "\(key.rawValue) is allowlisted but differs; drop it from the list")
        } else {
            #expect(s.en != s.de, "\(key.rawValue) is still English in German")
        }
    }

    @Test(arguments: Lang.allCases)
    func nothingIsBlank(lang: Lang) {
        for key in L10nKey.allCases {
            switch L10n.value(key, lang) {
            case .text(let s): #expect(!s.trimmingCharacters(in: .whitespaces).isEmpty, "\(lang) \(key.rawValue)")
            case let .forms(one, other): #expect(!one.isEmpty && !other.isEmpty, "\(lang) \(key.rawValue)")
            }
        }
    }

    @Test(arguments: Lang.allCases)
    func rowLabelsAreUpperCase(lang: Lang) {
        for key in [L10nKey.uiWeek, .uiModelWeek, .uiSessions, .uiDay, .uiWeek7, .uiHist] {
            let s = L10n.t(key, lang)
            #expect(s == s.uppercased(), "\(lang) \(key.rawValue): \(s)")
        }
    }

    @Test func germanCountsPickTheirForms() {
        #expect(L10n.count(1, .pluralSession, .de) == "1 Sitzung")
        #expect(L10n.count(2, .pluralSession, .de) == "2 Sitzungen")
        #expect(L10n.count(1, .pluralRequest, .de) == "1 Anfrage")
        #expect(L10n.count(0, .pluralRequest, .de) == "0 Anfragen")
    }

    private func placeholders(_ v: L10nValue) -> [String] {
        switch v {
        case .text(let s): placeholders(s)
        case let .forms(one, other): (placeholders(one) + placeholders(other)).sorted()
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
