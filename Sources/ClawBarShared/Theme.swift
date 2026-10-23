import Foundation

/// The colours a theme changes, one per role, as theme.ps1's `$ThemeBase` names them; every other colour is a `Palette`
/// constant. The presenter resolves one into each view state, so roles that share a value in classic never recolour
/// each other: the label's grey is the dead level's too.
public struct ThemePalette: Sendable, Hashable {
    /// The card's and Clawd Run's background: theme.ps1's `bg`, not its `card`.
    public var background: RGBA
    /// The reset line, the stats' first lines, project names, the game's score and messages (`text2`).
    public var secondary: RGBA
    /// The header, row values, `%`, quiet status text and the legend (`muted`).
    public var muted: RGBA
    /// Row labels, the ClawBar line and the developer caption over the play area (`dim`).
    public var label: RGBA
    /// The account, the update stamp, the chart's weekdays and the game's hint (`faint`).
    public var footer: RGBA
    /// The week bar and the chart's week line (`accent`).
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
