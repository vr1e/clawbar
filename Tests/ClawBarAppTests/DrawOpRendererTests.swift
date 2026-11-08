import CoreGraphics
import SwiftUI
import Testing
@testable import ClawBar
import ClawBarShared

@Suite struct DrawOpLayerTests {
    let a = CGRect(x: 0, y: 0, width: 2, height: 2)
    let b = CGRect(x: 4, y: 0, width: 2, height: 2)
    let c = CGRect(x: 8, y: 0, width: 2, height: 2)
    let red = RGBA("#FFF87171"), blue = RGBA("#FF60A5FA")

    @Test func aRectsOpIsOneLayerWithAllItsRects() {
        let layers = DrawOpRenderer.layers([.rects([a, b, c], red, opacity: 1)])
        #expect(layers == [.rects([a, b, c], red, opacity: 1)])
    }

    @Test func consecutiveOpaqueLayersOfOneColourShareAPath() {
        let layers = DrawOpRenderer.layers([.rects([a], red, opacity: 1), .rects([b], red, opacity: 1), .rects([c], red, opacity: 1)])
        #expect(layers == [.rects([a, b, c], red, opacity: 1)])
    }

    @Test func translucentLayersStaySeparateBecauseOverlapsWouldBlendDifferently() {
        let faded = DrawOpRenderer.layers([.rects([a], red, opacity: 0.5), .rects([b], red, opacity: 0.5)])
        #expect(faded.count == 2)
        let glassy = RGBA("#8093C5FD")
        #expect(DrawOpRenderer.layers([.rects([a], glassy, opacity: 1), .rects([b], glassy, opacity: 1)]).count == 2)
    }

    @Test func zOrderIsKeptAcrossColours() {
        let layers = DrawOpRenderer.layers([.rects([a], red, opacity: 1), .rects([b], blue, opacity: 1), .rects([c], red, opacity: 1)])
        #expect(layers == [.rects([a], red, opacity: 1), .rects([b], blue, opacity: 1), .rects([c], red, opacity: 1)])
    }

    @Test func otherOpsPassThroughAndBreakAMerge() {
        let text = DrawOp.text("z", at: .zero, size: 9, weight: .semibold, color: Palette.zzz, opacity: 0.5, anchor: .bottomLeading)
        let layers = DrawOpRenderer.layers([.rects([a], red, opacity: 1), text, .rects([b], red, opacity: 1)])
        #expect(layers == [.rects([a], red, opacity: 1), text, .rects([b], red, opacity: 1)])
    }

    @Test func opsThatDrawNothingAreDropped() {
        let layers = DrawOpRenderer.layers([
            .rects([], red, opacity: 1),
            .rects([a], red, opacity: 0),
            .rects([a], red.withAlpha(0), opacity: 1),
            .rects([CGRect(x: 1, y: 1, width: 0, height: 3)], red, opacity: 1),
            .text("", at: .zero, size: 9, weight: .regular, color: red, opacity: 1, anchor: .topLeading),
            .radialGlow(a, inner: red, outer: blue, opacity: 0),
            .hGradient(a, stops: [], opacity: 1),
            .vGradient(a, stops: [GradientStop(location: 0, color: red.withAlpha(0))], opacity: 1),
            .stroke([CGPoint(x: 1, y: 1)], red, width: 1, opacity: 1),
            .stroke([.zero, CGPoint(x: 4, y: 0)], red, width: 0, opacity: 1),
            .strokedEllipse(a, red, width: 0, opacity: 1),
            .strokedEllipse(.zero, red, width: 1, opacity: 1),
            .polygon([.zero, CGPoint(x: 4, y: 0)], stops: [GradientStop(location: 0, color: red)], opacity: 1),
            .polygon([.zero, CGPoint(x: 4, y: 0), CGPoint(x: 0, y: 4)], stops: [GradientStop(location: 0, color: red)], opacity: 0),
            .group([.rects([], red, opacity: 1)], .translation(0, 0), opacity: 1, clip: nil),
            .group([.rects([a], red, opacity: 1)], .translation(0, 0), opacity: 0, clip: nil),
            .group([.rects([a], red, opacity: 1)], .translation(0, 0), opacity: 1, clip: .zero),
        ])
        #expect(layers.isEmpty)
    }

    @Test func aGroupsChildrenAreLayeredToo() {
        let layers = DrawOpRenderer.layers([.group([.rects([a], red, opacity: 1), .rects([b], red, opacity: 1), .rects([], blue, opacity: 1)], .translation(0, 0), opacity: 0.5, clip: nil)])
        #expect(layers == [.group([.rects([a, b], red, opacity: 1)], .translation(0, 0), opacity: 0.5, clip: nil)])
    }
}

@Suite struct WPFLineBoxTests {
    @Test func theLineBoxIsSegoeUIs() {
        #expect(abs(WPFLineBox.height - 1.33) < 0.001)
        #expect(abs(WPFLineBox.baseline - 1.0791) < 0.0001)
    }

    @Test func anchorsNameAPointOfTheLineBox() {
        // A 10-pt line box is 13.30 tall.
        let tl = WPFLineBox.topLeft(anchor: .topLeading, at: CGPoint(x: 5, y: 7), size: 10, width: 6)
        #expect(tl == CGPoint(x: 5, y: 7))
        let bl = WPFLineBox.topLeft(anchor: .bottomLeading, at: CGPoint(x: 5, y: 20), size: 10, width: 6)
        #expect(abs(bl.x - 5) < 1e-9 && abs(bl.y - (20 - 13.30078)) < 1e-4)
        let bc = WPFLineBox.topLeft(anchor: .bottom, at: CGPoint(x: 18, y: 20), size: 10, width: 6)
        #expect(abs(bc.x - 15) < 1e-9 && abs(bc.y - (20 - 13.30078)) < 1e-4)
    }
}

@Suite struct DrawOpPaintTests {
    /// Paints layers into a 20 × 10 base-unit canvas at scale `k` on black, one pixel per point.
    func paint(_ ops: [DrawOp], k: Double) -> Raster {
        let layers = DrawOpRenderer.layers(ops)
        let view = Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            ctx.scaleBy(x: k, y: k)
            DrawOpRenderer.draw(layers, in: &ctx)
        }
        .frame(width: 20 * k, height: 10 * k)
        let r = ImageRenderer(content: view)
        r.scale = 1
        return Raster(r.cgImage!, scale: 1)
    }

    @Test func rectsAreDrawnInBaseUnitsTimesTheScale() {
        let r = paint([.rects([CGRect(x: 5, y: 2, width: 4, height: 4)], Palette.ok, opacity: 1)], k: 2)
        #expect(close(r.color(atPoint: 14, 6), Palette.ok))
        #expect(close(r.color(atPoint: 9, 6), Palette.black))
        #expect(close(r.color(atPoint: 19, 6), Palette.black))
    }

    @Test func opacityFadesTheWholeLayer() {
        let r = paint([.rects([CGRect(x: 0, y: 0, width: 10, height: 10)], Palette.white, opacity: 0.5)], k: 1)
        let c = r.color(atPoint: 5, 5)
        #expect(abs(Int(c.r) - 128) <= 3 && c.r == c.g && c.g == c.b)
    }

    @Test func aGlowIsBrightAtItsCentreAndFadesToItsEdge() {
        let r = paint([.radialGlow(CGRect(x: 0, y: 0, width: 10, height: 10), inner: Palette.white, outer: Palette.white.withAlpha(0), opacity: 1)], k: 1)
        #expect(r.color(atPoint: 5, 5).r > 200)
        #expect(r.color(atPoint: 9.6, 5).r < 60)
        #expect(r.color(atPoint: 15, 5).r < 5)
    }

    @Test func aGradientRunsLeftToRight() {
        let stops = [GradientStop(location: 0, color: Palette.black), GradientStop(location: 1, color: Palette.white)]
        let r = paint([.hGradient(CGRect(x: 0, y: 0, width: 20, height: 10), stops: stops, opacity: 1)], k: 1)
        #expect(r.color(atPoint: 1, 5).r < 40)
        #expect(r.color(atPoint: 18.5, 5).r > 215)
    }

    @Test func aVerticalGradientRunsTopToBottom() {
        let stops = [GradientStop(location: 0, color: Palette.white), GradientStop(location: 1, color: Palette.black)]
        let r = paint([.vGradient(CGRect(x: 0, y: 0, width: 20, height: 10), stops: stops, opacity: 1)], k: 1)
        #expect(r.color(atPoint: 10, 0.5).r > 215)
        #expect(r.color(atPoint: 10, 9.5).r < 40)
    }

    @Test func aPolygonFillsTopToBottomInsideItsEdges() {
        // A cone from its tip at the bottom, bright there and clear at its wide top.
        let stops = [GradientStop(location: 0, color: Palette.white.withAlpha(0)), GradientStop(location: 1, color: Palette.white)]
        let r = paint([.polygon([CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)], stops: stops, opacity: 1)], k: 2)
        // In view points at k = 2: (10, 8.5) near the tip, (10, 0.5) at the top, (3, 8.5) beside the cone.
        #expect(r.color(atPoint: 20, 17).r > 180)
        #expect(r.color(atPoint: 20, 1).r < 40)
        #expect(r.color(atPoint: 6, 17).r < 5)
    }

    @Test func aSkewSlidesRowsByTheirDistanceFromItsAnchor() {
        // 45° about y = 8: the bottom row stays put and the top row, 8 above it, slides 8 to the left.
        let column = DrawOp.rects([CGRect(x: 10, y: 0, width: 2, height: 8)], Palette.white, opacity: 1)
        let r = paint([.group([column], .skewX(degrees: 45).about(CGPoint(x: 0, y: 8)), opacity: 1, clip: nil)], k: 2)
        #expect(r.color(atPoint: 21, 15).r > 200)
        #expect(r.color(atPoint: 7, 1).r > 200)
        #expect(r.color(atPoint: 21, 1).r < 5)
    }

    @Test func aScaleKeepsItsCentreWhereItIs() {
        let square = DrawOp.rects([CGRect(x: 6, y: 1, width: 8, height: 8)], Palette.white, opacity: 1)
        let r = paint([.group([square], .scale(0.5, 0.5).about(CGPoint(x: 10, y: 5)).concatenating(.translation(2, 0)), opacity: 1, clip: nil)], k: 2)
        // Halved about (10, 5) to 8...12 × 3...7, then moved 2 to the right.
        #expect(r.color(atPoint: 24, 10).r > 200)
        #expect(r.color(atPoint: 18, 10).r < 5)
        #expect(r.color(atPoint: 24, 4).r < 5)
    }

    @Test func aStrokeFollowsItsPointsAtItsWidth() {
        let r = paint([.stroke([CGPoint(x: 0, y: 2), CGPoint(x: 10, y: 2), CGPoint(x: 10, y: 8)], Palette.white, width: 2, opacity: 1)], k: 2)
        #expect(r.color(atPoint: 10, 4).r > 200)
        #expect(r.color(atPoint: 20, 12).r > 200)
        #expect(r.color(atPoint: 10, 10).r < 5)
    }

    @Test func anEllipseIsStrokedInsideItsRect() {
        let r = paint([.strokedEllipse(CGRect(x: 0, y: 0, width: 20, height: 10), Palette.white, width: 2, opacity: 1)], k: 2)
        // The outline's left and top edges lie just inside the rect; its middle stays empty.
        #expect(r.color(atPoint: 1, 10).r > 200)
        #expect(r.color(atPoint: 20, 1).r > 200)
        #expect(r.color(atPoint: 20, 10).r < 5)
    }

    @Test func aGroupFadesAsOnePictureSoOverlapsDontAddUp() {
        let square = CGRect(x: 0, y: 0, width: 10, height: 10)
        let r = paint([.group([.rects([square], Palette.white, opacity: 1), .rects([square], Palette.white, opacity: 1)], .translation(0, 0), opacity: 0.5, clip: nil)], k: 1)
        // Faded one by one, the two would reach 75%; faded together, half.
        #expect(abs(Int(r.color(atPoint: 5, 5).r) - 128) <= 3)
    }

    @Test func aGroupIsPlacedByItsTransformAndClippedInItsOwnSpace() {
        let bar = DrawOp.rects([CGRect(x: 0, y: 0, width: 4, height: 6)], Palette.white, opacity: 1)
        let r = paint([.group([bar], .translation(10, 2), opacity: 1, clip: CGRect(x: 0, y: 0, width: 4, height: 3))], k: 2)
        #expect(r.color(atPoint: 24, 6).r > 200)
        #expect(r.color(atPoint: 24, 14).r < 5)
        #expect(r.color(atPoint: 4, 6).r < 5)
        // A quarter turn lays a bar along x down along y.
        let bar8 = DrawOp.rects([CGRect(x: 0, y: -1, width: 8, height: 2)], Palette.white, opacity: 1)
        let turned = paint([.group([.group([bar8], .rotation(.pi / 2), opacity: 1, clip: nil)], .translation(5, 1), opacity: 1, clip: nil)], k: 2)
        #expect(turned.color(atPoint: 10, 14).r > 200)
        #expect(turned.color(atPoint: 18, 4).r < 5)
    }
}

@Suite struct CaptionOrderTests {
    let r = CGRect(x: 0, y: 0, width: 2, height: 2)

    @Test func theDeveloperCaptionSplitsTheOpsWhereTheEngineSaysSo() {
        let body = DrawOp.rects([r], Palette.clawdBody, opacity: 1)
        // The love heart shares confetti's first colour: only the engine's index can tell them apart.
        let love = DrawOp.rects([r], Palette.love, opacity: 1)
        let confetti = DrawOp.rects([r], Palette.confetti[0], opacity: 1)
        let split = DrawOpRenderer.captionSplit(ClawdFrame(ops: [body, love, confetti], spriteRect: r, captionIndex: 2))
        #expect(split.below == [body, love] && split.above == [confetti])
        #expect(DrawOpRenderer.captionSplit(ClawdFrame(ops: [body], spriteRect: r)).above.isEmpty)
        #expect(DrawOpRenderer.captionSplit(ClawdFrame(ops: [body], spriteRect: r, captionIndex: 9)).below == [body])
    }
}
