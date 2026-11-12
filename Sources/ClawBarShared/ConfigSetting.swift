import Foundation

/// How one config.json key is read, written, kept in range and dumped. Decoding, writing, clamping, `--dump-state`
/// and `--diagnose`'s everything-shown config all read these, so a setting is declared once, in `ConfigKey.setting`.
public struct ConfigSetting: Sendable {
    /// Reads the file's value leniently; one it cannot read leaves the key's default.
    let read: @Sendable (Any?, inout Config) -> Void
    /// What is written, compared and dumped; nil is written as null.
    public let value: @Sendable (Config) -> AnyHashable?
    let clamp: @Sendable (inout Config) -> Void
    public let range: ClosedRange<Double>?
    /// Set for something the card or the menu can hide: `--diagnose` shows it all.
    var turnOn: (@Sendable (inout Config) -> Void)?
    /// A home location, so `--dump-state` says only whether it is set.
    public let dumpsOnlyWhetherSet: Bool

    init(
        read: @escaping @Sendable (Any?, inout Config) -> Void,
        value: @escaping @Sendable (Config) -> AnyHashable?,
        clamp: @escaping @Sendable (inout Config) -> Void = { _ in },
        range: ClosedRange<Double>? = nil,
        turnOn: (@Sendable (inout Config) -> Void)? = nil,
        dumpsOnlyWhetherSet: Bool = false
    ) {
        self.read = read
        self.value = value
        self.clamp = clamp
        self.range = range
        self.turnOn = turnOn
        self.dumpsOnlyWhetherSet = dumpsOnlyWhetherSet
    }
}

extension ConfigKey {
    public var setting: ConfigSetting {
        switch self {
        case .language: .text(\.language)
        case .theme: .choice(\.theme, ThemeChoice.init(configValue:))
        case .accent: .accent
        case .skin: .text(\.skin)
        case .scale: .number(\.scale, 0.6 ... 4.0)
        case .opacity: .number(\.opacity, 0.2 ... 1.0)
        case .topmost: .flag(\.topmost)
        case .mainLimit: .choice(\.mainLimit, MainLimit.init(configValue:))
        case .warnPercent: .count(\.warnPercent, 1 ... 100)
        case .critPercent: .count(\.critPercent, 1 ... 100)
        case .expanded: .shows(\.expanded)
        case .showStats: .shows(\.showStats)
        case .showStatus: .shows(\.showStatus)
        case .showSessions: .shows(\.showSessions)
        case .showAccount: .shows(\.showAccount)
        case .showMascot: .shows(\.showMascot)
        case .showSky: .shows(\.showSky)
        case .showHistory: .shows(\.showHistory)
        case .weatherLat: .coordinate(\.weatherLat, -90 ... 90)
        case .weatherLon: .coordinate(\.weatherLon, -180 ... 180)
        case .refreshSeconds: .count(\.refreshSeconds, 2 ... 300)
        case .usageIntervalSeconds: .count(\.usageIntervalSeconds, 30 ... 3600)
        case .versionIntervalSeconds: .count(\.versionIntervalSeconds, 600 ... 86400)
        case .statusIntervalSeconds: .count(\.statusIntervalSeconds, 30 ... 3600)
        case .accountIntervalSeconds: .count(\.accountIntervalSeconds, 60 ... 86400)
        case .weatherIntervalSeconds: .count(\.weatherIntervalSeconds, 300 ... 86400)
        case .left: .position(\.left)
        case .top: .position(\.top)
        case .claudePath: .claudePath
        case .launchAtLogin: .flag(\.launchAtLogin)
        case .menuBarMascot: .flag(\.menuBarMascot)
        case .showRecentSessions: .shows(\.showRecentSessions)
        }
    }
}

typealias ConfigKeyPath<T> = WritableKeyPath<Config, T> & Sendable

extension ConfigSetting {
    static func flag(_ f: ConfigKeyPath<Bool>) -> Self {
        Self(read: { v, c in if let b = Lenient.bool(v) { c[keyPath: f] = b } }, value: { $0[keyPath: f] })
    }

    /// A flag that shows something on the card or in the menu.
    static func shows(_ f: ConfigKeyPath<Bool>) -> Self {
        var s = flag(f)
        s.turnOn = { $0[keyPath: f] = true }
        return s
    }

    static func count(_ f: ConfigKeyPath<Int>, _ r: ClosedRange<Int>) -> Self {
        Self(
            read: { v, c in if let n = Lenient.int(v) { c[keyPath: f] = n } }, value: { $0[keyPath: f] },
            clamp: { $0[keyPath: f] = min(r.upperBound, max(r.lowerBound, $0[keyPath: f])) },
            range: Double(r.lowerBound) ... Double(r.upperBound)
        )
    }

    /// A non-finite value goes back to the default.
    static func number(_ f: ConfigKeyPath<Double>, _ r: ClosedRange<Double>) -> Self {
        Self(
            read: { v, c in if let d = Lenient.double(v) { c[keyPath: f] = d } }, value: { $0[keyPath: f] },
            clamp: { c in
                let v = c[keyPath: f]
                c[keyPath: f] = v.isFinite ? min(r.upperBound, max(r.lowerBound, v)) : Config()[keyPath: f]
            },
            range: r
        )
    }

    /// Unset when out of range, so the weather falls back to the IP location.
    static func coordinate(_ f: ConfigKeyPath<Double?>, _ r: ClosedRange<Double>) -> Self {
        Self(
            read: { v, c in c[keyPath: f] = Lenient.double(v) }, value: { $0[keyPath: f].map(AnyHashable.init) },
            clamp: { c in
                if let v = c[keyPath: f], !(v.isFinite && r.contains(v)) { c[keyPath: f] = nil }
            },
            range: r, dumpsOnlyWhetherSet: true
        )
    }

    static func position(_ f: ConfigKeyPath<Double?>) -> Self {
        Self(
            read: { v, c in c[keyPath: f] = Lenient.double(v) }, value: { $0[keyPath: f].map(AnyHashable.init) },
            clamp: { c in if c[keyPath: f]?.isFinite == false { c[keyPath: f] = nil } }
        )
    }

    /// Kept as the user spelled it; `Config.lang` and `SkinCatalog` resolve it when read.
    static func text(_ f: ConfigKeyPath<String>) -> Self {
        Self(read: { v, c in if let s = v as? String { c[keyPath: f] = s } }, value: { $0[keyPath: f] })
    }

    /// Read by name, written by its raw value.
    static func choice<T: RawRepresentable & Hashable & Sendable>(
        _ f: ConfigKeyPath<T>, _ parse: @escaping @Sendable (String?) -> T
    ) -> Self where T.RawValue == String {
        Self(read: { v, c in c[keyPath: f] = parse(v as? String) }, value: { $0[keyPath: f].rawValue })
    }

    // Upstream keeps the previous theme's accent on a bad value; here the theme's own shows.
    static let accent = Self(
        read: { v, c in c.accent = (v as? String).flatMap { RGBA.parse($0.trimmingCharacters(in: .whitespacesAndNewlines)) } },
        value: { $0.accent?.hex }
    )

    static let claudePath = Self(
        read: { v, c in c.claudePath = v as? String }, value: { $0.claudePath.map(AnyHashable.init) },
        clamp: { c in
            let path = c.claudePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            c.claudePath = path.isEmpty ? nil : path
        }
    )
}

extension Config {
    /// config.json's values over the defaults, each key on its own: one bad value falls back to that key's default.
    public init(json j: [String: Any]) {
        self.init()
        for k in ConfigKey.allCases { k.setting.read(j[k.rawValue], &self) }
        self = clamped()
    }

    /// Everything shown and the details open, whatever config.json says: `--diagnose` looks at hidden rows too.
    public func everythingShown() -> Config {
        var c = self
        for k in ConfigKey.allCases { k.setting.turnOn?(&c) }
        return c
    }
}
