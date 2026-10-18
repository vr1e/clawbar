import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

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
        #expect(text.contains("status: none · incidents 0 · broken 0"))
        #expect(text.contains("weather: configured coordinates · Open-Meteo · Europe/Berlin · code 61 (rain)"))
        #expect(!text.contains("user@example.com"))
        #expect(!text.contains(h.home))
        #expect(!text.contains("10.5") && !text.contains("20.25"))
        #expect(h.runner.heldCount == 0)
        #expect(h.runner.shutdowns == 1)
    }

    @Test func aTildeConfigDirIsExpandedAsTheControllerDoes() async {
        let h = Harness()
        h.extraEnvironment = ["CLAUDE_CONFIG_DIR": "~/cfg"]
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        h.runner.reply(.account, stdout: #"{"loggedIn": true, "subscriptionType": "team", "email": "user@example.com"}"#)
        h.table = FakeTable(starts: [4242: .unknown])
        h.session(4242, in: h.home + "/cfg")
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("sessions: 1 · p4242 (busy)"))
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
        #expect(text.contains("claude: not found"))
        #expect(h.runner.calls.isEmpty)
    }

    @Test func aLatchedProbeIsReportedAndNotRunAgain() async {
        let h = Harness()
        LatchStore(url: h.paths.stateFile).save(UsageLatch(version: "2.1.302", issue: .flagRejected("--no-session-persistence")))
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("usage: latched for 2.1.302: claude rejected --no-session-persistence"))
        #expect(h.runner.count(.usage) == 0)
    }

    @Test func aTrippedGuardIsReportedAndLatched() async {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/model-reached.json"))
        let text = await Diagnostics.run(config: h.config, paths: h.paths, deps: h.deps).text
        #expect(text.contains("usage guard: num_turns 1 · total_cost_usd 0.0123 · tokens 1285 · modelUsage 1 · TRIPPED"))
        #expect(LatchStore(url: h.paths.stateFile).load()?.version == "2.1.302")
    }
}
