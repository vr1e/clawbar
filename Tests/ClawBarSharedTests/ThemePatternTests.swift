import Foundation
import Testing
import ClawBarShared

/// theme.ps1's `Get-PatternBrush`: sprite pixels at x + column × px, y + row × px, one fill per colour.
@Suite struct ThemePatternTests {
    @Test func spritePixelsLandAtTheirOffsetTimesTheirSize() {
        let p = ThemePattern(tile: 20, px: 2, opacity: 0.5, colors: ["r": "#FFFF0000", "b": "#FF0000FF"],
                             sprites: [(3, 4, [".rr", "b.r"]), (10, 10, ["r"])])
        #expect(p.tile == 20 && p.opacity == 0.5)
        // Letters in order, so b before r; a run of one colour is one rect.
        #expect(p.fills.map(\.color) == [RGBA("#FF0000FF"), RGBA("#FFFF0000")])
        #expect(p.fills[0].rects == [CGRect(x: 3, y: 6, width: 2, height: 2)])
        #expect(p.fills[1].rects == [
            CGRect(x: 5, y: 4, width: 4, height: 2), CGRect(x: 7, y: 6, width: 2, height: 2),
            CGRect(x: 10, y: 10, width: 2, height: 2),
        ])
    }

    @Test func aLetterWithoutAColourStaysEmpty() {
        let p = ThemePattern(tile: 8, px: 1, opacity: 1, colors: ["c": "#FF00E5FF"], sprites: [(0, 0, ["cxc"])])
        #expect(p.fills.count == 1 && p.fills[0].rects.count == 2)
    }

    @Test func theBuiltInPatternsKeepUpstreamsTiles() {
        #expect([ThemePattern.halloween, .space, .ocean, .christmas].map(\.tile) == [104, 96, 104, 104])
        #expect([ThemePattern.halloween, .space, .ocean, .christmas].map(\.opacity) == [0.1, 0.45, 0.07, 0.07])
        // Christmas's snowflake: 17 white pixels at 2 px from (6, 8); its first row is one pixel at column 3.
        let white = ThemePattern.christmas.fills.first { $0.color == RGBA("#FFF8FAFC") }
        #expect(white?.rects.first == CGRect(x: 12, y: 8, width: 2, height: 2))
        // Every sprite stays inside its tile, so tiles never overlap.
        for p in [ThemePattern.halloween, .space, .ocean, .christmas] {
            #expect(p.fills.allSatisfy { $0.rects.allSatisfy { $0.maxX <= p.tile && $0.maxY <= p.tile } })
        }
    }
}
