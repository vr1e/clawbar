import CoreGraphics
import Testing
@testable import ClawBarClawd
import ClawBarShared

/// mascot.ps1's skin accessories: where each pixel lands in a frame, and where it goes in the draw order.
@Suite struct SkinSpriteTests {
    static let hat = RGBA("#FF0000FF")
    /// Two head pixels side by side and one apart at row −2, a body pixel at row 4 and one at row 9.
    static let skin = Skin(id: "t", name: "T", body: RGBA("#FF00FF00"), eyes: RGBA("#FFFF00FF"), layers: [
        SkinLayer(color: hat, pixels: [
            SkinPixel(x: 3, y: -2), SkinPixel(x: 4, y: -2), SkinPixel(x: 7, y: -2), SkinPixel(x: 5, y: 4), SkinPixel(x: 5, y: 9),
        ]),
    ])

    /// Each rect as [x, y, width] in pixels.
    private func cells(_ pose: ClawdPose) -> [[Int]] {
        ClawdSprite.render(pose, skin: Self.skin).accessories[0].map {
            [Int(($0.minX / ClawdTables.px).rounded()), Int(($0.minY / ClawdTables.py).rounded()), Int(($0.width / ClawdTables.px).rounded())]
        }
    }

    @Test func standingTheyMergeIntoRunsPerRow() {
        #expect(cells(ClawdPose()) == [[3, -2, 2], [7, -2, 1], [5, 4, 1], [5, 9, 1]])
        let r = ClawdSprite.render(ClawdPose(), skin: Self.skin).accessories[0][0]
        #expect(r == CGRect(x: 6, y: -2 * ClawdTables.py, width: 4, height: ClawdTables.py))
    }

    @Test func theSkinLeavesTheBodyAlone() {
        for pose in [ClawdPose(), ClawdPose(arms: .up, off: 1), ClawdPose(facing: .back)] {
            var plain = ClawdSprite.render(pose)
            #expect(plain.accessories.isEmpty)
            plain.accessories = ClawdSprite.render(pose, skin: Self.skin).accessories
            #expect(plain == ClawdSprite.render(pose, skin: Self.skin))
        }
    }

    @Test func bellyUpHeLosesThemAll() {
        #expect(cells(ClawdPose(flip: true)).isEmpty)
    }

    @Test func turnedOnlyWhatIsAboveTheHeadStays() {
        #expect(cells(ClawdPose(facing: .back)) == [[3, -2, 2], [7, -2, 1]])
        #expect(cells(ClawdPose(facing: .right30)) == [[3, -2, 2], [7, -2, 1]])
    }

    @Test func loweredTheyComeAlongAndClipAtTheBottom() {
        // One glyph row down is four pixels: the head row shows at 2, row 9 falls out at 13.
        #expect(cells(ClawdPose(off: 1)) == [[3, 2, 2], [7, 2, 1], [5, 8, 1]])
    }

    @Test func aboveTheFrameTheHatGoesFirstThenTheBody() {
        // While the head is out of the frame, nothing above it shows; the body pixels show while inside.
        #expect(cells(ClawdPose(off: -1)) == [[5, 0, 1], [5, 5, 1]])
        #expect(cells(ClawdPose(off: -2)) == [[5, 1, 1]])
    }

    @Test func inTheBurrowTheyClipAtTheGround() {
        // dig 1: one row down, clipped two rows above the grid's bottom.
        #expect(cells(ClawdPose(dig: 1)) == [[3, -1, 2], [7, -1, 1], [5, 5, 1]])
    }

    @Test func shiftedTheyClipAtTheSides() {
        // x −2 is four pixels left: 3 falls off, 4 stays at 0.
        #expect(cells(ClawdPose(x: -2)) == [[0, -2, 1], [3, -2, 1], [1, 4, 1], [1, 9, 1]])
        #expect(cells(ClawdPose(x: 9)).isEmpty)
    }

    @Test func anotherSkinStartsTheCacheOver() {
        let sprite = ClawdSprite()
        #expect(sprite.geometry(ClawdPose()).accessories.isEmpty)
        sprite.skin = Self.skin
        #expect(sprite.geometry(ClawdPose()).accessories.count == 1)
        sprite.skin = .classic
        #expect(sprite.geometry(ClawdPose()).accessories.isEmpty)
    }

    @Test func theEngineDrawsTheSkinsColoursAndItsAccessoriesAfterTheSweat() {
        let engine = ClawdEngine(random: ScriptedRandom(), now: t0)
        engine.perform(.auto)
        engine.perform(.sweat(true))
        engine.wear(Self.skin)
        let ops = engine.step(env()).ops
        func color(_ op: DrawOp) -> RGBA? { if case let .rects(_, c, _) = op { c } else { nil } }
        #expect(color(ops[0]) == Self.skin.body && color(ops[1]) == Self.skin.eyes)
        let sweat = ops.firstIndex { color($0) == Palette.sweat }
        let hat = ops.firstIndex { color($0) == Self.hat }
        #expect(sweat != nil && hat == sweat.map { $0 + 1 })

        engine.wear(.classic)
        let plain = engine.step(env()).ops
        #expect(color(plain[0]) == Palette.clawdBody && !plain.contains { color($0) == Self.hat })
    }

    @Test func thePreviewIsHimStandingInTheSkin() {
        let ops = ClawdPreview.standing(in: Self.skin)
        let geo = ClawdSprite.render(ClawdPose(), skin: Self.skin)
        #expect(ops == [
            .rects(geo.body, Self.skin.body, opacity: 1), .rects(geo.eyes, Self.skin.eyes, opacity: 1),
            .rects(geo.accessories[0], Self.hat, opacity: 1),
        ])
    }

    @Test func thePreviewsFrameReachesTheHighestHatAtMostTwelveRowsUp() {
        let feet = 10 * ClawdTables.py
        #expect(ClawdPreview.frame(fitting: []) == CGRect(x: 0, y: 0, width: 36, height: feet))
        #expect(ClawdPreview.frame(fitting: [Self.skin]) == CGRect(x: 0, y: -2 * ClawdTables.py, width: 36, height: feet + 2 * ClawdTables.py))
        let tall = Skin(id: "tall", name: "", body: Self.hat, eyes: Self.hat, layers: [SkinLayer(color: Self.hat, pixels: [SkinPixel(x: 0, y: -20)])])
        func rowsUp(_ skins: [Skin]) -> Double { -(ClawdPreview.frame(fitting: skins).minY / ClawdTables.py).rounded() }
        #expect(rowsUp([tall]) == 12)
        // Party's and Santa's hats.
        #expect(rowsUp(BuiltInSkin.allCases.map(\.skin)) == 7)
    }
}
