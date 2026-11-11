import Foundation
import ClawBarShared

/// The menu bar item's Recent sessions submenu: each session's item and its tooltip.
public enum RecentSessionsMenu {
    static let limit = 15
    /// A `/rename` can be any length; the menu stays narrow.
    static let titleLimit = 60

    /// The newest `limit` sessions of the input's data snapshot. `terminal` says whether a click can reach a terminal
    /// app: without one a click copies the command, and a live session's item only informs.
    public static func items(_ input: PresenterInput, terminal: Bool) -> [RecentSessionItem] {
        let lang = input.config.lang
        return input.data.recentSessions.prefix(limit).map { s in
            let folder = s.cwd.isEmpty ? nil : HomePath.relative(s.cwd, home: input.homeDirectory)
            // Untitled, it goes by its folder's leaf, else by the start of its id.
            let leaf = (s.cwd as NSString).lastPathComponent
            let name = s.title ?? (leaf.isEmpty ? String(s.sessionId.prefix(8)) : leaf)
            let title = name.count > titleLimit ? name.prefix(titleLimit).trimmingCharacters(in: .whitespaces) + "…" : name
            let ago = Ago.text(since: s.lastActivity, now: input.now, timeZone: input.timeZone, lang: lang)
            let click = click(for: s, terminal: terminal)
            var hint = s.isLive ? [L10n.t(.recentRunning, lang, folder ?? "?")] : []
            switch click {
            case .focus?: hint.append(L10n.t(.recentFocus, lang))
            case .resume?: hint.append(L10n.t(.recentResume, lang))
            case .copy?: hint.append(L10n.t(.recentCopy, lang))
            case nil: break
            }
            return RecentSessionItem(
                sessionId: s.sessionId,
                title: (s.isLive ? "● " : "○ ") + [title, folder, ago].compactMap { $0 }.joined(separator: " · "),
                // The prompt shows here alone, never on the item.
                tooltip: [s.lastPrompt, hint.joined(separator: "\n")].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                click: click
            )
        }
    }

    /// What a click on a session's item does; nil for a live one with no terminal to bring forward. Asked again at
    /// the click, since the session may have started or ended while the menu was open.
    public static func click(for session: RecentSession, terminal: Bool) -> RecentSessionClick? {
        if session.isLive { return terminal ? .focus : nil }
        return terminal ? .resume : .copy
    }
}

/// The time since something happened, as short as the reset spans: `now`, `20m`, `2h`, `yesterday`, `3d`.
enum Ago {
    static func text(since then: Date, now: Date, timeZone: TimeZone, lang: Lang) -> String {
        let seconds = now.timeIntervalSince(then)
        if seconds < 60 { return L10n.t(.agoNow, lang) }
        if seconds < 3600 { return L10n.t(.spanM, lang, Int(seconds / 60)) }
        if seconds < 86_400 { return L10n.t(.agoH, lang, Int(seconds / 3600)) }
        // From a day on, calendar days in the input's zone: last night is yesterday, not 1d.
        let calendar = Calendar.gregorian(in: timeZone)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: then), to: calendar.startOfDay(for: now)).day ?? 1
        return days <= 1 ? L10n.t(.agoYesterday, lang) : L10n.t(.agoD, lang, days)
    }
}
