import CoreGraphics
import Foundation
import ClawBarShared
import ClawBarSky

/// The sky's size in base units, as the app passes it.
let skySize = PlayArea.skySize

enum Zones {
    static let utc = TimeZone(identifier: "UTC")!
    static let berlin = TimeZone(identifier: "Europe/Berlin")!
    static let oslo = TimeZone(identifier: "Europe/Oslo")!
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let reykjavik = TimeZone(identifier: "Atlantic/Reykjavik")!
}

/// A wall-clock moment in `zone`.
func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0, in zone: TimeZone) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = zone
    return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

/// 2026-10-17 at `minutes` after UTC midnight.
func utcDay(_ minutes: Double) -> Date {
    local(2026, 10, 17, 0, 0, in: Zones.utc).addingTimeInterval(minutes * 60)
}

func inputs(
    _ now: Date, zone: TimeZone = Zones.utc, sun: SunTimes = .fallback, weather: SkyWeather? = SkyWeather(code: 0, windKmh: 8),
    latitude: Double = 50, phase: SkyPhase? = nil
) -> SkyInputs {
    SkyInputs(now: now, timeZone: zone, sun: sun, weather: weather, latitude: latitude, forcedPhase: phase)
}

/// One step of a fresh engine.
func firstFrame(_ inputs: SkyInputs, random: any RandomSource = SeededRandomSource(seed: 1)) -> SkyFrame {
    SkyEngine(random: random).step(size: skySize, inputs: inputs)
}

/// Every draw is the same: `double` from nextDouble, `int` (clamped below the bound) from nextInt.
final class FixedRandom: RandomSource {
    var double: Double
    var int: Int

    init(double: Double = 0.5, int: Int = 1) {
        self.double = double
        self.int = int
    }

    func nextDouble() -> Double { double }
    func nextInt(_ upperBound: Int) -> Int { upperBound > 1 ? min(int, upperBound - 1) : 0 }
}

/// Hands out `doubles` in order, then `rest`; ints from `ints`, then `restInt`. Counts the int draws.
final class ScriptedRandom: RandomSource {
    private var doubles: [Double]
    private var ints: [Int]
    let rest: Double
    let restInt: Int
    private(set) var intDraws = 0

    init(_ doubles: [Double] = [], rest: Double = 0.5, ints: [Int] = [], restInt: Int = 1) {
        self.doubles = doubles
        self.ints = ints
        self.rest = rest
        self.restInt = restInt
    }

    func nextDouble() -> Double {
        return doubles.isEmpty ? rest : doubles.removeFirst()
    }

    func nextInt(_ upperBound: Int) -> Int {
        intDraws += 1
        let n = ints.isEmpty ? restInt : ints.removeFirst()
        return upperBound > 1 ? min(n, upperBound - 1) : 0
    }
}

/// A frame's ops sorted by sprite, recognised by the original's colours and pixel sizes.
struct Sprites {
    struct Layer {
        var rects: [CGRect]
        var color: RGBA
        var opacity: Double
    }

    var stars: [Layer] = []
    var moonDark: Layer?
    var moonLit: Layer?
    var glow: (rect: CGRect, opacity: Double)?
    var sun: Layer?
    var clouds: [Layer] = []
    var fog: [(rect: CGRect, opacity: Double)] = []
    var drops: Layer?
    var flakes: Layer?
    var ground: Layer?
    var flash: Layer?
    /// Sprite names in op order, to check the z-order.
    var order: [String] = []

    init(_ frame: SkyFrame) {
        for op in frame.ops {
            switch op {
            case .radialGlow(let rect, _, _, let opacity):
                glow = (rect, opacity)
                order.append("glow")
            case .hGradient(let rect, _, let opacity):
                fog.append((rect, opacity))
                order.append("fog")
            case .rects(let rects, let color, let opacity):
                let layer = Layer(rects: rects, color: color, opacity: opacity)
                let height = rects.first?.height ?? 0
                switch color {
                case RGBA("#2EE5E7EB"): moonDark = layer; order.append("moonDark")
                case RGBA("#FFF1F5F9"): moonLit = layer; order.append("moonLit")
                case RGBA("#8093C5FD"): drops = layer; order.append("rain")
                case RGBA("#C0E4E4E7"): flakes = layer; order.append("snow")
                case RGBA("#FFF8FAFC") where height < 2: stars.append(layer); order.append("stars")
                case RGBA("#FFF8FAFC"): flash = layer; order.append("flash")
                default:
                    if abs(height - 1.4) < 1e-9 {
                        sun = layer
                        order.append("sun")
                    } else if abs(height - 2) < 1e-9 {
                        clouds.append(layer)
                        order.append("clouds")
                    } else {
                        ground = layer
                        order.append("ground")
                    }
                }
            case .text:
                order.append("text")
            }
        }
    }
}

/// Pixel rows of `rects` laid out on a `px` grid from `origin`, '#' where a rect covers the cell.
func pixelRows(_ rects: [CGRect], px: Double, origin: CGPoint, columns: Int, rows: Int) -> [String] {
    (0 ..< rows).map { y in
        String((0 ..< columns).map { x -> Character in
            let cx = origin.x + (Double(x) + 0.5) * px, cy = origin.y + (Double(y) + 0.5) * px
            return rects.contains { $0.contains(CGPoint(x: cx, y: cy)) } ? "#" : "."
        })
    }
}

/// The top-left corner of a sprite's rects.
func topLeft(_ rects: [CGRect]) -> CGPoint {
    CGPoint(x: rects.map(\.minX).min() ?? .nan, y: rects.map(\.minY).min() ?? .nan)
}

func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

func near(_ a: CGPoint, _ b: CGPoint, _ eps: Double = 1e-9) -> Bool { near(a.x, b.x, eps) && near(a.y, b.y, eps) }
