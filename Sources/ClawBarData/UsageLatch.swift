import Foundation
import ClawBarShared

/// A latched usage issue and the CLI version it was seen with; a different version re-arms the probe.
struct UsageLatch: Sendable, Hashable {
    var version: String
    var issue: UsageIssue

    /// nil for issues that do not latch.
    init?(version: String, issue: UsageIssue) {
        guard issue.isLatched else { return nil }
        self.version = version
        self.issue = issue
    }

    func holds(forVersion v: String) -> Bool { v == version }
}

/// The latch in state.json, written patch-style so other keys survive.
struct LatchStore: Sendable {
    let url: URL
    static let key = "usageLatch"

    func load() -> UsageLatch? {
        guard let j = JSONFile.object(at: url)?[Self.key] as? [String: Any],
              let version = j["cliVersion"] as? String, !version.isEmpty
        else { return nil }
        switch j["issue"] as? String {
        case "flagRejected":
            return UsageLatch(version: version, issue: .flagRejected(j["option"] as? String ?? ""))
        case "modelReached":
            let turns = (j["turns"] as? NSNumber)?.intValue ?? 0
            let cost = (j["costUSD"] as? NSNumber)?.doubleValue ?? 0
            let tokens = (j["tokens"] as? NSNumber)?.intValue ?? 0
            return UsageLatch(version: version, issue: .modelReached(turns: turns, costUSD: cost, tokens: tokens))
        default:
            return nil
        }
    }

    /// nil clears the latch.
    func save(_ latch: UsageLatch?) throws {
        var j = JSONFile.object(at: url) ?? [:]
        if let latch {
            var entry: [String: Any] = ["cliVersion": latch.version]
            switch latch.issue {
            case .flagRejected(let option):
                entry["issue"] = "flagRejected"
                entry["option"] = option
            case .modelReached(let turns, let cost, let tokens):
                entry["issue"] = "modelReached"
                entry["turns"] = turns
                entry["costUSD"] = cost
                entry["tokens"] = tokens
            default:
                return
            }
            j[Self.key] = entry
        } else {
            guard j[Self.key] != nil else { return }
            j.removeValue(forKey: Self.key)
        }
        try JSONFile.write(j, to: url)
    }
}
