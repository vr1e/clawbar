import CoreGraphics
import Testing
import ClawBarShared

@Suite struct WindowPlacementTests {
    // A 1512 × 982 primary screen with a 33-pt menu bar, and a 1920 × 1080 screen to its right.
    let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let primaryVisible = CGRect(x: 0, y: 0, width: 1512, height: 949)
    let rightVisible = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    let size = CGSize(width: 314, height: 300)

    @Test func topLeftCountsDownFromThePrimaryScreensTop() {
        let frame = CGRect(x: 100, y: 600, width: 314, height: 300)
        let tl = WindowPlacement.topLeft(of: frame, primaryMaxY: primary.maxY)
        #expect(tl == CGPoint(x: 100, y: 82))
    }

    @Test func frameAndTopLeftRoundTrip() {
        let frame = WindowPlacement.frame(topLeft: CGPoint(x: 40, y: 50), size: size, primaryMaxY: primary.maxY)
        #expect(frame == CGRect(x: 40, y: 632, width: 314, height: 300))
        #expect(WindowPlacement.topLeft(of: frame, primaryMaxY: primary.maxY) == CGPoint(x: 40, y: 50))
    }

    @Test func aWindowGrowingPastTheBottomMovesUpJustEnough() {
        let old = CGRect(x: 100, y: 100, width: 314, height: 300)
        let grown = CGRect(x: 100, y: -150, width: 314, height: 550)
        #expect(WindowPlacement.keptOnScreen(grown, was: old, visible: primaryVisible) == CGRect(x: 100, y: 0, width: 314, height: 550))
    }

    @Test func aWindowGrowingPastTheRightMovesLeftJustEnough() {
        let old = CGRect(x: 1100, y: 100, width: 314, height: 300)
        let grown = CGRect(x: 1100, y: 100, width: 500, height: 300)
        #expect(WindowPlacement.keptOnScreen(grown, was: old, visible: primaryVisible).minX == 1012)
    }

    @Test func aWindowThatStillFitsOrShrinksStays() {
        let old = CGRect(x: 100, y: 100, width: 314, height: 300)
        let taller = CGRect(x: 100, y: 50, width: 314, height: 350)
        let shorter = CGRect(x: 100, y: 200, width: 314, height: 200)
        #expect(WindowPlacement.keptOnScreen(taller, was: old, visible: primaryVisible) == taller)
        #expect(WindowPlacement.keptOnScreen(shorter, was: old, visible: primaryVisible) == shorter)
    }

    @Test func aDeliberateOverhangOnlyKeepsItsDepth() {
        // Parked 50 pt below the bottom edge; growing 100 pt more moves it up by those 100 alone.
        let old = CGRect(x: 100, y: -50, width: 314, height: 300)
        let grown = CGRect(x: 100, y: -150, width: 314, height: 400)
        #expect(WindowPlacement.keptOnScreen(grown, was: old, visible: primaryVisible).minY == -50)
    }

    @Test func aWindowTallerThanTheScreenKeepsItsTopOnIt() {
        let old = CGRect(x: 100, y: 100, width: 314, height: 300)
        let grown = CGRect(x: 100, y: -700, width: 314, height: 1100)
        #expect(WindowPlacement.keptOnScreen(grown, was: old, visible: primaryVisible).maxY == primaryVisible.maxY)
    }

    @Test func aPositionOnAnyScreenIsKept() {
        let onRight = CGPoint(x: 2000, y: 100)
        #expect(WindowPlacement.validated(
            topLeft: onRight, size: size, visibleFrames: [primaryVisible, rightVisible], primaryMaxY: primary.maxY
        ) == onRight)
    }

    @Test func aPositionOnARemovedScreenIsDropped() {
        #expect(WindowPlacement.validated(
            topLeft: CGPoint(x: 2000, y: 100), size: size, visibleFrames: [primaryVisible], primaryMaxY: primary.maxY
        ) == nil)
    }

    @Test func aWindowHangingMostlyOffScreenIsDropped() {
        // Only 20 pt of it would still show at the left edge.
        #expect(WindowPlacement.validated(
            topLeft: CGPoint(x: -294, y: 100), size: size, visibleFrames: [primaryVisible], primaryMaxY: primary.maxY
        ) == nil)
    }

    @Test func noSavedPositionStaysNil() {
        #expect(WindowPlacement.validated(
            topLeft: nil, size: size, visibleFrames: [primaryVisible], primaryMaxY: primary.maxY
        ) == nil)
    }

    @Test func theDefaultSitsTwentyPointsInFromTheTopRight() {
        let tl = WindowPlacement.defaultTopLeft(size: size, visibleFrame: primaryVisible, primaryMaxY: primary.maxY)
        #expect(tl == CGPoint(x: 1512 - 20 - 314, y: 33 + 20))
    }
}

@Suite struct ClassifyHitTests {
    let sprite = CGRect(x: 100, y: 30, width: 36, height: 26.4)
    let sky = CGRect(x: 13, y: 30, width: 236, height: 43)
    let controls = [CGRect(x: 200, y: 8, width: 12, height: 12), CGRect(x: 13, y: 200, width: 236, height: 14)]

    func hit(_ x: Double, _ y: Double, secondary: Bool = false) -> WidgetHit {
        classifyHit(CGPoint(x: x, y: y), isSecondary: secondary, controls: controls, sprite: sprite, sky: [sky])
    }

    @Test func leftClickOnClawdIsForClawd() {
        #expect(hit(110, 40) == .clawd)
    }

    @Test func leftClickOnAControlGoesToTheControl() {
        #expect(hit(205, 12) == .control)
        #expect(hit(100, 205) == .control)
    }

    @Test func leftClickAnywhereElseDragsEvenOverTheSky() {
        #expect(hit(30, 40) == .drag)
        #expect(hit(5, 5) == .drag)
    }

    @Test func secondaryClickOnClawdOrTheSkyOpensTheDeveloperMenu() {
        #expect(hit(110, 40, secondary: true) == .menu)
        #expect(hit(30, 40, secondary: true) == .menu)
    }

    @Test func secondaryClickElsewhereIsLeftToTheView() {
        #expect(hit(205, 12, secondary: true) == .control)
        #expect(hit(5, 5, secondary: true) == .control)
    }

    @Test func withoutClawdAndSkyThereIsNoDeveloperMenu() {
        let r = classifyHit(CGPoint(x: 30, y: 40), isSecondary: true, controls: [], sprite: nil, sky: [])
        #expect(r == .control)
        #expect(classifyHit(CGPoint(x: 30, y: 40), isSecondary: false, controls: [], sprite: nil, sky: []) == .drag)
    }
}
