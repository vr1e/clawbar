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

/// A labelled row with a thin bar under it: the other limit, or a model's week.
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

/// A weekday under the 7-day chart, centred between the midnights at `from` and `to`; empty in a slot too narrow.
public struct ChartDay: Sendable, Hashable {
    public var text: String
    public var from: Double
    public var to: Double

    public init(text: String, from: Double, to: Double) {
        self.text = text
        self.from = from
        self.to = to
    }
}

/// The details' chart of the session and week limits over the last 7 days.
public struct HistoryView: Sendable, Hashable {
    /// The chart's box in base units: the bars' width, and widget.xaml's 44.
    public static let width = 236.0
    public static let height = 44.0

    /// LIMITS · 7 DAYS.
    public var label: String
    /// The legend's names for the session and the week line.
    public var sessionName: String
    public var weekName: String
    /// Runs of samples without a gap, each a line of its own; a lone sample is a 1-wide stub.
    public var sessionRuns: [[CGPoint]]
    public var weekRuns: [[CGPoint]]
    /// Every local day the week touches, oldest first.
    public var days: [ChartDay]
    /// Why the chart is empty, shown in place of the legend.
    public var caption: String
    /// The Unix minutes at the left and right edge, so a hover reads the minute the chart drew there.
    public var start: Int
    public var end: Int

    /// The x of each midnight inside the week.
    public var dayTicks: [Double] { days.dropFirst().map(\.from) }

    public init(
        label: String, sessionName: String = "", weekName: String = "", sessionRuns: [[CGPoint]] = [],
        weekRuns: [[CGPoint]] = [], days: [ChartDay] = [], caption: String = "", start: Int = 0, end: Int = 0
    ) {
        self.label = label
        self.sessionName = sessionName
        self.weekName = weekName
        self.sessionRuns = sessionRuns
        self.weekRuns = weekRuns
        self.days = days
        self.caption = caption
        self.start = start
        self.end = end
    }
}

/// The pointer over the 7-day chart: a cursor line, and what the chart says there in place of the legend.
public struct HistoryHover: Sendable, Hashable {
    /// Base units from the chart's left edge, within its width.
    public var x: Double
    /// `Sat 14:20  ·  5h 34%  ·  week 61%  ·  api`.
    public var caption: String

    public init(x: Double, caption: String) {
        self.x = x
        self.caption = caption
    }
}

/// One project under the 7-day chart: its name, a bar on the track, and its share of the week.
public struct ProjectRow: Sendable, Hashable {
    /// The folder's last part, `~` for the home folder, `parent/leaf` when another project of the week ends the same.
    public var name: String
    /// `42%`.
    public var share: String
    /// 0...1 of the track.
    public var fraction: Double

    public init(name: String, share: String, fraction: Double) {
        self.name = name
        self.share = share
        self.fraction = fraction
    }
}

/// widget.xaml's ProjPanel under the 7-day chart: the week's heaviest projects, or why there are none yet.
public struct ProjectsView: Sendable, Hashable {
    /// Show-Projects' bar track and share column, in base units.
    public static let trackWidth = 70.0
    public static let shareWidth = 34.0

    /// PROJECTS · 7 DAYS.
    public var label: String
    /// The top 4, heaviest first; empty before the first scan.
    public var rows: [ProjectRow]
    /// `counting...` in place of the rows before the first scan.
    public var caption: String

    public init(label: String, rows: [ProjectRow] = [], caption: String = "") {
        self.label = label
        self.rows = rows
        self.caption = caption
    }
}

/// A part of the card the pointer can reach, shown, with its tooltip; an empty tooltip means none.
public struct CardPart: Sendable, Hashable {
    /// Declared in the card's order, so sorting by id sorts the parts as the card stacks them.
    public enum ID: Sendable, Hashable, Comparable {
        case details, hide, exit, reset, play, sessions, status, projectsLabel
        /// A row of the top projects, by its index.
        case project(Int)
        /// The Claude Code version line, and the ClawBar line beside it.
        case version, appVersion
        case account
    }

    public var id: ID
    public var tooltip: String

    public init(_ id: ID, tooltip: String = "") {
        self.id = id
        self.tooltip = tooltip
    }
}

/// What clicking the Claude Code version line does.
public enum VersionAction: Sendable, Hashable {
    case none
    case runUpdate
    case open(URL)
}

/// Every string, colour, fraction and visibility of the widget and the menu bar item, and the parts the card shows
/// with their tooltips. An empty text hides a line that is not a part.
public struct WidgetViewState: Sendable, Hashable {
    /// The themed colours, read by role by the card, the hearts, the caption and Clawd Run. Where the role depends on
    /// the state or the row, the presenter resolves it into that field's own colour instead.
    public var palette: ThemePalette
    /// The parts the card shows, in its order; a part left out is not drawn and the pointer finds nothing there.
    public var parts: [CardPart]

    // Header
    public var title: String
    /// ▾ closed, ▴ open.
    public var detailsGlyph: String

    // Percent row and the main limit's bar
    /// The number without `%` ("42"), or "--".
    public var pctText: String
    public var pctColor: RGBA
    public var mainFraction: Double
    public var mainBarColor: RGBA

    // Reset line
    public var resetText: String
    public var resetColor: RGBA

    // Clawd Run
    /// The main limit is used up: the card and the menu offer the game.
    public var limitReached: Bool
    /// The button under the reset line, shown while the limit is reached.
    public var playText: String
    /// The game's corner: the time until the limit resets while it lasts, then the news that it has.
    public var gameCaption: String

    // The other limit (the week, or the session while the week is main) and the model weeks
    public var otherLimit: BarRow
    public var modelWeeks: [BarRow]

    // Sessions
    public var sessionsLabel: String
    public var sessionsText: String

    // Service status
    public var statusDotColor: RGBA
    public var statusText: String
    public var statusTextColor: RGBA
    /// Broken components; empty hides the second line.
    public var statusLine2: String

    // Details
    public var detailsExpanded: Bool
    public var statsVisible: Bool
    public var dayLabel: String
    public var dayMain: String
    public var dayExtra: String
    public var week7Label: String
    public var week7Main: String
    public var week7Extra: String
    /// The 7-day chart; nil unless it is switched on and the details are open.
    public var history: HistoryView?
    /// The week's top projects under the chart; nil with the chart, or once a scan found no usage this week.
    public var projects: ProjectsView?
    public var versionText: String
    public var versionColor: RGBA
    public var versionAction: VersionAction
    /// "ClawBar v0.1.0".
    public var appVersionText: String

    // Footer
    public var accountText: String
    public var accountColor: RGBA
    public var stampText: String
    public var stampColor: RGBA

    // Menu bar item
    /// The number without `%`, or "--".
    public var trayText: String
    public var trayColor: RGBA
    public var trayTooltip: String
    /// Clawd beside the pill.
    public var trayMascot: Bool

    public init(
        palette: ThemePalette = .classic,
        parts: [CardPart] = [],
        title: String = "CLAUDE USAGE",
        detailsGlyph: String = "▾",
        pctText: String = "--",
        pctColor: RGBA = Palette.dead,
        mainFraction: Double = 0,
        mainBarColor: RGBA = Palette.dead,
        resetText: String = "",
        resetColor: RGBA = Palette.secondary,
        limitReached: Bool = false,
        playText: String = "",
        gameCaption: String = "",
        otherLimit: BarRow = BarRow(label: "WEEK", value: "", fraction: 0, color: Palette.weekBar),
        modelWeeks: [BarRow] = [],
        sessionsLabel: String = "SESSIONS",
        sessionsText: String = "",
        statusDotColor: RGBA = Palette.dead,
        statusText: String = "",
        statusTextColor: RGBA = Palette.muted,
        statusLine2: String = "",
        detailsExpanded: Bool = false,
        statsVisible: Bool = true,
        dayLabel: String = "",
        dayMain: String = "",
        dayExtra: String = "",
        week7Label: String = "",
        week7Main: String = "",
        week7Extra: String = "",
        history: HistoryView? = nil,
        projects: ProjectsView? = nil,
        versionText: String = "",
        versionColor: RGBA = Palette.muted,
        versionAction: VersionAction = .none,
        appVersionText: String = AppInfo.title,
        accountText: String = "",
        accountColor: RGBA = Palette.footer,
        stampText: String = "",
        stampColor: RGBA = Palette.footer,
        trayText: String = "--",
        trayColor: RGBA = Palette.dead,
        trayTooltip: String = "",
        trayMascot: Bool = true
    ) {
        self.palette = palette
        self.parts = parts
        self.title = title
        self.detailsGlyph = detailsGlyph
        self.pctText = pctText
        self.pctColor = pctColor
        self.mainFraction = mainFraction
        self.mainBarColor = mainBarColor
        self.resetText = resetText
        self.resetColor = resetColor
        self.limitReached = limitReached
        self.playText = playText
        self.gameCaption = gameCaption
        self.otherLimit = otherLimit
        self.modelWeeks = modelWeeks
        self.sessionsLabel = sessionsLabel
        self.sessionsText = sessionsText
        self.statusDotColor = statusDotColor
        self.statusText = statusText
        self.statusTextColor = statusTextColor
        self.statusLine2 = statusLine2
        self.detailsExpanded = detailsExpanded
        self.statsVisible = statsVisible
        self.dayLabel = dayLabel
        self.dayMain = dayMain
        self.dayExtra = dayExtra
        self.week7Label = week7Label
        self.week7Main = week7Main
        self.week7Extra = week7Extra
        self.history = history
        self.projects = projects
        self.versionText = versionText
        self.versionColor = versionColor
        self.versionAction = versionAction
        self.appVersionText = appVersionText
        self.accountText = accountText
        self.accountColor = accountColor
        self.stampText = stampText
        self.stampColor = stampColor
        self.trayText = trayText
        self.trayColor = trayColor
        self.trayTooltip = trayTooltip
        self.trayMascot = trayMascot
    }
}

extension WidgetViewState {
    /// The part `id` while the card shows it.
    public func part(_ id: CardPart.ID) -> CardPart? {
        parts.first { $0.id == id }
    }

    public func shows(_ id: CardPart.ID) -> Bool {
        part(id) != nil
    }

    /// Shows the part `id` with this tooltip, in its place in the card's order; a shown one takes the new tooltip.
    public mutating func show(_ id: CardPart.ID, tooltip: String = "") {
        show(CardPart(id, tooltip: tooltip))
    }

    public mutating func show(_ part: CardPart) {
        if let i = parts.firstIndex(where: { $0.id == part.id }) {
            parts[i] = part
        } else {
            parts.insert(part, at: parts.firstIndex { $0.id > part.id } ?? parts.endIndex)
        }
    }
}
