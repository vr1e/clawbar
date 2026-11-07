import Testing
import ClawBarShared

/// skins.ps1's `Get-Skins` and how Set-Skin finds the config's skin among them.
@Suite struct SkinCatalogTests {
    private func skin(_ id: String, _ name: String? = nil) -> Skin {
        Skin(id: id, name: name ?? id, body: Palette.clawdBody, eyes: Palette.clawdEyes, layers: [])
    }

    @Test func theBuiltInOnesComeFirstThenYoursInFileOrder() {
        let catalog = SkinCatalog(own: [skin("mine"), skin("another")])
        #expect(catalog.skins.map(\.id) == BuiltInSkin.allCases.map(\.rawValue) + ["mine", "another"])
        #expect(SkinCatalog.builtIn.skins == BuiltInSkin.allCases.map(\.skin))
    }

    @Test func yourFileUnderABuiltInIdTakesItsPlace() {
        let catalog = SkinCatalog(own: [skin("santa", "Mine"), skin("classic", "Plain")])
        #expect(catalog.skins.map(\.id) == BuiltInSkin.allCases.map(\.rawValue))
        #expect(catalog.skin(for: "santa").name == "Mine")
        #expect(catalog.skin(for: "classic").name == "Plain")
        // An unknown name is the original Classic, as Set-Skin's $SkinDefault, not the user's classic.txt.
        #expect(catalog.skin(for: "nothing") == .classic)
    }

    @Test func theConfigNamesASkinInAnyCase() {
        let catalog = SkinCatalog(own: [skin("mine")])
        #expect(catalog.skin(for: " Santa ") == BuiltInSkin.santa.skin)
        #expect(catalog.skin(for: "TOPHAT") == BuiltInSkin.tophat.skin)
        #expect(catalog.skin(for: "Mine").id == "mine")
        #expect(SkinCatalog.builtIn.skin(for: "mine") == .classic)
        #expect(catalog.skin(for: nil) == .classic)
    }

    @Test func onlyAnUntouchedBuiltInSkinCountsAsBuiltIn() {
        let catalog = SkinCatalog(own: [skin("santa", "Mine"), skin("mine")])
        #expect(catalog.untouchedBuiltIn(BuiltInSkin.tophat.skin) == .tophat)
        #expect(catalog.untouchedBuiltIn(.classic) == .classic)
        // Even a file identical to the built-in one is the user's, named by its own `name:`.
        #expect(catalog.untouchedBuiltIn(skin("santa", "Mine")) == nil)
        #expect(SkinCatalog(own: [BuiltInSkin.santa.skin]).untouchedBuiltIn(BuiltInSkin.santa.skin) == nil)
        #expect(catalog.untouchedBuiltIn(skin("mine")) == nil)
    }
}
