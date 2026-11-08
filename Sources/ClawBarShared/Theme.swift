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

/// A named look whose colours are a theme palette: theme.ps1's `$Themes`, in its order.
public enum Theme: String, Sendable, CaseIterable {
    case classic, oled, midnight, mocha, forest, halloween, space, ocean, christmas, cyberpunk

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
        case .christmas: return row("#FF231317", "#FFE6D3D0", "#FFA08A88", "#FF7E6865", "#FF5C4A4A", "#FF7DD3FC", "#FF413236")
        case .cyberpunk: return row("#FF0C0B16", "#FFCBD9E3", "#FF8494A8", "#FF65708A", "#FF474F66", "#FF00E5FF", "#FF33364A")
        }
    }

    /// theme.ps1's `scene`: the animation behind the card's content and in the sky row, or none.
    public var scene: SceneID? {
        switch self {
        case .classic, .oled, .midnight, .mocha, .forest, .cyberpunk: return nil
        case .halloween: return .halloween
        case .space: return .space
        case .ocean: return .ocean
        case .christmas: return .christmas
        }
    }

    /// theme.ps1's `pattern`: the faint wallpaper under the card's content, or none.
    public var pattern: ThemePattern? {
        switch self {
        case .classic, .oled, .midnight, .mocha, .forest: return nil
        case .halloween: return .halloween
        case .space: return .space
        case .ocean: return .ocean
        case .christmas: return .christmas
        case .cyberpunk: return .cyberpunk
        }
    }
}

/// One tile of pixel sprites repeated over the card under its content, as theme.ps1's `$Patterns`.
public struct ThemePattern: Sendable, Hashable {
    /// The tile's side, in base units.
    public var tile: Double
    /// One `.rects` per colour, in the colour letters' order so a tile always draws the same.
    public var layers: [DrawOp]

    /// `sprites` place art rows at x, y in the tile; '.' and any letter missing from `colors` are empty.
    public init(tile: Double, px: Double, opacity: Double, colors: [Character: String],
                sprites: [(x: Double, y: Double, art: [String])]) {
        self.tile = tile
        // No two pixels overlap, so fading each colour equals upstream's fading the whole brush.
        layers = colors.sorted { $0.key < $1.key }.map { letter, hex in
            .rects(sprites.flatMap {
                PixelArt.rects($0.art, value: letter, px: px, py: px, origin: CGPoint(x: $0.x, y: $0.y))
            }, RGBA(hex), opacity: opacity)
        }
    }

    public static let halloween = ThemePattern(
        tile: 104, px: 2, opacity: 0.1,
        colors: ["o": "#FFF97316", "g": "#FF65A30D", "b": "#FFA78BFA", "w": "#FFF5F5F4", "y": "#FFFDE047"],
        sprites: [
            (6, 6, ["....gg...", "...g.....", ".ooo.ooo.", "ooooooooo", "oo.ooo.oo", "ooooooooo", "oo.o.o.oo", ".ooooooo."]),
            (58, 20, ["b.........b", "bb..b.b..bb", "bbbbbbbbbbb", ".bbb.b.bbb.", "..b.....b.."]),
            (30, 56, ["..www..", ".wwwww.", "ww.w.ww", "wwwwwww", "wwwwwww", "wwwwwww", "w.w.w.w"]),
            (76, 70, [".y.", "yyy", ".y."]),
            (8, 84, ["y"]),
            (92, 4, ["y"]),
        ]
    )

    public static let space = ThemePattern(
        tile: 96, px: 1, opacity: 0.45,
        colors: ["w": "#FFFFFFFF", "v": "#FFC4B5FD", "p": "#FFF9A8D4", "b": "#FF93C5FD"],
        sprites: [
            (10, 8, ["w"]), (41, 22, ["v"]), (77, 12, ["b"]),
            (24, 47, ["p"]), (63, 58, [".w.", "www", ".w."]),
            (88, 40, ["v"]), (6, 79, ["b"]), (47, 86, ["w"]),
            (83, 81, ["p"]),
        ]
    )

    public static let ocean = ThemePattern(
        tile: 104, px: 2, opacity: 0.07,
        colors: ["w": "#FFE0F2FE", "p": "#FFF9A8D4", "y": "#FFFDE68A"],
        sprites: [
            (8, 10, [".ww.", "w..w", "w..w", ".ww."]),
            (22, 2, ["w"]),
            (56, 28, [".p.p.", "ppppp", ".pyp.", "ppppp", ".p.p."]),
            (30, 70, [".w.", "w.w", ".w."]),
            (84, 76, [".ww.", "w..w", "w..w", ".ww."]),
            (94, 62, ["w"]),
        ]
    )

    public static let christmas = ThemePattern(
        tile: 104, px: 2, opacity: 0.07,
        colors: ["w": "#FFF8FAFC", "r": "#FFF43F5E", "y": "#FFFCD34D", "b": "#FF7DD3FC"],
        sprites: [
            (6, 8, ["...w...", ".w.w.w.", "..www..", "wwwwwww", "..www..", ".w.w.w.", "...w..."]),
            (60, 14, ["..y.y..", "...y...", "rrryrrr", "rrryrrr", "yyyyyyy", "rrryrrr", "rrryrrr"]),
            (32, 58, [".rwr.", "w...w", "....r", "....w", "....r", "....w", "....r"]),
            (80, 66, ["..y..", ".bbb.", "bwbbb", "bbbbb", ".bbb."]),
            (10, 82, ["w"]),
            (92, 40, [".w.", "w.w", ".w."]),
        ]
    )

    /// Scanlines, as on an old monitor.
    public static let cyberpunk = ThemePattern(
        tile: 3, px: 1, opacity: 0.05, colors: ["c": "#FF00E5FF"], sprites: [(0, 0, ["ccc"])]
    )
}

/// config.json's `theme`: one theme, or `auto`, which follows the season as upstream's default does.
public enum ThemeChoice: RawRepresentable, Sendable, Hashable {
    case bySeason
    case fixed(Theme)

    /// Every choice in upstream's picker order: by season first.
    public static let all: [ThemeChoice] = [.bySeason] + Theme.allCases.map(ThemeChoice.fixed)

    /// Case-insensitive; anything unknown is classic, as theme.ps1's `Get-ThemeId`.
    public init(configValue: String?) {
        self = .parse(configValue) ?? .fixed(.classic)
    }

    public init?(rawValue: String) {
        guard rawValue != "auto" else {
            self = .bySeason
            return
        }
        guard let t = Theme(rawValue: rawValue) else { return nil }
        self = .fixed(t)
    }

    public var rawValue: String {
        switch self {
        case .bySeason: "auto"
        case .fixed(let t): t.rawValue
        }
    }

    /// The season's theme in the given zone, as `Get-SeasonThemeId`.
    public func theme(at now: Date, in zone: TimeZone) -> Theme {
        switch self {
        case .fixed(let t): return t
        case .bySeason:
            let calendar = Calendar.gregorian(in: zone)
            let month = calendar.component(.month, from: now), day = calendar.component(.day, from: now)
            switch month {
            case 9, 10: return .halloween
            case 11, 12: return .christmas
            case 1 where day <= 14: return .christmas
            default: return .classic
            }
        }
    }
}
