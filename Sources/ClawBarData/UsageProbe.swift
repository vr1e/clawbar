import Foundation
import ClawBarShared

/// `claude -p /usage` in safe mode, read through the JSON envelope and the zero-token guard.
enum UsageProbe {
    static let arguments = ["-p", "/usage", "--no-session-persistence", "--output-format", "json"]

    enum Outcome: Sendable, Hashable {
        case usage(UsageSnapshot)
        case issue(UsageIssue)
    }

    struct Report: Sendable {
        var outcome: Outcome
        /// For diagnostics: the guard fields as the CLI reported them.
        var envelope: UsageEnvelope?
        /// With `.noLimits`: the stats the answer still carried.
        var stats: UsageSnapshot?
    }

    static func spec(claude: String, environment: [String: String], home: String) -> ProcessSpec {
        var env = environment
        // The variable form: a CLI that does not know the setting ignores it instead of rejecting a flag.
        env["CLAUDE_CODE_SAFE_MODE"] = "1"
        return ProcessSpec(executable: claude, arguments: arguments, environment: env, directory: home, timeout: 60)
    }

    static func interpret(_ result: ProcessResult, now: Date, timeZone: TimeZone) -> Report {
        let outcome: ProcessOutcome
        switch result {
        case .failure(.notFound):
            return Report(outcome: .issue(.claudeNotFound))
        case .failure(let e):
            return Report(outcome: .issue(.launchFailed(e.message)))
        case .success(let o):
            outcome = o
        }
        if outcome.timedOut { return Report(outcome: .issue(.timedOut)) }
        // The guard comes before the exit code: a run that spent and then failed must latch, not retry.
        let envelope = UsageEnvelope(data: outcome.stdout)
        if let env = envelope, !env.spentNothing {
            return Report(
                outcome: .issue(.modelReached(turns: env.numTurns, costUSD: env.costUSD, tokens: env.tokens)), envelope: env
            )
        }
        guard outcome.exitCode == 0 else {
            let said = outcome.stderrText + "\n" + outcome.stdoutText
            if let option = rejectedOption(said) { return Report(outcome: .issue(.flagRejected(option))) }
            let code = outcome.exitCode.map { "exit \($0)" } ?? "signal"
            return Report(outcome: .issue(.probeFailed("\(code): \(tail(outcome.stderrText))")))
        }
        guard let env = envelope else {
            return Report(outcome: .issue(.probeFailed("unreadable output: \(tail(outcome.stdoutText))")))
        }
        guard !env.isError, let text = env.result else {
            return Report(outcome: .issue(.probeFailed("error result: \(tail(env.result ?? ""))")), envelope: env)
        }
        switch UsageParser.parse(text, now: now, timeZone: timeZone) {
        case .usage(let u): return Report(outcome: .usage(u), envelope: env)
        case .noLimits(let stats): return Report(outcome: .issue(.noLimits), envelope: env, stats: stats)
        // Fixed text: the answer's stats change every minute, and the error log dedups identical messages only.
        case .unavailable: return Report(outcome: .issue(.probeFailed("no limit lines in /usage")), envelope: env)
        }
    }

    /// The option a non-zero exit complains about, e.g. `--no-session-persistence`.
    static func rejectedOption(_ text: String) -> String? {
        if let m = Rx.first(unknownOption, in: text), let o = m[1] { return o }
        if let m = Rx.first(invalidArgument, in: text), let o = m[1], let v = m[2] { return "\(o) \(v)" }
        return nil
    }

    private static func tail(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 300 ? "…" + String(t.suffix(300)) : t
    }

    private static let unknownOption = Rx.make(#"(?i)unknown option:?\s+['"‘“]?(-{1,2}[A-Za-z0-9][\w-]*)"#)
    private static let invalidArgument = Rx.make(#"(?i)option\s+'(-{1,2}[\w-]+)[^']*'\s+argument\s+'([^']*)'\s+is invalid"#)
}
