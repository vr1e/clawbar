import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

@Suite struct VersionProbeTests {
    func ran(_ stdout: String, exit: Int32 = 0) -> ProcessResult {
        .success(ProcessOutcome(pid: 9, termination: .exit(exit), stdout: Data(stdout.utf8)))
    }

    @Test func theLocalVersionIsTheFirstDottedTriple() {
        #expect(VersionProbe.spec(claude: "/c/claude", environment: [:], home: "/h").arguments == ["--version"])
        #expect(VersionProbe.local(ran("2.1.302 (Claude Code)\n")) == "2.1.302")
        #expect(VersionProbe.local(ran("claude 2.1.10-beta\n")) == "2.1.10")
        #expect(VersionProbe.local(ran("no version here")) == nil)
        #expect(VersionProbe.local(.failure(.notFound("/c"))) == nil)
    }

    @Test func theChannelComesFromSettingsAndDefaultsToLatest() {
        #expect(VersionProbe.channel(settings: Data(#"{"autoUpdatesChannel": "stable"}"#.utf8)) == "stable")
        #expect(VersionProbe.channel(settings: Data(#"{"autoUpdatesChannel": "Stable"}"#.utf8)) == "stable")
        #expect(VersionProbe.channel(settings: Data(#"{"autoUpdatesChannel": "latest"}"#.utf8)) == "latest")
        #expect(VersionProbe.channel(settings: Data(#"{"autoUpdatesChannel": "beta"}"#.utf8)) == "latest")
        #expect(VersionProbe.channel(settings: Data("{oops".utf8)) == "latest")
        #expect(VersionProbe.channel(settings: nil) == "latest")
    }

    @Test func theChannelsReleaseFile() {
        #expect(VersionProbe.latestURL(channel: "stable").absoluteString == "https://downloads.claude.ai/claude-code-releases/stable")
        #expect(VersionProbe.latest("2.1.302\n") == "2.1.302")
        #expect(VersionProbe.latest("  2.1.303 ") == "2.1.303")
        #expect(VersionProbe.latest("<html>2.1.303</html>") == nil)
    }
}

@Suite struct ChangelogSlicerTests {
    let log = Fixture.text("version/CHANGELOG.md")

    @Test func itemsAfterTheLocalVersionUpToTheLatestNewestFirst() {
        #expect(ChangelogSlicer.slice(log, after: "2.1.301", upTo: "2.1.303") == [
            "Fixed claude update on some installs",
            "Added a setting for the status line",
            "nested detail with inline code",
            "Faster /usage",
            "A star bullet with **bold** and a [link](https://example.com)",
        ])
    }

    @Test func versionsCompareAsNumbers() {
        #expect(ChangelogSlicer.slice(log, after: "2.1.9", upTo: "2.1.10") == ["Numeric comparison item"])
    }

    @Test func nothingNewIsEmpty() {
        #expect(ChangelogSlicer.slice(log, after: "2.1.303", upTo: "2.1.303").isEmpty)
        #expect(ChangelogSlicer.slice("no sections at all", after: "1.0.0", upTo: "9.0.0").isEmpty)
    }

    @Test func everyItemIsKeptForThePresentersCut() {
        let many = "## 3.0.0\n" + (1 ... 40).map { "- item \($0)" }.joined(separator: "\n")
        #expect(ChangelogSlicer.slice(many, after: "2.0.0", upTo: "3.0.0").count == 40)
    }
}

@Suite struct UpdateRunnerTests {
    let dir = TempDir("cb-update")

    @Test func aHeadlessUpdateThatSurvivesQuitting() {
        let log = dir.file("update.log")
        let spec = UpdateRunner.spec(claude: "/c/claude", environment: ["A": "b"], home: "/h", log: log)
        #expect(spec.arguments == ["update"])
        #expect(spec.output == .survivesQuit(log))
        #expect(spec.timeout == 900)
        #expect(spec.environment == ["A": "b"])
    }

    @Test func successIsNoFailure() {
        let ok = ProcessResult.success(ProcessOutcome(pid: 5, termination: .exit(0)))
        #expect(UpdateRunner.failure(ok, tail: "", home: "/Users/example") == nil)
    }

    @Test func aFailureCarriesTheExitCodeAndARedactedTail() throws {
        let log = dir.write("update.log", (1 ... 20).map { "line \($0)" }.joined(separator: "\n")
            + "\nChecking for updates...\r\u{1B}[32mDownloading 40%\u{1B}[0m\rDownloading 100%\n"
            + "Error: cannot write /Users/example/.local/bin/claude for user@example.com\n\n")
        let r = ProcessResult.success(ProcessOutcome(pid: 5, termination: .exit(1)))
        let f = try #require(UpdateRunner.failure(r, tail: UpdateRunner.tail(of: log, home: "/Users/example"), home: "/Users/example"))
        #expect(f.exitCode == 1)
        let lines = f.outputTail.split(separator: "\n")
        #expect(lines.count == UpdateRunner.tailLines)
        #expect(lines.last == "Error: cannot write ~/.local/bin/claude for <email>")
        #expect(lines.dropLast().last == "Downloading 100%")
    }

    @Test func aTimeoutHasNoExitCodeAndLaunchErrorsUseShellCodes() throws {
        let timedOut = ProcessResult.success(ProcessOutcome(pid: 5, termination: .signal(SIGTERM), timedOut: true))
        #expect(try #require(UpdateRunner.failure(timedOut, tail: "", home: "/h")).exitCode == nil)
        let killed = ProcessResult.success(ProcessOutcome(pid: 5, termination: .signal(SIGKILL)))
        #expect(UpdateRunner.failure(killed, tail: "", home: "/h")?.exitCode == 137)
        let missing = UpdateRunner.failure(.failure(.notFound("/Users/example/.local/bin/claude")), tail: "", home: "/Users/example")
        #expect(missing == UpdateFailure(exitCode: 127, outputTail: "not found: ~/.local/bin/claude"))
    }

    @Test func theInstallHintComesFromWhereClaudeReallyLives() throws {
        func link(_ from: String, to: String) throws -> String {
            let target = dir.write(to, "#!/bin/sh\n", executable: true).path
            let path = dir.url.appendingPathComponent(from).path
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
            return path
        }
        let brew = try link("opt/homebrew/bin/claude", to: "opt/homebrew/Caskroom/claude-code/2.1.302/claude")
        #expect(UpdateRunner.installHint(claudePath: brew) == .homebrew)
        let npm = try link("usr/local/bin/claude", to: "usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js")
        #expect(UpdateRunner.installHint(claudePath: npm) == .npm)
        let native = try link("home/.local/bin/claude", to: "home/.local/share/claude/versions/2.1.302")
        #expect(UpdateRunner.installHint(claudePath: native) == nil)
        #expect(UpdateRunner.installHint(claudePath: "/opt/homebrew/bin/claude-not-there") == .homebrew)
    }
}
