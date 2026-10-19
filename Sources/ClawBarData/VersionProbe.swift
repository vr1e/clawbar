import Foundation
import ClawBarShared

/// `claude --version` and the release channel's latest version.
enum VersionProbe {
    static func spec(claude: String, environment: [String: String], home: String) -> ProcessSpec {
        ProcessSpec(executable: claude, arguments: ["--version"], environment: environment, directory: home, timeout: 60)
    }

    /// "2.1.302 (Claude Code)" → "2.1.302".
    static func local(_ result: ProcessResult) -> String? {
        guard case .success(let o) = result, !o.timedOut else { return nil }
        return Rx.first(dottedTriple, in: o.stdoutText)?[1]
    }

    /// `autoUpdatesChannel` from settings.json when it is stable or latest, else latest.
    static func channel(settings: Data?) -> String {
        let v = settings.flatMap(JSONFile.object(from:)).flatMap { Lenient.string($0["autoUpdatesChannel"]) }?
            .trimmingCharacters(in: .whitespaces).lowercased()
        return v == "stable" ? "stable" : "latest"
    }

    static func latestURL(channel: String) -> URL { AppInfo.releasesBase.appendingPathComponent(channel) }

    static func latest(_ body: String) -> String? { Rx.first(leadingTriple, in: body)?[1] }

    private static let dottedTriple = Rx.make(#"(\d+\.\d+\.\d+)"#)
    private static let leadingTriple = Rx.make(#"^\s*(\d+\.\d+\.\d+)"#)
}

/// The CHANGELOG.md items between two versions.
enum ChangelogSlicer {
    /// `(from, to]`, in file order (newest first), every item kept, backticks removed.
    static func slice(_ text: String, after from: String, upTo to: String) -> [String] {
        var items: [String] = []
        for chunk in sections(text) {
            guard let v = Rx.first(version, in: chunk)?[1],
                  VersionState.isNewer(v, than: from), !VersionState.isNewer(v, than: to)
            else { continue }
            for line in chunk.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
                if let item = Rx.first(bullet, in: String(line))?[1] {
                    items.append(item.replacingOccurrences(of: "`", with: ""))
                }
            }
        }
        return items
    }

    /// The text split before each `## ` heading, the heading marker removed.
    private static func sections(_ text: String) -> [String] {
        var out: [String] = []
        var start = text.startIndex
        for m in heading.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            out.append(String(text[start ..< r.lowerBound]))
            start = r.upperBound
        }
        out.append(String(text[start...]))
        return out
    }

    private static let heading = Rx.make(#"(?m)^## "#)
    private static let version = Rx.make(#"^(\d+\.\d+\.\d+)"#)
    private static let bullet = Rx.make(#"^\s*[-*]\s+(.+)$"#)
}

/// A headless `claude update` whose output goes to a file, so it outlives ClawBar.
enum UpdateRunner {
    /// 15 minutes, a stated deviation: the original's console had no limit.
    static let timeout: TimeInterval = 900
    static let tailLines = 12

    static func spec(claude: String, environment: [String: String], home: String, log: URL) -> ProcessSpec {
        ProcessSpec(
            executable: claude, arguments: ["update"], environment: environment, directory: home,
            timeout: timeout, output: .survivesQuit(log)
        )
    }

    /// nil for a clean exit; otherwise the exit code (nil on timeout) and `tail`, the log's last lines, or the launch
    /// error.
    static func failure(_ result: ProcessResult, tail: String, home: String = NSHomeDirectory()) -> UpdateFailure? {
        switch result {
        case .failure(let e):
            let code: Int32 = if case .notFound = e { 127 } else { 126 }
            return UpdateFailure(exitCode: code, outputTail: Redact.text(e.message, home: home))
        case .success(let o):
            let code: Int32?
            if o.timedOut {
                code = nil
            } else {
                switch o.termination {
                case .exit(0): return nil
                case .exit(let c): code = c
                case .signal(let s): code = 128 + s
                }
            }
            return UpdateFailure(exitCode: code, outputTail: tail)
        }
    }

    /// The last lines a person would have seen: progress redraws resolved, colours and blanks dropped.
    static func tail(of log: URL, home: String) -> String {
        guard let h = try? FileHandle(forReadingFrom: log) else { return "" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 16384 ? size - 16384 : 0)
        let text = String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw -> String? in
            let shown = raw.split(separator: "\r", omittingEmptySubsequences: false).last.map(String.init) ?? ""
            let line = UsageParser.clean(shown).trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : line
        }
        return Redact.text(lines.suffix(tailLines).joined(separator: "\n"), home: home)
    }

    /// Homebrew and npm installs may refuse to self-update; judged by where the executable really lives.
    static func installHint(claudePath: String) -> InstallHint? {
        var places = [claudePath]
        if let real = realpath(claudePath, nil) {
            places.append(String(cString: real))
            free(real)
        }
        if places.contains(where: { $0.contains("/node_modules/") }) { return .npm }
        if places.contains(where: { $0.contains("/Caskroom/") || $0.contains("/Cellar/") || $0.hasPrefix("/opt/homebrew/") }) {
            return .homebrew
        }
        return nil
    }
}
