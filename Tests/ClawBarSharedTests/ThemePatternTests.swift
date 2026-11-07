import Foundation
import Testing
import ClawBarShared

/// theme.ps1's `Get-PatternBrush`: sprite pixels at x + column × px, y + row × px, one layer per colour.
@Suite struct ThemePatternTests {
    @Test func spritePixelsLandAtTheirOffsetTimesTheirSize() {
        let p = ThemePattern(tile: 20, px: 2, opacity: 0.5, colors: ["r": "#FFFF0000", "b": "#FF0000FF"],
                             sprites: [(3, 4, [".rr", "b.r"]), (10, 10, ["r"])])
        // Letters in order, so b before r; a run of one colour is one rect; each layer carries the opacity.
        #expect(p.layers == [
            .rects([CGRect(x: 3, y: 6, width: 2, height: 2)], RGBA("#FF0000FF"), opacity: 0.5),
            .rects([
                CGRect(x: 5, y: 4, width: 4, height: 2), CGRect(x: 7, y: 6, width: 2, height: 2),
                CGRect(x: 10, y: 10, width: 2, height: 2),
            ], RGBA("#FFFF0000"), opacity: 0.5),
        ])
    }

    @Test func aLetterWithoutAColourStaysEmpty() {
        let p = ThemePattern(tile: 8, px: 1, opacity: 1, colors: ["c": "#FF00E5FF"], sprites: [(0, 0, ["cxc"])])
        #expect(p.layers == [.rects([CGRect(x: 0, y: 0, width: 1, height: 1), CGRect(x: 2, y: 0, width: 1, height: 1)],
                                    RGBA("#FF00E5FF"), opacity: 1)])
    }

    @Test func theBuiltInPatternsStayInsideTheirTiles() {
        // Christmas's snowflake: 21 white pixels at 2 px from (6, 8); its first row is one pixel at column 3.
        let white = ThemePattern.christmas.layers.compactMap { op -> [CGRect]? in
            if case let .rects(rects, color, _) = op, color == RGBA("#FFF8FAFC") { rects } else { nil }
        }.first
        #expect(white?.first == CGRect(x: 12, y: 8, width: 2, height: 2))
        // Tiles never overlap, so the pattern repeats cleanly.
        for p in Theme.allCases.compactMap(\.pattern) {
            #expect(p.layers.allSatisfy { op in
                guard case let .rects(rects, _, _) = op else { return false }
                return rects.allSatisfy { $0.maxX <= p.tile && $0.maxY <= p.tile }
            })
        }
    }
}
