import CoreGraphics

/// Converts between AppKit frames (bottom-left origin) and the saved WPF-style top-left:
/// x from the primary screen's left edge, y down from its top edge.
public enum WindowPlacement {
    public static func frame(topLeft: CGPoint, size: CGSize, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: topLeft.x, y: primaryMaxY - topLeft.y - size.height, width: size.width, height: size.height)
    }

    public static func topLeft(of frame: CGRect, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX, y: primaryMaxY - frame.maxY)
    }

    /// The minimum of the window that must stay on one screen to keep a saved position.
    public static let minimumVisible = CGSize(width: 60, height: 30)

    /// The saved top-left when enough of the window lands on some screen's visible area, else nil.
    public static func validated(topLeft: CGPoint?, size: CGSize, visibleFrames: [CGRect], primaryMaxY: CGFloat) -> CGPoint? {
        guard let topLeft else { return nil }
        let f = frame(topLeft: topLeft, size: size, primaryMaxY: primaryMaxY)
        let needW = min(minimumVisible.width, size.width), needH = min(minimumVisible.height, size.height)
        for screen in visibleFrames {
            let i = f.intersection(screen)
            if !i.isNull, i.width >= needW, i.height >= needH { return topLeft }
        }
        return nil
    }

    /// A window that grew from `old` to `new` (AppKit frames), moved up and left only as far as its growth pushed it
    /// past the bottom and right of `visible`, and never past the top or left; a deliberate overhang stays as it was.
    public static func keptOnScreen(_ new: CGRect, was old: CGRect, visible: CGRect) -> CGRect {
        func overhang(_ edge: CGFloat, _ limit: CGFloat) -> CGFloat { max(0, limit - edge) }
        let up = max(0, overhang(new.minY, visible.minY) - overhang(old.minY, visible.minY))
        let left = max(0, overhang(visible.maxX, new.maxX) - overhang(visible.maxX, old.maxX))
        return new.offsetBy(
            dx: -min(left, max(0, new.minX - visible.minX)),
            dy: min(up, max(0, visible.maxY - new.maxY))
        )
    }

    /// 20 pt in from the top-right of a screen's visible area, measured with the real scaled size.
    public static func defaultTopLeft(size: CGSize, visibleFrame: CGRect, primaryMaxY: CGFloat) -> CGPoint {
        let margin: CGFloat = 20
        return CGPoint(x: visibleFrame.maxX - margin - size.width, y: primaryMaxY - visibleFrame.maxY + margin)
    }
}

/// What a mouse-down on the widget means.
public enum WidgetHit: Sendable, Hashable {
    /// Move the window.
    case drag
    /// A left click on Clawd.
    case clawd
    /// The developer menu: a secondary click on Clawd or the sky.
    case menu
    /// Leave it to the view under the pointer.
    case control
}

/// Sorts a mouse-down; all rects in one coordinate space. `isSecondary` is a right click or a ctrl-click.
public func classifyHit(_ point: CGPoint, isSecondary: Bool, controls: [CGRect], sprite: CGRect?, sky: [CGRect]) -> WidgetHit {
    let onSprite = sprite?.contains(point) ?? false
    if isSecondary {
        return onSprite || sky.contains(where: { $0.contains(point) }) ? .menu : .control
    }
    if onSprite { return .clawd }
    if controls.contains(where: { $0.contains(point) }) { return .control }
    return .drag
}
