import CoreGraphics
import Testing
import ClawBarShared

/// The play area's geometry in base units and in card space.
@Suite struct PlayAreaTests {
    @Test func theWidthIsWhatTheNumberLeavesOfTheRow() {
        #expect(PlayArea.width(numberWidth: 32) == 194)
        #expect(PlayArea.width(numberWidth: 47) == 179)
        #expect(PlayArea.width(numberWidth: 300) == 0)
        #expect(PlayArea.skySize == CGSize(width: 236, height: 43))
    }

    @Test func theGroundLineStartsAfterTheNumberAndItsMargin() {
        let row = CGRect(x: 15.6, y: 30, width: 283.2, height: 48)
        let ground = PlayArea.ground(row: row, numberWidth: 32, scale: 1.2)
        #expect(ground == CGPoint(x: 15.6 + 42 * 1.2, y: 30 + 43 * 1.2))
    }

    @Test func thePointerMapsIntoPlayAreaUnits() {
        let row = CGRect(x: 13, y: 30, width: 236, height: 40)
        // 13 of padding, the number's 32 and the margin 10 put x = 0 at 55 in card space; a 1.2 scale divides out.
        #expect(PlayArea.mouseX(cardX: 55, row: row, numberWidth: 32, scale: 1) == 0)
        #expect(PlayArea.mouseX(cardX: 115, row: row, numberWidth: 32, scale: 1) == 60)
        let scaled = CGRect(x: 15.6, y: 36, width: 283.2, height: 48)
        #expect(abs(PlayArea.mouseX(cardX: 15.6 + 42 * 1.2 + 24, row: scaled, numberWidth: 32, scale: 1.2) - 20) < 1e-9)
    }
}
