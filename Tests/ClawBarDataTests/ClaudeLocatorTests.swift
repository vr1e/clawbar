import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

@Suite struct ClaudeLocatorTests {
    let dir = TempDir("cb-locate")
    var home: String { dir.url.appendingPathComponent("home").path }

    @discardableResult
    func fakeClaude(_ relative: String) -> String {
        dir.write("home/\(relative)", "#!/bin/sh\necho 2.1.302\n", executable: true).path
    }

    @Test func theConfiguredPathComesFirst() {
        fakeClaude(".local/bin/claude")
        let mine = fakeClaude("tools/claude")
        let found = ClaudeLocator(home: home).locate(configPath: mine, login: nil)
        #expect(found == ClaudeLocator.Found(path: mine, source: .config))
    }

    @Test func aConfiguredTildePathIsExpanded() {
        let mine = fakeClaude("tools/claude")
        #expect(ClaudeLocator(home: home).locate(configPath: "~/tools/claude", login: nil)?.path == mine)
    }

    @Test func thenTheUsualInstallPathsInOrder() {
        let local = fakeClaude(".claude/local/claude")
        let missing = dir.url.appendingPathComponent("nope/claude").path
        #expect(ClaudeLocator(home: home).locate(configPath: missing, login: nil) == ClaudeLocator.Found(path: local, source: .candidate))
        let native = fakeClaude(".local/bin/claude")
        #expect(ClaudeLocator(home: home).locate(configPath: nil, login: nil)?.path == native)
    }

    @Test func thenTheLoginShellsCommandV() {
        let elsewhere = fakeClaude("elsewhere/claude")
        let login = LoginEnvironment(claudePath: elsewhere, path: "/usr/bin")
        let found = ClaudeLocator(home: home, candidates: []).locate(configPath: nil, login: login)
        #expect(found == ClaudeLocator.Found(path: elsewhere, source: .loginShell))
    }

    @Test func thenTheLoginPathsFolders() {
        let onPath = fakeClaude("node/bin/claude")
        let login = LoginEnvironment(path: "/usr/bin:" + (onPath as NSString).deletingLastPathComponent)
        #expect(ClaudeLocator(home: home, candidates: []).locate(configPath: nil, login: login)
            == ClaudeLocator.Found(path: onPath, source: .loginPath))
        #expect(ClaudeLocator(home: home, candidates: []).locate(configPath: nil, login: LoginEnvironment(path: "/usr/bin")) == nil)
    }

    @Test func aSymlinkIsKeptAsFoundBecauseAutoUpdateRePointsIt() throws {
        let target = fakeClaude(".local/share/claude/versions/2.1.302")
        let link = dir.url.appendingPathComponent("home/.local/bin/claude").path
        try FileManager.default.createDirectory(atPath: (link as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        #expect(ClaudeLocator(home: home).locate(configPath: nil, login: nil)?.path == link)
    }

    @Test func aFileWithoutTheExecutableBitIsSkipped() {
        dir.write("home/.local/bin/claude", "#!/bin/sh\n")
        #expect(ClaudeLocator(home: home, candidates: [home + "/.local/bin/claude"]).locate(configPath: nil, login: nil) == nil)
    }
}

@Suite struct LoginShellTests {
    @Test func readsTheValuesBetweenTheSentinelsPastAnyNoise() {
        let out = """
        Last login: Fri Oct 16 on ttys001
        __CLAWBAR_CLAUDE__
        alias claude='claude --verbose'
        /Users/example/.local/bin/claude
        __CLAWBAR_PATH__
        /Users/example/.local/bin:/usr/bin:/bin
        __CLAWBAR_CONFIG__
        ~/.claude-work
        __CLAWBAR_END__
        bye
        """
        #expect(LoginShell.parse(out, home: "/Users/example") == LoginEnvironment(
            claudePath: "/Users/example/.local/bin/claude",
            path: "/Users/example/.local/bin:/usr/bin:/bin",
            claudeConfigDir: "/Users/example/.claude-work"
        ))
    }

    @Test func unsetValuesStayNilAndAMissingStartMeansNothingRan() {
        let out = "__CLAWBAR_CLAUDE__\n__CLAWBAR_PATH__\n/usr/bin:/bin\n__CLAWBAR_CONFIG__\n__CLAWBAR_END__\n"
        #expect(LoginShell.parse(out, home: "/h") == LoginEnvironment(claudePath: nil, path: "/usr/bin:/bin", claudeConfigDir: nil))
        #expect(LoginShell.parse("zsh: command not found\n", home: "/h") == nil)
    }

    @Test func aCutOffRunKeepsTheFinishedSections() {
        let out = "__CLAWBAR_CLAUDE__\n/opt/c/claude\n__CLAWBAR_PATH__\n/usr/bin\n"
        #expect(LoginShell.parse(out, home: "/h") == LoginEnvironment(claudePath: "/opt/c/claude", path: nil, claudeConfigDir: nil))
    }

    @Test func theShellRunsAsAnInteractiveLoginShellWithStdinClosed() {
        let spec = LoginShell.spec(shell: "/bin/zsh", environment: ["HOME": "/h"], home: "/h")
        #expect(spec.executable == "/bin/zsh")
        #expect(spec.arguments == ["-ilc", LoginShell.script])
        #expect(spec.timeout == 5)
        #expect(spec.directory == "/h")
    }

    @Test func captureRunsTheShellOnceAndReadsItsAnswer() async {
        let dir = TempDir("cb-shell")
        // A stand-in login shell: profile noise, a PATH and a config dir of its own, then the command.
        let shell = dir.write("fake-shell", """
        #!/bin/sh
        echo "profile noise"
        PATH=/fake/bin:/usr/bin:/bin; export PATH
        CLAUDE_CONFIG_DIR=/Users/example/.claude-alt; export CLAUDE_CONFIG_DIR
        eval "$2"
        """, executable: true).path
        let env = await LoginShell.capture(runner: ProcessRunner(), shell: shell, environment: ["PATH": "/usr/bin:/bin"], home: dir.url.path)
        #expect(env == LoginEnvironment(claudePath: nil, path: "/fake/bin:/usr/bin:/bin", claudeConfigDir: "/Users/example/.claude-alt"))
    }

    @Test func aHangingShellGivesUpAfterTheTimeout() async {
        let dir = TempDir("cb-shell")
        let shell = dir.write("slow-shell", "#!/bin/sh\nexec /bin/sleep 30\n", executable: true).path
        let start = ContinuousClock.now
        let env = await LoginShell.capture(runner: ProcessRunner(), shell: shell, environment: [:], home: dir.url.path, timeout: 0.3)
        #expect(env == nil)
        #expect(ContinuousClock.now - start < .seconds(4))
    }

    @Test func theShellIsSHELLThenTheAccountsShell() {
        #expect(LoginShell.shell(environment: ["SHELL": "/bin/bash"]) == "/bin/bash")
        #expect(LoginShell.shell(environment: [:]).hasPrefix("/"))
    }
}
