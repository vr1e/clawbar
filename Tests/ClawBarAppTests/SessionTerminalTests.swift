import Foundation
import Testing
@testable import ClawBar
import ClawBarShared

/// What is typed into a terminal or put on the clipboard for a recent session; osascript itself never runs here.
@Suite struct SessionTerminalTests {
    let id = "00000000-0000-4000-8000-000000000003"
    var command: String { "claude -r \(id)" }

    @Test func onlyASessionIdBecomesACommand() {
        #expect(SessionTerminal.resumeCommand(sessionId: id) == "claude -r \(id)")
        #expect(SessionTerminal.resumeCommand(sessionId: id.uppercased()) == "claude -r \(id.uppercased())")
        for bad in ["", "abc", id + "; rm -rf ~", id + "\n", " " + id, "$(touch x)", String(id.dropLast())] {
            #expect(SessionTerminal.resumeCommand(sessionId: bad) == nil, "\(bad)")
        }
    }

    @Test func theClipboardLineQuotesTheFolder() {
        #expect(SessionTerminal.shellLine(cwd: "/Users/example/code/api", command: command) == "cd '/Users/example/code/api' && claude -r \(id)")
        #expect(SessionTerminal.shellLine(cwd: "/Users/example/it's $HOME; here", command: command)
            == #"cd '/Users/example/it'\''s $HOME; here' && claude -r "# + id)
        // No folder known, or one that cannot be typed: the command alone.
        #expect(SessionTerminal.shellLine(cwd: "", command: command) == "claude -r \(id)")
        #expect(SessionTerminal.shellLine(cwd: "/Users/example/a\nb", command: command) == "claude -r \(id)")
        #expect(SessionTerminal.shellLine(cwd: "-i", command: command) == "claude -r \(id)")
    }

    @Test func theFolderAndTheCommandReachGhosttyAsArgumentsNotAsScript() {
        let cwd = #"/Users/example/a "quoted" \ folder"#
        let args = SessionTerminal.newTab(cwd: cwd, command: "claude -r \(id)")
        #expect(args.count == 4 && args[0] == "-e")
        #expect(Array(args[2...]) == [cwd, "claude -r \(id)"])
        #expect(!args[1].contains("example") && !args[1].contains(id))
        #expect(args[1].contains(#"tell application "Ghostty""#) && args[1].contains("initial input"))
        // Neither a control character nor a would-be osascript option gets through as the folder.
        #expect(SessionTerminal.newTab(cwd: "/tmp/a\u{07}b", command: "x")[2].isEmpty)
        #expect(SessionTerminal.newTab(cwd: "-i", command: "x")[2].isEmpty)
        let focus = SessionTerminal.focus(pid: 4242)
        #expect(focus.count == 3 && focus[0] == "-e" && focus[2] == "4242")
        #expect(focus[1].contains("focus (first terminal whose pid is"))
    }

    /// osascript on scripts that reach no app: the completion hears the exit on the main actor.
    @Test func theCompletionHearsWhetherOsascriptExitedCleanly() async {
        func ran(_ script: String) async -> Bool {
            await withCheckedContinuation { done in
                SessionTerminal.run(["-e", script]) { ok in
                    MainActor.assertIsolated()
                    done.resume(returning: ok)
                }
            }
        }
        #expect(await ran("on run argv\nreturn 1\nend run"))
        #expect(await ran("error number -1743") == false)
    }
}
