import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ClawBarAnimation
import ClawBarPresenter
import ClawBarShared

/// `--record <scenario> <gif>`: record-gif.ps1 with a seeded RNG and a virtual clock, then compose-gif.py's framing.
enum Recorder {
    static let backdrop = RGBA(r: 13, g: 17, b: 23)

    static func run(_ scenario: RecordScenario, gif: URL) -> Int32 {
        let frames = record(scenario)
        do {
            try GIFWriter.write(frames, delay: 0.09, to: gif)
            print("wrote \(gif.path): \(frames.count) frames")
            return 0
        } catch {
            FileHandle.standardError.write(Data("ClawBar: \(error)\n".utf8))
            return 1
        }
    }

    static func record(_ s: RecordScenario, maxFrames: Int = .max, seed: UInt64 = 42) -> [CGImage] {
        let run = ScenarioRun(s, seed: seed)
        let layout = LayoutModel()
        var view = presenter(run.data, now: Samples.now, config: run.config)
        // A first pass measures the number, which sets the play area Clawd walks in.
        _ = CardRenderer.render(CardRenderer.Input(view: view), scale: 1, layout: layout)

        var cards: [CGImage] = []
        var cropHeight: Int?
        while cards.count < maxFrames, let f = run.next(numberWidth: layout.numberWidth) {
            if let data = f.data { view = presenter(data, now: f.at, config: run.config) }
            var animation = f.animation
            // The recorder collapses the developer caption.
            animation.clawd.devCaption = ""
            let card = CardRenderer.Input(view: view, animation: animation)
            guard let image = CardRenderer.render(card, scale: 1, layout: layout) else { break }
            if run.crop, cropHeight == nil, let reset = layout.rects[.reset] {
                cropHeight = Int(((reset.maxY + 9) * 2).rounded(.up))
            }
            cards.append(image)
        }
        return compose(cards, cropHeight: run.crop ? cropHeight : nil)
    }

    private static func presenter(_ data: DataSnapshot, now: Date, config: Config) -> WidgetViewState {
        WidgetPresenter.make(PresenterInput(
            config: config, now: now, timeZone: Samples.timeZone, data: data, appVersion: AppInfo.version,
            homeDirectory: Samples.home
        ))
    }

    /// compose-gif.py: every frame on one GitHub-dark canvas the size of the largest, 24 px of padding, scaled by 1/1.5.
    static func compose(_ cards: [CGImage], cropHeight: Int?) -> [CGImage] {
        let pad = 24
        let w = cards.map(\.width).max() ?? 0
        let h = cards.map { min($0.height, cropHeight ?? $0.height) }.max() ?? 0
        return cards.compactMap { card in
            guard let ctx = Imaging.context(width: w + 2 * pad, height: h + 2 * pad) else { return nil }
            ctx.setFillColor(cgColor(backdrop))
            ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
            // y-up: the card's top row sits `pad` below the canvas top; a crop clips away its bottom.
            ctx.clip(to: CGRect(x: pad, y: pad, width: w, height: h))
            ctx.draw(card, in: CGRect(x: pad, y: pad + h - card.height, width: card.width, height: card.height))
            return ctx.makeImage().flatMap { Imaging.scaled($0, by: 1 / 1.5) }
        }
    }
}

enum GIFWriter {
    /// A looping GIF with one delay for every frame, like ffmpeg's `-framerate 1/0.09` in compose-gif.py.
    static func write(_ frames: [CGImage], delay: Double, to url: URL) throws {
        guard !frames.isEmpty,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { throw CLIError(message: "cannot write \(url.path)") }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let props = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay],
        ] as CFDictionary
        for f in frames { CGImageDestinationAddImage(dest, f, props) }
        guard CGImageDestinationFinalize(dest) else { throw CLIError(message: "cannot write \(url.path)") }
    }
}
