import CoreGraphics
import Foundation
import ClawBarShared

/// What a click on a control does.
enum CardClick: Equatable {
    case toggleDetails, hide, quit, play
    case open(URL)
    case runUpdate
    /// The version line while an update runs: still a control, so the click does not drag the window.
    case nothing

    /// Which parts are controls, as events.ps1's MouseLeftButtonDown handlers mark their clicks handled, and what a
    /// click on one does now; nil for a part that only explains itself, which drags the window.
    static func on(_ id: CardPart.ID, in view: WidgetViewState) -> CardClick? {
        switch id {
        case .details: .toggleDetails
        case .hide: .hide
        case .exit: .quit
        case .play: .play
        case .status: .open(AppInfo.statusPage)
        case .appVersion: .open(AppInfo.originalRepo)
        case .version:
            switch view.versionAction {
            case .runUpdate: .runUpdate
            case .open(let url): .open(url)
            case .none: .nothing
            }
        case .reset, .sessions, .projectsLabel, .project, .account: nil
        }
    }
}

/// A rect of the card with one role, in card space.
struct CardRegion: Equatable {
    enum Role: Equatable {
        case control(CardClick)
        case tooltip(TooltipID)
        /// The 7-day chart, which reads out the minute under the pointer; not a control, so it still drags.
        case chart
        /// The sky's tooltip, and the developer menu on a secondary click.
        case sky
        /// Clawd: a click pets him, a secondary click opens the developer menu.
        case sprite
    }

    var rect: CGRect
    var role: Role
}

/// The card's regions, from the shown parts, the rects SwiftUI published, Clawd's sprite and the hearts.
/// Derived on every call, never kept: a click resolved from an older view state could start a second update.
struct CardRegions {
    var all: [CardRegion] = []

    static func make(app: AppModel, animation: AnimationModel, layout: LayoutModel) -> CardRegions {
        let view = app.view, rects = layout.rects, k = app.scale
        var regions = CardRegions()
        func add(_ rect: CGRect?, _ role: CardRegion.Role) {
            if let rect { regions.all.append(CardRegion(rect: rect, role: role)) }
        }
        // A hidden part's rect stays published where it last was, so only the shown parts are read.
        for part in view.parts {
            guard let rect = rects[.part(part.id)] else { continue }
            if let click = CardClick.on(part.id, in: view) { add(rect, .control(click)) }
            if !part.tooltip.isEmpty { add(rect, .tooltip(.part(part.id))) }
        }
        // The hearts' text changes every tick; it is read when shown, so only visibility matters here.
        if animation.hearts.visible, app.mascotVisible { add(rects[.hearts], .tooltip(.hearts)) }
        if view.history != nil { add(rects[.history], .chart) }
        guard let row = rects[.percentRow] else { return regions }
        if app.skyVisible {
            let band = CGRect(x: row.minX, y: row.minY, width: row.width, height: PlayArea.height * k)
            for rect in sky(band: band, number: rects[.number]) { add(rect, .sky) }
        }
        let sprite = animation.clawd.spriteRect
        if app.mascotVisible, !sprite.isEmpty {
            let ground = PlayArea.ground(row: row, numberWidth: layout.numberWidth, scale: k)
            add(CGRect(
                x: ground.x + sprite.minX * k, y: ground.y + sprite.minY * k, width: sprite.width * k, height: sprite.height * k
            ), .sprite)
        }
        return regions
    }

    /// The number covers the sky: WPF routes the pointer over it to the number, which has neither tooltip nor menu,
    /// and the rest of the band, the strip under the number included, to the sky. Right of the number the sky stays one
    /// rect, so its tooltip does not close as the pointer moves down past the number.
    private static func sky(band b: CGRect, number: CGRect?) -> [CGRect] {
        guard let n = number, n.intersects(b) else { return [b] }
        let left = max(n.minX, b.minX), right = min(n.maxX, b.maxX), top = max(n.minY, b.minY), bottom = min(n.maxY, b.maxY)
        return [
            CGRect(x: right, y: b.minY, width: b.maxX - right, height: b.height),
            CGRect(x: b.minX, y: b.minY, width: left - b.minX, height: b.height),
            CGRect(x: left, y: b.minY, width: right - left, height: top - b.minY),
            CGRect(x: left, y: bottom, width: right - left, height: b.maxY - bottom),
        ].filter { !$0.isEmpty }
    }

    /// What a tooltip says when it shows: a part's from the view, nothing once the part has gone; the hearts' and the
    /// sky's from the moving side.
    static func text(_ id: TooltipID, view: WidgetViewState, hearts: HeartsFrame, sky: () -> String) -> String {
        switch id {
        case .part(let part): view.part(part)?.tooltip ?? ""
        case .hearts: hearts.tooltip
        case .sky: sky()
        }
    }

    func classify(_ p: CGPoint, isSecondary: Bool) -> WidgetHit {
        classifyHit(p, isSecondary: isSecondary, controls: controls.map(\.rect), sprite: rects(.sprite).first, sky: rects(.sky))
    }

    func click(at p: CGPoint) -> CardClick? {
        controls.first { $0.rect.contains(p) }?.click
    }

    func wantsHand(at p: CGPoint) -> Bool {
        click(at: p) != nil || rects(.sprite).contains { $0.contains(p) }
    }

    /// The point's x in the chart's base units, or nil off the chart.
    func chartX(at p: CGPoint) -> Double? {
        guard let chart = rects(.chart).first, chart.contains(p) else { return nil }
        return (p.x - chart.minX) / chart.width * HistoryView.width
    }

    var tooltips: [TooltipRegion] {
        all.compactMap { region in
            switch region.role {
            case .tooltip(let id): TooltipRegion(id: id, rect: region.rect)
            case .sky: TooltipRegion(id: .sky, rect: region.rect)
            case .control, .chart, .sprite: nil
            }
        }
    }

    private var controls: [(click: CardClick, rect: CGRect)] {
        all.compactMap { region in
            guard case .control(let click) = region.role else { return nil }
            return (click, region.rect)
        }
    }

    func rects(_ role: CardRegion.Role) -> [CGRect] {
        all.filter { $0.role == role }.map(\.rect)
    }
}
