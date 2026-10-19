import CoreGraphics

/// Pixel art shared by the widget and the menu bar item. '#' is body (or the heart), 'o' is Clawd's face.
public enum PixelArt {
    /// Clawd standing: open eyes, arms down, both feet. 18 × 12 pixels, from the original's fixture.
    public static let clawdStanding: [String] = [
        "...#############..",
        "...#############..",
        "...##o#######o##..",
        "...##o#######o##..",
        ".#################",
        ".#################",
        "...#############..",
        "...#############..",
        "...#.#.......#.#..",
        "...#.#.......#.#..",
        "..................",
        "..................",
    ]

    /// 7 × 6; a half heart is columns 0..<4.
    public static let heart: [String] = [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
    public static let heartPx = 1.4
    public static let heartHalfColumns = 4
    /// Between hearts 1 and 2, and 2 and 3.
    public static let heartGap = 2.5

    /// One rect per horizontal run of `value`, each pixel `px` × `py`, columns before `maxColumn` only.
    public static func rects(
        _ rows: [String], value: Character, px: Double, py: Double, origin: CGPoint = .zero, maxColumn: Int = .max
    ) -> [CGRect] {
        var out: [CGRect] = []
        for (y, row) in rows.enumerated() {
            let cells = Array(row.prefix(maxColumn))
            var x = 0
            while x < cells.count {
                guard cells[x] == value else {
                    x += 1
                    continue
                }
                let start = x
                while x < cells.count, cells[x] == value { x += 1 }
                out.append(CGRect(
                    x: origin.x + Double(start) * px, y: origin.y + Double(y) * py,
                    width: Double(x - start) * px, height: py
                ))
            }
        }
        return out
    }
}

/// Clawd Run's sprites: '#' is body or obstacle, 'o' is Clawd's face, as in `PixelArt`.
public enum RunnerArt {
    /// Running, legs apart; rows 10 and 11 stay empty like `PixelArt.clawdStanding`'s.
    public static let clawdRunA: [String] = [
        "...#############..",
        "...#############..",
        "...##o#######o##..",
        "...##o#######o##..",
        ".#################",
        ".#################",
        "...#############..",
        "...#############..",
        "...#.#.......#.#..",
        "..#...#.....#...#.",
        "..................",
        "..................",
    ]

    /// Running, legs together.
    public static let clawdRunB: [String] = [
        "...#############..",
        "...#############..",
        "...##o#######o##..",
        "...##o#######o##..",
        ".#################",
        ".#################",
        "...#############..",
        "...#############..",
        "....#.#.....#.#...",
        "....#.#.....#.#...",
        "..................",
        "..................",
    ]

    /// Ducking: squashed to six rows and stretched forward.
    public static let clawdDuckA: [String] = [
        "...################.",
        "...##o##########o##.",
        "#####################",
        "#####################",
        "...################.",
        "...#.#..........#.#.",
    ]

    public static let clawdDuckB: [String] = [
        "...################.",
        "...##o##########o##.",
        "#####################",
        "#####################",
        "...################.",
        "....#.#........#.#..",
    ]

    /// After a crash: the eyes squeezed shut.
    public static let clawdCrashed: [String] = [
        "...#############..",
        "...#############..",
        "...#oo#######oo#..",
        "...#############..",
        ".#################",
        ".#################",
        "...#############..",
        "...#############..",
        "...#.#.......#.#..",
        "...#.#.......#.#..",
        "..................",
        "..................",
    ]

    public static let cactusSmall: [String] = [
        "..##..",
        "..##..",
        "#.##..",
        "#.##.#",
        "#.##.#",
        "####.#",
        "..####",
        "..##..",
        "..##..",
        "..##..",
        "..##..",
    ]

    public static let cactusLarge: [String] = [
        "...##...",
        "..####..",
        "..####..",
        "#.####..",
        "#.####.#",
        "#.####.#",
        "#.####.#",
        "######.#",
        "..######",
        "..####..",
        "..####..",
        "..####..",
        "..####..",
        "..####..",
        "..####..",
    ]

    /// A flying bug, side on and facing its way, wings up.
    public static let bugA: [String] = [
        "......##....",
        ".....####...",
        "..##..##....",
        ".#o#######..",
        ".##########.",
        "..########..",
        "...#.#.#....",
    ]

    /// Wings swept back.
    public static let bugB: [String] = [
        "............",
        "............",
        "..##...####.",
        ".#o#######..",
        ".##########.",
        "..########..",
        "...#.#.#....",
    ]

    /// A cloud for the background.
    public static let cloud: [String] = [
        "....######....",
        "..##########..",
        "##############",
        ".############.",
    ]

    /// Rows that hold any pixel, from the bottom: what stands on the ground.
    public static func usedHeight(_ rows: [String]) -> Int {
        (rows.lastIndex { $0.contains { $0 != "." } } ?? -1) + 1
    }

    public static func width(_ rows: [String]) -> Int {
        rows.map(\.count).max() ?? 0
    }
}
