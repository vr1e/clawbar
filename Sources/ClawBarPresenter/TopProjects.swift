import Foundation
import ClawBarShared

/// history.ps1 Show-Projects: the week's four heaviest projects, each with its share of all of them, and the name the
/// chart's hover gives an hour's busiest one.
enum TopProjects {
    static let shown = 4

    /// `counting...` before the first scan; nil once a scan found no usage this week, as the original collapses ProjPanel.
    /// The parts are the label, saying how the shares are estimated, and a row per project with its folder.
    static func view(_ usage: ProjectUsage?, home: String, lang: Lang) -> (view: ProjectsView, parts: [CardPart])? {
        var view = ProjectsView(label: L10n.t(.uiProjects, lang))
        let label = CardPart(.projectsLabel, tooltip: tooltip(usage, lang: lang))
        guard let usage else {
            view.caption = L10n.t(.histCounting, lang)
            return (view, [label])
        }
        let total = usage.projects.reduce(0) { $0 + $1.weight }
        guard total > 0, total.isFinite else { return nil }
        let named = names(usage, home: home)
        // The scan sorts heaviest first, ties by path.
        let top = usage.projects.prefix(shown).indices
        view.rows = top.map { i in
            // Show-Projects multiplies before it divides, which decides which way an exact half rounds.
            let share = 100 * usage.projects[i].weight / total
            return ProjectRow(name: named[i].name, share: percent(share), fraction: max(2 / ProjectsView.trackWidth, share / 100))
        }
        return (view, [label] + top.map { CardPart(.project($0), tooltip: named[$0].path) })
    }

    /// The name of the project with the most weight in `minutes`; nil before the first scan or when none has weight
    /// then. A tie goes to the scan's order: the week's heavier one.
    static func busiest(in minutes: Range<Int>, of usage: ProjectUsage?, home: String) -> String? {
        guard let usage else { return nil }
        let weights = usage.projects.map { $0.weight(in: minutes) }
        guard let top = weights.max(), top > 0, let i = weights.firstIndex(of: top) else { return nil }
        return names(usage, home: home)[i].name
    }

    /// '{0:0}%' is a .NET format string, which rounds half away from zero, unlike the original's casts.
    static func percent(_ share: Double) -> String {
        "\(Int(share.rounded(.toNearestOrAwayFromZero)))%"
    }

    /// Each project's `~/…` path and its last part, with the parent when another of the week's projects shares it.
    private static func names(_ usage: ProjectUsage, home: String) -> [(path: String, name: String)] {
        let paths = usage.projects.map { HomePath.relative($0.path, home: home) }
        let leaves = paths.map { tail($0, 1) }
        let counts = leaves.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return zip(paths, leaves).map { path, leaf in (path, counts[leaf, default: 0] > 1 ? tail(path, 2) : leaf) }
    }

    /// The last `n` parts of a path; a transcript folder's name, which has no slash, stays whole.
    private static func tail(_ path: String, _ n: Int) -> String {
        let parts = path.split(separator: "/")
        return parts.isEmpty ? path : parts.suffix(n).joined(separator: "/")
    }

    private static func tooltip(_ usage: ProjectUsage?, lang: Lang) -> String {
        let tip = L10n.t(.histProjTip, lang)
        guard let unpriced = usage?.unpriced, unpriced > 0 else { return tip }
        return tip + "\n" + L10n.t(.histUnpriced, lang, L10n.count(unpriced, .pluralReply, lang))
    }
}
