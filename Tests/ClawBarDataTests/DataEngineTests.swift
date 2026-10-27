import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

/// The engine alone: an event and its time in, the snapshot and the commands out; no fakes, no clock, no disk.
@Suite struct DataEngineTests {
    let t0 = utc("2026-10-16T22:30:00Z")
    let home = "/Users/example"
    let inherited = ["HOME": "/Users/example", "PATH": "/usr/bin:/bin", "CLAUDECODE": "1"]
    let found = ClaudeLocator.Found(path: "/Users/example/.local/bin/claude", source: .candidate)
    let altLogin = LoginEnvironment(path: "/Users/example/.nvm/bin:/usr/bin", claudeConfigDir: "/Users/example/.claude-alt")

    func engine(latch: UsageLatch? = nil, history: [UsageSample] = [], _ edit: (inout Config) -> Void = { _ in }) -> DataEngine {
        var config = Config()
        edit(&config)
        return DataEngine(config: config, environment: inherited, home: home, latch: latch, history: history)
    }

    /// The first tick, the login shell's answer and claude's location: what the engine asks for once it can probe.
    @discardableResult
    func start(_ e: inout DataEngine, now: Date, missing: Bool = false) -> [DataCommand] {
        var out = e.handle(.tick, now: now)
        out += e.handle(.loginShell(LoginEnvironment()), now: now)
        out += e.handle(.located(missing ? nil : found, installHint: nil), now: now)
        return out
    }

    /// Started, with the version and the latest release answered.
    func running(local: String? = "2.1.302", latest: String = "2.1.302", now: Date) -> DataEngine {
        var e = engine()
        start(&e, now: now)
        _ = e.handle(.version(local: local, latest: latest), now: now)
        return e
    }

    /// One release behind, the update seen.
    func behind(now: Date) -> DataEngine { running(local: "2.1.302", latest: "2.1.303", now: now) }

    func usage(_ session: Int, stamps: [String] = []) -> DataEvent {
        .usage(UsageProbe.Report(outcome: .usage(UsageSnapshot(sessionPercent: session, weekPercent: 68)), unreadStamps: stamps))
    }

    func issue(_ i: UsageIssue) -> DataEvent {
        .usage(UsageProbe.Report(outcome: .issue(i)))
    }

    /// Each command's case name, for asserting what was asked and in which order.
    func kinds(_ commands: [DataCommand]) -> [String] {
        commands.map { command in String("\(command)".prefix { $0 != "(" }) }
    }

    func logs(_ commands: [DataCommand]) -> [String] {
        commands.compactMap { if case .log(let line) = $0 { line } else { nil } }
    }

    // MARK: - Startup and the schedule

    @Test func theFirstTickAsksForStatusAndTheLoginShellThenLocatesClaudeAndProbes() {
        var e = engine()
        #expect(kinds(e.handle(.tick, now: t0)) == ["probeStatus", "runLoginShell"])
        // Nothing until the shell answers: a second tick neither asks again nor probes.
        #expect(e.handle(.tick, now: t0 + 60).isEmpty)
        let answered = e.handle(.loginShell(altLogin), now: t0 + 1)
        #expect(kinds(answered) == ["readSessions", "locate"])
        #expect(answered.last == .locate(configPath: nil, login: altLogin))
        let probes = e.handle(.located(found, installHint: .npm), now: t0 + 1)
        #expect(kinds(probes) == ["probeVersion", "probeUsage", "probeAccount"])
        #expect(e.snapshot.version.installHint == .npm)
        guard case .readSessions(let dir) = answered.first, case .probeUsage(let claude, let env) = probes.dropFirst().first else {
            Issue.record("the sessions read or the usage probe is missing")
            return
        }
        #expect(dir.path == "/Users/example/.claude-alt/sessions")
        #expect(claude == found.path)
        #expect(env == ChildEnv.make(inherited: inherited, login: altLogin, claude: found.path))
    }

    @Test func hiddenRowsAreNotProbed() {
        var e = engine {
            $0.showStatus = false
            $0.showAccount = false
        }
        #expect(kinds(start(&e, now: t0)) == ["runLoginShell", "readSessions", "locate", "probeVersion", "probeUsage"])
    }

    @Test func usageStartsAgainOnlyWhenItsIntervalHasPassedSinceTheLastAttempt() {
        var e = engine()
        start(&e, now: t0)
        // still running: never a second usage probe
        #expect(!kinds(e.handle(.tick, now: t0 + 61)).contains("probeUsage"))
        _ = e.handle(usage(50), now: t0 + 61)
        #expect(e.snapshot.usage?.sessionPercent == 50)
        #expect(e.snapshot.usageAt == t0 + 61)
        #expect(e.snapshot.usageProbeCompleted)
        // 62 s after the attempt, though only 1 s after the answer
        #expect(kinds(e.handle(.tick, now: t0 + 62)) == ["probeUsage"])
        _ = e.handle(usage(50), now: t0 + 62)
        #expect(!kinds(e.handle(.tick, now: t0 + 121)).contains("probeUsage"))
        #expect(kinds(e.handle(.tick, now: t0 + 122)) == ["probeUsage"])
    }

    @Test func refreshStartsTheUsageProbeAtOnceUnlessOneRunsOrTheProbeIsLatched() {
        var e = engine()
        #expect(e.handle(.refresh, now: t0).isEmpty)
        start(&e, now: t0)
        #expect(e.handle(.refresh, now: t0 + 1).isEmpty)
        _ = e.handle(usage(50), now: t0 + 2)
        #expect(kinds(e.handle(.refresh, now: t0 + 3)) == ["probeUsage"])
        // Claude missing: the refresh looks for it first.
        var missing = engine()
        start(&missing, now: t0, missing: true)
        #expect(kinds(missing.handle(.refresh, now: t0 + 1)) == ["locate"])
        #expect(kinds(missing.handle(.located(found, installHint: nil), now: t0 + 1)) == ["probeUsage"])
    }

    @Test func aMissingClaudeIsRetriedEveryUsageInterval() {
        var e = engine()
        let missing = start(&e, now: t0, missing: true)
        #expect(e.snapshot.usageIssue == .claudeNotFound)
        #expect(e.snapshot.usageProbeCompleted)
        #expect(kinds(missing) == ["probeStatus", "runLoginShell", "readSessions", "locate", "log"])
        #expect(logs(missing) == ["locate: claude not found"])
        #expect(e.handle(.tick, now: t0 + 59).isEmpty)
        #expect(kinds(e.handle(.tick, now: t0 + 60)) == ["locate"])
        #expect(kinds(e.handle(.located(found, installHint: nil), now: t0 + 60)) == ["probeVersion", "probeUsage", "probeAccount"])
        #expect(e.snapshot.usageIssue == nil)
    }

    @Test func aLoginShellWithoutAnAnswerIsLoggedOnceAndAskedAgainUntilItFindsClaude() {
        var e = engine()
        #expect(kinds(e.handle(.tick, now: t0)) == ["probeStatus", "runLoginShell"])
        let first = e.handle(.loginShell(nil), now: t0)
        #expect(logs(first) == ["login: the login shell gave no answer"])
        #expect(first.contains(.locate(configPath: nil, login: nil)))
        _ = e.handle(.located(nil, installHint: nil), now: t0)
        #expect(e.snapshot.usageIssue == .claudeNotFound)
        #expect(!kinds(e.handle(.tick, now: t0 + 59)).contains("runLoginShell"))
        #expect(kinds(e.handle(.tick, now: t0 + 60)).contains("runLoginShell"))
        #expect(logs(e.handle(.loginShell(nil), now: t0 + 60)).isEmpty)
        _ = e.handle(.located(nil, installHint: nil), now: t0 + 60)
        #expect(kinds(e.handle(.tick, now: t0 + 120)).contains("runLoginShell"))
        let nvm = "/Users/example/.nvm/versions/node/v22.11.0/bin/claude"
        let login = LoginEnvironment(claudePath: nvm)
        #expect(e.handle(.loginShell(login), now: t0 + 120).last == .locate(configPath: nil, login: login))
        let probes = e.handle(.located(ClaudeLocator.Found(path: nvm, source: .loginShell), installHint: nil), now: t0 + 120)
        #expect(kinds(probes) == ["probeVersion", "probeUsage", "probeAccount"])
        #expect(e.snapshot.usageIssue == nil)
    }

    @Test func theLoginShellIsAskedAtMostFourTimes() {
        var e = engine()
        var runs = 0
        for i in 0 ..< 5 {
            let now = t0 + TimeInterval(60 * i)
            let asked = kinds(e.handle(.tick, now: now))
            if asked.contains("runLoginShell") {
                runs += 1
                _ = e.handle(.loginShell(nil), now: now)
                _ = e.handle(.located(nil, installHint: nil), now: now)
            } else if asked.contains("locate") {
                _ = e.handle(.located(nil, installHint: nil), now: now)
            }
        }
        #expect(runs == 4)
        #expect(kinds(e.handle(.tick, now: t0 + 300)) == ["locate"])
    }

    @Test func theLoginShellIsAskedAgainOnlyWhileItGaveNoAnswerAndClaudeIsMissing() {
        var answered = engine()
        start(&answered, now: t0, missing: true)
        #expect(kinds(answered.handle(.tick, now: t0 + 60)) == ["locate"])
        var present = engine()
        start(&present, now: t0)
        let later = kinds(present.handle(.tick, now: t0 + 60))
        #expect(!later.contains("locate") && !later.contains("runLoginShell"))
    }

    @Test func aChangedClaudePathIsLocatedAgainOnceTheShellAnswered() {
        var e = engine()
        var config = e.config
        config.claudePath = "/opt/claude"
        #expect(e.handle(.configChanged(config), now: t0).isEmpty)
        start(&e, now: t0)
        config.claudePath = "/opt/other"
        #expect(e.handle(.configChanged(config), now: t0 + 1) == [.locate(configPath: "/opt/other", login: LoginEnvironment())])
        #expect(e.handle(.located(nil, installHint: nil), now: t0 + 1) == [.log("locate: claude not found")])
        #expect(e.snapshot.usageIssue == .claudeNotFound)
    }

    @Test func shutdownCancelsEverythingAndEndsTheEngine() {
        var e = running(now: t0)
        #expect(e.handle(.shutdown, now: t0 + 1) == [.cancelAll])
        #expect(e.handle(.tick, now: t0 + 3600).isEmpty)
        #expect(e.handle(usage(50), now: t0 + 3600).isEmpty)
        #expect(e.snapshot.usage == nil)
    }

    // MARK: - Usage answers

    @Test func aFailedOrTimedOutProbeKeepsTheLastGoodValueAndIsLogged() {
        var e = engine()
        start(&e, now: t0)
        _ = e.handle(usage(50), now: t0)
        let failed = e.handle(issue(.probeFailed("exit 1: boom")), now: t0 + 60)
        #expect(e.snapshot.usageIssue == .probeFailed("exit 1: boom"))
        #expect(e.snapshot.usage?.sessionPercent == 50)
        #expect(e.snapshot.usageAt == t0)
        #expect(logs(failed) == ["usage: exit 1: boom"])
        // The same failure again is not logged again; a timeout is a new one.
        #expect(logs(e.handle(issue(.probeFailed("exit 1: boom")), now: t0 + 120)).isEmpty)
        #expect(logs(e.handle(issue(.timedOut), now: t0 + 180)) == ["usage: timed out after 60 s"])
        #expect(e.snapshot.usageIssue == .timedOut)
        #expect(e.snapshot.usage?.sessionPercent == 50)
    }

    @Test func aStampWithoutADateIsLoggedOncePerShape() {
        var e = engine()
        start(&e, now: t0)
        #expect(logs(e.handle(usage(5, stamps: ["in 2 hr"]), now: t0)) == ["usage-stamp: no date in \"in # hr\""])
        #expect(logs(e.handle(usage(6, stamps: ["in 1 hr"]), now: t0 + 60)).isEmpty)
    }

    @Test func aLoginWithoutASubscriptionClearsTheOldLimits() {
        var e = engine()
        start(&e, now: t0)
        _ = e.handle(usage(50), now: t0)
        _ = e.handle(issue(.noLimits), now: t0 + 60)
        #expect(e.snapshot.usageIssue == .noLimits)
        #expect(e.snapshot.usage == UsageSnapshot())
        #expect(e.snapshot.usageAt == t0 + 60)
    }

    @Test func aSubscriptionAnswerWithoutLimitsKeepsTheLastNumbers() {
        var e = engine()
        start(&e, now: t0)
        _ = e.handle(usage(50), now: t0)
        _ = e.handle(issue(.probeFailed("no limit lines in /usage")), now: t0 + 60)
        #expect(e.snapshot.usageIssue == .probeFailed("no limit lines in /usage"))
        #expect(e.snapshot.usage?.sessionPercent == 50)
        #expect(e.snapshot.usageAt == t0)
    }

    @Test func onlyAGoodAnswerIsASampleAndItIsSaved() {
        let old = [UsageSample(minute: UsageSample.minute(of: t0 - 3600), session: 40, week: 60)]
        var e = engine(history: old)
        start(&e, now: t0)
        let sample = UsageSample(minute: UsageSample.minute(of: t0), session: 50, week: 68)
        #expect(e.handle(usage(50), now: t0).contains(.saveHistory(old + [sample])))
        #expect(e.snapshot.history == old + [sample])
        #expect(!kinds(e.handle(issue(.noLimits), now: t0 + 600)).contains("saveHistory"))
        #expect(!kinds(e.handle(issue(.probeFailed("exit 1: boom")), now: t0 + 1200)).contains("saveHistory"))
        #expect(e.snapshot.history == old + [sample])
    }

    @Test func aFailureOutsideTheEngineIsLoggedOnceUntilItSucceeds() {
        var e = engine()
        #expect(e.handle(.historySaved(failure: "no room"), now: t0) == [.log("history: no room")])
        #expect(e.handle(.historySaved(failure: "no room"), now: t0 + 60).isEmpty)
        #expect(e.handle(.historySaved(failure: nil), now: t0 + 120).isEmpty)
        #expect(e.handle(.historySaved(failure: "no room"), now: t0 + 180) == [.log("history: no room")])
        #expect(e.handle(.latchSaved(failure: "no room"), now: t0 + 190) == [.log("latch: no room")])
        _ = e.handle(.weather(nil, Place(lat: 1, lon: 2)), now: t0 + 200)
        #expect(e.snapshot.place == Place(lat: 1, lon: 2))
        _ = e.handle(.place(nil), now: t0 + 201)
        #expect(e.snapshot.place == nil)
    }

    // MARK: - The latch

    @Test func reachingTheModelLatchesPerCLIVersionAndANewVersionReArms() {
        let reached = UsageIssue.modelReached(turns: 1, costUSD: 0.0123, tokens: 1285)
        var e = running(now: t0)
        #expect(e.handle(issue(reached), now: t0).contains(.saveLatch(UsageLatch(version: "2.1.302", issue: reached))))
        #expect(e.snapshot.usageIssue == reached)
        #expect(!kinds(e.handle(.tick, now: t0 + 600)).contains("probeUsage"))
        #expect(e.handle(.refresh, now: t0 + 600).isEmpty)

        // a restart with the same CLI stays stopped and says why
        var again = engine(latch: UsageLatch(version: "2.1.302", issue: reached))
        #expect(!kinds(start(&again, now: t0 + 700)).contains("probeUsage"))
        _ = again.handle(.version(local: "2.1.302", latest: "2.1.302"), now: t0 + 700)
        #expect(again.snapshot.usageProbeCompleted)
        #expect(again.snapshot.usageIssue == reached)
        #expect(!kinds(again.handle(.tick, now: t0 + 1400)).contains("probeUsage"))

        // the CLI updated: probing resumes and the latch is gone
        var updated = engine(latch: UsageLatch(version: "2.1.302", issue: reached))
        start(&updated, now: t0 + 800)
        let rearmed = updated.handle(.version(local: "2.1.303", latest: "2.1.303"), now: t0 + 800)
        #expect(rearmed == [.saveLatch(nil), .probeUsage(claude: found.path, environment: ChildEnv.make(inherited: inherited, login: LoginEnvironment(), claude: found.path))])
        #expect(updated.snapshot.usageIssue == nil)
    }

    @Test func aLatchBeforeTheVersionIsKnownWaitsForTheLookOrAsksForOne() {
        let reached = UsageIssue.modelReached(turns: 1, costUSD: 0.0123, tokens: 1285)
        // The first look is still running: the latch waits for its answer.
        var e = engine()
        start(&e, now: t0)
        #expect(kinds(e.handle(issue(reached), now: t0)) == ["log"])
        #expect(e.handle(.version(local: "2.1.302", latest: "2.1.302"), now: t0 + 1) == [.saveLatch(UsageLatch(version: "2.1.302", issue: reached))])
        #expect(e.snapshot.usageIssue == reached)
        // No look running: the latch asks for one.
        var late = running(local: nil, latest: "2.1.302", now: t0)
        #expect(kinds(late.handle(issue(reached), now: t0 + 1)) == ["probeVersion", "log"])
        #expect(late.handle(.version(local: "2.1.302", latest: "2.1.302"), now: t0 + 2).contains(.saveLatch(UsageLatch(version: "2.1.302", issue: reached))))
    }

    @Test func aRejectedOptionLatchesToo() {
        var e = running(now: t0)
        let rejected = UsageIssue.flagRejected("--no-session-persistence")
        #expect(e.handle(issue(rejected), now: t0).contains(.saveLatch(UsageLatch(version: "2.1.302", issue: rejected))))
        #expect(e.snapshot.usageIssue == rejected)
        #expect(!kinds(e.handle(.tick, now: t0 + 3600)).contains("probeUsage"))
    }

    // MARK: - Sessions, status, account

    @Test func sessionsAreReadOnceTheShellAnsweredFromTheAccountsConfigDirectory() {
        var e = engine()
        #expect(e.handle(.pollSessions, now: t0).isEmpty)
        start(&e, now: t0)
        guard case .readSessions(let dir) = e.handle(.pollSessions, now: t0 + 2).first else {
            Issue.record("no read")
            return
        }
        #expect(dir.path == "/Users/example/.claude/sessions")
        let session = SessionInfo(
            pid: 4242, sessionId: "s4242", name: "p4242", cwd: "/Users/example/p4242", state: .waiting,
            waitingFor: nil, kind: "interactive", startedAt: nil
        )
        _ = e.handle(.sessionsRead([session]), now: t0 + 2)
        #expect(e.snapshot.sessions == [session])
        #expect(e.snapshot.sessionsRead)
        let account = AccountInfo(loggedIn: true, plan: "Max", email: "user@example.com", configDirectory: "/Users/example/.claude-work")
        _ = e.handle(.account(account), now: t0 + 3)
        guard case .readSessions(let work) = e.handle(.pollSessions, now: t0 + 4).first else {
            Issue.record("no read")
            return
        }
        #expect(work.path == "/Users/example/.claude-work/sessions")
        var hidden = engine {
            $0.showSessions = false
            $0.showMascot = false
        }
        start(&hidden, now: t0)
        #expect(hidden.handle(.pollSessions, now: t0 + 2).isEmpty)
    }

    @Test func statusAndAccountLandInTheSnapshotWithTheirTimes() {
        var e = engine()
        start(&e, now: t0)
        _ = e.handle(.status(ServiceStatus(indicator: "none")), now: t0 + 1)
        #expect(e.snapshot.status?.indicator == "none")
        #expect(e.snapshot.statusAt == t0 + 1)
        let account = AccountInfo(loggedIn: true, plan: "Team", email: "user@example.com", configDirectory: "/Users/example/.claude")
        _ = e.handle(.account(account), now: t0 + 1)
        #expect(e.snapshot.account == account)
        _ = e.handle(.version(local: "2.1.302", latest: "2.1.302"), now: t0 + 1)
        #expect(e.snapshot.version.local == "2.1.302" && e.snapshot.version.latest == "2.1.302")
        // No answer keeps the last value and logs once.
        #expect(logs(e.handle(.status(nil), now: t0 + 121)) == ["status: no summary from status.claude.com"])
        #expect(e.snapshot.status?.indicator == "none")
        #expect(logs(e.handle(.account(nil), now: t0 + 601)) == ["account: claude auth status gave no answer"])
        #expect(e.snapshot.account == account)
    }

    // MARK: - Projects

    @Test func theTranscriptsAreScannedOnlyWithTheChartOnAndTheDetailsOpen() {
        for (history, expanded) in [(false, true), (true, false)] {
            var e = engine {
                $0.showHistory = history
                $0.expanded = expanded
            }
            #expect(!kinds(start(&e, now: t0)).contains("scanProjects"))
        }
        var e = engine {
            $0.showHistory = true
            $0.expanded = true
        }
        // Before the shell answers the config dir is unknown; claude itself is not needed.
        #expect(!kinds(e.handle(.tick, now: t0)).contains("scanProjects"))
        _ = e.handle(.loginShell(LoginEnvironment()), now: t0)
        #expect(e.handle(.located(nil, installHint: nil), now: t0).contains(.scanProjects(root: "/Users/example/.claude/projects")))
        // Every 15 minutes from the last attempt, and never two at once.
        #expect(!kinds(e.handle(.tick, now: t0 + 900)).contains("scanProjects"))
        _ = e.handle(.projects(ProjectScan()), now: t0 + 30)
        #expect(!kinds(e.handle(.tick, now: t0 + 899)).contains("scanProjects"))
        #expect(kinds(e.handle(.tick, now: t0 + 900)).contains("scanProjects"))
    }

    @Test func openingTheDetailsScansAtTheNextTick() {
        var e = engine { $0.showHistory = true }
        start(&e, now: t0)
        var open = e.config
        open.expanded = true
        _ = e.handle(.configChanged(open), now: t0 + 5)
        #expect(kinds(e.handle(.tick, now: t0 + 6)).contains("scanProjects"))
    }

    @Test func aScanLandsInTheSnapshotAndItsProblemsAreLoggedOnce() {
        var e = engine {
            $0.showHistory = true
            $0.expanded = true
        }
        start(&e, now: t0)
        let usage = ProjectUsage(projects: [ProjectWeight(path: "/Users/example/api", quarters: [0: 2])], unpriced: 3)
        let scan = ProjectScan(usage: usage, files: 4, bytes: 1000, unreadable: 1, unpricedModels: ["claude-opus-6", "claude-quill-1"])
        #expect(logs(e.handle(.projects(scan), now: t0 + 1)) == [
            "projects: unreadable transcripts: 1",
            "projects-price: no list price for claude-opus-6, claude-quill-1; estimated from the closest one listed",
        ])
        #expect(e.snapshot.projects == usage)
        #expect(e.snapshot.projectsAt == t0 + 1)
        #expect(logs(e.handle(.projects(scan), now: t0 + 901)).isEmpty)
    }

    @Test func anAccountInAnotherConfigDirHasItsTranscriptsScannedAtOnce() {
        var e = engine {
            $0.showHistory = true
            $0.expanded = true
        }
        start(&e, now: t0)
        _ = e.handle(.projects(ProjectScan()), now: t0 + 1)
        _ = e.handle(.account(AccountInfo(loggedIn: true, plan: "Max", configDirectory: "/Users/example/.claude")), now: t0 + 2)
        #expect(!kinds(e.handle(.tick, now: t0 + 3)).contains("scanProjects"))
        _ = e.handle(.account(AccountInfo(loggedIn: true, plan: "Max", configDirectory: "/Users/example/.claude-work")), now: t0 + 4)
        #expect(e.handle(.tick, now: t0 + 5).contains(.scanProjects(root: "/Users/example/.claude-work/projects")))
        // A move during a scan waits for it, then scans the new root.
        _ = e.handle(.account(AccountInfo(loggedIn: true, plan: "Max", configDirectory: "/Users/example/.claude")), now: t0 + 6)
        #expect(!kinds(e.handle(.tick, now: t0 + 7)).contains("scanProjects"))
        _ = e.handle(.projects(ProjectScan()), now: t0 + 8)
        #expect(e.handle(.tick, now: t0 + 9).contains(.scanProjects(root: "/Users/example/.claude/projects")))
    }

    // MARK: - The update and the changelog

    @Test func anUpdateRunsOnceAndTheVersionIsLookedAtAgainAfterIt() {
        var e = running(now: t0)
        let started = e.handle(.startUpdate, now: t0 + 5)
        guard case .runUpdate(let claude, let env) = started.first, started.count == 1 else {
            Issue.record("no update")
            return
        }
        #expect(claude == found.path)
        #expect(env["CLAUDECODE"] == nil)
        #expect(e.snapshot.version.updating)
        #expect(e.handle(.startUpdate, now: t0 + 6).isEmpty)
        #expect(kinds(e.handle(.update(nil, logTail: "Done"), now: t0 + 60)) == ["probeVersion"])
        #expect(!e.snapshot.version.updating)
        #expect(e.snapshot.version.updateFailure == nil)
        _ = e.handle(.version(local: "2.1.303", latest: "2.1.302"), now: t0 + 61)
        #expect(e.snapshot.version.local == "2.1.303")

        _ = e.handle(.version(local: "2.1.303", latest: "2.1.304"), now: t0 + 3700)
        #expect(e.snapshot.version.updateAvailable)
        _ = e.handle(.startUpdate, now: t0 + 3701)
        let failure = UpdateFailure(exitCode: 1, outputTail: "Error: managed by a package manager")
        let failed = e.handle(.update(failure, logTail: failure.outputTail), now: t0 + 3800)
        #expect(e.snapshot.version.updateFailure == UpdateFailure(exitCode: 1, outputTail: failure.outputTail, from: "2.1.303", to: "2.1.304"))
        #expect(logs(failed) == ["update: exit 1: Error: managed by a package manager"])
    }

    @Test func aFailedUpdateStaysUntilClaudeCodeHasUpdatedAnyway() {
        var e = behind(now: t0)
        _ = e.handle(.startUpdate, now: t0)
        _ = e.handle(.update(UpdateFailure(exitCode: 1, outputTail: ""), logTail: ""), now: t0 + 1)
        let failed = UpdateFailure(exitCode: 1, outputTail: "", from: "2.1.302", to: "2.1.303")
        #expect(e.snapshot.version.updateFailure == failed)
        // The look right after the run, and a look whose claude --version failed, change nothing.
        _ = e.handle(.version(local: "2.1.302", latest: "2.1.303"), now: t0 + 2)
        #expect(e.snapshot.version.updateFailure == failed)
        _ = e.handle(.version(local: nil, latest: "2.1.303"), now: t0 + 3600)
        #expect(e.snapshot.version.updateFailure == failed)
        // Claude Code's own updater got there.
        _ = e.handle(.version(local: "2.1.303", latest: "2.1.303"), now: t0 + 7200)
        #expect(e.snapshot.version.local == "2.1.303")
        #expect(e.snapshot.version.updateFailure == nil)
    }

    @Test func aNewerReleaseClearsAFailedUpdate() {
        var e = behind(now: t0)
        _ = e.handle(.startUpdate, now: t0)
        _ = e.handle(.update(UpdateFailure(exitCode: 1, outputTail: ""), logTail: ""), now: t0 + 1)
        #expect(e.snapshot.version.updateFailure != nil)
        _ = e.handle(.version(local: "2.1.302", latest: "2.1.304"), now: t0 + 3600)
        #expect(e.snapshot.version.latest == "2.1.304")
        #expect(e.snapshot.version.updateFailure == nil)
    }

    @Test func aCleanExitThatLeavesTheVersionIsAFailure() {
        var e = behind(now: t0)
        _ = e.handle(.startUpdate, now: t0)
        #expect(kinds(e.handle(.update(nil, logTail: "Checking for updates...\nDone"), now: t0 + 1)) == ["probeVersion"])
        let judged = e.handle(.version(local: "2.1.302", latest: "2.1.303"), now: t0 + 2)
        #expect(e.snapshot.version.updateFailure == UpdateFailure(
            exitCode: 0, outputTail: "Checking for updates...\nDone", from: "2.1.302", to: "2.1.303"
        ))
        #expect(logs(judged) == ["update: exit 0, but Claude Code is still 2.1.302"])
    }

    @Test func onlyALookStartedAfterACleanExitJudgesIt() {
        var e = behind(now: t0)
        _ = e.handle(.startUpdate, now: t0)
        // A look already running when the update ends still sees the old version.
        #expect(kinds(e.handle(.tick, now: t0 + 3600)).contains("probeVersion"))
        #expect(e.handle(.update(nil, logTail: ""), now: t0 + 3601).isEmpty)
        let old = e.handle(.version(local: "2.1.302", latest: "2.1.303"), now: t0 + 3602)
        #expect(e.snapshot.version.updateFailure == nil)
        // The look after the run is the one that counts.
        #expect(kinds(old) == ["probeVersion"])
        _ = e.handle(.version(local: "2.1.303", latest: "2.1.303"), now: t0 + 3603)
        #expect(e.snapshot.version.local == "2.1.303")
        #expect(e.snapshot.version.updateFailure == nil)
    }

    @Test func aFailedLookAfterACleanExitIsNoFailure() {
        var e = behind(now: t0)
        _ = e.handle(.startUpdate, now: t0)
        _ = e.handle(.update(nil, logTail: ""), now: t0 + 1)
        _ = e.handle(.version(local: nil, latest: "2.1.303"), now: t0 + 2)
        #expect(e.snapshot.version.updateFailure == nil)
    }

    @Test func theChangelogIsFetchedOnlyWhileAnUpdateIsAvailable() {
        var e = engine()
        start(&e, now: t0)
        #expect(e.handle(.version(local: "2.1.301", latest: "2.1.303"), now: t0) == [.fetchChangelog])
        _ = e.handle(.changelog(Fixture.text("version/CHANGELOG.md")), now: t0 + 1)
        #expect(e.snapshot.version.changes == ChangesExcerpt(forVersion: "2.1.303", fromVersion: "2.1.301", items: [
            "Fixed claude update on some installs", "Added a setting for the status line",
            "nested detail with inline code", "Faster /usage",
            "A star bullet with **bold** and a [link](https://example.com)",
        ]))
        #expect(!kinds(e.handle(.tick, now: t0 + 3600)).contains("fetchChangelog"))
        // A failed download is tried again after 10 minutes.
        var failed = running(local: "2.1.301", latest: "2.1.303", now: t0)
        #expect(logs(failed.handle(.changelog(nil), now: t0 + 1)) == ["changelog: download failed"])
        #expect(!kinds(failed.handle(.tick, now: t0 + 300)).contains("fetchChangelog"))
        #expect(kinds(failed.handle(.tick, now: t0 + 600)).contains("fetchChangelog"))
        // Up to date: never.
        var current = engine()
        start(&current, now: t0)
        #expect(current.handle(.version(local: "2.1.303", latest: "2.1.303"), now: t0).isEmpty)
    }

    // MARK: - One instant

    /// What `--diagnose` relies on: at one instant every slot starts once and the next tick asks for nothing.
    @Test func atOneInstantEverySlotStartsOnceAndThenNothingIsDue() {
        var e = engine { $0 = $0.everyBlockOn() }
        #expect(kinds(start(&e, now: t0)) == ["probeStatus", "runLoginShell", "readSessions", "locate", "scanProjects", "probeVersion", "probeUsage", "probeAccount"])
        #expect(e.handle(.version(local: "2.1.301", latest: "2.1.303"), now: t0) == [.fetchChangelog])
        _ = e.handle(.changelog(nil), now: t0)
        _ = e.handle(usage(50), now: t0)
        _ = e.handle(.account(AccountInfo(loggedIn: true, plan: "Max", configDirectory: "/Users/example/.claude-work")), now: t0)
        _ = e.handle(.status(ServiceStatus(indicator: "none")), now: t0)
        _ = e.handle(.sessionsRead([]), now: t0)
        _ = e.handle(.projects(ProjectScan()), now: t0)
        // The account moved the transcripts once; the poll always reads, so it is not a reason to go on.
        #expect(e.handle(.tick, now: t0) == [.scanProjects(root: "/Users/example/.claude-work/projects")])
        #expect(kinds(e.handle(.pollSessions, now: t0)) == ["readSessions"])
        _ = e.handle(.projects(ProjectScan()), now: t0)
        #expect(e.handle(.tick, now: t0).isEmpty)
        // A latch lifted by the version re-arms the usage probe once.
        var latched = engine(latch: UsageLatch(version: "2.1.301", issue: .flagRejected("--x")))
        #expect(!kinds(start(&latched, now: t0)).contains("probeUsage"))
        #expect(kinds(latched.handle(.version(local: "2.1.302", latest: "2.1.302"), now: t0)) == ["saveLatch", "probeUsage"])
        _ = latched.handle(usage(50), now: t0)
        _ = latched.handle(.account(AccountInfo(loggedIn: true)), now: t0)
        _ = latched.handle(.status(ServiceStatus(indicator: "none")), now: t0)
        #expect(latched.handle(.tick, now: t0).isEmpty)
        // A tripped guard while the version is unknown asks for one more look; unkeyed, the latch holds unsaved.
        var unknown = engine()
        start(&unknown, now: t0)
        _ = unknown.handle(.version(local: nil, latest: "2.1.302"), now: t0)
        #expect(kinds(unknown.handle(issue(.flagRejected("--x")), now: t0)) == ["probeVersion", "log"])
        _ = unknown.handle(.version(local: nil, latest: "2.1.302"), now: t0)
        _ = unknown.handle(.account(AccountInfo(loggedIn: true)), now: t0)
        _ = unknown.handle(.status(ServiceStatus(indicator: "none")), now: t0)
        #expect(unknown.handle(.tick, now: t0).isEmpty)
        #expect(unknown.snapshot.usageIssue == .flagRejected("--x"))
        // A shell without an answer and no claude anywhere: looked for once.
        var missing = engine()
        _ = missing.handle(.tick, now: t0)
        _ = missing.handle(.loginShell(nil), now: t0)
        _ = missing.handle(.located(nil, installHint: nil), now: t0)
        _ = missing.handle(.status(ServiceStatus(indicator: "none")), now: t0)
        #expect(missing.handle(.tick, now: t0).isEmpty)
    }
}
