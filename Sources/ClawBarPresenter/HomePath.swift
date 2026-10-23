import Foundation

/// Paths under the home folder as `~/…`, as the sessions and projects tooltips show them.
enum HomePath {
    static func relative(_ path: String, home: String) -> String {
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard home.count > 1 else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
