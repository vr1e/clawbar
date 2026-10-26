import Foundation

/// record-gif.ps1's scenarios.
public enum RecordScenario: String, CaseIterable, Sendable {
    case tour, sleep, limit, reset, hearts, weather, clicks
}

/// One frame of a scenario run: the animation before the frame's steps applied, its time on the virtual clock, and
/// the fake data after them on a frame where a step ran, changed or not, since record-gif.ps1 calls Update-Widget then.
public struct ScenarioFrame: Sendable, Equatable {
    public var animation: AnimationFrame
    public var at: Date
    public var data: DataSnapshot?

    public init(animation: AnimationFrame, at: Date, data: DataSnapshot?) {
        self.animation = animation
        self.at = at
        self.data = data
    }
}
