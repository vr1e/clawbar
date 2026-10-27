import CoreGraphics
import Foundation
import Testing
@testable import ClawBar
import ClawBarShared

/// The regions from hand-filled models: what the card shows, the rects it published, Clawd's layer.
@MainActor
@Suite struct CardRegionsTests {
    /// A row of 236 × 40 at (13, 34), a number of 50 × 39.9 at its bottom left, k = 1.
    static let row = CGRect(x: 13, y: 34, width: 236, height: 40)
    static let number = CGRect(x: 13, y: 34.1, width: 50, height: 39.9)
    /// The row with the 3 below it to the ground line.
    static let band = CGRect(x: 13, y: 34, width: 236, height: 43)
    static let sprite = CGRect(x: 0, y: 0, width: 36, height: 26.4)

    func regions(
        _ view: WidgetViewState = .sample, rects: [CardRectID: CGRect] = [:], mascot: Bool = true, sky: Bool = true,
        hearts: Bool = false, sprite: CGRect = .zero
    ) -> CardRegions {
        let app = AppModel(), animation = AnimationModel(), layout = LayoutModel()
        app.view = view
        app.scale = 1
        app.mascotVisible = mascot
        app.skyVisible = sky
        var clawd = ClawdFrame.empty
        clawd.spriteRect = sprite
        clawd.hearts = HeartsFrame(visible: hearts, shownHalves: 6)
        animation.publish(clawd)
        for (id, rect) in rects { layout.set(id, rect) }
        return .make(app: app, animation: animation, layout: layout)
    }

    /// One rect per part, each in a row of its own.
    func partRects(_ ids: [CardPart.ID]) -> [CardRectID: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { i, id in
            (CardRectID.part(id), CGRect(x: 13, y: 100 + 20 * Double(i), width: 236, height: 12))
        })
    }

    @Test func aShownPartWithARectBecomesTheRegionsOfItsRoles() {
        let ids: [CardPart.ID] = [.details, .hide, .exit, .reset, .sessions, .status, .account]
        let rects = partRects(ids)
        func r(_ id: CardPart.ID) -> CGRect { rects[.part(id)]! }
        #expect(regions(rects: rects).all == [
            CardRegion(rect: r(.details), role: .control(.toggleDetails)),
            CardRegion(rect: r(.details), role: .tooltip(.part(.details))),
            CardRegion(rect: r(.hide), role: .control(.hide)),
            CardRegion(rect: r(.hide), role: .tooltip(.part(.hide))),
            CardRegion(rect: r(.exit), role: .control(.quit)),
            CardRegion(rect: r(.exit), role: .tooltip(.part(.exit))),
            // The reset line without an issue neither explains itself nor takes the click.
            CardRegion(rect: r(.sessions), role: .tooltip(.part(.sessions))),
            CardRegion(rect: r(.status), role: .control(.open(AppInfo.statusPage))),
            CardRegion(rect: r(.status), role: .tooltip(.part(.status))),
            CardRegion(rect: r(.account), role: .tooltip(.part(.account))),
        ])
    }

    @Test func aHiddenPartsRectAndAPartWithoutARectLeaveNone() {
        // Rects a closed details block, a reset limit and a gone row left behind; the sessions never published.
        let shown: [CardPart.ID] = [.details, .hide, .exit, .status, .account]
        let hidden: [CardPart.ID] = [.version, .appVersion, .play, .project(0)]
        var rects = partRects(shown + hidden)
        rects[.history] = CGRect(x: 13, y: 300, width: 236, height: 44)
        let r = regions(rects: rects)
        // Neither a click nor a tooltip nor the chart's readout lands on a rect left behind.
        let leftBehind = hidden.map { rects[.part($0)]! } + [rects[.history]!]
        #expect(!r.all.contains { leftBehind.contains($0.rect) })
        let shownRects = shown.map { rects[.part($0)]! }
        #expect(r.all.allSatisfy { shownRects.contains($0.rect) })
        #expect(shownRects.allSatisfy { rect in r.all.contains { $0.rect == rect } })
    }

    @Test func theNumberCoversTheSky() {
        let r = regions(rects: [.percentRow: Self.row, .number: Self.number])
        let sky = r.rects(.sky)
        // Right of the number at the band's height, as one rect; then the slivers above and below the number.
        #expect(sky.first == CGRect(x: Self.number.maxX, y: Self.band.minY, width: Self.band.maxX - Self.number.maxX, height: Self.band.height))
        #expect(sky.count == 3)
        #expect(r.tooltips.filter { $0.id == .sky }.map(\.rect) == sky)
        let inside: [CGPoint] = [CGPoint(x: 30, y: 60), CGPoint(x: 13, y: 34.1), CGPoint(x: 62.9, y: 73.9)]
        let outside: [CGPoint] = [CGPoint(x: 30, y: 75.5), CGPoint(x: 30, y: 34.05), CGPoint(x: 63, y: 60), CGPoint(x: 248.9, y: 76.9)]
        for p in inside {
            #expect(!sky.contains { $0.contains(p) }, "\(p)")
            #expect(r.classify(p, isSecondary: true) == .control)
        }
        for p in outside {
            #expect(sky.contains { $0.contains(p) }, "\(p)")
            #expect(r.classify(p, isSecondary: true) == .menu)
        }
        // Below the band and left of the row is no sky.
        #expect(r.classify(CGPoint(x: 100, y: 77), isSecondary: true) == .control)
        #expect(r.classify(CGPoint(x: 12.9, y: 60), isSecondary: true) == .control)
    }

    @Test func beforeTheNumberIsMeasuredTheSkyIsTheWholeBand() {
        #expect(regions(rects: [.percentRow: Self.row]).rects(.sky) == [Self.band])
    }

    @Test func withoutTheSkyOrClawdTheyLeaveNoRegions() {
        let rects: [CardRectID: CGRect] = [.percentRow: Self.row, .number: Self.number, .hearts: CGRect(x: 180, y: 12, width: 40, height: 10)]
        let all = regions(rects: rects, hearts: true, sprite: Self.sprite)
        #expect(all.rects(.sprite).count == 1 && !all.rects(.sky).isEmpty)
        #expect(all.rects(.tooltip(.hearts)) == [CGRect(x: 180, y: 12, width: 40, height: 10)])
        let noSky = regions(rects: rects, sky: false, hearts: true, sprite: Self.sprite)
        #expect(noSky.rects(.sky).isEmpty && noSky.rects(.sprite).count == 1)
        // The engine never shows the sky without Clawd.
        let none = regions(rects: rects, mascot: false, sky: false, hearts: true, sprite: Self.sprite)
        #expect(none.rects(.sprite).isEmpty && none.rects(.sky).isEmpty && none.rects(.tooltip(.hearts)).isEmpty)
        // Hidden hearts and a sprite not yet drawn leave none either.
        let quiet = regions(rects: rects)
        #expect(quiet.rects(.sprite).isEmpty && quiet.rects(.tooltip(.hearts)).isEmpty)
    }

    @Test func theChartReadsOutOnlyWhileTheViewHasOne() {
        var view = WidgetViewState.sample
        view.history = HistoryView(label: "LIMITS · 7 DAYS")
        let chart = CGRect(x: 13, y: 300, width: 236, height: 44)
        let r = regions(view, rects: [.history: chart])
        #expect(r.chartX(at: CGPoint(x: chart.midX, y: chart.midY)) == 118)
        #expect(r.chartX(at: CGPoint(x: chart.minX, y: chart.midY)) == 0)
        #expect(r.chartX(at: CGPoint(x: chart.midX, y: chart.maxY)) == nil)
        #expect(r.classify(CGPoint(x: chart.midX, y: chart.midY), isSecondary: false) == .drag)
        #expect(regions(rects: [.history: chart]).chartX(at: CGPoint(x: chart.midX, y: chart.midY)) == nil)
    }

    @Test func clicksAndTheHandFollowTheControlsAndClawd() {
        var view = WidgetViewState.sample
        view.versionAction = .none
        view.show(.version, tooltip: "updating")
        let rects = partRects([.status, .sessions, .version])
        let r = regions(view, rects: rects.merging([.percentRow: Self.row, .number: Self.number]) { a, _ in a }, sprite: Self.sprite)
        func center(_ id: CardPart.ID) -> CGPoint { CGPoint(x: rects[.part(id)]!.midX, y: rects[.part(id)]!.midY) }
        #expect(r.click(at: center(.status)) == .open(AppInfo.statusPage) && r.wantsHand(at: center(.status)))
        // While an update runs the line is still a control: the hand, and no drag.
        #expect(r.click(at: center(.version)) == .nothing && r.wantsHand(at: center(.version)))
        #expect(r.classify(center(.version), isSecondary: false) == .control)
        #expect(r.click(at: center(.sessions)) == nil && !r.wantsHand(at: center(.sessions)))
        let clawd = r.rects(.sprite)[0]
        #expect(r.click(at: CGPoint(x: clawd.midX, y: clawd.midY)) == nil && r.wantsHand(at: CGPoint(x: clawd.midX, y: clawd.midY)))
    }

    @Test func eachPartIsAControlOrOnlyExplainsItself() {
        var view = WidgetViewState.sample
        let constant: [(CardPart.ID, CardClick?)] = [
            (.details, .toggleDetails), (.hide, .hide), (.exit, .quit), (.play, .play),
            (.status, .open(AppInfo.statusPage)), (.appVersion, .open(AppInfo.originalRepo)),
            (.reset, nil), (.sessions, nil), (.projectsLabel, nil), (.project(0), nil), (.account, nil),
        ]
        for (id, click) in constant { #expect(CardClick.on(id, in: view) == click, "\(id)") }
        let changelog = URL(string: "https://example.com/changelog")!
        let version: [(VersionAction, CardClick)] = [(.runUpdate, .runUpdate), (.open(changelog), .open(changelog)), (.none, .nothing)]
        for (action, click) in version {
            view.versionAction = action
            #expect(CardClick.on(.version, in: view) == click)
        }
    }

    @Test func tooltipTextsAreTheCurrentOnesAskedForWhenShown() {
        var view = WidgetViewState.sample
        view.show(.reset, tooltip: "reset why")
        view.show(.project(0), tooltip: "~/code/api")
        let hearts = HeartsFrame(visible: true, shownHalves: 4, tooltip: "a bit tired")
        func text(_ id: TooltipID) -> String { CardRegions.text(id, view: view, hearts: hearts) { "sky now" } }
        #expect(text(.part(.details)) == "Details" && text(.part(.reset)) == "reset why")
        #expect(text(.part(.sessions)) == view.part(.sessions)?.tooltip)
        #expect(text(.part(.project(0))) == "~/code/api")
        // A tooltip can outlive a part that has since gone.
        #expect(text(.part(.project(1))) == "" && text(.part(.play)) == "")
        #expect(text(.hearts) == "a bit tired")
        #expect(text(.sky) == "sky now")
    }
}
