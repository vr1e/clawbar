import Foundation

/// The colours a theme changes, one per role, as theme.ps1's `$ThemeBase` names them; every other colour is a `Palette`
/// constant. The presenter resolves one into each view state, so roles that share a value in classic never recolour
/// each other: the label's grey is the dead level's too.
public struct ThemePalette: Sendable, Hashable {
    /// The card's and Clawd Run's background: theme.ps1's `bg`, not its `card`.
    public var background: RGBA
    /// theme.ps1's `text2`.
    public var secondary: RGBA
    /// theme.ps1's `muted`.
    public var muted: RGBA
    /// theme.ps1's `dim`.
    public var label: RGBA
    /// theme.ps1's `faint`.
    public var footer: RGBA
    /// theme.ps1's `accent`: the week bar and the chart's week line share it, so a theme moves both.
    public var accent: RGBA
    /// The model weeks' bars: Space's accent is this violet, so they need a role of their own to stay apart.
    public var modelWeekBar: RGBA
    /// The grey under each header heart (`off`).
    public var heartOff: RGBA

    public init(
        background: RGBA, secondary: RGBA, muted: RGBA, label: RGBA, footer: RGBA, accent: RGBA, modelWeekBar: RGBA,
        heartOff: RGBA
    ) {
        self.background = background
        self.secondary = secondary
        self.muted = muted
        self.label = label
        self.footer = footer
        self.accent = accent
        self.modelWeekBar = modelWeekBar
        self.heartOff = heartOff
    }

    public static let classic = ThemePalette(
        background: Palette.card, secondary: Palette.secondary, muted: Palette.muted, label: Palette.label,
        footer: Palette.footer, accent: Palette.weekBar, modelWeekBar: Palette.modelWeekBar, heartOff: Palette.heartOff
    )
}

/// A named look whose colours are a theme palette: theme.ps1's `$Themes`, in its order. Upstream's `cyberpunk` (1.18.0) is not ported yet.
public enum Theme: String, Sendable, CaseIterable {
    case classic, oled, midnight, mocha, forest, halloween, space, ocean

    /// theme.ps1's row: `bg`, `text2`, `muted`, `dim`, `faint`, `accent` and `off`; the rest of a row has no role here.
    public var palette: ThemePalette {
        func row(_ bg: String, _ text2: String, _ muted: String, _ dim: String, _ faint: String, _ accent: String,
                 _ off: String, modelWeekBar: RGBA = Palette.modelWeekBar) -> ThemePalette {
            ThemePalette(
                background: RGBA(bg), secondary: RGBA(text2), muted: RGBA(muted), label: RGBA(dim), footer: RGBA(faint),
                accent: RGBA(accent), modelWeekBar: modelWeekBar, heartOff: RGBA(off)
            )
        }
        switch self {
        case .classic: return .classic
        case .oled:
            var p = ThemePalette.classic
            p.background = Palette.black
            return p
        case .midnight: return row("#FF0F172A", "#FFCBD5E1", "#FF8494AB", "#FF64748B", "#FF475569", "#FF38BDF8", "#FF334155")
        case .mocha: return row("#FF1E1E2E", "#FFBAC2DE", "#FF9399B2", "#FF7F849C", "#FF585B70", "#FF89B4FA", "#FF45475A")
        case .forest: return row("#FF111814", "#FFCFDBD2", "#FF86998B", "#FF66786B", "#FF4B5B50", "#FF5EEAD4", "#FF35433A")
        case .halloween: return row("#FF1C1326", "#FFE7D3C4", "#FFA08B9C", "#FF7E6A80", "#FF5B4A63", "#FFF97316", "#FF3F3048")
        // Its violet accent is upstream's model-week bar, so the model weeks turn pink to stay apart from the week.
        case .space:
            return row(
                "#FF0E0820", "#FFD6D0EE", "#FF9A90BE", "#FF746A99", "#FF544A78", "#FFA78BFA", "#FF3A3160",
                modelWeekBar: RGBA("#FFF472B6")
            )
        case .ocean: return row("#FF0A2236", "#FFCDE6F5", "#FF86A9BF", "#FF62849A", "#FF456679", "#FF22D3EE", "#FF2F4C5E")
        }
    }
}

/// config.json's `theme`: one theme, or `auto`, which follows the season as upstream's default does.
public enum ThemeChoice: Sendable, Hashable {
    case bySeason
    case fixed(Theme)

    /// Every choice in upstream's picker order: by season first.
    public static let all: [ThemeChoice] = [.bySeason] + Theme.allCases.map(ThemeChoice.fixed)

    /// Case-insensitive; anything unknown is classic, as theme.ps1's `Get-ThemeId`.
    public init(configValue: String?) {
        let s = (configValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = s == "auto" ? .bySeason : .fixed(Theme(rawValue: s) ?? .classic)
    }

    public var configValue: String {
        switch self {
        case .bySeason: "auto"
        case .fixed(let t): t.rawValue
        }
    }

    /// Halloween from September to November in the given zone, classic otherwise (`Get-SeasonThemeId`).
    public func theme(at now: Date, in zone: TimeZone) -> Theme {
        guard case .fixed(let t) = self else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return (9 ... 11).contains(calendar.component(.month, from: now)) ? .halloween : .classic
        }
        return t
    }
}
