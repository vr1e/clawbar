import Foundation
import ClawBarShared

/// history.ps1 Show-Projects: the week's four heaviest projects, each with its share of all of them.
enum TopProjects {
    static let shown = 4

    /// `counting...` before the first scan; nil once a scan found no usage this week, as the original collapses ProjPanel.
    static func view(_ usage: ProjectUsage?, home: String, lang: Lang) -> ProjectsView? {
        var view = ProjectsView(label: L10n.t(.uiProjects, lang), tooltip: tooltip(usage, lang: lang))
        guard let usage else {
            view.caption = L10n.t(.histCounting, lang)
            return view
        }
        let total = usage.projects.reduce(0) { $0 + $1.weight }
        guard total > 0, total.isFinite else { return nil }
        // The scan sorts heaviest first, ties by path.
        let top = Array(usage.projects.prefix(shown))
        let paths = top.map { HomePath.relative($0.path, home: home) }
        let rowNames = names(paths)
        view.rows = top.indices.map { i in
            // Show-Projects multiplies before it divides, which decides which way an exact half rounds.
            let share = 100 * top[i].weight / total
            return ProjectRow(
                name: rowNames[i], share: percent(share), fraction: max(2 / ProjectsView.trackWidth, share / 100),
                tooltip: paths[i]
            )
        }
        return view
    }

    /// '{0:0}%' is a .NET format string, which rounds half away from zero, unlike the original's casts.
    static func percent(_ share: Double) -> String {
        "\(Int(share.rounded(.toNearestOrAwayFromZero)))%"
    }

    /// Each `~/…` path's last part, so `~` for the home folder; rows that would read the same also show their parent.
    static func names(_ paths: [String]) -> [String] {
        let leaves = paths.map { tail($0, 1) }
        return zip(paths, leaves).map { path, leaf in
            leaves.filter { $0 == leaf }.count > 1 ? tail(path, 2) : leaf
        }
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
