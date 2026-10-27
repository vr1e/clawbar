import Foundation
import ClawBarShared
@testable import ClawBarData

/// Fixture files live next to the tests; the target excludes them from compilation.
enum Fixture {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func data(_ name: String) -> Data {
        (try? Data(contentsOf: root.appendingPathComponent(name))) ?? Data()
    }

    static func text(_ name: String) -> String { String(decoding: data(name), as: UTF8.self) }
}

/// The usage probe's today.json envelope with some fields replaced.
func todayEnvelope(_ edit: (inout [String: Any]) -> Void) -> Data {
    var j = (try? JSONSerialization.jsonObject(with: Fixture.data("usage/today.json"))) as? [String: Any] ?? [:]
    edit(&j)
    return (try? JSONSerialization.data(withJSONObject: j)) ?? Data()
}

func utc(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso)!
}

let berlin = TimeZone(identifier: "Europe/Berlin")!

/// A fresh folder per test, removed when the returned object is released.
final class TempDir: @unchecked Sendable {
    let url: URL

    init(_ label: String = "cb") {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    var paths: AppPaths { AppPaths(root: url.appendingPathComponent("app", isDirectory: true)) }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    @discardableResult
    func write(_ name: String, _ text: String, executable: Bool = false) -> URL {
        let u = file(name)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: u)
        if executable { chmod(u.path, 0o755) }
        return u
    }
}

/// Polls `condition` until it holds or the deadline passes.
@MainActor
func eventually(_ timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

/// Lets queued main-actor work and fake completions run.
@MainActor
func settle(_ time: Duration = .milliseconds(60)) async {
    try? await Task.sleep(for: time)
}

/// One assistant line as Claude Code writes it, with the fields the scanner reads and a stand-in for what was said.
func assistantLine(
    _ id: String, at date: Date, cwd: String = "/Users/example/api", model: String = "claude-opus-5-5", input: Int = 0,
    writes5m: Int = 0, writes1h: Int = 0, reads: Int = 0, output: Int = 0, speed: String? = "standard", text: String = "…"
) -> String {
    var usage: [String: Any] = [
        "input_tokens": input, "cache_creation_input_tokens": writes5m + writes1h, "cache_read_input_tokens": reads,
        "output_tokens": output, "cache_creation": ["ephemeral_5m_input_tokens": writes5m, "ephemeral_1h_input_tokens": writes1h],
    ]
    if let speed { usage["speed"] = speed }
    let line: [String: Any] = [
        "type": "assistant", "cwd": cwd, "timestamp": Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date),
        "requestId": "req_" + id, "isSidechain": false,
        "message": ["id": id, "model": model, "role": "assistant", "content": [["type": "text", "text": text]], "usage": usage],
    ]
    let data = (try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

/// Each project's weight in millionths of a dollar, keyed by its path.
func weights(_ usage: ProjectUsage) -> [String: Double] {
    Dictionary(uniqueKeysWithValues: usage.projects.map { ($0.path, micro($0.weight)) })
}

/// Each project's weight per quarter hour in millionths of a dollar, keyed by its path.
func quarters(_ usage: ProjectUsage) -> [String: [Int: Double]] {
    Dictionary(uniqueKeysWithValues: usage.projects.map { ($0.path, $0.quarters.mapValues(micro)) })
}

private func micro(_ dollars: Double) -> Double { (dollars * 1e6).rounded() / 1e6 }

/// The data side over fakes: a fake claude on disk (never run), a fake runner, fake HTTP and a clock stopped at t0.
/// The recipes, the controller and `--diagnose` all take `deps` from it.
@MainActor
final class Harness {
    static let t0 = utc("2026-10-16T22:30:00Z")
    let dir = TempDir("cb-dc")
    let runner = FakeRunner()
    let http = FakeHTTP()
    let spy = ReadSpy()
    var table = FakeTable(starts: [:])
    var shell: LoginEnvironment?
    var config = Config()
    /// Added to the environment the controller inherits.
    var extraEnvironment: [String: String] = [:]

    var home: String { dir.url.appendingPathComponent("home").path }
    var paths: AppPaths { dir.paths }

    init(claude: Bool = true) {
        config.showSky = false
        if claude { config.claudePath = installClaude("tools/claude") }
        runner.reply(.version, stdout: "2.1.302 (Claude Code)\n")
        // No configDirectory: the auth probe's outranks the shell's, so one would move the sessions mid-test.
        runner.reply(.account, stdout: #"{"loggedIn": true, "subscriptionType": "team", "email": "user@example.com"}"#)
        http.answer("status.claude.com", Fixture.data("status/ok.json"))
        http.answer("downloads.claude.ai", Data("2.1.302\n".utf8))
    }

    func installClaude(_ relative: String) -> String {
        dir.write("home/\(relative)", "#!/bin/sh\nexit 0\n", executable: true).path
    }

    var deps: CommandRecipes.Dependencies {
        let shell = shell, t0 = Harness.t0
        return CommandRecipes.Dependencies(
            runner: runner, http: http, clock: { t0 }, timeZone: berlin,
            environment: ["HOME": home, "PATH": "/usr/bin:/bin", "CLAUDECODE": "1"].merging(extraEnvironment) { $1 }, home: home,
            table: table, readFile: spy.reader, loginShell: { _, _, _ in shell }, candidates: []
        )
    }

    func make() -> DataController { DataController(config: config, paths: paths, deps: deps) }

    func recipes() -> CommandRecipes { CommandRecipes(deps: deps, paths: paths) }

    /// The report `--diagnose` prints.
    func diagnose() async -> String { await Diagnostics.run(config: config, paths: paths, deps: deps).text }

    func session(_ pid: Int32, in configDir: String, status: String = "busy", _ extra: [String: Any] = [:]) {
        let j: [String: Any] = ["pid": pid, "sessionId": "s\(pid)", "cwd": "/Users/example/p\(pid)", "status": status, "kind": "interactive"]
            .merging(extra) { $1 }
        let url = URL(fileURLWithPath: configDir).appendingPathComponent("sessions/\(pid).json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: j).write(to: url)
    }
}
