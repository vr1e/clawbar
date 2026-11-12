import CoreGraphics
import Testing
import ClawBarScenes
import ClawBarShared

/// What the scene engine promises whichever scene plays.
@Suite struct EverySceneTests {
    @Test(arguments: SceneID.allCases)
    func nothingDrawsBeforeTheCardHasASize(scene: SceneID) {
        #expect(runScene(scene, 3, size: .zero).allSatisfy { $0 == .empty })
    }

    /// Upstream's scenes leaked WPF children; here a long run draws no more than a short one.
    @Test(arguments: SceneID.allCases)
    func nothingPilesUpOverAThousandSteps(scene: SceneID) {
        for size in [CGSize(width: 260, height: 140), sceneCard, CGSize(width: 260, height: 520)] {
            let counts = runScene(scene, 1_000, size: size).map { $0.backdrop.count + $0.sky.count }
            #expect(counts[500...].max()! <= counts[..<500].max()!, "\(size)")
        }
    }
}
