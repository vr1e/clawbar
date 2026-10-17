import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

@Suite struct UsageProbeTests {
    let now = utc("2026-10-16T22:30:00Z")

    func finished(_ stdout: Data, exit: Int32 = 0, stderr: String = "", timedOut: Bool = false) -> ProcessResult {
        .success(ProcessOutcome(pid: 4242, termination: .exit(exit), stdout: stdout, stderr: Data(stderr.utf8), timedOut: timedOut))
    }

    func outcome(_ r: ProcessResult) -> UsageProbe.Outcome {
        UsageProbe.interpret(r, now: now, timeZone: berlin).outcome
    }

    /// today.json with one field replaced.
    func todayEnvelope(_ edit: (inout [String: Any]) -> Void) -> Data {
        var j = (try? JSONSerialization.jsonObject(with: Fixture.data("usage/today.json"))) as? [String: Any] ?? [:]
        edit(&j)
        return (try? JSONSerialization.data(withJSONObject: j)) ?? Data()
    }

    @Test func theProbeAsksForUsageInSafeModeWithoutTouchingSessions() {
        let spec = UsageProbe.spec(claude: "/opt/x/claude", environment: ["PATH": "/usr/bin"], home: "/Users/example")
        #expect(spec.executable == "/opt/x/claude")
        #expect(spec.arguments == ["-p", "/usage", "--no-session-persistence", "--output-format", "json"])
        #expect(spec.environment["CLAUDE_CODE_SAFE_MODE"] == "1")
        #expect(spec.environment["PATH"] == "/usr/bin")
        #expect(spec.directory == "/Users/example")
        #expect(spec.timeout == 60)
    }

    @Test func aZeroCostEnvelopeYieldsTheParsedUsage() throws {
        let report = UsageProbe.interpret(finished(Fixture.data("usage/today.json")), now: now, timeZone: berlin)
        guard case .usage(let u) = report.outcome else {
            Issue.record("expected usage, got \(report.outcome)")
            return
        }
        #expect(u.sessionPercent == 50)
        let env = try #require(report.envelope)
        #expect(env.numTurns == 0 && env.costUSD == 0 && env.tokens == 0 && env.modelUsageCount == 0)
    }

    @Test func reachingTheModelTripsTheGuardWithTurnsCostAndTokens() {
        // input 1200 + output 85; the model usage repeats them and is not added twice
        #expect(outcome(finished(Fixture.data("usage/model-reached.json")))
            == .issue(.modelReached(turns: 1, costUSD: 0.0123, tokens: 1285)))
    }

    @Test func anySingleNonZeroGuardFieldTrips() {
        #expect(outcome(finished(todayEnvelope { $0["num_turns"] = 2 })) == .issue(.modelReached(turns: 2, costUSD: 0, tokens: 0)))
        #expect(outcome(finished(todayEnvelope { $0["total_cost_usd"] = 0.5 })) == .issue(.modelReached(turns: 0, costUSD: 0.5, tokens: 0)))
        let nested = todayEnvelope {
            var usage = $0["usage"] as? [String: Any] ?? [:]
            usage["output_tokens_details"] = ["thinking_tokens": 7]
            $0["usage"] = usage
        }
        #expect(outcome(finished(nested)) == .issue(.modelReached(turns: 0, costUSD: 0, tokens: 7)))
        let modelOnly = todayEnvelope { $0["modelUsage"] = ["claude-x": ["inputTokens": 3, "outputTokens": 4]] }
        #expect(outcome(finished(modelOnly)) == .issue(.modelReached(turns: 0, costUSD: 0, tokens: 7)))
    }

    @Test func spendingTripsTheGuardEvenWhenTheRunThenFails() {
        // An API error after reaching the model exits 1; retrying it every minute would keep spending.
        let failed = finished(Fixture.data("usage/model-reached.json"), exit: 1, stderr: "API Error: 529 Overloaded")
        #expect(outcome(failed) == .issue(.modelReached(turns: 1, costUSD: 0.0123, tokens: 1285)))
    }

    @Test func aRejectedOptionNamesTheOption() {
        let r = finished(Data(), exit: 1, stderr: Fixture.text("usage/flag-rejected-stderr.txt"))
        #expect(outcome(r) == .issue(.flagRejected("--no-session-persistence")))
        let bad = finished(Data(), exit: 1, stderr: "error: option '--output-format <format>' argument 'json' is invalid.")
        #expect(outcome(bad) == .issue(.flagRejected("--output-format json")))
    }

    @Test func otherNonZeroExitsAreProbeFailures() {
        guard case .issue(.probeFailed(let why)) = outcome(finished(Data(), exit: 3, stderr: "boom")) else {
            Issue.record("expected probeFailed")
            return
        }
        #expect(why.contains("3") && why.contains("boom"))
    }

    @Test func timeoutsLaunchErrorsAndBadOutput() {
        #expect(outcome(finished(Data(), exit: 0, timedOut: true)) == .issue(.timedOut))
        #expect(outcome(.failure(.notFound("/x/claude"))) == .issue(.claudeNotFound))
        #expect(outcome(.failure(.notExecutable("/x/claude"))) == .issue(.launchFailed("not executable: /x/claude")))
        guard case .issue(.probeFailed) = outcome(finished(Data("not json".utf8))) else {
            Issue.record("expected probeFailed for bad JSON")
            return
        }
        guard case .issue(.probeFailed) = outcome(finished(todayEnvelope { $0["is_error"] = true })) else {
            Issue.record("expected probeFailed for is_error")
            return
        }
    }

    @Test func theCostSummaryIsNoLimits() {
        let data = todayEnvelope { $0["result"] = Fixture.text("usage/no-limits.txt") }
        let report = UsageProbe.interpret(finished(data), now: now, timeZone: berlin)
        #expect(report.outcome == .issue(.noLimits))
        #expect(report.stats == UsageSnapshot())
    }

    @Test func anyOtherAnswerWithoutLimitsIsAFailedProbeWithAFixedMessage() {
        for result in ["", Fixture.text("usage/subscription-unavailable.txt")] {
            let data = todayEnvelope { $0["result"] = result }
            #expect(outcome(finished(data)) == .issue(.probeFailed("no limit lines in /usage")))
        }
    }
}

@Suite struct UsageLatchTests {
    @Test func bothLatchesRoundTripThroughTheStateFile() {
        let dir = TempDir()
        let store = LatchStore(url: dir.paths.stateFile)
        #expect(store.load() == nil)
        let reached = UsageLatch(version: "2.1.302", issue: .modelReached(turns: 1, costUSD: 0.0123, tokens: 1285))
        store.save(reached)
        #expect(LatchStore(url: dir.paths.stateFile).load() == reached)
        let rejected = UsageLatch(version: "2.1.303", issue: .flagRejected("--no-session-persistence"))
        store.save(rejected)
        #expect(store.load() == rejected)
    }

    @Test func savingAndClearingKeepOtherState() throws {
        let dir = TempDir()
        let url = dir.paths.stateFile
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"somethingElse": {"kept": true}}"#.utf8).write(to: url)
        let store = LatchStore(url: url)
        store.save(UsageLatch(version: "2.1.302", issue: .flagRejected("--x")))
        store.save(nil)
        let j = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(j["usageLatch"] == nil)
        #expect((j["somethingElse"] as? [String: Any])?["kept"] as? Bool == true)
    }

    @Test func onlyLatchedIssuesAreStoredAndAVersionChangeReArms() {
        #expect(UsageLatch(version: "2.1.302", issue: .timedOut) == nil)
        let latch = UsageLatch(version: "2.1.302", issue: .flagRejected("--x"))
        #expect(latch?.holds(forVersion: "2.1.302") == true)
        #expect(latch?.holds(forVersion: "2.1.303") == false)
    }

    @Test func aDamagedStateFileMeansNoLatch() throws {
        let dir = TempDir()
        let url = dir.paths.stateFile
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{nope".utf8).write(to: url)
        #expect(LatchStore(url: url).load() == nil)
        try Data(#"{"usageLatch": {"cliVersion": "2.1.302", "issue": "mystery"}}"#.utf8).write(to: url)
        #expect(LatchStore(url: url).load() == nil)
    }
}
