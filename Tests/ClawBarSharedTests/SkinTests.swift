import Testing
import ClawBarShared

/// skins.ps1's `Read-SkinFile` and the built-in set.
@Suite struct SkinTests {
    private func pixels(_ s: Skin?, _ layer: Int = 0) -> [[Int]] {
        (s?.layers[layer].pixels ?? []).map { [$0.x, $0.y] }
    }

    @Test func readsTheFrontMatterAndPlacesTheArtFromTop() throws {
        let s = try #require(Skin.parse("""
        ---
        name: Test hat
        body: #112233
        eyes: #80445566
        top: -3
        r: #DC2626
        w: #F8FAFC
        ---
        ..rr.
        .rwwr
        """, id: "test"))
        #expect(s.id == "test" && s.name == "Test hat")
        #expect(s.body == RGBA("#FF112233") && s.eyes == RGBA("#80445566"))
        #expect(s.layers.map(\.color) == [RGBA("#FFDC2626"), RGBA("#FFF8FAFC")])
        #expect(pixels(s, 0) == [[2, -3], [3, -3], [1, -2], [4, -2]])
        #expect(pixels(s, 1) == [[2, -2], [3, -2]])
    }

    @Test func withoutTopTheArtSitsRightOnHisHead() {
        let s = Skin.parse("---\nk: #000000\n---\nk\nk  \n\n\n", id: "a")
        // Row ends are trimmed and empty rows at the end dropped: two rows, so they start at −2.
        #expect(pixels(s) == [[0, -2], [0, -1]])
    }

    @Test func colourKeysAreSingleLettersWhoseCaseIsIgnored() {
        let s = Skin.parse("---\nr: #111111\nR: #222222\nrr: #333333\nBody: #444444\n---\nrR\n", id: "a")
        #expect(s?.layers == [SkinLayer(color: RGBA("#FF222222"), pixels: [SkinPixel(x: 0, y: -1), SkinPixel(x: 1, y: -1)])])
        // The other keys are case-sensitive, as upstream's switch: `Body` is not the body.
        #expect(s?.body == Skin.classic.body)
    }

    @Test func badValuesKeepTheirDefaults() {
        let s = Skin.parse("---\nname:\nbody: pink\neyes: #12345\ntop: +2\nk: #GG0000\n---\nk\n", id: "mine")
        #expect(s == Skin(id: "mine", name: "mine", body: Skin.classic.body, eyes: Skin.classic.eyes, layers: []))
    }

    @Test func artPastClawdsEighteenColumnsIsCut() {
        let s = Skin.parse("---\nk: #000000\ntop: 0\n---\n.................kkk\n", id: "a")
        #expect(pixels(s) == [[17, 0]])
    }

    @Test func windowsLineEndingsRead() {
        let s = Skin.parse("---\r\nname: Crlf\r\nk: #000000\r\n---\r\nk\r\n", id: "a")
        #expect(s?.name == "Crlf" && pixels(s) == [[0, -1]])
    }

    @Test func aFileWithoutFrontMatterIsNoSkin() {
        #expect(Skin.parse("k: #000000\n..k..\n", id: "a") == nil)
        #expect(Skin.parse("", id: "a") == nil)
    }

    @Test func everyBuiltInParsesWithItsOwnId() {
        #expect(BuiltInSkin.allCases.count == 28)
        #expect(BuiltInSkin.classic.skin == .classic)
        for b in BuiltInSkin.allCases where b != .classic {
            #expect(b.skin.id == b.rawValue)
            #expect(!b.skin.layers.isEmpty, "\(b)")
            #expect(b.skin.name != b.rawValue, "\(b) has no name:")
        }
    }

    @Test func theSantaHatIsUpstreamsArt() {
        let s = BuiltInSkin.santa.skin
        #expect(s.name == "Santa hat" && s.body == Skin.classic.body)
        // `w` comes first in the art: the bobble at the top right.
        #expect(s.layers.map(\.color) == [RGBA("#FFF8FAFC"), RGBA("#FFDC2626")])
        #expect(s.layers[0].pixels.prefix(2) == [SkinPixel(x: 13, y: -7), SkinPixel(x: 14, y: -7)])
        #expect(s.layers.flatMap(\.pixels).map(\.y).min() == -7)
        #expect(s.layers.flatMap(\.pixels).map(\.y).max() == -1)
    }
}
