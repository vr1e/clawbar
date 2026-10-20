import AppKit
import Testing
@testable import ClawBar
import ClawBarShared

/// Draws an NSImage into an sRGB bitmap so tests can read its pixels in points (top-left origin).
struct Raster {
    let width: Int, height: Int, scale: CGFloat
    let bytes: [UInt8]

    init(_ image: NSImage, scale: CGFloat = 2) {
        self.scale = scale
        width = Int((image.size.width * scale).rounded())
        height = Int((image.size.height * scale).rounded())
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let w = width, h = height
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            NSGraphicsContext.restoreGraphicsState()
        }
        bytes = buf
    }

    init(_ cg: CGImage, scale: CGFloat) {
        self.scale = scale
        width = cg.width
        height = cg.height
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let w = width, h = height
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        bytes = buf
    }

    /// The pixel under the point (x, y) in points, y down from the top; un-premultiplied.
    func color(atPoint x: CGFloat, _ y: CGFloat) -> RGBA {
        let px = min(width - 1, max(0, Int(x * scale)))
        let py = min(height - 1, max(0, Int(y * scale)))
        let i = (py * width + px) * 4
        let a = bytes[i + 3]
        func un(_ v: UInt8) -> UInt8 { a == 0 ? 0 : UInt8(min(255, (Int(v) * 255 + Int(a) / 2) / Int(a))) }
        return RGBA(a: a, r: un(bytes[i]), g: un(bytes[i + 1]), b: un(bytes[i + 2]))
    }

    func count(in rect: CGRect, where test: (RGBA) -> Bool) -> Int {
        var n = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                if test(color(atPoint: x, y)) { n += 1 }
                x += 1 / scale
            }
            y += 1 / scale
        }
        return n
    }
}

func close(_ a: RGBA, _ b: RGBA, tolerance: Int = 3) -> Bool {
    abs(Int(a.a) - Int(b.a)) <= tolerance && abs(Int(a.r) - Int(b.r)) <= tolerance
        && abs(Int(a.g) - Int(b.g)) <= tolerance && abs(Int(a.b) - Int(b.b)) <= tolerance
}

@Suite struct StatusItemImageTests {
    @Test func thePillKeepsOneWidthWhateverTheNumber() {
        let images = ["--", "7", "42", "100"].map { StatusItemImage.make(text: $0, color: Palette.ok, mascot: true) }
        #expect(Set(images.map { $0.size.width }).count == 1)
        #expect(images.allSatisfy { $0.size == StatusItemImage.size(mascot: true) })
        // "100" is the widest text and must still fit inside the pill with room to spare.
        #expect(StatusItemImage.textWidth("100") + 4 <= StatusItemImage.pillRect(mascot: true).width)
    }

    @Test func clawdStandsLeftOfThePillAtOnePointPerPixel() {
        #expect(StatusItemImage.clawdRect.size == CGSize(width: 18, height: 12))
        #expect(StatusItemImage.clawdRect.maxX < StatusItemImage.pillRect(mascot: true).minX)
        #expect(StatusItemImage.size(mascot: true).height <= 22)
    }

    @Test func withoutClawdThePillStandsAloneAtTheLeftEdge() {
        let pill = StatusItemImage.pillRect(mascot: false)
        #expect(pill.minX == 0)
        #expect(pill.size == StatusItemImage.pillRect(mascot: true).size)
        #expect(StatusItemImage.size(mascot: false) == CGSize(width: pill.maxX, height: StatusItemImage.height))
        let image = StatusItemImage.make(text: "42", color: Palette.ok, mascot: false)
        #expect(image.size == StatusItemImage.size(mascot: false))
        let r = Raster(image)
        #expect(close(r.color(atPoint: pill.minX + 3, pill.midY), Palette.ok))
        let body = r.count(in: CGRect(origin: .zero, size: image.size)) { close($0, Palette.clawdBody) }
        #expect(body == 0, "no Clawd anywhere")
    }

    @Test func colorsAreClawdsThePillsLevelAndBlackText() {
        let image = StatusItemImage.make(text: "42", color: Palette.warn, mascot: true)
        #expect(!image.isTemplate)
        let r = Raster(image)
        let clawd = StatusItemImage.clawdRect
        // Row 4 column 1 is body, row 2 column 5 an eye (PixelArt.clawdStanding).
        #expect(close(r.color(atPoint: clawd.minX + 1.5, clawd.minY + 4.5), Palette.clawdBody))
        #expect(close(r.color(atPoint: clawd.minX + 5.5, clawd.minY + 2.5), Palette.clawdEyes))
        let pill = StatusItemImage.pillRect(mascot: true)
        #expect(close(r.color(atPoint: pill.minX + 3, pill.midY), Palette.warn))
        let dark = r.count(in: pill.insetBy(dx: 4, dy: 2)) { $0.a > 200 && Int($0.r) + Int($0.g) + Int($0.b) < 120 }
        #expect(dark > 10, "the digits are drawn in black")
        #expect(r.color(atPoint: 0.25, 0.25).a == 0, "the corner stays transparent")
    }

    @Test func withoutDataThePillIsDeadGrey() {
        let r = Raster(StatusItemImage.make(text: "--", color: Palette.dead, mascot: true))
        let pill = StatusItemImage.pillRect(mascot: true)
        #expect(close(r.color(atPoint: pill.minX + 3, pill.midY), Palette.dead))
    }

    @Test func theImageIsRebuiltOnlyWhenTextColourOrClawdChanges() {
        let cache = StatusItemImageCache()
        let a = cache.image(text: "42", color: Palette.ok, mascot: true)
        let b = cache.image(text: "42", color: Palette.ok, mascot: true)
        #expect(a === b)
        #expect(cache.builds == 1)
        let c = cache.image(text: "43", color: Palette.ok, mascot: true)
        #expect(c !== a)
        let d = cache.image(text: "43", color: Palette.warn, mascot: true)
        #expect(d !== c)
        #expect(cache.builds == 3)
        _ = cache.image(text: "43", color: Palette.warn, mascot: true)
        #expect(cache.builds == 3)
        let e = cache.image(text: "43", color: Palette.warn, mascot: false)
        #expect(e !== d)
        #expect(cache.builds == 4)
    }
}
