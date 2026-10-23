import Foundation

/// An sRGB colour as WPF stores it: four bytes, alpha first.
public struct RGBA: Sendable, Hashable, CustomStringConvertible {
    public var a: UInt8
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(a: UInt8 = 255, r: UInt8, g: UInt8, b: UInt8) {
        self.a = a
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parses `#AARRGGBB` or `#RRGGBB` (the `#` is optional). Anything else is transparent black.
    public init(_ hex: String) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else {
            self.init(a: 0, r: 0, g: 0, b: 0)
            return
        }
        let a: UInt32 = s.count == 8 ? (v >> 24) & 0xFF : 0xFF
        self.init(a: UInt8(a), r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "#%02X%02X%02X%02X", a, r, g, b) }
    public var description: String { hex }

    public var alpha: Double { Double(a) / 255 }

    public func withAlpha(_ alpha: UInt8) -> RGBA { RGBA(a: alpha, r: r, g: g, b: b) }

    /// Per-channel ARGB lerp with `k` clamped to 0...1 (sky.ps1 Mix-Color).
    public static func mix(_ x: RGBA, _ y: RGBA, _ k: Double) -> RGBA {
        let k = k.isNaN ? 0 : min(1, max(0, k))
        func lerp(_ p: UInt8, _ q: UInt8) -> UInt8 { byte(Double(p) + (Double(q) - Double(p)) * k) }
        return RGBA(a: lerp(x.a, y.a), r: lerp(x.r, y.r), g: lerp(x.g, y.g), b: lerp(x.b, y.b))
    }

    /// Fades towards grey and darkens with cloud cover `g` (sky.ps1 Dim-Color); alpha is kept.
    public static func dim(_ c: RGBA, _ g: Double) -> RGBA {
        let l = 0.3 * Double(c.r) + 0.59 * Double(c.g) + 0.11 * Double(c.b)
        let f = 1 - 0.3 * g
        func ch(_ v: UInt8) -> UInt8 { byte((Double(v) + (l - Double(v)) * g) * f) }
        return RGBA(a: c.a, r: ch(c.r), g: ch(c.g), b: ch(c.b))
    }

    /// PowerShell's [byte] cast: banker's rounding, clamped to the byte range.
    public static func byte(_ v: Double) -> UInt8 {
        guard v.isFinite else { return 0 }
        return UInt8(clamping: Int(v.rounded(.toNearestOrEven)))
    }
}

/// Every colour of the original UI, named once.
public enum Palette {
    public static let ok = RGBA("#FF4ADE80")
    public static let warn = RGBA("#FFFBBF24")
    public static let crit = RGBA("#FFF87171")
    public static let dead = RGBA("#FF6B7280")

    public static let card = RGBA("#FF1A1A1E")
    public static let border = RGBA("#33FFFFFF")
    public static let white = RGBA("#FFFFFFFF")
    public static let black = RGBA("#FF000000")
    /// Header title and glyphs, row values, `%`, muted status text.
    public static let muted = RGBA("#FF8B8B94")
    /// Row labels (WEEK, SESSIONS, …) and the ClawBar version line.
    public static let label = RGBA("#FF6B7280")
    /// Reset line, status text with issues, the stats' first lines.
    public static let secondary = RGBA("#FFD4D4D8")
    /// Account and last-update stamp.
    public static let footer = RGBA("#FF52525B")
    public static let track = RGBA("#26FFFFFF")
    public static let divider = RGBA("#1AFFFFFF")
    public static let weekBar = RGBA("#FF60A5FA")
    public static let modelWeekBar = RGBA("#FFA78BFA")
    /// Under the 7-day chart's session line.
    public static let chartFill = RGBA("#264ADE80")
    /// The line under the pointer on the 7-day chart.
    public static let chartCursor = RGBA("#66FFFFFF")
    /// The bars of the week's top projects.
    public static let projectBar = clawdBody

    public static let clawdBody = RGBA("#FFD77757")
    public static let clawdEyes = RGBA("#FF141416")
    /// Dust puffs and the coin-hop shadow.
    public static let clawdFx = RGBA("#FF6B7280")
    public static let sand = RGBA("#FFB8955E")
    public static let sweat = RGBA("#FF7DD3FC")
    public static let zzz = RGBA("#FF8B8B94")
    public static let love = RGBA("#FFF87171")
    public static let soul = RGBA("#FFF4F4F5")
    /// The developer caption at the play area's top-left.
    public static let caption = RGBA("#FF6B7280")
    public static let dust = RGBA("#FF8B8B94")
    public static let confetti: [RGBA] = [
        RGBA("#FFF87171"), RGBA("#FFFBBF24"), RGBA("#FF4ADE80"),
        RGBA("#FF60A5FA"), RGBA("#FFA78BFA"), RGBA("#FFD77757"),
    ]
    public static let bubbleQuestion = RGBA("#FFFBBF24")
    public static let bubbleBang = RGBA("#FF4ADE80")
    public static let bubbleNote = RGBA("#FF93C5FD")

    public static let heartOn = RGBA("#FFF87171")
    public static let heartOff = RGBA("#FF3F3F46")
}

/// How close a percentage is to its limit.
public enum Level: String, Sendable, CaseIterable {
    case ok, warn, crit, dead

    public static func of(_ pct: Int, warn: Int, crit: Int) -> Level {
        if pct >= crit { return .crit }
        if pct >= warn { return .warn }
        return .ok
    }

    public var color: RGBA {
        switch self {
        case .ok: Palette.ok
        case .warn: Palette.warn
        case .crit: Palette.crit
        case .dead: Palette.dead
        }
    }
}
