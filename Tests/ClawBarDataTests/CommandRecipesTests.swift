import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

/// One command in, its answer out, over the fakes: what each recipe runs and how it reads what came back. The
/// schedule is DataEngineTests; the Tasks, the log and the stores across restarts are DataControllerTests.
@MainActor
@Suite struct CommandRecipesTests {
    let t0 = Harness.t0

    enum Way { case now, later, none }

    func way(_ h: Harness, _ command: DataCommand) -> Way {
        switch h.recipes().recipe(for: command, now: t0) {
        case .now?: .now
        case .later?: .later
        case nil: .none
        }
    }

    @Test func lookupsAndSavesAnswerNowProbesLaterAndTheLogAndCancelHaveNoRecipe() {
        let h = Harness()
        let env = ["PATH": "/usr/bin"]
        #expect(way(h, .locate(configPath: nil, login: nil)) == .now)
        #expect(way(h, .readSessions(directory: h.dir.url)) == .now)
        #expect(way(h, .saveLatch(nil)) == .now)
        #expect(way(h, .saveHistory([])) == .now)
        #expect(way(h, .runLoginShell) == .later)
        #expect(way(h, .probeUsage(claude: "claude", environment: env)) == .later)
        #expect(way(h, .probeVersion(claude: "claude", environment: env, configDirectory: h.home)) == .later)
        #expect(way(h, .probeAccount(claude: "claude", environment: env)) == .later)
        #expect(way(h, .probeStatus) == .later)
        #expect(way(h, .fetchChangelog) == .later)
        #expect(way(h, .runUpdate(claude: "claude", environment: env)) == .later)
        #expect(way(h, .scanProjects(root: h.home)) == .later)
        #expect(way(h, .log("x")) == .none)
        #expect(way(h, .cancelAll) == .none)
    }

    @Test func theUsageProbeRunsTheClaudeAndEnvironmentItWasGivenPlusSafeModeInHome() async throws {
        let h = Harness()
        h.runner.reply(.usage, data: Fixture.data("usage/today.json"))
        let claude = try #require(h.config.claudePath)
        let login = LoginEnvironment(path: "/Users/example/.nvm/bin:/usr/bin", claudeConfigDir: "/Users/example/.claude-alt")
        let env = ChildEnv.make(inherited: h.deps.environment, login: login, claude: claude)
        guard case .usage(let report)? = await h.recipes().answer(.probeUsage(claude: claude, environment: env)),
              case .usage(let u) = report.outcome
        else {
            Issue.record("no usage answer")
            return
        }
        #expect(u.sessionPercent == 50 && u.weekPercent == 68)
        let spec = try #require(h.runner.calls.first)
        #expect(spec.executable == claude)
        #expect(spec.arguments == UsageProbe.arguments)
        #expect(spec.environment["CLAUDE_CONFIG_DIR"] == "/Users/example/.claude-alt")
        #expect(spec.environment["PATH"]?.hasPrefix("/Users/example/.nvm/bin:/usr/bin:") == true)
        #expect(spec.environment["CLAUDECODE"] == nil)
        #expect(spec.environment["CLAUDE_CODE_SAFE_MODE"] == "1")
        #expect(spec.directory == h.home)
    }

    @Test func theVersionProbeReadsTheChannelFromTheDirectoryAsked() async {
        let h = Harness()
        h.dir.write("home/.claude-work/settings.json", #"{"autoUpdatesChannel": "stable"}"#)
        h.http.answer("downloads.claude.ai", Data("2.1.303\n".utf8))
        let r = h.recipes()
        let command = DataCommand.probeVersion(claude: h.config.claudePath ?? "", environment: [:], configDirectory: h.home + "/.claude-work")
        guard case .version(let local, let latest, let channel)? = await r.answer(command) else {
            Issue.record("no version answer")
            return
        }
        #expect(local == "2.1.302" && latest == "2.1.303" && channel == "stable")
        #expect(h.http.urls.map(\.lastPathComponent) == ["stable"])
        // A failed claude and a dead release host each answer nil, for the engine to keep what it had.
        h.runner.reply(.version, stdout: "", exit: 1)
        h.http.answer("downloads.claude.ai", nil)
        guard case .version(let none, let noLatest, _)? = await r.answer(command) else {
            Issue.record("no version answer")
            return
        }
        #expect(none == nil && noLatest == nil)
    }

    @Test func theSessionsAreReadWithoutOurChildrenAndNoKeyFileIsOpened() async {
        let h = Harness()
        let dir = h.home + "/.claude"
        h.table = FakeTable(starts: [4242: .unknown, 4343: .unknown])
        h.session(4242, in: dir)
        h.session(4343, in: dir, status: "waiting")
        h.dir.write("home/.claude/sessions/4343.key", "secret")
        h.runner.setOwn([4242])
        let directory = SessionRegistry.directory(configDir: dir, home: h.home)
        guard case .sessionsRead(let sessions)? = await h.recipes().answer(.readSessions(directory: directory)) else {
            Issue.record("no sessions answer")
            return
        }
        #expect(sessions.map(\.pid) == [4343])
        #expect(sessions.first?.state == .waiting)
        #expect(!h.spy.names.contains { $0.hasSuffix(".key") })
    }

    @Test func theLocatorAnswersWithWhereClaudeIsAndHowItWasInstalled() async {
        let h = Harness(claude: false)
        let r = h.recipes()
        guard case .located(.none, .none)? = await r.answer(.locate(configPath: nil, login: nil)) else {
            Issue.record("claude should be missing")
            return
        }
        let npm = h.installClaude("lib/node_modules/@anthropic-ai/claude-code/cli.js")
        guard case .located(let found?, let hint)? = await r.answer(.locate(configPath: npm, login: nil)) else {
            Issue.record("claude should be found")
            return
        }
        #expect(found == ClaudeLocator.Found(path: npm, source: .config))
        #expect(hint == .npm)
    }

    @Test func theLoginShellAccountStatusAndChangelogAnswerAsTheirProbesReadThem() async {
        let h = Harness()
        h.shell = LoginEnvironment(path: "/opt/bin:/usr/bin", claudeConfigDir: "/Users/example/.claude-alt")
        h.runner.reply(.account, data: Fixture.data("account/logged-in.json"))
        h.http.answer("raw.githubusercontent.com", Fixture.data("version/CHANGELOG.md"))
        let r = h.recipes()
        let claude = h.config.claudePath ?? ""
        guard case .loginShell(let login)? = await r.answer(.runLoginShell),
              case .account(let account)? = await r.answer(.probeAccount(claude: claude, environment: [:])),
              case .status(let status)? = await r.answer(.probeStatus),
              case .changelog(let text)? = await r.answer(.fetchChangelog)
        else {
            Issue.record("an answer is missing")
            return
        }
        #expect(login == h.shell)
        #expect(account == AccountInfo(loggedIn: true, plan: "Team", email: "user@example.com", configDirectory: "/Users/example/.claude"))
        #expect(status?.indicator == "none")
        #expect(text == Fixture.text("version/CHANGELOG.md"))
        // A host without an answer is nil, for the engine to keep the last good value.
        h.http.answer("status.claude.com", nil)
        guard case .status(.none)? = await r.answer(.probeStatus) else {
            Issue.record("the status should be nil")
            return
        }
    }

    @Test func theUpdateRunsHeadlessAndItsTailComesFromTheLog() async throws {
        let h = Harness()
        try FileManager.default.createDirectory(at: h.paths.root, withIntermediateDirectories: true)
        // What the real child would have written there.
        try Data("Error: managed by a package manager\n".utf8).write(to: h.paths.updateLog)
        h.runner.reply(.update, data: Data(), exit: 1)
        let r = h.recipes()
        let command = DataCommand.runUpdate(claude: h.config.claudePath ?? "", environment: [:])
        guard case .update(let failure, let tail)? = await r.answer(command) else {
            Issue.record("no update answer")
            return
        }
        #expect(failure == UpdateFailure(exitCode: 1, outputTail: "Error: managed by a package manager"))
        #expect(tail == "Error: managed by a package manager")
        let spec = try #require(h.runner.calls.first)
        #expect(spec.output == .survivesQuit(h.paths.updateLog))
        #expect(spec.timeout == 900)
        // A clean exit is no failure; the tail still comes back for the next look to judge.
        h.runner.reply(.update, data: Data())
        guard case .update(.none, let cleanTail)? = await r.answer(command) else {
            Issue.record("no update answer")
            return
        }
        #expect(cleanTail == "Error: managed by a package manager")
    }

    @Test func theScanCountsTheWeeksTranscriptsAtUtilityPriority() async {
        let h = Harness()
        h.dir.write("home/.claude/projects/-Users-example-api/s1.jsonl", assistantLine("msg_1", at: t0, output: 1000) + "\n")
        let r = h.recipes()
        let command = DataCommand.scanProjects(root: TranscriptScanner.root(configDir: h.home + "/.claude"))
        guard case .later(let priority, _)? = r.recipe(for: command, now: t0) else {
            Issue.record("the scan should run later")
            return
        }
        #expect(priority == .utility)
        guard case .projects(let scan)? = await r.answer(command) else {
            Issue.record("no scan answer")
            return
        }
        #expect(scan.files == 1)
        let quarter = UsageSample.minute(of: t0)
        #expect(scan.usage.projects == [ProjectWeight(path: "/Users/example/api", weight: 0.02, quarters: [quarter: 0.02])])
    }

    @Test func aSaveAnswersWithWhatWentWrong() async throws {
        let h = Harness()
        let r = h.recipes()
        let latch = UsageLatch(version: "2.1.302", issue: .flagRejected("--no-session-persistence"))
        let sample = UsageSample(minute: UsageSample.minute(of: t0), session: 50, week: 68)
        guard case .latchSaved(let latchFailure)? = await r.answer(.saveLatch(latch)),
              case .historySaved(let historyFailure)? = await r.answer(.saveHistory([sample]))
        else {
            Issue.record("a save did not answer")
            return
        }
        #expect(latchFailure == nil && historyFailure == nil)
        #expect(r.savedLatch() == latch)
        #expect(r.savedHistory() == [sample])
        // A path that cannot be written names the problem; the engine logs it once.
        let blocked = TempDir("cb-blocked")
        try FileManager.default.createDirectory(at: blocked.paths.stateFile, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: blocked.paths.historyFile, withIntermediateDirectories: true)
        let b = CommandRecipes(deps: h.deps, paths: blocked.paths)
        guard case .latchSaved(let f1)? = await b.answer(.saveLatch(latch)),
              case .historySaved(let f2)? = await b.answer(.saveHistory([sample]))
        else {
            Issue.record("a save did not answer")
            return
        }
        #expect(f1 != nil && f2 != nil)
    }
}
