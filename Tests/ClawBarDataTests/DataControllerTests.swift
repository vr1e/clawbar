import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

final class Counter {
    var value = 0
}

/// The controller as the engine's live adapter: Tasks, `onChange`, the stores across restarts, the error log and
/// shutdown. The decisions are DataEngineTests; what each command runs is CommandRecipesTests.
@MainActor
@Suite struct DataControllerTests {
    let t0 = Harness.t0

    @Test func aFailedProbeIsLogged() async throws {
        let h = Harness()
        h.runner.reply(.usage, data: Data(), exit: 1, stderr: "boom")
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually {
            if case .probeFailed = dc.snapshot.usageIssue { return true }
            return false
        })
        let log = try String(contentsOf: h.paths.errorLog, encoding: .utf8)
        #expect(log.contains("usage: exit 1: boom"))
    }

    @Test func theHistorySurvivesARestart() async {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let dc = h.make()
        #expect(dc.snapshot.history.isEmpty)
        dc.tick(now: t0)
        let sample = UsageSample(minute: UsageSample.minute(of: t0), session: 50, week: 68)
        #expect(await eventually { dc.snapshot.history == [sample] })
        dc.shutdown()
        #expect(h.make().snapshot.history == [sample])
    }

    @Test func aHistoryFileThatCannotBeWrittenIsLogged() async throws {
        let h = Harness()
        try FileManager.default.createDirectory(at: h.paths.historyFile, withIntermediateDirectories: true)
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.history.count == 1 })
        let log = try String(contentsOf: h.paths.errorLog, encoding: .utf8)
        #expect(log.contains("\thistory: "))
    }

    @Test func aLatchSurvivesARestart() async {
        let h = Harness()
        let reached = UsageIssue.modelReached(turns: 1, costUSD: 0.0123, tokens: 1285)
        h.runner.reply(.usage, data: Fixture.data("usage/model-reached.json"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { LatchStore(url: h.paths.stateFile).load() == UsageLatch(version: "2.1.302", issue: reached) })
        dc.shutdown()
        let again = h.make()
        again.tick(now: t0 + 700)
        #expect(await eventually { again.snapshot.usageProbeCompleted })
        #expect(again.snapshot.usageIssue == reached)
        await settle()
        #expect(h.runner.count(.usage) == 1)
    }

    @Test func aLatchFileThatCannotBeWrittenIsLogged() async throws {
        let h = Harness()
        try FileManager.default.createDirectory(at: h.paths.stateFile, withIntermediateDirectories: true)
        let reached = UsageIssue.modelReached(turns: 1, costUSD: 0.0123, tokens: 1285)
        h.runner.reply(.usage, data: Fixture.data("usage/model-reached.json"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usageIssue == reached })
        #expect(await eventually { (try? String(contentsOf: h.paths.errorLog, encoding: .utf8))?.contains("\tlatch: ") == true })
    }

    @Test func onChangeComesOnlyFromAsyncCompletions() async {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        h.runner.reply(.update, .hold)
        let dc = h.make()
        let changes = Counter()
        dc.onChange = { changes.value += 1 }
        dc.tick(now: t0)
        dc.pollSessions(now: t0)
        dc.apply(config: h.config)
        dc.refreshNow()
        #expect(changes.value == 0)
        #expect(await eventually { dc.snapshot.usage != nil })
        #expect(changes.value > 0)
        let seen = changes.value
        dc.startClaudeUpdate()
        #expect(dc.snapshot.version.updating)
        dc.pollSessions(now: t0 + 2)
        dc.tick(now: t0 + 10)
        dc.shutdown()
        #expect(changes.value == seen)
    }

    @Test func pollSessionsAnswersAtOnceFromTheConfigDirTheShellNamed() async {
        let h = Harness()
        let alt = h.home + "/.claude-alt"
        h.shell = LoginEnvironment(claudeConfigDir: alt)
        h.table = FakeTable(starts: [4242: .unknown, 4343: .unknown])
        h.session(4242, in: alt)
        h.session(4343, in: h.home + "/.claude")
        let dc = h.make()
        dc.pollSessions(now: t0)
        #expect(!dc.snapshot.sessionsRead)
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.sessionsRead })
        #expect(dc.snapshot.sessions.map(\.pid) == [4242])
        // The answer is in the snapshot when the poll returns: the presenter reads it right after.
        h.session(4343, in: alt, status: "waiting")
        dc.pollSessions(now: t0 + 2)
        #expect(dc.snapshot.sessions.map(\.pid) == [4242, 4343])
        #expect(dc.snapshot.sessions.last?.state == .waiting)
    }

    @Test func anotherToolsFreshUsageCheckIsNoSession() async {
        let h = Harness()
        let dir = h.home + "/.claude"
        h.table = FakeTable(starts: [8001: .unknown, 8002: .unknown])
        let ms = { (d: Date) in d.timeIntervalSince1970 * 1000 }
        h.session(8001, in: dir, ["entrypoint": "sdk-cli", "startedAt": ms(t0 - 3)])
        h.session(8002, in: dir, ["entrypoint": "sdk-cli", "startedAt": ms(t0 - 60)])
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.sessionsRead })
        // The hand clock, not the wall clock, decides what is fresh.
        dc.pollSessions(now: t0)
        #expect(dc.snapshot.sessions.map(\.pid) == [8002])
        dc.pollSessions(now: t0 + 30)
        #expect(dc.snapshot.sessions.map(\.pid) == [8001, 8002])
    }

    @Test func aHeldUpdateCompletesLaterAndTheVersionIsLookedAtAgain() async {
        let h = Harness()
        h.runner.reply(.update, .hold)
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.version.local == "2.1.302" })
        dc.startClaudeUpdate()
        #expect(dc.snapshot.version.updating)
        #expect(await eventually { h.runner.count(.update) == 1 })
        dc.startClaudeUpdate()
        await settle()
        #expect(h.runner.count(.update) == 1)
        let versions = h.runner.count(.version)
        h.runner.reply(.version, stdout: "2.1.303 (Claude Code)\n")
        h.runner.release(.update, data: Data())
        #expect(await eventually { !dc.snapshot.version.updating })
        #expect(dc.snapshot.version.updateFailure == nil)
        #expect(await eventually { dc.snapshot.version.local == "2.1.303" })
        #expect(h.runner.count(.version) > versions)
    }

    @Test func weatherAndThePlaceReachTheSnapshot() async {
        let h = Harness()
        h.config.showSky = true
        h.config.weatherLat = 10.5
        h.config.weatherLon = 20.25
        h.http.answer("api.open-meteo.com", Fixture.data("weather/open-meteo.json"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(dc.snapshot.place == Place(lat: 10.5, lon: 20.25))
        #expect(await eventually { dc.snapshot.weather?.code == 61 })
    }

    @Test func shutdownStopsEveryProbe() async {
        let h = Harness()
        let dc = h.make()
        dc.tick(now: t0)
        // every probe of the first tick, since one still on its way to the runner would pass for a start after shutdown
        #expect(await eventually { [.version, .usage, .account].allSatisfy { h.runner.count($0) == 1 } })
        dc.shutdown()
        #expect(h.runner.shutdowns == 1)
        let calls = h.runner.calls.count
        dc.tick(now: t0 + 3600)
        dc.refreshNow()
        await settle()
        #expect(h.runner.calls.count == calls)
    }
}
