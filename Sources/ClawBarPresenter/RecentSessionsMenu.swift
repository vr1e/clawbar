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
            let title = s.title.count > titleLimit ? s.title.prefix(titleLimit).trimmingCharacters(in: .whitespaces) + "…" : s.title
            let ago = Ago.text(since: s.lastActivity, now: input.now, timeZone: input.timeZone, lang: lang)
            var hint: [String] = []
            let click: RecentSessionClick?
            if s.isLive {
                hint.append(L10n.t(.recentRunning, lang, folder ?? "?"))
                if terminal { hint.append(L10n.t(.recentFocus, lang)) }
                click = terminal ? .focus : nil
            } else {
                hint.append(L10n.t(terminal ? .recentResume : .recentCopy, lang))
                click = .resume
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
