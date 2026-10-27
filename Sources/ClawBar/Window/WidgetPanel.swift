import AppKit
import ClawBarShared

/// The screens as placement sees them; injected so tests can plug and unplug monitors.
struct ScreenLayout: Equatable {
    /// `screens[0].frame.maxY`: WPF-style y counts down from the primary screen's top.
    var primaryMaxY: CGFloat
    var visibleFrames: [CGRect]
    /// Where a widget without a usable saved position goes, like the original's primary work area.
    var defaultVisibleFrame: CGRect

    static func current() -> ScreenLayout {
        let screens = NSScreen.screens
        return ScreenLayout(
            primaryMaxY: screens.first?.frame.maxY ?? 0,
            visibleFrames: screens.map(\.visibleFrame),
            defaultVisibleFrame: screens.first?.visibleFrame ?? .zero
        )
    }
}

enum PanelPlacement {
    /// The saved top-left when enough of the window still lands on a screen, else 20 pt in from the top-right.
    static func topLeft(saved: CGPoint?, size: CGSize, screens: ScreenLayout) -> CGPoint {
        WindowPlacement.validated(topLeft: saved, size: size, visibleFrames: screens.visibleFrames, primaryMaxY: screens.primaryMaxY)
            ?? WindowPlacement.defaultTopLeft(size: size, visibleFrame: screens.defaultVisibleFrame, primaryMaxY: screens.primaryMaxY)
    }
}

/// Where a mouse-down on the widget goes.
enum PanelRoute: Equatable {
    case clawd
    case devMenu
    case drag
    case control(CardClick)
    /// Not ours: AppKit's normal handling.
    case pass
}

/// What the panel asks of the app.
@MainActor
protocol WidgetPanelDelegate: AnyObject {
    func regions() -> CardRegions
    func clawdClicked()
    func clicked(_ click: CardClick)
    func developerMenu() -> NSMenu?
    /// The pointer moved over the widget, in card space.
    func pointerMoved(to p: CGPoint)
    func pointerLeft()
}

/// The floating widget: borderless, never key, never activating the app, on every Space.
final class WidgetPanel: NSPanel {
    weak var widgetDelegate: WidgetPanelDelegate?
    var screens: @MainActor () -> ScreenLayout = { ScreenLayout.current() }
    private(set) var isTopmost = false

    init(content: NSView) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 262, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        allowsToolTipsWhenApplicationIsInactive = true
        isReleasedWhenClosed = false
        contentView = content
        apply(topmost: false)
        content.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil
        ))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(topmost: Bool) {
        isTopmost = topmost
        level = topmost ? .floating : .normal
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if topmost { behavior.insert(.fullScreenAuxiliary) }
        collectionBehavior = behavior
    }

    // MARK: Placement

    /// The frame's top-left, WPF-style.
    var topLeft: CGPoint { WindowPlacement.topLeft(of: frame, primaryMaxY: screens().primaryMaxY) }

    func place(topLeft: CGPoint) {
        setFrame(WindowPlacement.frame(topLeft: topLeft, size: frame.size, primaryMaxY: screens().primaryMaxY), display: true)
    }

    /// Sizes the window to the card, keeping its top-left where it is; the shadow follows the new shape.
    func fit(contentSize size: CGSize) {
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        let tl = topLeft
        setFrame(WindowPlacement.frame(topLeft: tl, size: size, primaryMaxY: screens().primaryMaxY), display: true)
        invalidateShadow()
    }

    /// After the screens changed: keep the top-left while enough of the window shows, else move to the default.
    /// Returns whether the window moved.
    @discardableResult
    func revalidatePlacement() -> Bool {
        let s = screens()
        let tl = PanelPlacement.topLeft(saved: topLeft, size: frame.size, screens: s)
        guard tl != topLeft else { return false }
        place(topLeft: tl)
        return true
    }

    // MARK: Events

    /// The one choke point for clicks: Clawd, the developer menu, drags and controls, from the card's regions.
    func route(_ event: NSEvent) -> PanelRoute {
        guard event.type == .leftMouseDown || event.type == .rightMouseDown, let regions = widgetDelegate?.regions() else { return .pass }
        let p = cardPoint(event.locationInWindow)
        let secondary = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
        switch regions.classify(p, isSecondary: secondary) {
        case .clawd: return .clawd
        case .menu: return .devMenu
        case .drag: return .drag
        case .control:
            if !secondary, let click = regions.click(at: p) { return .control(click) }
            return .pass
        }
    }

    override func sendEvent(_ event: NSEvent) {
        let r = route(event)
        // Clicking a normal-level widget raises it, without activating the app.
        if event.type == .leftMouseDown || event.type == .rightMouseDown, !isTopmost { orderFrontRegardless() }
        switch r {
        case .clawd: widgetDelegate?.clawdClicked()
        case .devMenu:
            if let menu = widgetDelegate?.developerMenu(), let view = contentView {
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            }
        case .drag: performDrag(with: event)
        case .control(let click): widgetDelegate?.clicked(click)
        case .pass: super.sendEvent(event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = cardPoint(event.locationInWindow)
        let hand = widgetDelegate?.regions().wantsHand(at: p) ?? false
        (hand ? NSCursor.pointingHand : NSCursor.arrow).set()
        widgetDelegate?.pointerMoved(to: p)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        widgetDelegate?.pointerLeft()
    }

    /// A panel ordered out from under the pointer gets no exit event.
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        widgetDelegate?.pointerLeft()
    }

    /// Window coordinates to card space: points with the origin at the card's top-left.
    func cardPoint(_ windowPoint: CGPoint) -> CGPoint {
        guard let view = contentView else { return windowPoint }
        let p = view.convert(windowPoint, from: nil)
        return view.isFlipped ? p : CGPoint(x: p.x, y: view.bounds.height - p.y)
    }
}
