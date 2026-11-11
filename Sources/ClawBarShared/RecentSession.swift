import Foundation

/// A session of the last 7 days, live or ended, as its transcript and the registry describe it.
public struct RecentSession: Sendable, Hashable {
    public var sessionId: String
    /// What it was named: by `/rename` or `claude -n`, else Claude Code's summary, else a name given in the registry.
    public var title: String?
    /// The folder it was started in, where `claude -r` finds it; empty when no line named one.
    public var cwd: String
    public var lastActivity: Date
    /// The user's last prompt, cut short. In memory only: never logged, dumped or written to disk.
    public var lastPrompt: String
    /// A live session's pid; nil once it ended.
    public var pid: Int32?

    public init(
        sessionId: String, title: String? = nil, cwd: String = "", lastActivity: Date, lastPrompt: String = "",
        pid: Int32? = nil
    ) {
        self.sessionId = sessionId
        self.title = title
        self.cwd = cwd
        self.lastActivity = lastActivity
        self.lastPrompt = lastPrompt
        self.pid = pid
    }

    public var isLive: Bool { pid != nil }

    /// A session id is a UUID: it names the transcript, and it is typed into a shell.
    public static func isSessionId(_ text: String) -> Bool { Rx.matches(uuid, text) }

    private static let uuid = Rx.make(#"^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z"#)
}

/// What a click on a recent session's menu item does.
public enum RecentSessionClick: Sendable, Hashable {
    /// An ended session: `claude -r` in its folder, in a new terminal tab.
    case resume
    /// An ended one with no terminal app to reach: the command goes on the clipboard.
    case copy
    /// A live one: its terminal comes forward, since a second process on the conversation would fork it.
    case focus
}

/// One item of the menu bar item's Recent sessions submenu.
public struct RecentSessionItem: Sendable, Hashable {
    public var sessionId: String
    /// `● Title · ~/folder · 2h`.
    public var title: String
    /// The last prompt and what a click does.
    public var tooltip: String
    /// nil for a live session with no terminal to bring forward.
    public var click: RecentSessionClick?

    public init(sessionId: String, title: String, tooltip: String = "", click: RecentSessionClick? = nil) {
        self.sessionId = sessionId
        self.title = title
        self.tooltip = tooltip
        self.click = click
    }
}
