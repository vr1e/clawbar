import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

/// One controller over fakes: a fake claude on disk (never run), a fake runner, fake HTTP and a hand clock.
@MainActor
final class Harness {
    static let t0 = utc("2026-10-16T22:30:00Z")
    let dir = TempDir("cb-dc")
    let runner = FakeRunner()
    let http = FakeHTTP()
    let clock = TestClock(Harness.t0)
    let spy = ReadSpy()
    var table = FakeTable(starts: [:])
    var shell = FakeLoginShell([nil])
    var candidates: [String] = []
    var config = Config()
    /// Added to the environment the controller inherits.
    var extraEnvironment: [String: String] = [:]

    var home: String { dir.url.appendingPathComponent("home").path }
    var paths: AppPaths { dir.paths }

    init(claude: Bool = true) {
        config.showSky = false
        if claude { config.claudePath = installClaude("tools/claude") }
        runner.reply(.version, stdout: "2.1.302 (Claude Code)\n")
        runner.reply(.account, data: Fixture.data("account/logged-in.json"))
        http.answer("status.claude.com", Fixture.data("status/ok.json"))
        http.answer("downloads.claude.ai", Data("2.1.302\n".utf8))
    }

    @discardableResult
    func installClaude(_ relative: String) -> String {
        dir.write("home/\(relative)", "#!/bin/sh\nexit 0\n", executable: true).path
    }

    var deps: DataController.Dependencies {
        let shell = shell
        return DataController.Dependencies(
            runner: runner, http: http, clock: clock.read, timeZone: berlin,
            environment: ["HOME": home, "PATH": "/usr/bin:/bin", "CLAUDECODE": "1"].merging(extraEnvironment) { $1 }, home: home,
            table: table, readFile: spy.reader, loginShell: { _, _, _ in shell.answer() }, candidates: candidates
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

@MainActor
@Suite struct DataControllerTests {
    let t0 = Harness.t0

    @Test func usageStartsAgainOnlyWhenItsIntervalHasPassedSinceTheLastAttempt() async {
        let h = Harness()
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { h.runner.count(.usage) == 1 })
        // still running: never a second usage child
        dc.tick(now: t0 + 61)
        await settle()
        #expect(h.runner.count(.usage) == 1)
        h.clock.now = t0 + 61
        h.runner.release(.usage, data: Fixture.data("usage/today.json"))
        #expect(await eventually { dc.snapshot.usage?.sessionPercent == 50 })
        #expect(dc.snapshot.usageAt == t0 + 61)
        #expect(dc.snapshot.usageProbeCompleted)
        // 62 s after the attempt, though only 1 s after the answer
        dc.tick(now: t0 + 62)
        #expect(await eventually { h.runner.count(.usage) == 2 })
        h.runner.release(.usage, data: Fixture.data("usage/today.json"))
        await settle()
        dc.tick(now: t0 + 121)
        await settle()
        #expect(h.runner.count(.usage) == 2)
        dc.tick(now: t0 + 122)
        #expect(await eventually { h.runner.count(.usage) == 3 })
    }

    @Test func probesRunTheLocatedClaudeWithTheScrubbedEnvironment() async throws {
        let h = Harness()
        h.shell = FakeLoginShell([LoginEnvironment(path: "/Users/example/.nvm/bin:/usr/bin", claudeConfigDir: "/Users/example/.claude-alt")])
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

    @Test func aFailedProbeKeepsTheLastGoodValueAndIsLogged() async throws {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usage?.sessionPercent == 50 })
        h.runner.reply(.usage, data: Data(), exit: 1, stderr: "boom")
        dc.tick(now: t0 + 60)
        #expect(await eventually {
            if case .probeFailed = dc.snapshot.usageIssue { return true }
            return false
        })
        #expect(dc.snapshot.usage?.sessionPercent == 50)
        #expect(dc.snapshot.usageAt == t0)
        let log = try String(contentsOf: h.paths.errorLog, encoding: .utf8)
        #expect(log.contains("usage: exit 1: boom"))
    }

    @Test func aTimedOutProbeKeepsTheLastGoodValue() async {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usage?.sessionPercent == 50 })
        h.runner.reply(.usage, .now(.success(ProcessOutcome(pid: 900, termination: .signal(SIGTERM), timedOut: true))))
        h.clock.now = t0 + 60
        dc.tick(now: t0 + 60)
        #expect(await eventually { dc.snapshot.usageIssue == .timedOut })
        #expect(dc.snapshot.usage?.sessionPercent == 50)
        #expect(dc.snapshot.usageAt == t0)
    }

    @Test func aStampWithoutADateIsLoggedOncePerShape() async throws {
        let h = Harness()
        h.runner.reply(.usage, data: todayEnvelope { $0["result"] = "Current session: 5% used · resets in 2 hr\n" })
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usage?.sessionPercent == 5 })
        h.runner.reply(.usage, data: todayEnvelope { $0["result"] = "Current session: 6% used · resets in 1 hr\n" })
        h.clock.now = t0 + 60
        dc.tick(now: t0 + 60)
        #expect(await eventually { dc.snapshot.usage?.sessionPercent == 6 })
        let log = try String(contentsOf: h.paths.errorLog, encoding: .utf8)
        #expect(log.split(separator: "\n").filter { $0.hasSuffix("\tusage-stamp: no date in \"in # hr\"") }.count == 1)
    }

    @Test func aLoginWithoutASubscriptionClearsTheOldLimits() async {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usage?.sessionPercent == 50 })
        h.runner.reply(.usage, data: todayEnvelope { $0["result"] = Fixture.text("usage/no-limits.txt") })
        h.clock.now = t0 + 60
        dc.tick(now: t0 + 60)
        #expect(await eventually { dc.snapshot.usageIssue == .noLimits })
        // The subscription's limits no longer apply; the /cost summary carries no stats.
        #expect(dc.snapshot.usage == UsageSnapshot())
        #expect(dc.snapshot.usageAt == t0 + 60)
    }

    @Test func aSubscriptionAnswerWithoutLimitsKeepsTheLastNumbers() async {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usage?.sessionPercent == 50 })
        h.runner.reply(.usage, data: todayEnvelope { $0["result"] = Fixture.text("usage/subscription-unavailable.txt") })
        h.clock.now = t0 + 60
        dc.tick(now: t0 + 60)
        #expect(await eventually { dc.snapshot.usageIssue == .probeFailed("no limit lines in /usage") })
        #expect(dc.snapshot.usage?.sessionPercent == 50)
        #expect(dc.snapshot.usageAt == t0)
    }

    @Test func reachingTheModelLatchesPerCLIVersionAndANewVersionReArms() async {
        let h = Harness()
        let reached = UsageIssue.modelReached(turns: 1, costUSD: 0.0123, tokens: 1285)
        h.runner.reply(.usage, data: Fixture.data("usage/model-reached.json"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usageIssue == reached })
        #expect(LatchStore(url: h.paths.stateFile).load() == UsageLatch(version: "2.1.302", issue: reached))
        dc.tick(now: t0 + 600)
        dc.refreshNow()
        await settle()
        #expect(h.runner.count(.usage) == 1)
        dc.shutdown()

        // a restart with the same CLI stays stopped and says why
        let again = h.make()
        again.tick(now: t0 + 700)
        #expect(await eventually { again.snapshot.usageProbeCompleted })
        #expect(again.snapshot.usageIssue == reached)
        again.tick(now: t0 + 1400)
        await settle()
        #expect(h.runner.count(.usage) == 1)
        again.shutdown()

        // the CLI updated: probing resumes and the latch is gone
        h.runner.reply(.version, stdout: "2.1.303 (Claude Code)\n")
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let updated = h.make()
        updated.tick(now: t0 + 800)
        #expect(await eventually { updated.snapshot.usage?.sessionPercent == 50 })
        #expect(updated.snapshot.usageIssue == nil)
        #expect(LatchStore(url: h.paths.stateFile).load() == nil)
    }

    @Test func aRejectedOptionLatchesToo() async {
        let h = Harness()
        h.runner.reply(.usage, data: Data(), exit: 1, stderr: Fixture.text("usage/flag-rejected-stderr.txt"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usageIssue == .flagRejected("--no-session-persistence") })
        #expect(LatchStore(url: h.paths.stateFile).load()?.issue == .flagRejected("--no-session-persistence"))
        dc.tick(now: t0 + 3600)
        await settle()
        #expect(h.runner.count(.usage) == 1)
    }

    @Test func aMissingClaudeIsRetriedEveryUsageInterval() async {
        let h = Harness(claude: false)
        h.candidates = [h.home + "/.local/bin/claude"]
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usageIssue == .claudeNotFound })
        #expect(dc.snapshot.usageProbeCompleted)
        #expect(h.runner.calls.isEmpty)
        h.installClaude(".local/bin/claude")
        dc.tick(now: t0 + 59)
        await settle()
        #expect(h.runner.calls.isEmpty)
        dc.tick(now: t0 + 60)
        #expect(await eventually { h.runner.count(.usage) == 1 })
        #expect(dc.snapshot.usageIssue == nil)
    }

    @Test func aLoginShellWithoutAnAnswerIsLoggedOnceAndAskedAgainUntilItFindsClaude() async throws {
        let h = Harness(claude: false)
        let nvm = h.installClaude(".nvm/versions/node/v22.11.0/bin/claude")
        h.shell = FakeLoginShell([nil, nil, LoginEnvironment(claudePath: nvm)])
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.usageIssue == .claudeNotFound })
        dc.tick(now: t0 + 59)
        await settle()
        #expect(h.shell.runs == 1)
        h.clock.now = t0 + 60
        dc.tick(now: t0 + 60)
        #expect(await eventually { h.shell.runs == 2 })
        await settle()
        #expect(dc.snapshot.usageIssue == .claudeNotFound)
        h.clock.now = t0 + 120
        dc.tick(now: t0 + 120)
        #expect(await eventually { h.runner.count(.usage) == 1 })
        #expect(dc.snapshot.usageIssue == nil)
        #expect(h.runner.calls.allSatisfy { $0.executable == nvm })
        let log = try String(contentsOf: h.paths.errorLog, encoding: .utf8)
        #expect(log.split(separator: "\n").filter { $0.contains("\tlogin: ") }.count == 1)
    }

    /// A new controller ticked once a minute from t0, the clock along, with each tick's completions let run.
    func tickEveryMinute(_ h: Harness, times: Int) async {
        let dc = h.make()
        for i in 0 ..< times {
            h.clock.now = t0 + TimeInterval(60 * i)
            dc.tick(now: h.clock.now)
            await settle()
        }
    }

    @Test func theLoginShellIsAskedAtMostFourTimes() async {
        let h = Harness(claude: false)
        await tickEveryMinute(h, times: 5)
        #expect(h.shell.runs == 4)
    }

    @Test func theLoginShellIsAskedAgainOnlyWhileItGaveNoAnswerAndClaudeIsMissing() async {
        let answered = Harness(claude: false)
        answered.shell = FakeLoginShell([LoginEnvironment()])
        for h in [answered, Harness()] {
            await tickEveryMinute(h, times: 3)
            #expect(h.shell.runs == 1)
        }
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
        h.shell = FakeLoginShell([LoginEnvironment(claudeConfigDir: alt)])
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

    @Test func theAuthProbesConfigDirectoryTakesOver() async {
        let h = Harness()
        let work = h.home + "/.claude-work"
        let account = #"{"loggedIn": true, "subscriptionType": "max", "email": "user@example.com", "configDirectory": "\#(work)"}"#
        h.runner.reply(.account, stdout: account)
        h.table = FakeTable(starts: [7001: .unknown, 7002: .unknown])
        h.session(7001, in: h.home + "/.claude")
        h.session(7002, in: work)
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.account?.plan == "Max" })
        dc.pollSessions(now: t0 + 2)
        #expect(dc.snapshot.sessions.map(\.pid) == [7002])
    }

    @Test func statusAndAccountLandInTheSnapshotWithTheirTimes() async {
        let h = Harness()
        let dc = h.make()
        h.clock.now = t0 + 1
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.status != nil && dc.snapshot.account != nil })
        #expect(dc.snapshot.status?.indicator == "none")
        #expect(dc.snapshot.statusAt == t0 + 1)
        #expect(dc.snapshot.account == AccountInfo(loggedIn: true, plan: "Team", email: "user@example.com", configDirectory: "/Users/example/.claude"))
        #expect(await eventually { dc.snapshot.version.local == "2.1.302" && dc.snapshot.version.latest == "2.1.302" })
    }

    @Test func hiddenRowsAreNotProbed() async {
        let h = Harness()
        h.config.showStatus = false
        h.config.showAccount = false
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { h.runner.count(.usage) == 1 })
        await settle()
        #expect(h.http.count("status.claude.com") == 0)
        #expect(h.runner.count(.account) == 0)
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

    /// A controller whose Claude Code is one release behind, once it has seen the update.
    func behind() async -> (Harness, DataController) {
        let h = Harness()
        h.http.answer("downloads.claude.ai", Data("2.1.303\n".utf8))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.version.updateAvailable })
        return (h, dc)
    }

    /// Ticks one version interval later and waits until that look has finished.
    func lookAgain(_ h: Harness, _ dc: DataController, at now: Date) async {
        let versions = h.runner.count(.version)
        dc.tick(now: now)
        _ = await eventually { h.runner.count(.version) > versions }
        await settle()
    }

    /// Runs an update with this exit and waits for the look the controller takes right after it.
    func runUpdate(_ h: Harness, _ dc: DataController, exit: Int32) async {
        h.runner.reply(.update, data: Data(), exit: exit)
        let versions = h.runner.count(.version)
        dc.startClaudeUpdate()
        #expect(await eventually { h.runner.count(.version) > versions })
        await settle()
    }

    @Test func aFailedUpdateStaysUntilClaudeCodeHasUpdatedAnyway() async {
        let (h, dc) = await behind()
        await runUpdate(h, dc, exit: 1)
        // The look right after the run, and a look whose claude --version failed, change nothing.
        let failed = UpdateFailure(exitCode: 1, outputTail: "", from: "2.1.302", to: "2.1.303")
        #expect(dc.snapshot.version.updateFailure == failed)
        h.runner.reply(.version, stdout: "", exit: 1)
        await lookAgain(h, dc, at: t0 + 3600)
        #expect(dc.snapshot.version.updateFailure == failed)
        // Claude Code's own updater got there.
        h.runner.reply(.version, stdout: "2.1.303 (Claude Code)\n")
        await lookAgain(h, dc, at: t0 + 7200)
        #expect(dc.snapshot.version.local == "2.1.303")
        #expect(dc.snapshot.version.updateFailure == nil)
    }

    @Test func aNewerReleaseClearsAFailedUpdate() async {
        let (h, dc) = await behind()
        await runUpdate(h, dc, exit: 1)
        #expect(dc.snapshot.version.updateFailure != nil)
        h.http.answer("downloads.claude.ai", Data("2.1.304\n".utf8))
        await lookAgain(h, dc, at: t0 + 3600)
        #expect(dc.snapshot.version.latest == "2.1.304")
        #expect(dc.snapshot.version.updateFailure == nil)
    }

    @Test func aCleanExitThatLeavesTheVersionIsAFailure() async throws {
        let (h, dc) = await behind()
        try FileManager.default.createDirectory(at: h.paths.root, withIntermediateDirectories: true)
        try Data("Checking for updates...\nDone\n".utf8).write(to: h.paths.updateLog)
        await runUpdate(h, dc, exit: 0)
        #expect(await eventually { dc.snapshot.version.updateFailure != nil })
        #expect(dc.snapshot.version.updateFailure == UpdateFailure(
            exitCode: 0, outputTail: "Checking for updates...\nDone", from: "2.1.302", to: "2.1.303"
        ))
        let log = try String(contentsOf: h.paths.errorLog, encoding: .utf8)
        #expect(log.contains("update: exit 0, but Claude Code is still 2.1.302"))
    }

    @Test func onlyALookStartedAfterACleanExitJudgesIt() async {
        let (h, dc) = await behind()
        h.runner.reply(.update, .hold)
        dc.startClaudeUpdate()
        #expect(await eventually { h.runner.count(.update) == 1 })
        // A look already running when the update ends still sees the old version.
        h.runner.reply(.version, .hold)
        dc.tick(now: t0 + 3600)
        #expect(await eventually { h.runner.count(.version) == 2 })
        await settle()
        h.runner.release(.update, data: Data())
        #expect(await eventually { !dc.snapshot.version.updating })
        h.runner.release(.version, data: Data("2.1.302 (Claude Code)\n".utf8))
        #expect(await eventually { h.runner.count(.version) == 3 })
        await settle()
        #expect(dc.snapshot.version.updateFailure == nil)
        // The look after the run is the one that counts.
        h.runner.release(.version, data: Data("2.1.303 (Claude Code)\n".utf8))
        #expect(await eventually { dc.snapshot.version.local == "2.1.303" })
        #expect(dc.snapshot.version.updateFailure == nil)
    }

    @Test func aFailedLookAfterACleanExitIsNoFailure() async {
        let (h, dc) = await behind()
        h.runner.reply(.version, stdout: "", exit: 1)
        await runUpdate(h, dc, exit: 0)
        #expect(dc.snapshot.version.updateFailure == nil)
    }

    @Test func theChangelogIsFetchedOnlyWhileAnUpdateIsAvailable() async {
        let h = Harness()
        h.runner.reply(.version, stdout: "2.1.301 (Claude Code)\n")
        h.http.answer("downloads.claude.ai", Data("2.1.303\n".utf8))
        h.http.answer("raw.githubusercontent.com", Fixture.data("version/CHANGELOG.md"))
        let dc = h.make()
        dc.tick(now: t0)
        #expect(await eventually { dc.snapshot.version.changes != nil })
        #expect(dc.snapshot.version.changes == ChangesExcerpt(forVersion: "2.1.303", fromVersion: "2.1.301", items: [
            "Fixed claude update on some installs", "Added a setting for the status line",
            "nested detail with inline code", "Faster /usage",
            "A star bullet with **bold** and a [link](https://example.com)",
        ]))
        dc.tick(now: t0 + 3600)
        await settle()
        #expect(h.http.count("raw.githubusercontent.com") == 1)
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
