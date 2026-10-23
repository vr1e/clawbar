import Foundation
import ClawBarShared

/// record-gif.ps1's `S name state for`.
struct FakeSession: Equatable {
    var name: String
    var state: SessionState
    var waitingFor: String?

    init(_ name: String, _ state: SessionState = .idle, waitingFor: String? = nil) {
        self.name = name
        self.state = state
        self.waitingFor = waitingFor
    }
}

enum ScenarioAction: Equatable {
    /// Set-Sky: a forced phase and weather code.
    case sky(SkyPhase, Int)
    /// Set-Usage: the session %, its reset that many minutes away, week 41 and Fable 18.
    case usage(Int, resetMinutes: Double)
    case sessions([FakeSession])
    case click
    /// `$script:Mz.drainT = 0`: Play losing hearts.
    case drain
}

struct ScenarioStep: Equatable {
    var at: Double
    var actions: [ScenarioAction]
}

struct ScenarioScript {
    var steps: [ScenarioStep]
    /// Crop below the reset line, as every scenario but the tour does.
    var crop: Bool
    /// The last step's time ends the recording.
    var length: Double { steps.last?.at ?? 0 }
}

/// tools/record-gif.ps1's scenarios, step for step, on its clock: scenario time is frames × 0.09 s whatever the tick
/// interval.
enum Scenarios {
    /// record-gif.ps1's config.json.
    static let config = Config(
        language: "en", scale: 1.0, topmost: true, expanded: false, showStats: false, showStatus: true,
        showSessions: true, showAccount: false, left: 40, top: 40
    )

    static func time(frame n: Int) -> Double { Double(n) * 0.09 }

    /// record-gif.ps1 captures a frame on every tick until the last step is due.
    static func frameCount(_ script: ScenarioScript) -> Int {
        var n = 0
        while time(frame: n) < script.length { n += 1 }
        return n
    }

    static func script(_ s: RecordScenario) -> ScenarioScript {
        func S(_ name: String, _ state: SessionState = .idle, _ waitingFor: String? = nil) -> FakeSession {
            FakeSession(name, state, waitingFor: waitingFor)
        }
        func step(_ at: Double, _ actions: ScenarioAction...) -> ScenarioStep { ScenarioStep(at: at, actions: actions) }
        func usage(_ pct: Int, _ resetMinutes: Double = 192) -> ScenarioAction { .usage(pct, resetMinutes: resetMinutes) }
        switch s {
        case .tour:
            return ScenarioScript(steps: [
                step(0, .sky(.day, 2), usage(34), .sessions([S("api"), S("web")])),
                step(2.5, .sessions([S("api", .busy), S("web")])),
                step(4, usage(36)), step(5.5, usage(39)), step(7, usage(42)),
                step(8.5, .sessions([S("api"), S("web")])),
                step(10.5, .sessions([S("api"), S("web", .waiting, "permission")])),
                step(14.5),
            ], crop: false)
        case .sleep:
            return ScenarioScript(steps: [
                step(0, .sky(.night, 0), usage(12), .sessions([S("api")])),
                step(1.5, .sessions([])),
                step(9),
            ], crop: true)
        case .limit:
            return ScenarioScript(steps: [
                step(0, .sky(.day, 3), usage(100), .sessions([S("api")])),
                step(2, .click),
                step(9.5),
            ], crop: true)
        case .reset:
            return ScenarioScript(steps: [
                step(0, .sky(.day, 1), usage(96, 3), .sessions([S("api", .busy)])),
                step(4, usage(0, 300)),
                step(8.5),
            ], crop: true)
        case .hearts:
            return ScenarioScript(steps: [
                step(0, .sky(.dusk, 2), usage(10), .sessions([S("api", .busy)]), .drain),
                step(15.5),
            ], crop: true)
        case .weather:
            return ScenarioScript(steps: [
                step(0, .sky(.day, 63), usage(27), .sessions([S("api")])),
                step(3, .sky(.night, 73)),
                step(6, .sky(.dusk, 95)),
                step(9, .sky(.dawn, 2)),
                step(12),
            ], crop: true)
        case .clicks:
            return ScenarioScript(steps: [
                step(0, .sky(.day, 1), usage(22), .sessions([S("api")])),
                step(1, .click), step(3.5, .click), step(6, .click), step(8.5, .click),
                step(11),
            ], crop: true)
        }
    }
}
