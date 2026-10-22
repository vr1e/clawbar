import CoreGraphics
import ClawBarShared

/// The card's interactive regions in card space, assembled from what SwiftUI published and Clawd's sprite.
struct WidgetHitMap {
    var controls: [(id: HitID, rect: CGRect)] = []
    var sprite: CGRect?
    var sky: CGRect?
    var number: CGRect?
    /// The 7-day chart, which reads out what lies under the pointer; not a control, so it still drags.
    var chart: CGRect?

    func classify(_ p: CGPoint, isSecondary: Bool) -> WidgetHit {
        // The number lies over the sky and has no menu of its own, as in WPF where the menu hangs on the Sky border.
        let sky = (number?.contains(p) ?? false) ? nil : self.sky
        return classifyHit(p, isSecondary: isSecondary, controls: controls.map(\.rect), sprite: sprite, sky: sky)
    }

    func control(at p: CGPoint) -> HitID? {
        controls.first { $0.rect.contains(p) }?.id
    }

    /// The point's x in the chart's base units, or nil off the chart.
    func chartX(at p: CGPoint) -> Double? {
        guard let chart, chart.contains(p) else { return nil }
        return (p.x - chart.minX) / chart.width * HistoryView.width
    }

    /// Controls are the elements whose MouseLeftButtonDown handlers mark the click handled in events.ps1.
    static func make(
        layout: LayoutModel, view: WidgetViewState, spriteRect: CGRect, scale k: Double, mascotVisible: Bool, skyVisible: Bool
    ) -> WidgetHitMap {
        var ids: [HitID] = [.details, .hide, .exit]
        if view.limitReached { ids.append(.play) }
        if view.statusVisible { ids.append(.status) }
        if view.detailsExpanded { ids += view.versionText.isEmpty ? [.appVersion] : [.version, .appVersion] }
        var map = WidgetHitMap()
        map.controls = ids.compactMap { id in layout.rects[id].map { (id, $0) } }
        map.number = layout.rects[.number]
        // A closed chart's rect stays published where it last was.
        if view.history != nil { map.chart = layout.rects[.history] }
        guard let row = layout.rects[.percentRow] else { return map }
        if skyVisible {
            map.sky = CGRect(x: row.minX, y: row.minY, width: row.width, height: PlayArea.height * k)
        }
        if mascotVisible, !spriteRect.isEmpty {
            let ground = PlayArea.ground(row: row, numberWidth: layout.numberWidth, scale: k)
            map.sprite = CGRect(
                x: ground.x + spriteRect.minX * k, y: ground.y + spriteRect.minY * k,
                width: spriteRect.width * k, height: spriteRect.height * k
            )
        }
        return map
    }
}

/// Clawd's play area: right of the number with MascotArea's margin 10, its bottom edge 3 below the row.
enum PlayArea {
    /// The percent row's 40 plus the 3 it reaches below it: its bottom is the ground line.
    static let height = 43.0
    /// MascotArea's left margin after the number.
    static let margin = 10.0

    static func width(numberWidth: Double) -> Double {
        max(0, CardView.content - numberWidth - margin)
    }

    /// The play area's left end of the ground line in card space.
    static func ground(row: CGRect, numberWidth: Double, scale k: Double) -> CGPoint {
        CGPoint(x: row.minX + (numberWidth + margin) * k, y: row.minY + height * k)
    }
}
