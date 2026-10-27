import AppKit
import Testing
@testable import ClawBar
import ClawBarShared

/// Screens the test can swap under a live panel.
@MainActor
final class ScreenBox {
    var layout: ScreenLayout
    init(_ layout: ScreenLayout) { self.layout = layout }
}

@MainActor
@Suite struct PanelPlacementTests {
    // A 1512 × 982 primary screen with a 33-pt menu bar, and a 1920 × 1080 screen to its right.
    let primaryVisible = CGRect(x: 0, y: 0, width: 1512, height: 949)
    let rightVisible = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    var both: ScreenLayout { ScreenLayout(primaryMaxY: 982, visibleFrames: [primaryVisible, rightVisible], defaultVisibleFrame: primaryVisible) }
    var primaryOnly: ScreenLayout { ScreenLayout(primaryMaxY: 982, visibleFrames: [primaryVisible], defaultVisibleFrame: primaryVisible) }
    // Whole points: AppKit snaps window frames to the pixel grid, as SwiftUI's card sizes already are.
    let size = CGSize(width: 314, height: 300)

    func panel(_ box: ScreenBox) -> WidgetPanel {
        let p = WidgetPanel(content: NSView())
        p.screens = { box.layout }
        p.fit(contentSize: size)
        return p
    }

    @Test func aSavedPositionOnAnyScreenIsKept() {
        #expect(PanelPlacement.topLeft(saved: CGPoint(x: 2000, y: 100), size: size, screens: both) == CGPoint(x: 2000, y: 100))
    }

    @Test func withoutAUsableSavedPositionTheWidgetSitsTwentyPointsInFromTheTopRight() {
        let expected = CGPoint(x: 1512 - 20 - 314, y: 33 + 20)
        #expect(PanelPlacement.topLeft(saved: nil, size: size, screens: both) == expected)
        #expect(PanelPlacement.topLeft(saved: CGPoint(x: 2000, y: 100), size: size, screens: primaryOnly) == expected)
    }

    @Test func unpluggingTheScreenItWasOnMovesTheWidgetHome() {
        let box = ScreenBox(both)
        let p = panel(box)
        p.place(topLeft: CGPoint(x: 2000, y: 100))
        #expect(p.topLeft == CGPoint(x: 2000, y: 100))
        box.layout = primaryOnly
        #expect(p.revalidatePlacement())
        #expect(p.topLeft == CGPoint(x: 1512 - 20 - 314, y: 53))
        #expect(p.frame.size == size)
    }

    @Test func aPositionThatStillShowsSurvivesAScreenChange() {
        let box = ScreenBox(primaryOnly)
        let p = panel(box)
        p.place(topLeft: CGPoint(x: 100, y: 100))
        box.layout = both
        #expect(!p.revalidatePlacement())
        #expect(p.topLeft == CGPoint(x: 100, y: 100))
    }

    @Test func growingTheCardKeepsTheTopLeftWhereItWas() {
        let p = panel(ScreenBox(both))
        p.place(topLeft: CGPoint(x: 100, y: 100))
        p.fit(contentSize: CGSize(width: 314, height: 420))
        #expect(p.topLeft == CGPoint(x: 100, y: 100))
        #expect(p.frame == CGRect(x: 100, y: 982 - 100 - 420, width: 314, height: 420))
    }

    @Test func topmostFloatsAboveFullScreenAppsAndNormalStaysOnEverySpace() {
        let p = panel(ScreenBox(both))
        p.apply(topmost: true)
        #expect(p.level == .floating)
        #expect(p.collectionBehavior.contains([.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]))
        p.apply(topmost: false)
        #expect(p.level == .normal)
        #expect(p.collectionBehavior.contains([.canJoinAllSpaces, .stationary, .ignoresCycle]))
        #expect(!p.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    @Test func thePanelNeverTakesFocusAndShowsTooltipsWhileTheAppIsInactive() {
        let p = panel(ScreenBox(both))
        #expect(!p.canBecomeKey && !p.canBecomeMain)
        #expect(p.styleMask.contains([.borderless, .nonactivatingPanel]))
        #expect(!p.hidesOnDeactivate && !p.isOpaque && p.hasShadow)
        #expect(p.backgroundColor == .clear)
        #expect(p.allowsToolTipsWhenApplicationIsInactive)
    }
}

/// Mouse-downs through the panel's real routing: window coordinates, card space, published rects.
@MainActor
final class StubPanelDelegate: WidgetPanelDelegate {
    let card: LaidOutCard
    /// The pointer as the panel reported it, nil once it left.
    var pointer: CGPoint?
    init(_ card: LaidOutCard) { self.card = card }
    func regions() -> CardRegions { card.regions }
    func clawdClicked() {}
    func clicked(_ click: CardClick) {}
    func developerMenu() -> NSMenu? { nil }
    func pointerMoved(to p: CGPoint, over regions: CardRegions) { pointer = p }
    func pointerLeft() { pointer = nil }
}

@MainActor
@Suite struct PanelRouteTests {
    func setUp() -> (WidgetPanel, LaidOutCard, StubPanelDelegate) {
        let card = LaidOutCard()
        let panel = WidgetPanel(content: card.host)
        panel.fit(contentSize: card.layout.cardSize)
        card.host.layoutSubtreeIfNeeded()
        let delegate = StubPanelDelegate(card)
        panel.widgetDelegate = delegate
        return (panel, card, delegate)
    }

    func event(_ type: NSEvent.EventType, at p: CGPoint, in panel: WidgetPanel, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        let view = panel.contentView!
        let windowPoint = CGPoint(x: p.x, y: view.bounds.height - p.y)
        return NSEvent.mouseEvent(
            with: type, location: windowPoint, modifierFlags: flags, timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    @Test func windowPointsLandInCardSpace() throws {
        let (panel, card, _) = setUp()
        let p = try card.center(.hide)
        let e = event(.leftMouseDown, at: p, in: panel)
        let back = panel.cardPoint(e.locationInWindow)
        #expect(abs(back.x - p.x) < 0.01 && abs(back.y - p.y) < 0.01)
    }

    @Test func leftDownsRouteToDragClawdOrTheControl() throws {
        let (panel, card, delegate) = setUp()
        _ = delegate
        #expect(panel.route(event(.leftMouseDown, at: try card.center(.number), in: panel)) == .drag)
        let sprite = try #require(card.regions.rects(.sprite).first)
        #expect(panel.route(event(.leftMouseDown, at: CGPoint(x: sprite.midX, y: sprite.midY), in: panel)) == .clawd)
        #expect(panel.route(event(.leftMouseDown, at: try card.center(.hide), in: panel)) == .control(.hide))
        #expect(panel.route(event(.leftMouseDown, at: try card.center(.status), in: panel)) == .control(.open(AppInfo.statusPage)))
    }

    @Test func rightAndControlClicksOpenTheMenuOnlyOverClawdAndTheSky() throws {
        let (panel, card, delegate) = setUp()
        _ = delegate
        let row = try card.rect(.percentRow)
        let sky = CGPoint(x: row.maxX - 8 * card.k, y: row.minY + 8 * card.k)
        #expect(panel.route(event(.rightMouseDown, at: sky, in: panel)) == .devMenu)
        #expect(panel.route(event(.leftMouseDown, at: sky, in: panel, flags: .control)) == .devMenu)
        #expect(panel.route(event(.rightMouseDown, at: try card.center(.number), in: panel)) == .pass)
        #expect(panel.route(event(.rightMouseDown, at: try card.center(.hide), in: panel)) == .pass)
    }

    @Test func thePointerReachesTheAppInCardSpaceUntilItLeaves() throws {
        let (panel, card, delegate) = setUp()
        let p = try card.center(.number)
        panel.mouseMoved(with: event(.mouseMoved, at: p, in: panel))
        let reported = try #require(delegate.pointer)
        #expect(abs(reported.x - p.x) < 0.01 && abs(reported.y - p.y) < 0.01)
        let exit = NSEvent.enterExitEvent(
            with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        )!
        panel.mouseExited(with: exit)
        #expect(delegate.pointer == nil)
    }

    @Test func otherEventsAreLeftToAppKit() throws {
        let (panel, card, delegate) = setUp()
        _ = delegate
        #expect(panel.route(event(.leftMouseUp, at: try card.center(.hide), in: panel)) == .pass)
        #expect(panel.route(event(.mouseMoved, at: try card.center(.number), in: panel)) == .pass)
    }
}
