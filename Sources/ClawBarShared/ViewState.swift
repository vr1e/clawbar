import Foundation

/// Everything `WidgetPresenter.make` reads. The clock and the zone come in here, never from the system.
public struct PresenterInput: Sendable, Hashable {
    public var config: Config
    public var now: Date
    /// For the HH:mm:ss stamp and reset spans.
    public var timeZone: TimeZone
    public var data: DataSnapshot
    /// The last data tick threw: the stamp says "error".
    public var tickError: Bool
    /// "0.1.0".
    public var appVersion: String
    /// Session cwds under it are shown as `~/…`.
    public var homeDirectory: String

    public init(
        config: Config, now: Date, timeZone: TimeZone, data: DataSnapshot, tickError: Bool = false,
        appVersion: String = AppInfo.version, homeDirectory: String = ""
    ) {
        self.config = config
        self.now = now
        self.timeZone = timeZone
        self.data = data
        self.tickError = tickError
        self.appVersion = appVersion
        self.homeDirectory = homeDirectory
    }
}

/// A labelled row with a thin bar under it: WEEK, or a model's week.
public struct BarRow: Sendable, Hashable {
    public var label: String
    public var value: String
    /// 0...1 of the content width.
    public var fraction: Double
    public var color: RGBA

    public init(label: String, value: String, fraction: Double, color: RGBA) {
        self.label = label
        self.value = value
        self.fraction = fraction
        self.color = color
    }
}

/// What clicking the Claude Code version line does.
public enum VersionAction: Sendable, Hashable {
    case none
    case runUpdate
    case open(URL)
}

/// Every string, colour, fraction, visibility and tooltip of the widget and the menu bar item.
/// An empty tooltip means none; an empty line text hides that line.
public struct WidgetViewState: Sendable, Hashable {
    // Header
    public var title: String
    /// ▾ closed, ▴ open.
    public var detailsGlyph: String
    public var detailsTooltip: String
    public var hideTooltip: String
    public var exitTooltip: String

    // Percent row and session bar
    /// The number without `%` ("42"), or "--".
    public var pctText: String
    public var pctColor: RGBA
    public var sessionFraction: Double
    public var sessionBarColor: RGBA

    // Reset line
    public var resetText: String
    public var resetColor: RGBA
    public var resetTooltip: String

    // Clawd Run
    /// The session limit is used up: the card and the menu offer the game.
    public var limitReached: Bool
    /// The link under the reset line; empty hides it.
    public var playText: String
    public var playTooltip: String

    // Week and model weeks
    public var week: BarRow
    public var modelWeeks: [BarRow]

    // Sessions
    public var sessionsVisible: Bool
    public var sessionsLabel: String
    public var sessionsText: String
    /// One line per session.
    public var sessionsTooltip: String

    // Service status
    public var statusVisible: Bool
    public var statusDotColor: RGBA
    public var statusText: String
    public var statusTextColor: RGBA
    /// Broken components; empty hides the second line.
    public var statusLine2: String
    public var statusTooltip: String
    public var statusURL: URL

    // Details
    public var detailsExpanded: Bool
    public var statsVisible: Bool
    public var dayLabel: String
    public var dayMain: String
    public var dayExtra: String
    public var week7Label: String
    public var week7Main: String
    public var week7Extra: String
    public var versionText: String
    public var versionColor: RGBA
    public var versionTooltip: String
    public var versionAction: VersionAction
    /// "ClawBar v0.1.0".
    public var appVersionText: String
    public var appVersionTooltip: String
    public var appVersionURL: URL

    // Footer
    public var accountText: String
    public var accountColor: RGBA
    public var accountTooltip: String
    public var stampText: String
    public var stampColor: RGBA

    // Menu bar item
    /// The number without `%`, or "--".
    public var trayText: String
    public var trayColor: RGBA
    public var trayTooltip: String

    public init(
        title: String = "CLAUDE USAGE",
        detailsGlyph: String = "▾",
        detailsTooltip: String = "",
        hideTooltip: String = "",
        exitTooltip: String = "",
        pctText: String = "--",
        pctColor: RGBA = Palette.dead,
        sessionFraction: Double = 0,
        sessionBarColor: RGBA = Palette.dead,
        resetText: String = "",
        resetColor: RGBA = Palette.secondary,
        resetTooltip: String = "",
        limitReached: Bool = false,
        playText: String = "",
        playTooltip: String = "",
        week: BarRow = BarRow(label: "WEEK", value: "", fraction: 0, color: Palette.weekBar),
        modelWeeks: [BarRow] = [],
        sessionsVisible: Bool = true,
        sessionsLabel: String = "SESSIONS",
        sessionsText: String = "",
        sessionsTooltip: String = "",
        statusVisible: Bool = true,
        statusDotColor: RGBA = Palette.dead,
        statusText: String = "",
        statusTextColor: RGBA = Palette.muted,
        statusLine2: String = "",
        statusTooltip: String = "",
        statusURL: URL = AppInfo.statusPage,
        detailsExpanded: Bool = false,
        statsVisible: Bool = true,
        dayLabel: String = "",
        dayMain: String = "",
        dayExtra: String = "",
        week7Label: String = "",
        week7Main: String = "",
        week7Extra: String = "",
        versionText: String = "",
        versionColor: RGBA = Palette.muted,
        versionTooltip: String = "",
        versionAction: VersionAction = .none,
        appVersionText: String = AppInfo.title,
        appVersionTooltip: String = "",
        appVersionURL: URL = AppInfo.originalRepo,
        accountText: String = "",
        accountColor: RGBA = Palette.footer,
        accountTooltip: String = "",
        stampText: String = "",
        stampColor: RGBA = Palette.footer,
        trayText: String = "--",
        trayColor: RGBA = Palette.dead,
        trayTooltip: String = ""
    ) {
        self.title = title
        self.detailsGlyph = detailsGlyph
        self.detailsTooltip = detailsTooltip
        self.hideTooltip = hideTooltip
        self.exitTooltip = exitTooltip
        self.pctText = pctText
        self.pctColor = pctColor
        self.sessionFraction = sessionFraction
        self.sessionBarColor = sessionBarColor
        self.resetText = resetText
        self.resetColor = resetColor
        self.resetTooltip = resetTooltip
        self.limitReached = limitReached
        self.playText = playText
        self.playTooltip = playTooltip
        self.week = week
        self.modelWeeks = modelWeeks
        self.sessionsVisible = sessionsVisible
        self.sessionsLabel = sessionsLabel
        self.sessionsText = sessionsText
        self.sessionsTooltip = sessionsTooltip
        self.statusVisible = statusVisible
        self.statusDotColor = statusDotColor
        self.statusText = statusText
        self.statusTextColor = statusTextColor
        self.statusLine2 = statusLine2
        self.statusTooltip = statusTooltip
        self.statusURL = statusURL
        self.detailsExpanded = detailsExpanded
        self.statsVisible = statsVisible
        self.dayLabel = dayLabel
        self.dayMain = dayMain
        self.dayExtra = dayExtra
        self.week7Label = week7Label
        self.week7Main = week7Main
        self.week7Extra = week7Extra
        self.versionText = versionText
        self.versionColor = versionColor
        self.versionTooltip = versionTooltip
        self.versionAction = versionAction
        self.appVersionText = appVersionText
        self.appVersionTooltip = appVersionTooltip
        self.appVersionURL = appVersionURL
        self.accountText = accountText
        self.accountColor = accountColor
        self.accountTooltip = accountTooltip
        self.stampText = stampText
        self.stampColor = stampColor
        self.trayText = trayText
        self.trayColor = trayColor
        self.trayTooltip = trayTooltip
    }
}
