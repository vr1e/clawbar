import CoreGraphics
import ClawBarShared

/// Which parts of the card carry a tooltip, and what each says right now. An empty tooltip registers nothing.
enum TooltipLayout {
    static func regions(
        rects: [HitID: CGRect], view v: WidgetViewState, heartsVisible: Bool, mascotVisible: Bool, skyVisible: Bool, scale k: Double
    ) -> [TooltipRegion] {
        var out: [TooltipRegion] = []
        func add(_ id: HitID, when shown: Bool = true) {
            guard shown, !text(.hit(id), view: v, hearts: .hidden, sky: { "" }).isEmpty, let r = rects[id] else { return }
            out.append(TooltipRegion(id: .hit(id), rect: r))
        }
        add(.details)
        add(.hide)
        add(.exit)
        // The hearts' text changes every tick; it is read when shown, so only visibility matters here.
        if heartsVisible, mascotVisible, let r = rects[.hearts] { out.append(TooltipRegion(id: .hit(.hearts), rect: r)) }
        add(.reset, when: !v.resetText.isEmpty)
        add(.play, when: v.limitReached)
        add(.sessions, when: v.sessionsVisible)
        add(.status, when: v.statusVisible)
        add(.projectsLabel, when: v.projects != nil)
        // Every row is one line and its 2 below, so the block splits evenly into a tooltip per row, as each Grid has its own.
        if let rows = v.projects?.rows, !rows.isEmpty, let block = rects[.projects] {
            let h = block.height / Double(rows.count)
            for i in rows.indices {
                out.append(TooltipRegion(id: .project(i), rect: CGRect(x: block.minX, y: block.minY + Double(i) * h, width: block.width, height: h)))
            }
        }
        add(.version, when: v.detailsExpanded && !v.versionText.isEmpty)
        add(.appVersion, when: v.detailsExpanded)
        add(.account, when: !v.accountText.isEmpty)
        // WPF routes the hover over the number to the number, which has no tooltip; the sky gets the rest of the row.
        if skyVisible, let row = rects[.percentRow] {
            let left = rects[.number]?.maxX ?? row.minX
            out.append(TooltipRegion(id: .sky, rect: CGRect(x: left, y: row.minY, width: max(0, row.maxX - left), height: PlayArea.height * k)))
        }
        return out
    }

    static func text(_ id: TooltipID, view v: WidgetViewState, hearts: HeartsFrame, sky: () -> String) -> String {
        switch id {
        case .sky: sky()
        case .project(let i): v.projects.flatMap { $0.rows.indices.contains(i) ? $0.rows[i].tooltip : nil } ?? ""
        case .hit(let h):
            switch h {
            case .details: v.detailsTooltip
            case .hide: v.hideTooltip
            case .exit: v.exitTooltip
            case .hearts: hearts.tooltip
            case .reset: v.resetTooltip
            case .play: v.playTooltip
            case .sessions: v.sessionsTooltip
            case .status: v.statusTooltip
            case .version: v.versionTooltip
            case .appVersion: v.appVersionTooltip
            case .account: v.accountTooltip
            case .projectsLabel: v.projects?.tooltip ?? ""
            case .percentRow, .number, .history, .projects: ""
            }
        }
    }
}
