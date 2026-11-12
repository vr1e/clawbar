import CoreGraphics
import Testing
@testable import ClawBarClawd
import ClawBarShared

/// The rasterizer against visuals-verbatim.txt §D and the frame-transform rules of mascot.ps1.
@Suite struct SpriteTests {
    /// The pose a §D label describes.
    static func pose(for label: String) -> ClawdPose? {
        var pose = ClawdPose()
        for part in label.split(separator: " ") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if part.hasPrefix("face:") {
                guard let f = ClawdFacing(rawValue: String(part.dropFirst(5))) else { return nil }
                pose.facing = f
            } else if kv.count == 2, kv[0] == "arms", let a = ClawdArms(rawValue: kv[1]) {
                pose.arms = a
            } else if kv.count == 2, kv[0] == "feet", let f = ClawdFeet(rawValue: kv[1]) {
                pose.feet = f
            } else if kv.count == 2, kv[0] == "eyes", let e = ClawdEyes(rawValue: kv[1]) {
                pose.eyes = e
            } else if kv.count == 2, kv[0] == "look", let l = Int(kv[1]) {
                pose.look = l
            } else {
                return nil
            }
        }
        return pose
    }

    @Test func everyFixtureLineIsCovered() {
        #expect(PixelFixtures.all.allSatisfy { Self.pose(for: $0.label) != nil })
        let faces = Set(PixelFixtures.all.compactMap { Self.pose(for: $0.label)?.facing })
        #expect(faces == Set(ClawdFacing.allCases))
        let eyes = Set(PixelFixtures.all.compactMap { Self.pose(for: $0.label) }.filter { $0.facing == nil }.map(\.eyes))
        #expect(eyes == Set(ClawdEyes.allCases))
    }

    @Test(arguments: PixelFixtures.all.map(\.label))
    func matchesTheFixture(_ label: String) throws {
        let fixture = try #require(PixelFixtures.all.first { $0.label == label })
        let pose = try #require(Self.pose(for: label))
        let rows = grid(ClawdSprite.render(pose))
        #expect(Array(rows[fixture.firstRow ..< fixture.firstRow + fixture.rows.count]) == fixture.rows)
        // Unshifted poses end on the ground line: pixel rows 10 and 11 stay empty.
        #expect(rows[10] == emptyRow && rows[11] == emptyRow)
    }

    @Test func openEyesFollowTheGazeWithTheReadyMadePoses() {
        #expect(grid(ClawdSprite.render(ClawdPose(look: -1))) == grid(ClawdSprite.render(ClawdPose(eyes: .left))))
        #expect(grid(ClawdSprite.render(ClawdPose(look: 1))) == grid(ClawdSprite.render(ClawdPose(eyes: .right))))
        // Wink and the ready-made shapes ignore the gaze.
        #expect(grid(ClawdSprite.render(ClawdPose(eyes: .wink, look: 1))) == grid(ClawdSprite.render(ClawdPose(eyes: .wink))))
        #expect(grid(ClawdSprite.render(ClawdPose(eyes: .left, look: 1))) == grid(ClawdSprite.render(ClawdPose(eyes: .left))))
    }

    @Test func runsMergeIntoOneRectPerColour() {
        let geo = ClawdSprite.render(ClawdPose())
        // Row 0 is one body run from pixel 3 to 15; row 2 splits around the two pupils.
        #expect(close(geo.body[0], CGRect(x: 6, y: 0, width: 26, height: 2.2)))
        #expect(close(Array(geo.body[2 ... 4]), [
            CGRect(x: 6, y: 4.4, width: 4, height: 2.2),
            CGRect(x: 12, y: 4.4, width: 14, height: 2.2),
            CGRect(x: 28, y: 4.4, width: 4, height: 2.2),
        ]))
        #expect(close(Array(geo.eyes[0 ... 1]), [
            CGRect(x: 10, y: 4.4, width: 2, height: 2.2),
            CGRect(x: 26, y: 4.4, width: 2, height: 2.2),
        ]))
        #expect(geo.fx.isEmpty && geo.sand.isEmpty)
    }

    @Test func offLowersByWholeGlyphRowsAndClipsAtTheBottom() {
        let standing = grid(ClawdSprite.render(ClawdPose()))
        let crouched = grid(ClawdSprite.render(ClawdPose(off: 1)))
        #expect(Array(crouched[0 ..< 4]) == Array(repeating: emptyRow, count: 4))
        #expect(Array(crouched[4 ..< 12]) == Array(standing[0 ..< 8]))
        // Above the frame: off −3 lifts everything out of it.
        #expect(ClawdSprite.render(ClawdPose(off: -3)).body.isEmpty)
        let high = grid(ClawdSprite.render(ClawdPose(off: -1)))
        #expect(Array(high[0 ..< 6]) == Array(standing[4 ..< 10]))
    }

    @Test func xShiftsByCellsAndClipsAtTheSides() {
        #expect(ClawdSprite.render(ClawdPose(x: -9)).body.isEmpty)
        let standing = grid(ClawdSprite.render(ClawdPose()))
        let left = grid(ClawdSprite.render(ClawdPose(x: -3)))
        for y in 0 ..< 12 {
            #expect(left[y] == String(standing[y].dropFirst(6)) + "......")
        }
    }

    @Test func flipMirrorsRowsZeroToNine() {
        let standing = grid(ClawdSprite.render(ClawdPose()))
        let flipped = grid(ClawdSprite.render(ClawdPose(flip: true)))
        #expect(Array(flipped[0 ..< 10]) == Array(standing[0 ..< 10].reversed()))
        #expect(flipped[10] == emptyRow && flipped[11] == emptyRow)
    }

    @Test func digSinksIntoTheSandAndClipsAtTheGround() {
        let standing = grid(ClawdSprite.render(ClawdPose()))
        let dug = ClawdSprite.render(ClawdPose(dig: 4))
        let rows = grid(dug)
        #expect(Array(rows[4 ..< 10]) == Array(standing[0 ..< 6]))
        #expect(rows[10] == emptyRow && rows[11] == emptyRow)
        #expect(close(dug.sand, [
            CGRect(x: -4, y: 9 * 2.2, width: 44, height: 2.2),
            CGRect(x: -2, y: 8 * 2.2, width: 40, height: 2.2),
            CGRect(x: -2, y: 7 * 2.2, width: 4, height: 2.2),
            CGRect(x: 34, y: 7 * 2.2, width: 4, height: 2.2),
        ]))
        #expect(close(ClawdSprite.render(ClawdPose(dig: 1)).sand, [CGRect(x: -4, y: 9 * 2.2, width: 44, height: 2.2)]))
    }

    @Test func sprayThrowsTwoGrainsEachSide() {
        let sand = ClawdSprite.render(ClawdPose(spray: 1)).sand
        // d = 1 and 3: sx = 1.5 + 0.9d, sy = 8 − 0.45d(5 − d).
        #expect(close(sand, [
            CGRect(x: -2.4 * 2, y: 6.2 * 2.2, width: 1.6, height: 0.8 * 2.2),
            CGRect(x: (17.2 + 2.4) * 2, y: 6.2 * 2.2, width: 1.6, height: 0.8 * 2.2),
            CGRect(x: -4.2 * 2, y: 5.3 * 2.2, width: 1.6, height: 0.8 * 2.2),
            CGRect(x: (17.2 + 4.2) * 2, y: 5.3 * 2.2, width: 1.6, height: 0.8 * 2.2),
        ]))
    }

    @Test func poofOnlyWhileCrouched() {
        #expect(ClawdSprite.render(ClawdPose(poof: .dot)).fx.isEmpty)
        #expect(close(ClawdSprite.render(ClawdPose(off: 1, poof: .dot)).fx, [
            CGRect(x: 1.2, y: 9.4 * 2.2, width: 1.6, height: 0.9 * 2.2),
            CGRect(x: 33.2, y: 9.4 * 2.2, width: 1.6, height: 0.9 * 2.2),
        ]))
        let wave = ClawdSprite.render(ClawdPose(off: 1, poof: .wave)).fx
        #expect(wave.count == 6)
        #expect(close(wave[3], CGRect(x: 32, y: 9.6 * 2.2, width: 1.4, height: 0.6 * 2.2)))
    }

    @Test func coinShadowSitsBelowTheGround() {
        #expect(close(ClawdSprite.render(ClawdPose(shadow: .wide)).fx, [CGRect(x: 12, y: 11.5 * 2.2, width: 12, height: 1.1)]))
        #expect(close(ClawdSprite.render(ClawdPose(shadow: .narrow)).fx, [CGRect(x: 16, y: 11.5 * 2.2, width: 4, height: 1.1)]))
    }

    @Test func soulHangsAboveItsOrigin() {
        let rects = ClawdSprite.soul(height: 20, t: 0)
        // A 14-square thread, then the 7-row body whose top is 20 + 7 × 1.4 above the mouth.
        #expect(rects.count == 14 + 9)
        #expect(close(rects[0], CGRect(x: -0.7, y: -1.4, width: 1.4, height: 1.4)))
        #expect(close(rects[14], CGRect(x: 2 * 1.4 - 6 * 1.4, y: -20 - 9.8, width: 8 * 1.4, height: 1.4)))
        #expect(ClawdSprite.soul(height: 0.4, t: 3).count == 9)
    }
}
