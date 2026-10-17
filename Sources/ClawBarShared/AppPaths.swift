import Foundation

/// Where ClawBar keeps its own files. Tests pass a temporary root; `CLAWBAR_HOME` overrides the live one.
public struct AppPaths: Sendable, Equatable {
    public let root: URL
    public let configFile: URL
    /// Small persisted state, such as the per-CLI-version probe latch.
    public let stateFile: URL
    public let errorLog: URL
    public let lockFile: URL
    /// Output of a headless `claude update`, written to a file so the update survives quitting.
    public let updateLog: URL

    public init(root: URL) {
        self.root = root
        configFile = root.appendingPathComponent("config.json")
        stateFile = root.appendingPathComponent("state.json")
        errorLog = root.appendingPathComponent("error.log")
        lockFile = root.appendingPathComponent("clawbar.lock")
        updateLog = root.appendingPathComponent("update.log")
    }

    /// `$CLAWBAR_HOME`, else `~/Library/Application Support/ClawBar`. Nothing is created here.
    public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppPaths {
        if let home = environment["CLAWBAR_HOME"], !home.isEmpty {
            return AppPaths(root: URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return AppPaths(root: support.appendingPathComponent("ClawBar", isDirectory: true))
    }

    /// The root with symlinks resolved, so /tmp/x and /private/tmp/x, which share one lock file, are one root.
    public var canonicalRoot: String { Self.canonical(root) }

    /// Whether this is the root ClawBar uses without `CLAWBAR_HOME`, however it is spelled.
    public func isDefault(defaultRoot: URL = AppPaths.live(environment: [:]).root) -> Bool {
        canonicalRoot == Self.canonical(defaultRoot)
    }

    /// realpath of the deepest folder that exists plus the rest, so a root not created yet compares too.
    static func canonical(_ url: URL) -> String {
        var head = url.standardizedFileURL
        var rest: [String] = []
        while true {
            if let real = realpath(head.path, nil) {
                defer { free(real) }
                return rest.reversed().reduce(String(cString: real)) { ($0 as NSString).appendingPathComponent($1) }
            }
            guard head.path != "/" else { return url.standardizedFileURL.path }
            rest.append(head.lastPathComponent)
            head = head.deletingLastPathComponent()
        }
    }
}

public enum AppInfo {
    public static let name = "ClawBar"
    public static let version = "0.1.1"
    public static let bundleID = "dev.vr1e.clawbar"
    /// The release of clawd-usage-winwidget this is a port of.
    public static let originalVersion = "1.3.0"
    public static let originalRepo = URL(string: "https://github.com/Enhed/clawd-usage-winwidget")!
    /// No contact URL until ClawBar has a public home: the original's would send complaints about ClawBar to Enhed.
    public static let userAgent = "\(name)/\(version)"
    public static let statusPage = URL(string: "https://status.claude.com")!
    public static let statusSummary = URL(string: "https://status.claude.com/api/v2/summary.json")!
    public static let changelogPage = URL(string: "https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md")!
    public static let changelogRaw = URL(string: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md")!
    public static let releasesBase = URL(string: "https://downloads.claude.ai/claude-code-releases")!
    /// "ClawBar v0.1.0": the menu header and the details line.
    public static var title: String { "\(name) v\(version)" }
}
