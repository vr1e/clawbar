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
