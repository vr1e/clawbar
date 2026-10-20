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
