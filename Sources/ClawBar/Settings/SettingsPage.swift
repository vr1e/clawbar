import ClawBarShared

/// A change asked for in the Settings window.
enum SettingsAction: Hashable {
    case larger, smaller, moreOpaque, lessOpaque
    case toggleTopmost, toggleLaunchAtLogin, toggleMenuBarMascot
    case language(Lang)
    case toggleBlock(WidgetBlock)
    case openConfig
}

/// The window's tabs: the original's Look and Window; its Clawd and Claude Code tabs belong to skipped features.
enum SettingsTab: String, CaseIterable, Hashable {
    case look, widget

    var title: L10nKey {
        switch self {
        case .look: .setTabLook
        case .widget: .setTabWindow
        }
    }

    /// The toolbar icon, an SF Symbol.
    var symbol: String {
        switch self {
        case .look: "paintbrush"
        case .widget: "macwindow"
        }
    }
}

/// The widget's switchable blocks, in the original Settings window's order.
enum WidgetBlock: CaseIterable, Hashable {
    case mascot, sky, status, sessions, account, stats, history

    var title: L10nKey {
        switch self {
        case .mascot: .setShowMascot
        case .sky: .setShowSky
        case .status: .setShowStatus
        case .sessions: .setShowSessions
        case .account: .setShowAccount
        case .stats: .setShowStats
        case .history: .setShowHistory
        }
    }

    var flag: WritableKeyPath<Config, Bool> {
        switch self {
        case .mascot: \.showMascot
        case .sky: \.showSky
        case .status: \.showStatus
        case .sessions: \.showSessions
        case .account: \.showAccount
        case .stats: \.showStats
        case .history: \.showHistory
        }
    }
}

/// A switch, or one choice of a picker.
struct SettingsOption: Hashable {
    var title: String
    var on: Bool
    var enabled = true
    var action: SettingsAction
}

/// One control of a page.
enum SettingsRow: Hashable {
    case toggle(SettingsOption)
    /// One of several; the option that is on is the current one.
    case picker(title: String, options: [SettingsOption])
    /// "Size  − 120% +"; an action is nil where the value cannot move further.
    case stepper(title: String, value: String, decrease: SettingsAction?, increase: SettingsAction?)
    case note(String)
    case button(title: String, action: SettingsAction)
}

struct SettingsSection: Hashable {
    var header: String?
    var rows: [SettingsRow]
}

/// The tabs' pages as data, so they can be tested and dumped as text; rebuilt from the config on every change.
enum SettingsPage {
    static func sections(_ tab: SettingsTab, config: Config) -> [SettingsSection] {
        let lang = config.lang
        func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
        func toggle(_ key: L10nKey, _ on: Bool, _ action: SettingsAction, enabled: Bool = true) -> SettingsRow {
            .toggle(SettingsOption(title: t(key), on: on, enabled: enabled, action: action))
        }
        // As the original's footer, on every tab: what the window leaves to config.json.
        let more = SettingsSection(rows: [.note(t(.setMore)), .button(title: t(.setConfig), action: .openConfig)])
        switch tab {
        case .look:
            let languages = Lang.allCases.map { SettingsOption(title: $0.nativeName, on: $0 == lang, action: .language($0)) }
            return [SettingsSection(rows: [.picker(title: t(.setLanguage), options: languages)]), more]
        case .widget:
            // The sky sits in Clawd's play area, so it cannot show without him.
            let blocks = WidgetBlock.allCases.map { b in
                toggle(b.title, config[keyPath: b.flag], .toggleBlock(b), enabled: b != .sky || config.showMascot)
            }
            return [
                SettingsSection(rows: [
                    .stepper(
                        title: t(.setSize), value: percent(config.scale),
                        decrease: ConfigStep.smaller(config.scale).map { _ in .smaller },
                        increase: ConfigStep.larger(config.scale).map { _ in .larger }
                    ),
                    .stepper(
                        title: t(.setOpacity), value: percent(config.opacity),
                        decrease: ConfigStep.lessOpaque(config.opacity).map { _ in .lessOpaque },
                        increase: ConfigStep.moreOpaque(config.opacity).map { _ in .moreOpaque }
                    ),
                    toggle(.setTopmost, config.topmost, .toggleTopmost),
                ]),
                SettingsSection(header: t(.setShown), rows: blocks),
                SettingsSection(header: t(.setSystem), rows: [
                    toggle(.setLogin, config.launchAtLogin, .toggleLaunchAtLogin),
                    toggle(.setMenuBarMascot, config.menuBarMascot, .toggleMenuBarMascot),
                ]),
                more,
            ]
        }
    }

    /// '{0:N0}%' of the original's stepper; N0, unlike [math]::Round, rounds half away from zero.
    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    /// Every tab as text: `[x]`/`[ ]` switches, `(•)`/`( )` choices, `(disabled)`, `−`/`+` where a stepper can move.
    static func dump(config: Config) -> String {
        let lang = config.lang
        return SettingsTab.allCases.map { tab in
            var lines = ["  \(L10n.t(tab.title, lang)):"]
            for s in sections(tab, config: config) {
                // Only rows under a header sit deeper, so a headerless section after one stands apart.
                if let h = s.header { lines.append("    \(h.uppercased())") }
                let indent = s.header == nil ? "    " : "      "
                for r in s.rows { lines.append(indent + line(r)) }
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private static func line(_ row: SettingsRow) -> String {
        func disabled(_ o: SettingsOption) -> String { o.enabled ? "" : "  (disabled)" }
        switch row {
        case .toggle(let o): return (o.on ? "[x] " : "[ ] ") + o.title + disabled(o)
        case .picker(let title, let options):
            return title + ": " + options.map { ($0.on ? "(•) " : "( ) ") + $0.title }.joined(separator: "  ")
        case .stepper(let title, let value, let down, let up):
            return "\(title): \(down == nil ? " " : "−") \(value) \(up == nil ? "" : "+")"
        case .note(let s): return s
        case .button(let title, _): return "[\(title)]"
        }
    }
}

/// The steppers' moves, rounded to two decimals like [math]::Round; nil where the value cannot move that way.
/// Size steps 0.1 within the config's range; opacity 0.05 within the original window's 0.3–1.0.
enum ConfigStep {
    static let scaleStep = 0.1
    static let scaleRange = ConfigLimits.ranges[.scale]!
    static let opacityStep = 0.05
    static let opacityRange = 0.3 ... 1.0

    static func larger(_ scale: Double) -> Double? { step(scale, scaleStep, scaleRange) }
    static func smaller(_ scale: Double) -> Double? { step(scale, -scaleStep, scaleRange) }
    static func moreOpaque(_ opacity: Double) -> Double? { step(opacity, opacityStep, opacityRange) }
    static func lessOpaque(_ opacity: Double) -> Double? { step(opacity, -opacityStep, opacityRange) }

    /// A hand-set value outside the range only moves back into it, never further out.
    private static func step(_ value: Double, _ delta: Double, _ range: ClosedRange<Double>) -> Double? {
        let v = min(range.upperBound, max(range.lowerBound, ((value + delta) * 100).rounded(.toNearestOrEven) / 100))
        return delta > 0 ? (v > value ? v : nil) : (v < value ? v : nil)
    }
}
