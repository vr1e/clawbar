import CoreGraphics
import ClawBarShared

/// A sprite measured once: its runs of each value at the origin, its width and the height it stands on.
struct Sprite {
    let width: Double
    /// Down to the lowest row that holds a pixel: what stands on the ground.
    let usedHeight: Double
    private let runs: [Character: [CGRect]]

    init(_ rows: [String]) {
        let px = RunnerTuning.px
        width = Double(rows.map(\.count).max() ?? 0) * px
        usedHeight = Double((rows.lastIndex { $0.contains { $0 != "." } } ?? -1) + 1) * px
        runs = Dictionary(uniqueKeysWithValues: ["#", "o"].map { ($0, PixelArt.rects(rows, value: $0, px: px, py: px)) })
    }

    /// The runs of `value` ('#' body or obstacle, 'o' a face) with the sprite's top-left at `origin`.
    func rects(_ value: Character, at origin: CGPoint) -> [CGRect] {
        (runs[value] ?? []).map { $0.offsetBy(dx: origin.x, dy: origin.y) }
    }
}

/// Clawd Run's sprites: '#' is body or obstacle, 'o' is Clawd's face, as in `PixelArt`.
enum RunnerArt {
    static let clawdStanding = Sprite(PixelArt.clawdStanding)

    /// Running, legs apart; rows 10 and 11 stay empty like `PixelArt.clawdStanding`'s.
    static let clawdRunA = Sprite(standing(replacing: 8 ... 9, with: [
        "...#.#.......#.#..",
        "..#...#.....#...#.",
    ]))

    /// Running, legs together.
    static let clawdRunB = Sprite(standing(replacing: 8 ... 9, with: [
        "....#.#.....#.#...",
        "....#.#.....#.#...",
    ]))

    /// Ducking: squashed to six rows and stretched forward.
    static let clawdDuckA = Sprite([
        "...################.",
        "...##o##########o##.",
        "#####################",
        "#####################",
        "...################.",
        "...#.#..........#.#.",
    ])

    static let clawdDuckB = Sprite([
        "...################.",
        "...##o##########o##.",
        "#####################",
        "#####################",
        "...################.",
        "....#.#........#.#..",
    ])

    /// After a crash: the eyes squeezed shut.
    static let clawdCrashed = Sprite(standing(replacing: 2 ... 3, with: [
        "...#oo#######oo#..",
        "...#############..",
    ]))

    static let cactusSmall = Sprite([
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
    ])

    static let cactusLarge = Sprite([
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
    ])

    /// A flying bug, side on and facing its way, wings up.
    static let bugA = Sprite([
        "......##....",
        ".....####...",
        "..##..##....",
        ".#o#######..",
        ".##########.",
        "..########..",
        "...#.#.#....",
    ])

    /// Wings swept back.
    static let bugB = Sprite([
        "............",
        "............",
        "..##...####.",
        ".#o#######..",
        ".##########.",
        "..########..",
        "...#.#.#....",
    ])

    /// A cloud for the background.
    static let cloud = Sprite([
        "....######....",
        "..##########..",
        "##############",
        ".############.",
    ])

    /// Clawd standing with some rows swapped, so every pose keeps the fixture's body.
    private static func standing(replacing rows: ClosedRange<Int>, with replacement: [String]) -> [String] {
        var out = PixelArt.clawdStanding
        out.replaceSubrange(rows, with: replacement)
        return out
    }
}
