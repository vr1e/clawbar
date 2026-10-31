import Foundation

public enum Lang: String, Sendable, CaseIterable {
    case en, de

    /// Case-insensitive; anything unknown (an old `ru`, a typo) is English.
    public init(configValue: String?) {
        let v = (configValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = Lang(rawValue: v) ?? .en
    }

    /// The name in its own language, for the Language menu.
    public var nativeName: String {
        switch self {
        case .en: "English"
        case .de: "Deutsch"
        }
    }
}

/// The JSON key of every setting in config.json.
public enum ConfigKey: String, CaseIterable, Sendable {
    case language, scale, opacity, topmost, warnPercent, critPercent, expanded
    case showStats, showStatus, showSessions, showAccount, showMascot, showSky, showHistory
    case weatherLat, weatherLon
    case refreshSeconds, usageIntervalSeconds, versionIntervalSeconds, statusIntervalSeconds
    case accountIntervalSeconds, weatherIntervalSeconds
    case left, top, claudePath, launchAtLogin, menuBarMascot
}

/// config.json in memory. Values may be out of range until `clamped()`.
public struct Config: Sendable, Hashable {
    public var language: String
    public var scale: Double
    public var opacity: Double
    public var topmost: Bool
    public var warnPercent: Int
    public var critPercent: Int
    public var expanded: Bool
    public var showStats: Bool
    public var showStatus: Bool
    public var showSessions: Bool
    public var showAccount: Bool
    public var showMascot: Bool
    public var showSky: Bool
    /// The 7-day chart of the session and week limits in the details.
    public var showHistory: Bool
    /// Both set: weather for these coordinates; otherwise the IP location.
    public var weatherLat: Double?
    public var weatherLon: Double?
    /// The data tick.
    public var refreshSeconds: Int
    public var usageIntervalSeconds: Int
    public var versionIntervalSeconds: Int
    public var statusIntervalSeconds: Int
    public var accountIntervalSeconds: Int
    public var weatherIntervalSeconds: Int
    /// The widget's top-left, WPF-style: x from the left of the primary screen, y down from its top.
    public var left: Double?
    public var top: Double?
    /// An explicit claude executable, tried before the usual install locations.
    public var claudePath: String?
    public var launchAtLogin: Bool
    /// Clawd beside the session % in the menu bar; off leaves the pill alone.
    public var menuBarMascot: Bool

    public init(
        language: String = "en",
        scale: Double = 1.2,
        opacity: Double = 1.0,
        topmost: Bool = false,
        warnPercent: Int = 60,
        critPercent: Int = 85,
        expanded: Bool = false,
        showStats: Bool = true,
        showStatus: Bool = true,
        showSessions: Bool = true,
        showAccount: Bool = true,
        showMascot: Bool = true,
        showSky: Bool = true,
        showHistory: Bool = false,
        weatherLat: Double? = nil,
        weatherLon: Double? = nil,
        refreshSeconds: Int = 10,
        usageIntervalSeconds: Int = 60,
        versionIntervalSeconds: Int = 3600,
        statusIntervalSeconds: Int = 120,
        accountIntervalSeconds: Int = 600,
        weatherIntervalSeconds: Int = 900,
        left: Double? = nil,
        top: Double? = nil,
        claudePath: String? = nil,
        launchAtLogin: Bool = true,
        menuBarMascot: Bool = true
    ) {
        self.language = language
        self.scale = scale
        self.opacity = opacity
        self.topmost = topmost
        self.warnPercent = warnPercent
        self.critPercent = critPercent
        self.expanded = expanded
        self.showStats = showStats
        self.showStatus = showStatus
        self.showSessions = showSessions
        self.showAccount = showAccount
        self.showMascot = showMascot
        self.showSky = showSky
        self.showHistory = showHistory
        self.weatherLat = weatherLat
        self.weatherLon = weatherLon
        self.refreshSeconds = refreshSeconds
        self.usageIntervalSeconds = usageIntervalSeconds
        self.versionIntervalSeconds = versionIntervalSeconds
        self.statusIntervalSeconds = statusIntervalSeconds
        self.accountIntervalSeconds = accountIntervalSeconds
        self.weatherIntervalSeconds = weatherIntervalSeconds
        self.left = left
        self.top = top
        self.claudePath = claudePath
        self.launchAtLogin = launchAtLogin
        self.menuBarMascot = menuBarMascot
    }

    public var lang: Lang { Lang(configValue: language) }

    /// Every number pulled into its range (`ConfigLimits.ranges`), non-finite values back to the default,
    /// out-of-range coordinates unset, and warn never above crit.
    public func clamped() -> Config {
        let d = Config()
        var c = self
        func int(_ v: Int, _ key: ConfigKey) -> Int {
            let r = ConfigLimits.ranges[key]!
            return min(Int(r.upperBound), max(Int(r.lowerBound), v))
        }
        func double(_ v: Double, _ key: ConfigKey, _ fallback: Double) -> Double {
            guard v.isFinite else { return fallback }
            let r = ConfigLimits.ranges[key]!
            return min(r.upperBound, max(r.lowerBound, v))
        }
        func coordinate(_ v: Double?, _ key: ConfigKey) -> Double? {
            guard let v, v.isFinite, ConfigLimits.ranges[key]!.contains(v) else { return nil }
            return v
        }
        c.scale = double(scale, .scale, d.scale)
        c.opacity = double(opacity, .opacity, d.opacity)
        c.refreshSeconds = int(refreshSeconds, .refreshSeconds)
        c.usageIntervalSeconds = int(usageIntervalSeconds, .usageIntervalSeconds)
        c.versionIntervalSeconds = int(versionIntervalSeconds, .versionIntervalSeconds)
        c.statusIntervalSeconds = int(statusIntervalSeconds, .statusIntervalSeconds)
        c.accountIntervalSeconds = int(accountIntervalSeconds, .accountIntervalSeconds)
        c.weatherIntervalSeconds = int(weatherIntervalSeconds, .weatherIntervalSeconds)
        c.critPercent = int(critPercent, .critPercent)
        c.warnPercent = min(int(warnPercent, .warnPercent), c.critPercent)
        c.weatherLat = coordinate(weatherLat, .weatherLat)
        c.weatherLon = coordinate(weatherLon, .weatherLon)
        c.left = left.flatMap { $0.isFinite ? $0 : nil }
        c.top = top.flatMap { $0.isFinite ? $0 : nil }
        let path = claudePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        c.claudePath = path.isEmpty ? nil : path
        return c
    }
}

public enum ConfigLimits {
    public static let ranges: [ConfigKey: ClosedRange<Double>] = [
        .refreshSeconds: 2 ... 300,
        .usageIntervalSeconds: 30 ... 3600,
        .statusIntervalSeconds: 30 ... 3600,
        .accountIntervalSeconds: 60 ... 86400,
        .versionIntervalSeconds: 600 ... 86400,
        .weatherIntervalSeconds: 300 ... 86400,
        .scale: 0.6 ... 4.0,
        .opacity: 0.2 ... 1.0,
        .warnPercent: 1 ... 100,
        .critPercent: 1 ... 100,
        .weatherLat: -90 ... 90,
        .weatherLon: -180 ... 180,
    ]
}
