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
    /// nil when the update timed out.
    public var exitCode: Int32?
    /// The last lines of its output, redacted.
    public var outputTail: String

    public init(exitCode: Int32?, outputTail: String) {
        self.exitCode = exitCode
        self.outputTail = outputTail
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

    public init(
        usage: UsageSnapshot? = nil, usageAt: Date? = nil, usageProbeCompleted: Bool = false,
        usageIssue: UsageIssue? = nil, sessions: [SessionInfo] = [], sessionsRead: Bool = false,
        status: ServiceStatus? = nil, statusAt: Date? = nil, account: AccountInfo? = nil,
        version: VersionState = VersionState(), weather: WeatherSnapshot? = nil, place: Place? = nil
    ) {
        self.usage = usage
        self.usageAt = usageAt
        self.usageProbeCompleted = usageProbeCompleted
        self.usageIssue = usageIssue
        self.sessions = sessions
        self.sessionsRead = sessionsRead
        self.status = status
        self.statusAt = statusAt
        self.account = account
        self.version = version
        self.weather = weather
        self.place = place
    }

    public static let empty = DataSnapshot()

    public func count(of state: SessionState) -> Int { sessions.count { $0.state == state } }

    /// Data is stale when older than 3 × its interval + 30 s.
    public static func isStale(_ at: Date?, interval: Int, now: Date) -> Bool {
        guard let at else { return true }
        return now.timeIntervalSince(at) > Double(3 * interval + 30)
    }
}
