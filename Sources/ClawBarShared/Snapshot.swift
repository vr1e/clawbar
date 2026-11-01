import Foundation

public enum SessionState: String, Sendable, CaseIterable {
    /// `busy` or `shell` in the registry.
    case busy
    /// Waiting for the user: a permission, a question, a dialog.
    case waiting
    case idle
}

/// One live Claude Code session from `~/.claude/sessions/<pid>.json`.
public struct SessionInfo: Sendable, Hashable {
    public var pid: Int32
    public var sessionId: String
    /// The session's name, else the leaf of its cwd.
    public var name: String
    public var cwd: String
    public var state: SessionState
    /// What a waiting session waits for, e.g. "permission".
    public var waitingFor: String?
    /// interactive, bg or daemon-worker.
    public var kind: String?
    public var startedAt: Date?

    public init(
        pid: Int32, sessionId: String = "", name: String, cwd: String = "", state: SessionState = .idle,
        waitingFor: String? = nil, kind: String? = nil, startedAt: Date? = nil
    ) {
        self.pid = pid
        self.sessionId = sessionId
        self.name = name
        self.cwd = cwd
        self.state = state
        self.waitingFor = waitingFor
        self.kind = kind
        self.startedAt = startedAt
    }
}

/// A `Last 24h` / `Last 7d` block of `/usage`.
public struct UsagePeriod: Sendable, Hashable {
    public var requests: Int
    public var sessions: Int
    /// The indented lines below the header, trimmed and raw; the presenter translates them.
    public var lines: [String]

    public init(requests: Int, sessions: Int, lines: [String] = []) {
        self.requests = requests
        self.sessions = sessions
        self.lines = lines
    }
}

/// A per-model weekly limit, e.g. `Current week (Fable)`.
public struct ModelWeek: Sendable, Hashable {
    /// As /usage names it, minus a trailing " only": "Fable", "Sonnet".
    public var name: String
    public var percent: Int
    public var reset: Date?

    public init(name: String, percent: Int, reset: Date? = nil) {
        self.name = name
        self.percent = percent
        self.reset = reset
    }
}

/// One successful parse of `claude -p /usage`.
public struct UsageSnapshot: Sendable, Hashable {
    public var sessionPercent: Int?
    public var weekPercent: Int?
    public var sessionReset: Date?
    public var weekReset: Date?
    public var modelWeeks: [ModelWeek]
    public var day: UsagePeriod?
    public var week7: UsagePeriod?

    public init(
        sessionPercent: Int? = nil, weekPercent: Int? = nil, sessionReset: Date? = nil, weekReset: Date? = nil,
        modelWeeks: [ModelWeek] = [], day: UsagePeriod? = nil, week7: UsagePeriod? = nil
    ) {
        self.sessionPercent = sessionPercent
        self.weekPercent = weekPercent
        self.sessionReset = sessionReset
        self.weekReset = weekReset
        self.modelWeeks = modelWeeks
        self.day = day
        self.week7 = week7
    }

    /// One of the two limits `MainLimit` chooses between.
    public func limit(_ kind: MainLimit) -> UsageLimit {
        switch kind {
        case .session: UsageLimit(kind: .session, percent: sessionPercent, reset: sessionReset)
        case .week: UsageLimit(kind: .week, percent: weekPercent, reset: weekReset)
        }
    }
}

/// The session or the all-models week: its percentage and reset, nil without data.
public struct UsageLimit: Sendable, Hashable {
    public var kind: MainLimit
    public var percent: Int?
    public var reset: Date?

    public init(kind: MainLimit, percent: Int? = nil, reset: Date? = nil) {
        self.kind = kind
        self.percent = percent
        self.reset = reset
    }
}

extension MainLimit {
    /// The limit that is not main: it takes the row under the big number.
    public var other: MainLimit { self == .session ? .week : .session }

    /// Get-Limits: this limit of `usage`, empty without one.
    public func of(_ usage: UsageSnapshot?) -> UsageLimit { usage?.limit(self) ?? UsageLimit(kind: self) }
}

/// The session and week percentages at one minute, for the 7-day history.
public struct UsageSample: Sendable, Hashable {
    /// Minutes since 1970 in UTC, so a DST change never reorders samples.
    public var minute: Int
    public var session: Int?
    public var week: Int?

    public init(minute: Int, session: Int? = nil, week: Int? = nil) {
        self.minute = minute
        self.session = session
        self.week = week
    }

    public static func minute(of date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded(.down)) }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(minute) * 60) }
}

/// One project's share of the week, from the replies in its transcript folder.
public struct ProjectWeight: Sendable, Hashable {
    /// The folder Claude Code was started in, else the one most replies ran in, else the transcript folder's name.
    public var path: String
    /// The replies at list prices, in dollars; only its ratio to the other projects' weights means anything.
    public let weight: Double
    /// The weight per quarter hour, keyed by the Unix minute it starts at. Every time zone is a whole number of
    /// quarter hours off UTC, so four of them make any local hour.
    public let quarters: [Int: Double]

    /// `quarters` may be keyed by any minute of its quarter hour.
    public init(path: String, quarters: [Int: Double]) {
        self.path = path
        self.quarters = Dictionary(quarters.map { (Self.quarterStart(of: $0.key), $0.value) }, uniquingKeysWith: +)
        // Added in time order, so the same quarters always weigh the same.
        weight = self.quarters.sorted { $0.key < $1.key }.reduce(0) { $0 + $1.value }
    }

    /// The Unix minute the quarter hour holding `minute` starts at.
    public static func quarterStart(of minute: Int) -> Int { minute - minute % 15 }

    /// The weight of every quarter hour that overlaps `minutes`.
    public func weight(in minutes: Range<Int>) -> Double {
        stride(from: Self.quarterStart(of: minutes.lowerBound), to: minutes.upperBound, by: 15).reduce(0) {
            $0 + (quarters[$1] ?? 0)
        }
    }
}

/// The week's Claude Code transcripts on this Mac, weighed per project.
public struct ProjectUsage: Sendable, Hashable {
    /// Heaviest first; only projects with replies this week.
    public var projects: [ProjectWeight]
    /// Replies priced as a nearby model, since the price table has none for theirs.
    public var unpriced: Int

    public init(projects: [ProjectWeight] = [], unpriced: Int = 0) {
        self.projects = projects
        self.unpriced = unpriced
    }
}

/// Why the usage numbers are missing or stopped.
public enum UsageIssue: Sendable, Hashable {
    /// No claude executable anywhere; retried every usage interval.
    case claudeNotFound
    case launchFailed(String)
    case timedOut
    case probeFailed(String)
    /// /usage answered with the `/cost` summary: a login without a Claude subscription, e.g. an API key.
    case noLimits
    /// Claude Code refused one of the probe's options. Latched per CLI version.
    case flagRejected(String)
    /// The zero-token guard saw the probe reach the model. Latched per CLI version.
    case modelReached(turns: Int, costUSD: Double, tokens: Int)

    /// Latched issues stop probing until the CLI version changes.
    public var isLatched: Bool {
        switch self {
        case .flagRejected, .modelReached: true
        default: false
        }
    }

    /// Without claude, or under a login without a subscription, no limit applies, not even an old number.
    public var voidsLimits: Bool {
        switch self {
        case .claudeNotFound, .noLimits: true
        default: false
        }
    }
}

public struct BrokenComponent: Sendable, Hashable {
    /// The name without a trailing parenthetical: "Claude API".
    public var name: String
    /// The raw Statuspage state, e.g. "partial_outage".
    public var state: String

    public init(name: String, state: String) {
        self.name = name
        self.state = state
    }
}

/// status.claude.com's summary.
public struct ServiceStatus: Sendable, Hashable {
    /// none, minor, major, critical or maintenance.
    public var indicator: String
    public var incidents: [String]
    public var broken: [BrokenComponent]

    public init(indicator: String, incidents: [String] = [], broken: [BrokenComponent] = []) {
        self.indicator = indicator
        self.incidents = incidents
        self.broken = broken
    }
}

/// `claude auth status`.
public struct AccountInfo: Sendable, Hashable {
    public var loggedIn: Bool
    /// Max, Pro, Team, Enterprise, Free, API or the raw subscription type.
    public var plan: String
    public var email: String
    public var configDirectory: String?

    public init(loggedIn: Bool, plan: String = "", email: String = "", configDirectory: String? = nil) {
        self.loggedIn = loggedIn
        self.plan = plan
        self.email = email
        self.configDirectory = configDirectory
    }
}

public struct UpdateFailure: Sendable, Hashable {
    /// nil when the update timed out; 0 when it exited cleanly but left the version where it was.
    public var exitCode: Int32?
    /// The last lines of its output, redacted.
    public var outputTail: String
    /// The local and latest versions the run started from; the failure lasts only while both still hold.
    public var from: String?
    public var to: String?

    public init(exitCode: Int32?, outputTail: String, from: String? = nil, to: String? = nil) {
        self.exitCode = exitCode
        self.outputTail = outputTail
        self.from = from
        self.to = to
    }

    /// Whether the versions the run started from still hold; an unrecorded one holds for any.
    public func holds(local: String?, latest: String?) -> Bool {
        (from == nil || local == from) && (to == nil || latest == to)
    }
}

/// Install methods whose `claude update` may refuse to self-update.
public enum InstallHint: String, Sendable, CaseIterable {
    case homebrew, npm
}

/// The changelog items between the local and the latest version: `(from, for]`, newest first.
public struct ChangesExcerpt: Sendable, Hashable {
    /// The latest version this excerpt was cut for.
    public var forVersion: String
    /// The local version it starts after.
    public var fromVersion: String
    public var items: [String]

    public init(forVersion: String, fromVersion: String, items: [String]) {
        self.forVersion = forVersion
        self.fromVersion = fromVersion
        self.items = items
    }
}

public struct VersionState: Sendable, Hashable {
    public var local: String?
    public var latest: String?
    public var updating: Bool
    public var updateFailure: UpdateFailure?
    public var installHint: InstallHint?
    public var changes: ChangesExcerpt?

    public init(
        local: String? = nil, latest: String? = nil, updating: Bool = false, updateFailure: UpdateFailure? = nil,
        installHint: InstallHint? = nil, changes: ChangesExcerpt? = nil
    ) {
        self.local = local
        self.latest = latest
        self.updating = updating
        self.updateFailure = updateFailure
        self.installHint = installHint
        self.changes = changes
    }

    /// Only when both are known and latest is numerically newer (2.1.10 > 2.1.9).
    public var updateAvailable: Bool {
        guard let local, let latest else { return false }
        return Self.isNewer(latest, than: local)
    }

    /// Numeric dotted comparison like .NET's System.Version; false when either fails to parse.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        guard let x = numbers(a), let y = numbers(b) else { return false }
        for i in 0 ..< max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private static func numbers(_ s: String) -> [Int]? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard (2 ... 4).contains(parts.count) else { return nil }
        let n = parts.compactMap { Int($0) }
        return n.count == parts.count && n.allSatisfy { $0 >= 0 } ? n : nil
    }
}

/// Where the weather is for.
public struct Place: Sendable, Hashable {
    public var lat: Double
    public var lon: Double
    /// From the IP lookup, localized; nil for configured coordinates.
    public var city: String?
    /// IANA zone from the IP lookup.
    public var timeZoneID: String?

    public init(lat: Double, lon: Double, city: String? = nil, timeZoneID: String? = nil) {
        self.lat = lat
        self.lon = lon
        self.city = city
        self.timeZoneID = timeZoneID
    }
}

public struct WeatherSnapshot: Sendable, Hashable {
    /// WMO weather code.
    public var code: Int
    public var tempC: Double
    public var windKmh: Double
    /// Minutes after midnight in the location's time zone; nil from met.no.
    public var sunriseMin: Double?
    public var sunsetMin: Double?
    /// Open-Meteo's `timezone` for the location.
    public var timeZoneID: String?
    public var at: Date

    public init(
        code: Int, tempC: Double, windKmh: Double, sunriseMin: Double? = nil, sunsetMin: Double? = nil,
        timeZoneID: String? = nil, at: Date
    ) {
        self.code = code
        self.tempC = tempC
        self.windKmh = windKmh
        self.sunriseMin = sunriseMin
        self.sunsetMin = sunsetMin
        self.timeZoneID = timeZoneID
        self.at = at
    }
}

/// Everything the data layer knows, as one value. Each source keeps its last good value when a probe fails.
public struct DataSnapshot: Sendable, Hashable {
    public var usage: UsageSnapshot?
    /// Time of the last good parse; drives the stamp and staleness.
    public var usageAt: Date?
    /// Some usage probe has finished, good or bad: "loading..." stops here.
    public var usageProbeCompleted: Bool
    public var usageIssue: UsageIssue?
    /// The last 8 days of usage samples, oldest first.
    public var history: [UsageSample]
    public var sessions: [SessionInfo]
    /// The session registry has been read once; Clawd's mood waits for it.
    public var sessionsRead: Bool
    public var status: ServiceStatus?
    /// Time of the last good status; drives staleness.
    public var statusAt: Date?
    public var account: AccountInfo?
    public var version: VersionState
    public var weather: WeatherSnapshot?
    public var place: Place?
    /// nil until the first scan of the transcripts has finished.
    public var projects: ProjectUsage?
    public var projectsAt: Date?

    public init(
        usage: UsageSnapshot? = nil, usageAt: Date? = nil, usageProbeCompleted: Bool = false,
        usageIssue: UsageIssue? = nil, history: [UsageSample] = [], sessions: [SessionInfo] = [], sessionsRead: Bool = false,
        status: ServiceStatus? = nil, statusAt: Date? = nil, account: AccountInfo? = nil,
        version: VersionState = VersionState(), weather: WeatherSnapshot? = nil, place: Place? = nil,
        projects: ProjectUsage? = nil, projectsAt: Date? = nil
    ) {
        self.usage = usage
        self.usageAt = usageAt
        self.usageProbeCompleted = usageProbeCompleted
        self.usageIssue = usageIssue
        self.history = history
        self.sessions = sessions
        self.sessionsRead = sessionsRead
        self.status = status
        self.statusAt = statusAt
        self.account = account
        self.version = version
        self.weather = weather
        self.place = place
        self.projects = projects
        self.projectsAt = projectsAt
    }

    public static let empty = DataSnapshot()

    public func count(of state: SessionState) -> Int { sessions.count { $0.state == state } }

    public static func isStale(_ at: Date?, interval: Int, now: Date) -> Bool {
        guard let at else { return true }
        return now.timeIntervalSince(at) > staleAfter(interval: interval)
    }

    /// Data is stale when older than 3 × its interval + 30 s.
    public static func staleAfter(interval: Int) -> TimeInterval { Double(3 * interval + 30) }
}
