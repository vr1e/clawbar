import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

/// The scanner against real files in a temporary config dir; reply times are relative to the clock, as file times are.
@Suite struct TranscriptScannerTests {
    let dir = TempDir("cb-ts")
    let now = Date()
    var root: String { dir.url.appendingPathComponent("projects").path }

    /// Opus 5.5 output at $20 per million: `n` thousand tokens weigh n × 2 cents.
    func line(_ id: String, _ thousands: Int, cwd: String = "/Users/example/api", ago: TimeInterval = 600) -> String {
        assistantLine(id, at: now - ago, cwd: cwd, output: thousands * 1000) + "\n"
    }

    @discardableResult
    func write(_ relative: String, _ text: String) -> URL { dir.write("projects/" + relative, text) }

    func append(_ url: URL, _ text: String) throws {
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        try h.close()
    }

    @Test func subagentTranscriptsCountWithTheirProject() async {
        write("-Users-example-api/s1.jsonl", line("msg_1", 1) + #"{"type":"user","cwd":"/Users/example/api"}"# + "\n")
        write("-Users-example-api/s1/subagents/agent-a1.jsonl", line("msg_2", 2))
        write("-Users-example-api/s1/subagents/workflows/wf_1/agent-b.jsonl", line("msg_3", 3))
        // Not a transcript, and not in a project folder.
        write("-Users-example-api/s1/notes.txt", line("msg_4", 4))
        write("stray.jsonl", line("msg_5", 5))
        let scan = await TranscriptScanner().scan(root: root, now: now)
        #expect(weights(scan.usage) == ["/Users/example/api": 0.12])
        #expect(scan.files == 3 && scan.unreadable == 0)
    }

    @Test func aLineStillBeingWrittenIsReadOnTheNextPass() async throws {
        let url = write("-Users-example-api/s1.jsonl", line("msg_1", 1) + line("msg_2", 2).dropLast())
        let scanner = TranscriptScanner()
        #expect(weights(await scanner.scan(root: root, now: now).usage) == ["/Users/example/api": 0.02])
        try append(url, "\n" + line("msg_3", 4))
        #expect(weights(await scanner.scan(root: root, now: now).usage) == ["/Users/example/api": 0.14])
        // Nothing new: nothing changes.
        #expect(weights(await scanner.scan(root: root, now: now).usage) == ["/Users/example/api": 0.14])
    }

    @Test func aReplacedOrTruncatedFileIsReadAgainWithoutCountingTwice() async throws {
        let url = write("-Users-example-api/s1.jsonl", line("msg_1", 1) + line("msg_2", 2))
        let scanner = TranscriptScanner()
        #expect(weights(await scanner.scan(root: root, now: now).usage) == ["/Users/example/api": 0.06])
        // Written anew: msg_1 again with its final count, and a new reply.
        try Data((line("msg_1", 3) + line("msg_9", 1)).utf8).write(to: url, options: .atomic)
        #expect(weights(await scanner.scan(root: root, now: now).usage) == ["/Users/example/api": 0.12])
        // Cut short in place.
        let h = try FileHandle(forWritingTo: url)
        try h.truncate(atOffset: 0)
        try h.write(contentsOf: Data(line("msg_1", 3).utf8))
        try h.close()
        #expect(weights(await scanner.scan(root: root, now: now).usage) == ["/Users/example/api": 0.12])
    }

    @Test func aTranscriptUntouchedForAWeekIsSkippedAndRepliesBeforeTheWeekAreLeftOut() async throws {
        let old = write("-Users-example-old/s1.jsonl", line("msg_1", 1, cwd: "/Users/example/old"))
        try FileManager.default.setAttributes([.modificationDate: now - 8 * 86400], ofItemAtPath: old.path)
        write("-Users-example-api/s1.jsonl", line("msg_2", 1, ago: 7 * 86400 + 3600) + line("msg_3", 2))
        let scan = await TranscriptScanner().scan(root: root, now: now)
        #expect(weights(scan.usage) == ["/Users/example/api": 0.04])
        #expect(scan.files == 1)
    }

    @Test func anotherConfigDirStartsOver() async {
        write("-Users-example-api/s1.jsonl", line("msg_1", 1))
        dir.write("alt/projects/-Users-example-web/s1.jsonl", line("msg_2", 2, cwd: "/Users/example/web"))
        let scanner = TranscriptScanner()
        #expect(weights(await scanner.scan(root: root, now: now).usage) == ["/Users/example/api": 0.02])
        let alt = dir.url.appendingPathComponent("alt/projects").path
        #expect(weights(await scanner.scan(root: alt, now: now).usage) == ["/Users/example/web": 0.04])
    }

    @Test func anUnreadableTranscriptIsCountedAndAMissingRootIsAnEmptyWeek() async throws {
        let url = write("-Users-example-api/s1.jsonl", line("msg_1", 1))
        write("-Users-example-api/s2.jsonl", line("msg_2", 2))
        chmod(url.path, 0)
        defer { chmod(url.path, 0o644) }
        let scan = await TranscriptScanner().scan(root: root, now: now)
        #expect(scan.unreadable == 1 && weights(scan.usage) == ["/Users/example/api": 0.04])
        let none = await TranscriptScanner().scan(root: dir.url.appendingPathComponent("nowhere").path, now: now)
        #expect(none == ProjectScan())
    }
}
