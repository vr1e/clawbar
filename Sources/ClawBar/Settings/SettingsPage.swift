import ClawBarShared

/// A change asked for in the Settings window.
enum SettingsAction: Hashable {
    case step(SteppedSetting, up: Bool)
    case toggleTopmost, toggleMainWeek, toggleLaunchAtLogin, toggleMenuBarMascot
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
        case .widget: .setTabWidget
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
    /// A line under the title saying what the switch changes.
    var detail: String?
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
        func toggle(
            _ key: L10nKey, _ on: Bool, _ action: SettingsAction, enabled: Bool = true, detail: L10nKey? = nil
        ) -> SettingsRow {
            .toggle(SettingsOption(title: t(key), on: on, enabled: enabled, action: action, detail: detail.map(t)))
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
                SettingsSection(rows: SteppedSetting.allCases.map { s in
                    let v = config[keyPath: s.key]
                    return .stepper(
                        title: t(s.title), value: percent(v),
                        decrease: s.next(from: v, up: false).map { _ in .step(s, up: false) },
                        increase: s.next(from: v, up: true).map { _ in .step(s, up: true) }
                    )
                } + [
                    toggle(.setTopmost, config.topmost, .toggleTopmost),
                    toggle(.setMainWeek, config.mainLimit == .week, .toggleMainWeek, detail: .setMainWeekTip),
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
        case .toggle(let o): return (o.on ? "[x] " : "[ ] ") + o.title + disabled(o) + (o.detail.map { "\n        " + $0 } ?? "")
        case .picker(let title, let options):
            return title + ": " + options.map { ($0.on ? "(•) " : "( ) ") + $0.title }.joined(separator: "  ")
        case .stepper(let title, let value, let down, let up):
            return "\(title): \(down == nil ? " " : "−") \(value) \(up == nil ? "" : "+")"
        case .note(let s): return s
        case .button(let title, _): return "[\(title)]"
        }
    }
}

/// The settings a stepper moves: size by 0.1 within the config's range, opacity by 0.05 within the original
/// window's 0.3–1.0.
enum SteppedSetting: CaseIterable, Hashable {
    case size, opacity

    var title: L10nKey {
        switch self {
        case .size: .setSize
        case .opacity: .setOpacity
        }
    }

    var key: WritableKeyPath<Config, Double> {
        switch self {
        case .size: \.scale
        case .opacity: \.opacity
        }
    }

    private var step: Double { self == .size ? 0.1 : 0.05 }
    private var range: ClosedRange<Double> { self == .size ? ConfigLimits.ranges[.scale]! : 0.3 ... 1.0 }

    /// One step, rounded to two decimals like [math]::Round; nil where the value cannot move that way.
    /// Clamped only at the end it moves toward: 0.2 opacity steps up to 0.25 as in the original; '−' stays disabled.
    func next(from value: Double, up: Bool) -> Double? {
        let v = ((value + (up ? step : -step)) * 100).rounded(.toNearestOrEven) / 100
        let c = up ? min(range.upperBound, v) : max(range.lowerBound, v)
        return (up ? c > value : c < value) ? c : nil
    }
}
