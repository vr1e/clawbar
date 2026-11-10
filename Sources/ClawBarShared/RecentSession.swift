import Foundation

/// Where a recent session's title came from, best first.
public enum SessionTitleSource: String, Sendable, CaseIterable {
    /// `/rename` or `claude -n`.
    case custom
    /// Claude Code's own summary of the conversation.
    case ai
    /// The registry's name, when it was given and not derived from the folder.
    case registry
    /// The leaf of its folder.
    case folder
}

/// A session of the last 7 days, live or ended, as its transcript and the registry describe it.
public struct RecentSession: Sendable, Hashable {
    public var sessionId: String
    public var title: String
    public var titleSource: SessionTitleSource
    /// The folder it was started in, where `claude -r` finds it; empty when no line named one.
    public var cwd: String
    public var lastActivity: Date
    /// The user's last prompt, cut short. In memory only: never logged, dumped or written to disk.
    public var lastPrompt: String
    /// A live session's pid and state; nil once it ended.
    public var pid: Int32?
    public var state: SessionState?

    public init(
        sessionId: String, title: String, titleSource: SessionTitleSource, cwd: String = "", lastActivity: Date,
        lastPrompt: String = "", pid: Int32? = nil, state: SessionState? = nil
    ) {
        self.sessionId = sessionId
        self.title = title
        self.titleSource = titleSource
        self.cwd = cwd
        self.lastActivity = lastActivity
        self.lastPrompt = lastPrompt
        self.pid = pid
        self.state = state
    }

    public var isLive: Bool { state != nil }
}

/// What a click on a recent session's menu item does.
public enum RecentSessionClick: Sendable, Hashable {
    /// An ended session: `claude -r` in its folder.
    case resume
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
