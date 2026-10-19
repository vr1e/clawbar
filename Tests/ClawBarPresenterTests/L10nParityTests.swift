import Foundation
import Testing
import ClawBarShared

@Suite struct L10nParityTests {
    /// Keys whose German is, correctly, the English: pure formats and a proper name.
    static let sameInBothLanguages: Set<L10nKey> = [.period, .spanD, .statMcp, .setShowMascot]

    @Test func bothTablesHaveExactlyTheKeys() {
        let all = Set(L10nKey.allCases)
        #expect(Set(StringsEN.table.keys) == all)
        #expect(Set(StringsDE.table.keys) == all)
    }

    @Test(arguments: L10nKey.allCases)
    func placeholdersMatch(key: L10nKey) throws {
        let en = try #require(StringsEN.table[key]), de = try #require(StringsDE.table[key])
        #expect(placeholders(en) == placeholders(de), "\(key.rawValue)")
    }

    @Test(arguments: L10nKey.allCases)
    func pluralShapeMatches(key: L10nKey) throws {
        let en = try #require(StringsEN.table[key]), de = try #require(StringsDE.table[key])
        switch (en, de) {
        case (.text, .text): break
        case let (.forms(e), .forms(d)): #expect(e.count == 2 && d.count == 2, "\(key.rawValue)")
        default: Issue.record("\(key.rawValue) is plural in one language only")
        }
    }

    @Test(arguments: L10nKey.allCases)
    func germanIsNotEnglish(key: L10nKey) throws {
        let en = try #require(StringsEN.table[key]), de = try #require(StringsDE.table[key])
        if Self.sameInBothLanguages.contains(key) {
            #expect(en == de, "\(key.rawValue) is allowlisted but differs; drop it from the list")
        } else {
            #expect(en != de, "\(key.rawValue) is still English in German")
        }
    }

    @Test(arguments: Lang.allCases)
    func nothingIsBlank(lang: Lang) {
        for (key, value) in L10n.table(lang) {
            switch value {
            case .text(let s): #expect(!s.trimmingCharacters(in: .whitespaces).isEmpty, "\(lang) \(key.rawValue)")
            case .forms(let f): #expect(f.allSatisfy { !$0.isEmpty }, "\(lang) \(key.rawValue)")
            }
        }
    }

    @Test(arguments: Lang.allCases)
    func rowLabelsAreUpperCase(lang: Lang) {
        for key in [L10nKey.uiWeek, .uiModelWeek, .uiSessions, .uiDay, .uiWeek7] {
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
        case .forms(let f): f.flatMap { placeholders($0) }.sorted()
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
