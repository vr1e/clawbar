import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

/// One controller over fakes: a fake claude on disk (never run), a fake runner, fake HTTP and a clock stopped at t0.
@MainActor
final class Harness {
    static let t0 = utc("2026-10-16T22:30:00Z")
    let dir = TempDir("cb-dc")
    let runner = FakeRunner()
    let http = FakeHTTP()
    let spy = ReadSpy()
    var table = FakeTable(starts: [:])
    var shell: LoginEnvironment?
    var config = Config()
    /// Added to the environment the controller inherits.
    var extraEnvironment: [String: String] = [:]

    var home: String { dir.url.appendingPathComponent("home").path }
    var paths: AppPaths { dir.paths }

    init(claude: Bool = true) {
        config.showSky = false
        if claude { config.claudePath = installClaude("tools/claude") }
        runner.reply(.version, stdout: "2.1.302 (Claude Code)\n")
        // No configDirectory: the auth probe's outranks the shell's, so one would move the sessions mid-test.
        runner.reply(.account, stdout: #"{"loggedIn": true, "subscriptionType": "team", "email": "user@example.com"}"#)
        http.answer("status.claude.com", Fixture.data("status/ok.json"))
        http.answer("downloads.claude.ai", Data("2.1.302\n".utf8))
    }

    func installClaude(_ relative: String) -> String {
        dir.write("home/\(relative)", "#!/bin/sh\nexit 0\n", executable: true).path
    }

    var deps: DataController.Dependencies {
        let shell = shell, t0 = Harness.t0
        return DataController.Dependencies(
            runner: runner, http: http, clock: { t0 }, timeZone: berlin,
            environment: ["HOME": home, "PATH": "/usr/bin:/bin", "CLAUDECODE": "1"].merging(extraEnvironment) { $1 }, home: home,
            table: table, readFile: spy.reader, loginShell: { _, _, _ in shell }, candidates: []
        )
    }

    func make() -> DataController { DataController(config: config, paths: paths, deps: deps) }

    func session(_ pid: Int32, in configDir: String, status: String = "busy", _ extra: [String: Any] = [:]) {
        let j: [String: Any] = ["pid": pid, "sessionId": "s\(pid)", "cwd": "/Users/example/p\(pid)", "status": status, "kind": "interactive"]
            .merging(extra) { $1 }
        let url = URL(fileURLWithPath: configDir).appendingPathComponent("sessions/\(pid).json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: j).write(to: url)
    }
}

final class Counter {
    var value = 0
}

/// The controller as the engine's adapter: what crosses a real seam. The decisions themselves are DataEngineTests.
@MainActor
@Suite struct DataControllerTests {
    let t0 = Harness.t0

    @Test func probesRunTheLocatedClaudeWithTheScrubbedEnvironment() async throws {
        let h = Harness()
        h.shell = LoginEnvironment(path: "/Users/example/.nvm/bin:/usr/bin", claudeConfigDir: "/Users/example/.claude-alt")
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { h.runner.count(.usage) == 1 })
        let spec = try #require(h.runner.calls.first { FakeRunner.kind($0) == .usage })
        #expect(spec.executable == h.config.claudePath)
        #expect(spec.environment["CLAUDECODE"] == nil)
        #expect(spec.environment["CLAUDE_CODE_SAFE_MODE"] == "1")
        #expect(spec.environment["CLAUDE_CONFIG_DIR"] == "/Users/example/.claude-alt")
        #expect(spec.environment["PATH"]?.hasPrefix("/Users/example/.nvm/bin:/usr/bin:") == true)
        #expect(spec.directory == h.home)
    }

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

    @Test func sessionsAreReadSynchronouslyFromTheLoginConfigDirWithoutOurChildren() async {
        let h = Harness()
        let alt = h.home + "/.claude-alt"
        h.shell = LoginEnvironment(claudeConfigDir: alt)
        h.table = FakeTable(starts: [4242: .unknown, 4343: .unknown])
        h.session(4242, in: alt)
        h.session(4343, in: alt, status: "waiting")
        h.session(5555, in: h.home + "/.claude")
        let dc = h.make()
        dc.pollSessions(now: t0)
        #expect(!dc.snapshot.sessionsRead)
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.sessionsRead })
        #expect(dc.snapshot.sessions.map(\.pid) == [4242, 4343])
        h.runner.setOwn([4242])
        dc.pollSessions(now: t0 + 2)
        #expect(dc.snapshot.sessions.map(\.pid) == [4343])
        #expect(dc.snapshot.sessions.first?.state == .waiting)
        #expect(!h.spy.names.contains { $0.hasSuffix(".key") })
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

    @Test func anUpdateRunsHeadlessAndTheVersionIsProbedAgainAfterIt() async throws {
        let h = Harness()
        h.runner.reply(.update, .hold)
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.version.local == "2.1.302" })
        dc.startClaudeUpdate()
        #expect(dc.snapshot.version.updating)
        #expect(await eventually { h.runner.count(.update) == 1 })
        let spec = try #require(h.runner.calls.first { FakeRunner.kind($0) == .update })
        #expect(spec.output == .survivesQuit(h.paths.updateLog))
        #expect(spec.timeout == 900)
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

        h.http.answer("downloads.claude.ai", Data("2.1.304\n".utf8))
        dc.tick(now: t0 + 3600)
        #expect(await eventually { dc.snapshot.version.updateAvailable })
        dc.startClaudeUpdate()
        #expect(await eventually { h.runner.count(.update) == 2 })
        // What the real child would have written there.
        try FileManager.default.createDirectory(at: h.paths.root, withIntermediateDirectories: true)
        try Data("Error: managed by a package manager\n".utf8).write(to: h.paths.updateLog)
        h.runner.release(.update, data: Data(), exit: 1)
        #expect(await eventually { dc.snapshot.version.updateFailure != nil })
        #expect(dc.snapshot.version.updateFailure == UpdateFailure(
            exitCode: 1, outputTail: "Error: managed by a package manager", from: "2.1.303", to: "2.1.304"
        ))
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

    @Test func statusAccountChangelogAndInstallHintReachTheSnapshot() async {
        let h = Harness(claude: false)
        h.config.claudePath = h.installClaude("lib/node_modules/@anthropic-ai/claude-code/cli.js")
        h.dir.write("home/.claude/settings.json", #"{"autoUpdatesChannel": "stable"}"#)
        h.runner.reply(.version, stdout: "2.1.301 (Claude Code)\n")
        h.runner.reply(.account, data: Fixture.data("account/logged-in.json"))
        h.http.answer("downloads.claude.ai", Data("2.1.303\n".utf8))
        h.http.answer("raw.githubusercontent.com", Fixture.data("version/CHANGELOG.md"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.version.changes != nil })
        #expect(dc.snapshot.version.installHint == .npm)
        #expect(dc.snapshot.version.changes == ChangesExcerpt(forVersion: "2.1.303", fromVersion: "2.1.301", items: [
            "Fixed claude update on some installs", "Added a setting for the status line",
            "nested detail with inline code", "Faster /usage",
            "A star bullet with **bold** and a [link](https://example.com)",
        ]))
        // The channel comes from settings.json in the config directory.
        #expect(h.http.urls.contains { $0.host == "downloads.claude.ai" && $0.lastPathComponent == "stable" })
        #expect(await eventually { dc.snapshot.status != nil && dc.snapshot.account != nil })
        #expect(dc.snapshot.status?.indicator == "none")
        #expect(dc.snapshot.statusAt == t0)
        #expect(dc.snapshot.account == AccountInfo(loggedIn: true, plan: "Team", email: "user@example.com", configDirectory: "/Users/example/.claude"))
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
