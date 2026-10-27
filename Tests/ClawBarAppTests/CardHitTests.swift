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

    /// The presenter's view of a `--snapshot` case, in English.
    convenience init(case name: String, scale k: Double = 1.2) throws {
        let c = try #require(SnapshotCases.all().first { $0.name == name })
        self.init(SnapshotMode.view(for: c, lang: .en), scale: k)
    }

    func relayout() {
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
    }

    var k: Double { app.scale }

    var regions: CardRegions { .make(app: app, animation: animation, layout: layout) }

    func rect(_ id: CardRectID) throws -> CGRect { try #require(layout.rects[id], "\(id) was not published") }
    func rect(_ part: CardPart.ID) throws -> CGRect { try rect(.part(part)) }

    func center(_ id: CardRectID) throws -> CGPoint {
        let r = try rect(id)
        return CGPoint(x: r.midX, y: r.midY)
    }

    func center(_ part: CardPart.ID) throws -> CGPoint { try center(.part(part)) }
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

    /// What ties the card to the parts: it publishes a rect for every part it shows, and for no other.
    @Test func everyStateDrawsExactlyThePartsItShows() throws {
        for c in SnapshotCases.all() where c.card {
            let card = LaidOutCard(SnapshotMode.view(for: c, lang: .en))
            let published = Set(card.layout.rects.keys.compactMap { id -> CardPart.ID? in
                guard case .part(let part) = id else { return nil }
                return part
            })
            #expect(published == Set(card.app.view.parts.map(\.id)), "\(c.name)")
        }
    }

    @Test func theNumberTheSkyAndTheLabelsDragTheWindow() throws {
        let card = LaidOutCard()
        let regions = card.regions, k = card.k
        let row = try card.rect(.percentRow)
        #expect(regions.classify(try card.center(.number), isSecondary: false) == .drag)
        let sky = CGPoint(x: row.maxX - 8 * k, y: row.minY + 8 * k)
        #expect(regions.classify(sky, isSecondary: false) == .drag)
        let title = CGPoint(x: 13 * k + 12 * k, y: try card.center(.details).y)
        #expect(regions.classify(title, isSecondary: false) == .drag)
        let sessions = try card.rect(.sessions)
        #expect(regions.classify(CGPoint(x: sessions.minX + 4 * k, y: sessions.midY), isSecondary: false) == .drag)
        #expect(regions.classify(try card.center(.reset), isSecondary: false) == .drag)
    }

    @Test func clawdAndTheButtonsAreNotDragHandles() throws {
        let card = LaidOutCard()
        let regions = card.regions
        let sprite = try #require(regions.rects(.sprite).first)
        #expect(regions.classify(CGPoint(x: sprite.midX, y: sprite.midY), isSecondary: false) == .clawd)
        let clicks: [(CardPart.ID, CardClick)] = [
            (.details, .toggleDetails), (.hide, .hide), (.exit, .quit), (.status, .open(AppInfo.statusPage)),
        ]
        for (id, click) in clicks {
            let p = try card.center(id)
            #expect(regions.classify(p, isSecondary: false) == .control, "\(id)")
            #expect(regions.click(at: p) == click)
        }
    }

    @Test func secondaryClicksOpenTheDeveloperMenuOnlyOnClawdAndTheSky() throws {
        let card = LaidOutCard()
        let regions = card.regions, k = card.k
        let row = try card.rect(.percentRow), number = try card.rect(.number)
        let sprite = try #require(regions.rects(.sprite).first)
        #expect(regions.classify(CGPoint(x: sprite.midX, y: sprite.midY), isSecondary: true) == .menu)
        #expect(regions.classify(CGPoint(x: row.maxX - 8 * k, y: row.minY + 8 * k), isSecondary: true) == .menu)
        // The number covers the sky: right-clicking it does nothing, as in WPF.
        #expect(regions.classify(try card.center(.number), isSecondary: true) == .control)
        #expect(regions.classify(try card.center(.reset), isSecondary: true) == .control)
        // The sky reaches 3 below the row, under the number too, for its menu and its tooltip alike.
        let under = CGPoint(x: number.midX, y: row.minY + 41.5 * k)
        #expect(regions.classify(under, isSecondary: true) == .menu)
        #expect(regions.tooltips.contains { $0.id == .sky && $0.rect.contains(under) })
    }

    @Test func theSpriteStandsOnTheGroundRightOfTheNumber() throws {
        let card = LaidOutCard()
        let k = card.k
        let row = try card.rect(.percentRow)
        let sprite = try #require(card.regions.rects(.sprite).first)
        let s = ClawdFrame.sample.spriteRect
        #expect(abs(sprite.minX - (row.minX + (card.layout.numberWidth + 10 + s.minX) * k)) < 0.01)
        // The 26.4-tall box hangs 4.4 below the ground line, which is 3 below the 40-tall row.
        #expect(abs(sprite.maxY - (row.minY + (43 + 4.4) * k)) < 0.01)
        #expect(abs(sprite.width - 36 * k) < 0.01 && abs(sprite.height - 26.4 * k) < 0.01)
    }

    @Test func theChartReadsOutItsXAndStillDragsTheWindow() throws {
        let card = try LaidOutCard(case: "history")
        let chart = try card.rect(.history)
        #expect(abs(chart.width - 236 * card.k) < 0.01 && abs(chart.height - 44 * card.k) < 0.01)
        let regions = card.regions
        let x = try #require(regions.chartX(at: CGPoint(x: chart.midX, y: chart.midY)))
        #expect(abs(x - 118) < 0.01)
        #expect(regions.chartX(at: CGPoint(x: chart.minX, y: chart.minY)) == 0)
        #expect(regions.chartX(at: CGPoint(x: chart.midX, y: chart.maxY + 1)) == nil)
        #expect(regions.classify(CGPoint(x: chart.midX, y: chart.midY), isSecondary: false) == .drag)
    }

    @Test func withoutClawdOrTheSkyThereIsNoDeveloperMenu() throws {
        let card = LaidOutCard(mascot: false, sky: false)
        let regions = card.regions, k = card.k
        let row = try card.rect(.percentRow)
        #expect(regions.rects(.sprite).isEmpty && regions.rects(.sky).isEmpty)
        #expect(regions.classify(CGPoint(x: row.maxX - 8 * k, y: row.minY + 8 * k), isSecondary: true) == .control)
        #expect(regions.classify(CGPoint(x: row.minX + 100 * k, y: row.minY + 30 * k), isSecondary: false) == .drag)
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
