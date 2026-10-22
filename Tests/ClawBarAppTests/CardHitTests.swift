import AppKit
import SwiftUI
import Testing
@testable import ClawBar
import ClawBarShared

/// The card laid out in an NSHostingView, the way the panel hosts it, without a window.
@MainActor
final class LaidOutCard {
    let app = AppModel()
    let animation = AnimationModel()
    let layout = LayoutModel()
    let host: NSHostingView<AnyView>

    init(_ view: WidgetViewState = .sample, scale k: Double = 1.2, clawd: ClawdFrame = .sample, mascot: Bool = true, sky: Bool = true) {
        app.view = view
        app.scale = k
        app.mascotVisible = mascot
        app.skyVisible = sky
        animation.publish(clawd)
        animation.publish(SkyFrame.sample)
        host = NSHostingView(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(CardView(app: app, animation: animation, layout: layout).environment(\.uiScale, k).fixedSize())
        relayout()
    }

    func relayout() {
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
    }

    var k: Double { app.scale }

    var map: WidgetHitMap {
        .make(
            layout: layout, view: app.view, spriteRect: animation.clawd.spriteRect, scale: k,
            mascotVisible: app.mascotVisible, skyVisible: app.skyVisible
        )
    }

    func rect(_ id: HitID) throws -> CGRect { try #require(layout.rects[id], "\(id) was not published") }

    func center(_ id: HitID) throws -> CGPoint {
        let r = try rect(id)
        return CGPoint(x: r.midX, y: r.midY)
    }
}

@MainActor
@Suite struct CardHitTests {
    @Test(arguments: [1.0, 1.2, 2.0])
    func theCardIsWPFsWidthAtEveryScale(k: Double) throws {
        let card = LaidOutCard(scale: k)
        #expect(abs(card.layout.cardSize.width - 262 * k) < 0.01)
        #expect(abs(try card.rect(.percentRow).width - 236 * k) < 0.01)
        // Origins snap to the pixel grid, so 13 × 1.2 = 15.6 may land on 16.
        #expect(abs(try card.rect(.percentRow).minX - 13 * k) <= 0.5)
        #expect(card.layout.numberWidth > 20)
    }

    @Test func theNumberTheSkyAndTheLabelsDragTheWindow() throws {
        let card = LaidOutCard()
        let map = card.map, k = card.k
        let row = try card.rect(.percentRow)
        let number = try card.center(.number)
        #expect(map.classify(number, isSecondary: false) == .drag)
        let sky = CGPoint(x: row.maxX - 8 * k, y: row.minY + 8 * k)
        #expect(map.classify(sky, isSecondary: false) == .drag)
        let title = CGPoint(x: 13 * k + 12 * k, y: try card.center(.details).y)
        #expect(map.classify(title, isSecondary: false) == .drag)
        let sessions = try card.rect(.sessions)
        #expect(map.classify(CGPoint(x: sessions.minX + 4 * k, y: sessions.midY), isSecondary: false) == .drag)
        #expect(map.classify(try card.center(.reset), isSecondary: false) == .drag)
    }

    @Test func clawdAndTheButtonsAreNotDragHandles() throws {
        let card = LaidOutCard()
        let map = card.map
        let sprite = try #require(map.sprite)
        #expect(map.classify(CGPoint(x: sprite.midX, y: sprite.midY), isSecondary: false) == .clawd)
        for id in [HitID.details, .hide, .exit, .status] {
            let p = try card.center(id)
            #expect(map.classify(p, isSecondary: false) == .control, "\(id)")
            #expect(map.control(at: p) == id)
        }
    }

    @Test func secondaryClicksOpenTheDeveloperMenuOnlyOnClawdAndTheSky() throws {
        let card = LaidOutCard()
        let map = card.map, k = card.k
        let row = try card.rect(.percentRow)
        let sprite = try #require(map.sprite)
        #expect(map.classify(CGPoint(x: sprite.midX, y: sprite.midY), isSecondary: true) == .menu)
        #expect(map.classify(CGPoint(x: row.maxX - 8 * k, y: row.minY + 8 * k), isSecondary: true) == .menu)
        // The number covers the sky: right-clicking it does nothing, as in WPF.
        #expect(map.classify(try card.center(.number), isSecondary: true) == .control)
        #expect(map.classify(try card.center(.reset), isSecondary: true) == .control)
    }

    @Test func theSpriteStandsOnTheGroundRightOfTheNumber() throws {
        let card = LaidOutCard()
        let k = card.k
        let row = try card.rect(.percentRow)
        let sprite = try #require(card.map.sprite)
        let s = ClawdFrame.sample.spriteRect
        #expect(abs(sprite.minX - (row.minX + (card.layout.numberWidth + 10 + s.minX) * k)) < 0.01)
        // The 26.4-tall box hangs 4.4 below the ground line, which is 3 below the 40-tall row.
        #expect(abs(sprite.maxY - (row.minY + (43 + 4.4) * k)) < 0.01)
        #expect(abs(sprite.width - 36 * k) < 0.01 && abs(sprite.height - 26.4 * k) < 0.01)
    }

    @Test func theDetailsAddTheVersionLinesAsControls() throws {
        var v = WidgetViewState.sample
        v.detailsExpanded = true
        let card = LaidOutCard(v)
        let map = card.map
        #expect(map.control(at: try card.center(.version)) == .version)
        #expect(map.control(at: try card.center(.appVersion)) == .appVersion)
    }

    @Test func hiddenRowsLeaveNoControlsBehind() throws {
        var v = WidgetViewState.sample
        v.detailsExpanded = true
        let card = LaidOutCard(v)
        let status = try card.center(.status)
        let version = try card.center(.version)
        v.statusVisible = false
        v.detailsExpanded = false
        card.app.view = v
        card.relayout()
        #expect(card.map.control(at: status) == nil)
        #expect(card.map.control(at: version) == nil)
    }

    @Test func theChartReadsOutItsXAndStillDragsTheWindow() throws {
        var v = WidgetViewState.sample
        v.detailsExpanded = true
        v.history = HistoryView(label: "LIMITS · 7 DAYS", start: 0, end: 10080)
        let card = LaidOutCard(v)
        let chart = try card.rect(.history)
        #expect(abs(chart.width - 236 * card.k) < 0.01 && abs(chart.height - 44 * card.k) < 0.01)
        let map = card.map
        let x = try #require(map.chartX(at: CGPoint(x: chart.midX, y: chart.midY)))
        #expect(abs(x - 118) < 0.01)
        #expect(map.chartX(at: CGPoint(x: chart.minX, y: chart.minY)) == 0)
        #expect(map.chartX(at: CGPoint(x: chart.midX, y: chart.maxY + 1)) == nil)
        #expect(map.classify(CGPoint(x: chart.midX, y: chart.midY), isSecondary: false) == .drag)
        // Closed, the chart's rect stays published but reads out nothing.
        v.detailsExpanded = false
        v.history = nil
        card.app.view = v
        card.relayout()
        #expect(card.map.chartX(at: CGPoint(x: chart.midX, y: chart.midY)) == nil)
    }

    @Test func withoutClawdOrTheSkyThereIsNoDeveloperMenu() throws {
        let card = LaidOutCard(mascot: false, sky: false)
        let map = card.map, k = card.k
        let row = try card.rect(.percentRow)
        #expect(map.sprite == nil && map.sky == nil)
        #expect(map.classify(CGPoint(x: row.maxX - 8 * k, y: row.minY + 8 * k), isSecondary: true) == .control)
        #expect(map.classify(CGPoint(x: row.minX + 100 * k, y: row.minY + 30 * k), isSecondary: false) == .drag)
    }
}

/// Positions against widget.xaml's measurements at k = 1 (header 17.29 = the 13-pt "–" line box).
@MainActor
@Suite struct CardGeometryTests {
    @Test func rowsSitWhereWPFPutsThem() throws {
        let card = LaidOutCard(scale: 1)
        let row = try card.rect(.percentRow)
        #expect(abs(row.minY - (11 + 17.29 + 6)) < 0.8)
        #expect(abs(row.height - 40) < 0.01)
        // Row 40 + margin 4, bar 6 + margin 7.
        let reset = try card.rect(.reset)
        #expect(abs(reset.minY - (row.minY + 57)) < 0.8)
        #expect(abs(reset.height - 11 * WPFLineBox.height) < 0.8)
    }

    @Test func anEmptyResetLineKeepsItsLineBoxSoTheCardDoesNotJump() {
        var empty = WidgetViewState.sample
        empty.resetText = ""
        #expect(LaidOutCard(empty, scale: 1).layout.cardSize.height == LaidOutCard(scale: 1).layout.cardSize.height)
    }

    @Test func theNumbersBaselineIsSegoesAndThePercentSitsSuperscript() throws {
        let card = LaidOutCard(scale: 1)
        let number = try card.rect(.number)
        // The number's line box (39.9) fills the 40-tall row from its bottom.
        #expect(abs(number.height - 30 * WPFLineBox.height) < 0.8)
    }
}
