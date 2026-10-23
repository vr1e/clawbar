import Foundation

/// record-gif.ps1's scenarios.
public enum RecordScenario: String, CaseIterable, Sendable {
    case tour, sleep, limit, reset, hearts, weather, clicks
}

/// record-gif.ps1's `S name state for`.
public struct FakeSession: Sendable, Equatable {
    public var name: String
    public var state: SessionState
    public var waitingFor: String?

    public init(_ name: String, _ state: SessionState = .idle, waitingFor: String? = nil) {
        self.name = name
        self.state = state
        self.waitingFor = waitingFor
    }
}

public enum ScenarioAction: Sendable, Equatable {
    /// Set-Sky: a forced phase and weather code.
    case sky(SkyPhase, Int)
    /// Set-Usage: the session %, its reset that many minutes away, week 41 and Fable 18.
    case usage(Int, resetMinutes: Double)
    case sessions([FakeSession])
    case click
    /// `$script:Mz.drainT = 0`: Play losing hearts.
    case drain
}

public struct ScenarioStep: Sendable, Equatable {
    public var at: Double
    public var actions: [ScenarioAction]

    public init(at: Double, actions: [ScenarioAction]) {
        self.at = at
        self.actions = actions
    }
}

public struct ScenarioScript: Sendable {
    public var steps: [ScenarioStep]
    /// Crop below the reset line, as every scenario but the tour does.
    public var crop: Bool
    /// The last step's time ends the recording.
    public var length: Double { steps.last?.at ?? 0 }

    public init(steps: [ScenarioStep], crop: Bool) {
        self.steps = steps
        self.crop = crop
    }
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

/// tools/record-gif.ps1's scenarios, step for step.
public enum Scenarios {
    /// record-gif.ps1's config.json.
    public static let config = Config(
        language: "en", scale: 1.0, topmost: true, expanded: false, showStats: false, showStatus: true,
        showSessions: true, showAccount: false, left: 40, top: 40
    )

    public static func script(_ s: RecordScenario) -> ScenarioScript {
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

/// Plays a script on the original's clock: scenario time is frames × 0.09 s, whatever the tick interval. Keeps the
/// fake data the steps set; the sky overrides, the clicks and the drain are the animation engine's.
public final class ScenarioPlayer {
    public let script: ScenarioScript
    private var next = 0
    private var pct: Int?
    private var sessionReset: Date?
    private var weekReset: Date?
    private var usageAt: Date?
    private var sessions: [FakeSession] = []

    public init(_ script: ScenarioScript) {
        self.script = script
    }

    public var finished: Bool { next >= script.steps.count }

    public static func time(frame n: Int) -> Double { Double(n) * 0.09 }

    /// record-gif.ps1 captures a frame on every tick until the last step is due.
    public static func frameCount(_ script: ScenarioScript) -> Int {
        var n = 0
        while time(frame: n) < script.length { n += 1 }
        return n
    }

    /// Applies every step due by frame `n`; returns the actions, in order.
    public func advance(frame n: Int, now: Date) -> [ScenarioAction] {
        let t = Self.time(frame: n)
        var applied: [ScenarioAction] = []
        while next < script.steps.count, script.steps[next].at <= t {
            for a in script.steps[next].actions {
                apply(a, now: now)
                applied.append(a)
            }
            next += 1
        }
        return applied
    }

    private func apply(_ a: ScenarioAction, now: Date) {
        switch a {
        case let .usage(p, minutes):
            pct = p
            sessionReset = now.addingTimeInterval(minutes * 60)
            weekReset = now.addingTimeInterval(2.4 * 86400)
            usageAt = now
        case let .sessions(s):
            sessions = s
        case .sky, .click, .drain:
            break
        }
    }

    /// The fake data, with a fresh status so the line never says loading.
    public func snapshot(now: Date) -> DataSnapshot {
        let usage = pct.map { p in
            UsageSnapshot(
                sessionPercent: p, weekPercent: 41, sessionReset: sessionReset, weekReset: weekReset,
                modelWeeks: [ModelWeek(name: "Fable", percent: 18, reset: weekReset)]
            )
        }
        return DataSnapshot(
            usage: usage, usageAt: usageAt, usageProbeCompleted: true,
            sessions: sessions.enumerated().map { i, s in
                SessionInfo(
                    pid: Int32(4200 + i), name: s.name, cwd: "\(Samples.home)/code/\(s.name)", state: s.state,
                    waitingFor: s.waitingFor, kind: "interactive"
                )
            },
            sessionsRead: true, status: ServiceStatus(indicator: "none"), statusAt: now
        )
    }
}
