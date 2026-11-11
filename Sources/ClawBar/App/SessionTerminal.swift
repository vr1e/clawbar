import AppKit
import ClawBarShared

/// Reaching a session in its terminal. Only Ghostty can be told to open a tab in a folder with a command typed in, or
/// to bring forward the tab a pid runs in; macOS has no default terminal to ask instead.
enum SessionTerminal {
    static let ghosttyBundleID = "com.mitchellh.ghostty"

    static var ghosttyInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: ghosttyBundleID) != nil
    }

    /// `claude -r <id>`; nil unless the id is a UUID, since the line is typed into a shell.
    nonisolated static func resumeCommand(sessionId: String) -> String? {
        RecentSession.isSessionId(sessionId) ? "claude -r \(sessionId)" : nil
    }

    /// The command with its folder, for the clipboard: `cd '<cwd>' && claude -r <id>`.
    nonisolated static func shellLine(cwd: String, command: String) -> String {
        let folder = typeable(cwd)
        return folder.isEmpty ? command : "cd '\(folder.replacingOccurrences(of: "'", with: #"'\''"#))' && \(command)"
    }

    /// osascript's arguments for a new Ghostty tab in `cwd` with `command` typed into its shell, so the user's own
    /// PATH finds claude and the tab outlives it. The folder and the command are arguments, never script text.
    nonisolated static func newTab(cwd: String, command: String) -> [String] {
        ["-e", newTabScript, typeable(cwd), command]
    }

    /// osascript's arguments for bringing forward the Ghostty tab whose foreground process is `pid`.
    nonisolated static func focus(pid: Int32) -> [String] {
        ["-e", focusScript, String(pid)]
    }

    /// Runs osascript off the main thread; `completion` hears whether it exited cleanly.
    static func run(_ arguments: [String], completion: @escaping @MainActor (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let ok = finished.terminationStatus == 0
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(ok) } }
        }
        do {
            try process.run()
        } catch {
            completion(false)
        }
    }

    /// A folder that is no absolute path, or has a control character, cannot be typed or passed on safely (osascript
    /// would read a leading `-` as an option): it counts as unknown.
    private nonisolated static func typeable(_ cwd: String) -> String {
        cwd.hasPrefix("/") && !cwd.unicodeScalars.contains { $0.properties.generalCategory == .control } ? cwd : ""
    }

    private nonisolated static let newTabScript = """
    on run argv
        tell application "Ghostty"
            activate
            set cfg to new surface configuration
            if (item 1 of argv) is not "" then set initial working directory of cfg to (item 1 of argv)
            set initial input of cfg to (item 2 of argv) & linefeed
            if (count of windows) > 0 then
                new tab in front window with configuration cfg
            else
                new window with configuration cfg
            end if
        end tell
    end run
    """

    private nonisolated static let focusScript = """
    on run argv
        tell application "Ghostty"
            focus (first terminal whose pid is ((item 1 of argv) as integer))
            activate
        end tell
    end run
    """
}
