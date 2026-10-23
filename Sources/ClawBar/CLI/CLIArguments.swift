import Foundation
import ClawBarShared

/// What one launch of the executable does.
enum CLIMode: Equatable {
    /// The menu bar app itself.
    case run
    case version
    case diagnose
    case snapshot(dir: String)
    case record(RecordScenario, gif: String)
    case dumpState
    case command(RemoteCommand)
    case makeIcon(dir: String)
}

/// What `--command` asks the running instance to do.
enum RemoteCommand: Equatable, Sendable {
    case toggle, show, larger, smaller, refresh, quit
    case lang(Lang)

    /// The string sent in the distributed notification.
    var wire: String {
        switch self {
        case .toggle: "toggle"
        case .show: "show"
        case .larger: "larger"
        case .smaller: "smaller"
        case .refresh: "refresh"
        case .quit: "quit"
        case .lang(let l): "lang:\(l.rawValue)"
        }
    }

    init?(wire: String) {
        switch wire {
        case "toggle": self = .toggle
        case "show": self = .show
        case "larger": self = .larger
        case "smaller": self = .smaller
        case "refresh": self = .refresh
        case "quit": self = .quit
        default:
            guard wire.hasPrefix("lang:"), let l = Lang(rawValue: String(wire.dropFirst(5))) else { return nil }
            self = .lang(l)
        }
    }
}

struct CLIError: Error, Equatable {
    let message: String
}

enum CLI {
    static let usage = """
        usage: ClawBar [mode]
          (no mode)                     run the menu bar app
          --version                     print the version
          --diagnose                    run every probe once and print what it found
          --snapshot <dir>              render the widget, the menu bar item and the menus into <dir>
          --record <scenario> <gif>     record a scenario: \(RecordScenario.allCases.map(\.rawValue).joined(separator: ", "))
          --dump-state                  print the running instance's state
          --command <cmd>               toggle | show | larger | smaller | refresh | quit | lang <en|de>
          --make-icon <dir>             write AppIcon.iconset into <dir>
        """

    /// `args` excludes the executable path.
    static func parse(_ args: [String]) -> Result<CLIMode, CLIError> {
        // LaunchServices and Xcode pass AppKit defaults (-psn_…, -NSKey value); they mean a normal launch.
        guard let first = args.first, first.hasPrefix("--") else { return .success(.run) }
        let rest = Array(args.dropFirst())
        func exactly(_ n: Int) -> CLIError? {
            rest.count == n ? nil : CLIError(message: "\(first) takes \(n == 0 ? "no" : "\(n)") argument\(n == 1 ? "" : "s")")
        }
        switch first {
        case "--version":
            if let e = exactly(0) { return .failure(e) }
            return .success(.version)
        case "--diagnose":
            if let e = exactly(0) { return .failure(e) }
            return .success(.diagnose)
        case "--dump-state":
            if let e = exactly(0) { return .failure(e) }
            return .success(.dumpState)
        case "--snapshot":
            if let e = exactly(1) { return .failure(e) }
            return .success(.snapshot(dir: rest[0]))
        case "--make-icon":
            if let e = exactly(1) { return .failure(e) }
            return .success(.makeIcon(dir: rest[0]))
        case "--record":
            if let e = exactly(2) { return .failure(e) }
            guard let s = RecordScenario(rawValue: rest[0]) else {
                return .failure(CLIError(message: "unknown scenario \(rest[0])"))
            }
            return .success(.record(s, gif: rest[1]))
        case "--command":
            return parseCommand(rest).map { .command($0) }
        default:
            return .failure(CLIError(message: "unknown option \(first)"))
        }
    }

    private static func parseCommand(_ rest: [String]) -> Result<RemoteCommand, CLIError> {
        guard let name = rest.first else { return .failure(CLIError(message: "--command needs a command")) }
        if name == "lang" {
            guard rest.count == 2 else { return .failure(CLIError(message: "--command lang needs a language code")) }
            guard let lang = Lang(rawValue: rest[1].lowercased()) else {
                return .failure(CLIError(message: "unknown language \(rest[1])"))
            }
            return .success(.lang(lang))
        }
        guard rest.count == 1, let c = RemoteCommand(wire: name) else {
            return .failure(CLIError(message: "unknown command \(rest.joined(separator: " "))"))
        }
        return .success(c)
    }
}
