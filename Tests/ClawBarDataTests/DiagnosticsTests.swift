import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

/// `--diagnose` as the engine's second adapter: one pass, every block on, the report's wording.
@MainActor
@Suite struct DiagnosticsTests {
    @Test func onePassReportsEveryProbeRedacted() async {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        h.config.weatherLat = 10.5
        h.config.weatherLon = 20.25
        h.http.answer("api.open-meteo.com", Fixture.data("weather/open-meteo.json"))
        h.table = FakeTable(starts: [4242: .unknown, 4343: .unknown])
        // The auth probe's configDirectory decides where the sessions are.
        h.runner.reply(.account, stdout: #"{"loggedIn": true, "subscriptionType": "team", "email": "user@example.com", "configDirectory": "\#(h.home)/.claude"}"#)
        h.session(4242, in: h.home + "/.claude")
        h.session(4343, in: h.home + "/.claude", status: "waiting")
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("config dir: ~/.claude"))
        #expect(text.contains("claude: ~/tools/claude (config)"))
        #expect(text.contains("version: 2.1.302 · channel latest · latest 2.1.302 · up to date"))
        #expect(text.contains("usage: session 50% · resets 2026-10-17 03:29 · week 68% · resets 2026-10-17 05:59 · Fable 8%"))
        #expect(text.contains("usage guard: num_turns 0 · total_cost_usd 0 · tokens 0 · modelUsage 0 · ok"))
        #expect(text.contains("usage 24h: 4756 requests · 26 sessions · 11 lines"))
        #expect(text.contains("account: Team · u…@example.com"))
        #expect(text.contains("sessions: 2 · p4242 (busy), p4343 (waiting)"))
        #expect(text.contains("projects: 0 transcripts · 0 MB · 0 projects · "))
        #expect(text.contains("status: none · incidents 0 · broken 0"))
        #expect(text.contains("weather: configured coordinates · Open-Meteo · Europe/Berlin · code 61 (rain)"))
        #expect(!text.contains("user@example.com"))
        #expect(!text.contains(h.home))
        #expect(!text.contains("10.5") && !text.contains("20.25"))
        // The pass ended: each probe once, nothing left running.
        #expect([.version, .usage, .account].allSatisfy { h.runner.count($0) == 1 })
        #expect(h.runner.heldCount == 0)
        #expect(h.runner.shutdowns == 1)
    }

    @Test func everyBlockIsOnWhateverTheConfigSays() async {
        let h = Harness()
        h.config.showStatus = false
        h.config.showAccount = false
        h.config.showSessions = false
        h.config.showMascot = false
        h.config.showHistory = false
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        for line in ["status: none", "account: Team", "sessions: 0", "projects: 0 transcripts"] { #expect(text.contains(line)) }
    }

    @Test func theTranscriptsAreCountedButNeverNamed() async {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let line = assistantLine("msg_1", at: Harness.t0, cwd: "/Users/example/secret", model: "claude-opus-6", output: 1000)
        h.dir.write("home/.claude/projects/-Users-example-secret/s1.jsonl", line + "\n")
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("projects: 1 transcripts · 0 MB · 1 projects · "))
        #expect(text.contains(" s · 1 replies without a list price (claude-opus-6)\n"))
        #expect(!text.contains("secret"))
    }

    @Test func aTildeConfigDirIsExpandedAsTheControllerDoes() async {
        let h = Harness()
        h.extraEnvironment = ["CLAUDE_CONFIG_DIR": "~/cfg"]
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        h.runner.reply(.account, stdout: #"{"loggedIn": true, "subscriptionType": "team", "email": "user@example.com"}"#)
        h.table = FakeTable(starts: [4242: .unknown])
        h.session(4242, in: h.home + "/cfg")
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("config dir: ~/cfg\nsessions: 1 · p4242 (busy)\n"))
    }

    @Test func aStampWithoutADateIsNamed() async {
        let h = Harness()
        h.runner.reply(.usage, data: todayEnvelope { $0["result"] = "Current session: 5% used · resets in 2 hr\n" })
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("usage: session 5%\nusage stamps without a date: \"in 2 hr\"\n"))
    }

    @Test func aMissingClaudeIsSaidPlainly() async {
        let h = Harness(claude: false)
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("claude: not found\nlog: locate: claude not found\n"))
        #expect(h.runner.calls.isEmpty)
    }

    @Test func aLatchedProbeIsReportedAndNotRunAgain() async throws {
        let h = Harness()
        try LatchStore(url: h.paths.stateFile).save(UsageLatch(version: "2.1.302", issue: .flagRejected("--no-session-persistence")))
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("usage: latched for 2.1.302: claude rejected --no-session-persistence"))
        #expect(h.runner.count(.usage) == 0)
    }

    @Test func aLatchIsHonouredWhileClaudeVersionFailsAsTheAppDoes() async throws {
        let h = Harness()
        try LatchStore(url: h.paths.stateFile).save(UsageLatch(version: "2.1.302", issue: .flagRejected("--no-session-persistence")))
        h.runner.reply(.version, stdout: "", exit: 1)
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("version: unknown · channel latest · latest 2.1.302 · up to date\nlog: version: claude --version failed\n"))
        #expect(text.contains("usage: latched for 2.1.302: claude rejected --no-session-persistence"))
        #expect(h.runner.count(.usage) == 0)
    }

    @Test func aTrippedGuardIsReportedAndLatched() async {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/model-reached.json"))
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("usage guard: num_turns 1 · total_cost_usd 0.0123 · tokens 1285 · modelUsage 1 · TRIPPED"))
        #expect(LatchStore(url: h.paths.stateFile).load()?.version == "2.1.302")
        // A look, not a sample.
        #expect(!FileManager.default.fileExists(atPath: h.paths.historyFile.path))
    }

    @Test func aTrippedGuardWithoutAVersionIsLookedAtAgainAndNotSaved() async {
        let h = Harness()
        h.runner.reply(.version, stdout: "", exit: 1)
        h.runner.reply(.usage, data: Fixture.data("usage/model-reached.json"))
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        // The engine asks for one more look to key the latch; without a version it stays unkeyed and unsaved.
        #expect(text.components(separatedBy: "version: unknown · channel latest · latest 2.1.302 · up to date\n").count == 3)
        #expect(text.contains("usage guard: num_turns 1 · total_cost_usd 0.0123 · tokens 1285 · modelUsage 1 · TRIPPED"))
        #expect(h.runner.count(.version) == 2)
        #expect(LatchStore(url: h.paths.stateFile).load() == nil)
    }

    @Test func aLatchTheVersionOutlivedIsClearedAsTheAppWouldClearIt() async throws {
        let h = Harness()
        try LatchStore(url: h.paths.stateFile).save(UsageLatch(version: "2.1.301", issue: .flagRejected("--no-session-persistence")))
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("usage: session 50%"))
        #expect(!text.contains("latched"))
        #expect(h.runner.count(.usage) == 1)
        #expect(LatchStore(url: h.paths.stateFile).load() == nil)
    }

    @Test func theEnginesLogLinesAreInTheReport() async {
        let h = Harness()
        h.http.answer("status.claude.com", nil)
        h.runner.reply(.usage, data: Data(), exit: 1, stderr: "boom")
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("status: no answer from status.claude.com\nlog: status: no summary from status.claude.com\n"))
        #expect(text.contains("usage: exit 1: boom\nlog: usage: exit 1: boom\n"))
        #expect(!FileManager.default.fileExists(atPath: h.paths.errorLog.path))
    }

    @Test func anUpdateOutIsFollowedByItsChangelog() async {
        let h = Harness()
        h.runner.reply(.version, stdout: "2.1.301 (Claude Code)\n")
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        h.http.answer("downloads.claude.ai", Data("2.1.303\n".utf8))
        h.http.answer("raw.githubusercontent.com", Fixture.data("version/CHANGELOG.md"))
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("version: 2.1.301 · channel latest · latest 2.1.303 · update available\nchangelog: 5 items\n"))
    }
}
