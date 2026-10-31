import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import ClawBarShared

/// The card drawn offscreen, for snapshots and recordings.
enum CardRenderer {
    /// One render: the view state, what shows, and the animation's frame.
    struct Input {
        var view: WidgetViewState
        var mascotVisible = true
        var skyVisible = true
        var animation = AnimationFrame.empty
        var historyHover: HistoryHover?
    }

    /// The card at scale `k`, `pixelScale` pixels per point. Renders twice when needed so the number's
    /// measured width (which places Clawd) has settled; pass the same `layout` across frames to skip that.
    static func render(_ input: Input, scale k: Double, pixelScale: Double = 2, layout: LayoutModel = LayoutModel()) -> CGImage? {
        let app = AppModel()
        app.view = input.view
        app.scale = k
        app.mascotVisible = input.mascotVisible
        app.skyVisible = input.skyVisible
        app.historyHover = input.historyHover
        let animation = AnimationModel()
        animation.publish(input.animation)
        func pass() -> CGImage? {
            let renderer = ImageRenderer(content: CardView(app: app, animation: animation, layout: layout).environment(\.uiScale, k))
            renderer.scale = pixelScale
            return renderer.cgImage
        }
        let width = layout.numberWidth
        let first = pass()
        return layout.numberWidth == width ? first : pass()
    }
}

/// Clawd Run drawn offscreen, for snapshots.
enum GameRenderer {
    /// One frame at the canvas's base size, `pixelScale` pixels per point.
    static func render(_ frame: RunnerFrame, pixelScale: Double = 2) -> CGImage? {
        let model = GameModel()
        model.frame = frame
        let renderer = ImageRenderer(content: GameView(model: model).frame(width: RunnerTuning.width, height: RunnerTuning.height))
        renderer.scale = pixelScale
        return renderer.cgImage
    }
}

enum Imaging {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// The image on a solid backdrop with `pad` pixels around it, like compose-gif.py's GitHub-dark canvas.
    static func onBackdrop(_ image: CGImage, pad: Int, color: RGBA) -> CGImage? {
        guard let ctx = context(width: image.width + 2 * pad, height: image.height + 2 * pad) else { return nil }
        ctx.setFillColor(cgColor(color))
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        ctx.draw(image, in: CGRect(x: pad, y: pad, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    static func scaled(_ image: CGImage, by factor: Double) -> CGImage? {
        let w = max(1, Int((Double(image.width) * factor).rounded())), h = max(1, Int((Double(image.height) * factor).rounded()))
        guard let ctx = context(width: w, height: h) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func image(_ ns: NSImage, pixelScale: Double, background: RGBA? = nil, pad: Double = 0) -> CGImage? {
        let w = Int(((ns.size.width + 2 * pad) * pixelScale).rounded()), h = Int(((ns.size.height + 2 * pad) * pixelScale).rounded())
        guard let ctx = context(width: w, height: h) else { return nil }
        if let background {
            ctx.setFillColor(cgColor(background))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ns.draw(in: CGRect(x: pad * pixelScale, y: pad * pixelScale, width: ns.size.width * pixelScale, height: ns.size.height * pixelScale))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// An AppKit view at its fitting size, drawn offscreen at `pixelScale`; a window gives its controls their appearance.
    static func image(of view: NSView, pixelScale: Double = 2) -> CGImage? {
        let size = view.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: true)
        window.appearance = view.appearance
        window.contentView = view
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * pixelScale), pixelsHigh: Int(size.height * pixelScale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let drawn = rep.cgImage, let ctx = context(width: drawn.width, height: drawn.height) else { return nil }
        // A real window paints the margins a view leaves clear; offscreen they would stay transparent.
        var background = CGColor.white
        view.effectiveAppearance.performAsCurrentDrawingAppearance { background = NSColor.windowBackgroundColor.cgColor }
        let bounds = CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height)
        ctx.setFillColor(background)
        ctx.fill(bounds)
        ctx.draw(drawn, in: bounds)
        return ctx.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CLIError(message: "cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CLIError(message: "cannot write \(url.path)") }
    }
}
