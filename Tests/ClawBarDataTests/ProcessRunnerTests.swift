import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

/// Real children, all of them /bin tools: never claude.
@Suite struct ProcessRunnerTests {
    let runner = ProcessRunner()
    let dir = TempDir("cb-proc")

    func sh(_ script: String, timeout: TimeInterval = 20, killAfter: TimeInterval = 3, grace: TimeInterval = 2,
            output: ProcessSpec.Output = .capture, env: [String: String] = ["PATH": "/usr/bin:/bin"]) -> ProcessSpec {
        ProcessSpec(
            executable: "/bin/sh", arguments: ["-c", script], environment: env, directory: dir.url.path,
            timeout: timeout, killAfter: killAfter, output: output, drainGrace: grace
        )
    }

    func outcome(_ spec: ProcessSpec) async throws -> ProcessOutcome {
        try await runner.run(spec).get()
    }

    @Test func probesGetTheAgreedDefaults() {
        let s = ProcessSpec(executable: "/x", arguments: [], environment: [:], directory: "/")
        #expect(s.timeout == 60 && s.killAfter == 3 && s.drainGrace == 2 && s.outputCap == 1_048_576)
        #expect(!s.survivesQuit)
    }

    @Test func capturesBothStreamsAndTheExitCode() async throws {
        let o = try await outcome(sh("echo out; echo err >&2; exit 3"))
        #expect(o.stdoutText == "out\n")
        #expect(o.stderrText == "err\n")
        #expect(o.termination == .exit(3))
        #expect(!o.timedOut)
    }

    @Test func stdinIsDevNullAndTheDirectoryIsTheSpecs() async throws {
        let o = try await outcome(sh("cat; pwd -P"))
        // realpath(3), because URL.resolvingSymlinksInPath drops the /private of /private/var
        let real = try #require(realpath(dir.url.path, nil))
        defer { free(real) }
        #expect(o.stdoutText == String(cString: real) + "\n")
    }

    @Test func eachStreamIsCappedAtOneMegabyteWithoutADeadlock() async throws {
        let start = ContinuousClock.now
        let o = try await outcome(sh("head -c 3000000 /dev/zero; head -c 3000000 /dev/zero >&2; exit 0"))
        #expect(o.stdout.count == 1_048_576)
        #expect(o.stderr.count == 1_048_576)
        #expect(o.termination == .exit(0))
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func aTimeoutSendsSigtermFirst() async throws {
        let o = try await outcome(sh("exec /bin/sleep 30", timeout: 0.3))
        #expect(o.timedOut)
        #expect(o.termination == .signal(SIGTERM))
    }

    @Test func aChildIgnoringSigtermIsKilledAfterTheGrace() async throws {
        let start = ContinuousClock.now
        let o = try await outcome(sh("trap '' TERM; while :; do /bin/sleep 0.05; done", timeout: 0.3, killAfter: 0.5))
        let took = ContinuousClock.now - start
        #expect(o.timedOut)
        #expect(o.termination == .signal(SIGKILL))
        #expect(took >= .milliseconds(750) && took < .seconds(5))
    }

    /// Backgrounds a member of the child's group that ignores SIGTERM and writes its pid to `member.pid`.
    var memberIgnoringSigterm: String {
        "/bin/sh -c \"trap '' TERM; exec /bin/sleep 30\" >/dev/null 2>&1 & echo $! > member.pid; exec /bin/sleep 30"
    }

    func member() async throws -> Int32 {
        let url = dir.file("member.pid")
        for _ in 0 ..< 200 where !FileManager.default.fileExists(atPath: url.path) { try await Task.sleep(for: .milliseconds(5)) }
        return try #require(Int32(String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// Whether the pid is gone within the deadline; a killed orphan lingers as a zombie until launchd reaps it.
    func gone(_ pid: Int32) async throws -> Bool {
        for _ in 0 ..< 300 {
            if kill(pid, 0) == -1, errno == ESRCH { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test func aTimeoutKillsAGroupMemberIgnoringSigtermThoughTheLeaderObeyed() async throws {
        let o = try await outcome(sh(memberIgnoringSigterm, timeout: 0.3, killAfter: 0.5))
        defer { kill(-o.pid, SIGKILL) }
        #expect(o.timedOut)
        #expect(o.termination == .signal(SIGTERM))
        #expect(try await gone(try await member()))
    }

    @Test func shutdownKillsAGroupMemberIgnoringSigtermThoughTheLeaderObeyed() async throws {
        let probe = Task { try await outcome(sh(memberIgnoringSigterm)) }
        let pid = try await member()
        runner.shutdown()
        let o = try await probe.value
        defer { kill(-o.pid, SIGKILL) }
        #expect(o.termination == .signal(SIGTERM))
        #expect(try await gone(pid))
    }

    @Test func aGrandchildHoldingThePipeDoesNotBlockTheResult() async throws {
        let start = ContinuousClock.now
        let o = try await outcome(sh("echo started; /bin/sleep 8 & echo done", grace: 0.4))
        let took = ContinuousClock.now - start
        kill(-o.pid, SIGKILL)
        #expect(o.stdoutText == "started\ndone\n")
        #expect(o.termination == .exit(0))
        #expect(took >= .milliseconds(350) && took < .seconds(4))
    }

    @Test func threeDistinctLaunchErrors() async {
        let missing = dir.url.appendingPathComponent("nope").path
        #expect(await runner.run(ProcessSpec(executable: missing, arguments: [], environment: [:], directory: "/"))
            == .failure(.notFound(missing)))
        let plain = dir.write("plain.sh", "#!/bin/sh\necho hi\n").path
        #expect(await runner.run(ProcessSpec(executable: plain, arguments: [], environment: [:], directory: "/"))
            == .failure(.notExecutable(plain)))
        #expect(await runner.run(ProcessSpec(executable: dir.url.path, arguments: [], environment: [:], directory: "/"))
            == .failure(.notExecutable(dir.url.path)))
        let garbage = dir.write("garbage", "\u{7}\u{1}not a program\n", executable: true).path
        guard case .failure(.failed(let p, let e)) = await runner.run(
            ProcessSpec(executable: garbage, arguments: [], environment: [:], directory: "/")
        ) else {
            Issue.record("expected a spawn failure")
            return
        }
        #expect(p == garbage)
        #expect(e == ENOEXEC)
    }

    @Test func theChildSeesTheScrubbedEnvironment() async throws {
        let inherited = [
            "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "CLAUDE_CODE_SESSION_ID": "s",
            "CLAUDE_CODE_MESSAGING_SOCKET": "/tmp/x.sock", "CLAUDE_PID": "7", "AI_AGENT": "agent",
            "CLAUDE_CONFIG_DIR": "/Users/example/.claude-work", "ANTHROPIC_BASE_URL": "https://example.invalid",
            "HOME": "/Users/example", "PATH": "/usr/bin:/bin",
        ]
        let env = ChildEnv.make(inherited: inherited, login: nil, claude: "/opt/tools/claude")
        let o = try await outcome(ProcessSpec(executable: "/usr/bin/env", arguments: [], environment: env, directory: "/"))
        let seen = Dictionary(uniqueKeysWithValues: o.stdoutText.split(separator: "\n").compactMap { line -> (String, String)? in
            guard let eq = line.firstIndex(of: "=") else { return nil }
            return (String(line[..<eq]), String(line[line.index(after: eq)...]))
        })
        #expect(seen["CLAUDECODE"] == nil)
        #expect(seen["CLAUDE_CODE_ENTRYPOINT"] == nil)
        #expect(seen["CLAUDE_CODE_SESSION_ID"] == nil)
        #expect(seen["CLAUDE_CODE_MESSAGING_SOCKET"] == nil)
        #expect(seen["CLAUDE_PID"] == nil)
        #expect(seen["AI_AGENT"] == nil)
        #expect(seen["CLAUDE_CONFIG_DIR"] == "/Users/example/.claude-work")
        #expect(seen["ANTHROPIC_BASE_URL"] == "https://example.invalid")
        #expect(seen["PATH"] == "/usr/bin:/bin:/opt/tools:/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin")
    }

    @Test func childPIDsAreRegisteredWhileTheyRun() async throws {
        let task = Task { try await outcome(sh("/bin/sleep 0.4")) }
        var seen: Set<Int32> = []
        for _ in 0 ..< 200 where seen.isEmpty {
            seen = runner.childPIDs
            try await Task.sleep(for: .milliseconds(5))
        }
        let o = try await task.value
        #expect(seen == [o.pid])
        #expect(runner.childPIDs.isEmpty)
    }

    @Test func shutdownEndsProbesButAnUpdateSurvivesWithItsOutputInAFile() async throws {
        let log = dir.file("update.log")
        let update = Task { try await outcome(sh("/bin/sleep 0.6; echo finished", output: .survivesQuit(log))) }
        let probe = Task { try await outcome(sh("exec /bin/sleep 30")) }
        for _ in 0 ..< 200 where runner.childPIDs.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(runner.childPIDs.count == 2)
        runner.shutdown()
        let p = try await probe.value
        #expect(p.termination == .signal(SIGTERM))
        let u = try await update.value
        #expect(u.termination == .exit(0))
        #expect(u.stdout.isEmpty)
        #expect(try String(contentsOf: log, encoding: .utf8) == "finished\n")
    }
}

@Suite struct ChildEnvTests {
    @Test func claudeCodesOwnVariablesGoAndUserSettingsStay() {
        let env = ChildEnv.scrub([
            "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "CLAUDE_CODE_EXECPATH": "/x",
            "CLAUDE_CODE_SESSION_ID": "a", "CLAUDE_CODE_SESSION_ATTENDED": "1", "CLAUDE_CODE_SESSION_FUTURE": "f",
            "CLAUDE_CODE_CHILD_SESSION": "1", "CLAUDE_CODE_MESSAGING_TOKEN": "t", "CLAUDE_CODE_MESSAGING_NEW": "n",
            "CLAUDE_CODE_SSE_PORT": "1234", "CLAUDE_PID": "9", "CLAUDE_EFFORT": "max", "AI_AGENT": "a",
            "CLAUDE_PROJECT_DIR": "/p", "CLAUDE_ENV_FILE": "/e", "CLAUDE_AGENT_SDK_VERSION": "1",
            "CLAUDE_CONFIG_DIR": "/c", "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_SUBAGENT_MODEL": "m",
            "ANTHROPIC_API_KEY": "k", "HOME": "/h",
        ])
        #expect(env == [
            "CLAUDE_CONFIG_DIR": "/c", "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_SUBAGENT_MODEL": "m",
            "ANTHROPIC_API_KEY": "k", "HOME": "/h",
        ])
    }

    @Test func pathIsTheLoginPathThenClaudesFolderThenBrewThenTheSystem() {
        let login = LoginEnvironment(claudePath: nil, path: "/Users/example/.nvm/bin:/usr/bin:/opt/homebrew/bin", claudeConfigDir: nil)
        let env = ChildEnv.make(inherited: ["PATH": "/usr/bin:/bin"], login: login, claude: "/Users/example/.local/bin/claude")
        #expect(env["PATH"] == "/Users/example/.nvm/bin:/usr/bin:/opt/homebrew/bin:/Users/example/.local/bin:/usr/local/bin:/bin:/usr/sbin:/sbin")
    }

    @Test func withoutALoginShellTheInheritedPathIsTheBase() {
        let env = ChildEnv.make(inherited: [:], login: nil, claude: nil)
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test func theLoginShellsConfigDirReachesTheChild() {
        let login = LoginEnvironment(claudePath: nil, path: nil, claudeConfigDir: "/Users/example/.claude-work")
        #expect(ChildEnv.make(inherited: [:], login: login, claude: nil)["CLAUDE_CONFIG_DIR"] == "/Users/example/.claude-work")
        let keep = ChildEnv.make(inherited: ["CLAUDE_CONFIG_DIR": "/a"], login: LoginEnvironment(), claude: nil)
        #expect(keep["CLAUDE_CONFIG_DIR"] == "/a")
    }
}
