import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ClawBar
import ClawBarShared

@MainActor
@Suite struct RecorderTests {
    @Test func framesAreCroppedBelowTheResetLineOnTheGitHubDarkBackdrop() throws {
        let frames = Recorder.record(.limit, maxFrames: 3)
        #expect(frames.count == 3)
        let f = try #require(frames.first)
        // 262 pt at 2 px, 24 px of padding each side, scaled down by 1.5.
        #expect(abs(Double(f.width) - (524 + 48) / 1.5) <= 1)
        let full = try #require(Recorder.record(.tour, maxFrames: 1).first)
        #expect(f.height < full.height)
        let r = Raster(f, scale: 1)
        #expect(close(r.color(atPoint: 2, 2), RGBA(r: 13, g: 17, b: 23)))
    }

    @Test func aGIFLoopsWithTheOriginalsNinetyMillisecondFrames() throws {
        let tmp = TempDir()
        try FileManager.default.createDirectory(at: tmp.url, withIntermediateDirectories: true)
        let url = tmp.url.appendingPathComponent("x.gif")
        let frames = Recorder.record(.clicks, maxFrames: 4)
        try GIFWriter.write(frames, delay: 0.09, to: url)
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(src) == 4)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 1, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect((gif?[kCGImagePropertyGIFDelayTime] as? Double).map { abs($0 - 0.09) < 0.001 } == true)
    }
}
