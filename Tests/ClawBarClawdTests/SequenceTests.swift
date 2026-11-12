import CoreGraphics
import Foundation
import Testing
@testable import ClawBarClawd
import ClawBarShared

/// What frame `t` of an act draws, observed through the engine.
func frameAt(_ act: ClawdAct, _ t: Int, engine: ClawdEngine = .settled(), _ e: ClawdStepEnv = env()) -> ClawdFrame {
    engine.perform(.act(act))
    return engine.run(t + 1, e).last!
}

/// The frame draws exactly `pose`, lifted by `lift`.
func expectPose(_ frame: ClawdFrame, _ pose: ClawdPose, lift: Double = 0, sourceLocation: SourceLocation = #_sourceLocation) {
    let view = FrameView(frame)
    let want = ClawdSprite.render(pose)
    let o = frame.spriteRect.origin
    func local(_ r: [CGRect]) -> [CGRect] { r.map { CGRect(x: $0.minX - o.x, y: $0.minY - o.y, width: $0.width, height: $0.height) } }
    #expect(view.pixels == grid(want), "pixels of \(pose)", sourceLocation: sourceLocation)
    #expect(close(local(view.fx), want.fx), "fx of \(pose)", sourceLocation: sourceLocation)
    #expect(close(local(view.sand), want.sand), "sand of \(pose)", sourceLocation: sourceLocation)
    #expect(abs(frame.spriteRect.minY - (4.4 - lift - 26.4)) < 1e-9, "lift \(lift)", sourceLocation: sourceLocation)
    #expect(frame.spriteRect.size == CGSize(width: 36, height: 26.4), sourceLocation: sourceLocation)
}

@Suite struct SequenceTests {
    /// visuals-verbatim.txt §E.
    static let lengths: [(ClawdAct, Int)] = [
        (.jump, 12), (.look, 11), (.celebrate, 15), (.skip, 14), (.spin, 10), (.peekaboo, 21), (.drop, 13), (.waddle, 19),
        (.peek, 20), (.wink, 6), (.boop, 11), (.tap, 14), (.sneeze, 12), (.turn, 19), (.coinHop, 14),
    ]
    static let customLengths: [(ClawdAct, Int)] = [
        (.wave, 24), (.stretch, 22), (.yawn, 22), (.stumble, 20), (.soul, 66), (.burrow, 30), (.unburrow, 28), (.stir, 22),
    ]

    @Test(arguments: lengths)
    func aSequencePlaysItsLengthAt60ms(_ act: ClawdAct, _ length: Int) {
        let engine = ClawdEngine.settled()
        engine.perform(.act(act))
        var ms: [Int] = []
        for _ in 0 ..< length {
            engine.step(env())
            ms.append(engine.tickMilliseconds)
        }
        #expect(ms == Array(repeating: 60, count: length - 1) + [90])
    }

    @Test(arguments: customLengths)
    func aCustomActPlaysItsLengthAt90ms(_ act: ClawdAct, _ length: Int) {
        let engine = ClawdEngine.settled()
        engine.perform(.mood(.idle))
        engine.perform(.act(act))
        let frames = engine.run(length + 1)
        #expect(frames.dropLast(2).allSatisfy { $0.devCaption == "dev · \(L10n.act(act, .en))" })
        #expect(frames[length - 1].devCaption == "dev · wandering")
        #expect(engine.tickMilliseconds == 90)
    }

    @Test func framesAtGivenTicks() {
        expectPose(frameAt(.jump, 0), ClawdPose(off: 1, poof: .dot))
        expectPose(frameAt(.jump, 1), ClawdPose(off: 1, poof: .wave))
        expectPose(frameAt(.jump, 2), ClawdPose(arms: .up))
        expectPose(frameAt(.jump, 5), ClawdPose())
        expectPose(frameAt(.look, 4), ClawdPose(eyes: .right))
        expectPose(frameAt(.look, 5), ClawdPose(eyes: .left))
        expectPose(frameAt(.celebrate, 13), ClawdPose(off: 1))
        expectPose(frameAt(.skip, 1), ClawdPose(arms: .up, x: -6))
        expectPose(frameAt(.spin, 2), ClawdPose(eyes: .right))
        expectPose(frameAt(.peekaboo, 0), ClawdPose(off: 3))
        expectPose(frameAt(.peekaboo, 4), ClawdPose(eyes: .right, off: 2))
        expectPose(frameAt(.drop, 1), ClawdPose(arms: .up, off: -2))
        expectPose(frameAt(.waddle, 3), ClawdPose(eyes: .right, feet: .right, x: -5))
        expectPose(frameAt(.peek, 9), ClawdPose(eyes: .right, x: -5))
        expectPose(frameAt(.wink, 0), ClawdPose(eyes: .wink))
        expectPose(frameAt(.boop, 2), ClawdPose(eyes: .closed, off: 1, poof: .wave))
        expectPose(frameAt(.tap, 2), ClawdPose(feet: .right))
        expectPose(frameAt(.sneeze, 0), ClawdPose(eyes: .closed, arms: .up))
        expectPose(frameAt(.turn, 4), ClawdPose(facing: .edge))
        expectPose(frameAt(.turn, 8), ClawdPose(facing: .back))
        expectPose(frameAt(.turn, 18), ClawdPose())
        expectPose(frameAt(.coinHop, 2), ClawdPose(arms: .up, shadow: .wide))
        expectPose(frameAt(.coinHop, 3), ClawdPose(facing: .right55, shadow: .narrow))
        expectPose(frameAt(.coinHop, 9), ClawdPose(facing: .left55, shadow: .narrow))
    }

    @Test func sequencesForceTheGazeToTheFront() {
        let engine = ClawdEngine.settled()
        // Standing with the pointer far right: he looks right.
        let right = env(over: true, mouseX: 179)
        expectPose(engine.run(1, right)[0], ClawdPose(eyes: .right))
        engine.perform(.act(.jump))
        let frames = engine.run(3, right)
        expectPose(frames[2], ClawdPose(arms: .up))
    }

    @Test func customActFrames() {
        expectPose(frameAt(.wave, 0), ClawdPose(eyes: .happy, arms: .right))
        expectPose(frameAt(.wave, 4), ClawdPose(eyes: .happy))
        expectPose(frameAt(.wave, 8), ClawdPose(eyes: .happy, arms: .right))
        expectPose(frameAt(.stretch, 3), ClawdPose())
        expectPose(frameAt(.stretch, 4), ClawdPose(eyes: .closed, arms: .up), lift: 1.5)
        expectPose(frameAt(.stretch, 18), ClawdPose())
        expectPose(frameAt(.yawn, 2), ClawdPose(eyes: .closed))
        expectPose(frameAt(.yawn, 3), ClawdPose(eyes: .yawn))
        expectPose(frameAt(.stumble, 11), ClawdPose(eyes: .closed, off: 1))
        expectPose(frameAt(.stumble, 12), ClawdPose(eyes: .wide))
        expectPose(frameAt(.soul, 1), ClawdPose(eyes: .x, feet: .left, flip: true))
        expectPose(frameAt(.soul, 2), ClawdPose(eyes: .x, feet: .right, flip: true))
        expectPose(frameAt(.soul, 30), ClawdPose(eyes: .gasp, flip: true))
        expectPose(frameAt(.soul, 55), ClawdPose(eyes: .wide, flip: true), lift: 2.5)
        expectPose(frameAt(.soul, 60), ClawdPose(eyes: .x, flip: true))
        expectPose(frameAt(.burrow, 0), ClawdPose(look: -1))
        expectPose(frameAt(.burrow, 2), ClawdPose(look: 1))
        // t = 8: dig ⌊4 / 3.5⌋ = 1, ⌊8 / 2⌋ even: right foot and arms down, spray 8 mod 3 + 1.
        expectPose(frameAt(.burrow, 8), ClawdPose(eyes: .focus, feet: .right, dig: 1, spray: 3))
        expectPose(frameAt(.burrow, 11), ClawdPose(eyes: .focus, arms: .up, feet: .left, dig: 2, spray: 3))
        expectPose(frameAt(.burrow, 24), ClawdPose(eyes: .blink, dig: 4))
        expectPose(frameAt(.burrow, 27), ClawdPose(eyes: .closed, dig: 4))
        expectPose(frameAt(.unburrow, 0), ClawdPose(eyes: .wide, dig: 4))
        expectPose(frameAt(.unburrow, 5), ClawdPose(eyes: .wide, arms: .up, dig: 2, spray: 3))
        expectPose(frameAt(.unburrow, 8), ClawdPose(eyes: .wide, arms: .up, spray: 3), lift: 2)
        expectPose(frameAt(.unburrow, 10), ClawdPose(eyes: .closed, feet: .left, look: -1, spray: 2))
        expectPose(frameAt(.unburrow, 16), ClawdPose(eyes: .closed, feet: .right, look: 1))
        expectPose(frameAt(.unburrow, 21), ClawdPose(eyes: .blink))
        expectPose(frameAt(.unburrow, 23), ClawdPose())
        expectPose(frameAt(.stir, 0), ClawdPose(eyes: .wide, dig: 3))
        expectPose(frameAt(.stir, 5), ClawdPose(look: -1, dig: 3))
        expectPose(frameAt(.stir, 9), ClawdPose(look: 1, dig: 3))
        expectPose(frameAt(.stir, 15), ClawdPose(eyes: .blink, dig: 4))
        expectPose(frameAt(.stir, 17), ClawdPose(eyes: .closed, dig: 4))
    }

    @Test func theSoulRisesOnItsThreadFromTheMouth() throws {
        // Not before t = 7 (height 20 × (1 − 0.95²) ≈ 1.95 > 0.5); full height 20 at t = 26.
        #expect(FrameView(frameAt(.soul, 6)).soul.isEmpty)
        let frame = frameAt(.soul, 26)
        let soul = try #require(FrameView(frame).soul.first)
        #expect(abs(soul.opacity - (0.7 + 0.15 * sin(26 / 1.7))) < 1e-12)
        // The origin is the mouth: x + 19 across, lift + 13.2 above the ground; the thread's first square sits just above it.
        let x = 72.0
        let want = ClawdSprite.soul(height: 20, t: 26).map { CGRect(x: $0.minX + x + 19, y: $0.minY - 13.2, width: $0.width, height: $0.height) }
        #expect(close(soul.rects, want))
    }
}
