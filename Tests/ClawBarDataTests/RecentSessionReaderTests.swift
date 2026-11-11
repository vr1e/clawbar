import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

/// The reader alone: a transcript's bytes in, what they say about the session out.
@Suite struct RecentSessionReaderTests {
    typealias L = TranscriptLine
    let now = utc("2026-10-16T22:30:00Z")
    var modified: Date { now - 5 }

    /// A whole transcript in memory, as the scanner reads one from disk.
    func reader(_ data: Data) -> RecentSessionReader {
        RecentSessionReader.read(size: data.count) { data.subdata(in: $0) }
    }

    func summary(_ data: Data) -> TranscriptSummary { reader(data).summary(sessionId: sessionID(1), modified: modified) }
    func summary(_ text: String) -> TranscriptSummary { summary(Data(text.utf8)) }
    func isSession(_ text: String) -> Bool { reader(Data(text.utf8)).isSession }

    /// Conversation lines of about `bytes` in all, the last one written at `now - 60`.
    func filler(_ bytes: Int, cwd: String = "/Users/example/api") -> String {
        let line = L.user(at: now - 120, cwd: cwd, text: String(repeating: "x", count: 900))
        return String(repeating: line, count: bytes / line.utf8.count + 1) + L.user(at: now - 60, cwd: cwd)
    }

    @Test func theLastTitleAndPromptOfTheFileAreCurrent() {
        let text = L.user(at: now - 900) + L.aiTitle("First guess") + L.lastPrompt("first prompt")
            + assistantLine("msg_1", at: now - 600) + "\n"
            + L.aiTitle("Sonos amp network connection") + L.lastPrompt("why is the amp offline?")
        let s = summary(text)
        #expect(s.aiTitle == "Sonos amp network connection" && s.customTitle == nil)
        #expect(s.lastPrompt == "why is the amp offline?")
        #expect(s.cwd == "/Users/example/api")
        #expect(s.lastActivity == now - 600)
        #expect(s.sessionId == sessionID(1) && isSession(text))
    }

    @Test func aRenameIsReadBesideTheSummaryAndFromTheFilesStart() {
        // `/rename`: Claude Code writes the custom title just before the summary it keeps appending.
        let renamed = summary(L.user(at: now) + L.customTitle("Amp") + L.aiTitle("Sonos amp network connection") + L.lastPrompt("p"))
        #expect(renamed.customTitle == "Amp" && renamed.aiTitle == "Sonos amp network connection")
        // `claude -n`: the name is the file's first line, far from a long conversation's end.
        let named = summary(L.customTitle("amp-debugging") + filler(200_000) + L.aiTitle("Sonos amp network connection") + L.lastPrompt("p"))
        #expect(named.customTitle == "amp-debugging" && named.aiTitle == "Sonos amp network connection")
        // A rename since then outranks it.
        let again = summary(L.customTitle("amp-debugging") + filler(200_000) + L.customTitle("Amp") + L.aiTitle("x") + L.lastPrompt("p"))
        #expect(again.customTitle == "Amp")
    }

    @Test func aCustomTitleSplitFromItsSummaryByAChunkEdgeIsStillRead() {
        // The summary and the prompt are the last step's first whole lines; the custom title ends 10 bytes into it.
        let titles = L.aiTitle("Summary") + L.lastPrompt("p")
        let room = RecentSessionReader.step - 10 - titles.utf8.count - L.user(at: now - 60, text: "").utf8.count
        let tail = titles + L.user(at: now - 60, text: String(repeating: "x", count: room))
        let data = Data((filler(4000) + L.customTitle("Mine") + tail).utf8)
        var reader = RecentSessionReader()
        reader.add(earlier: data.subdata(in: data.count - RecentSessionReader.step ..< data.count), atStart: false)
        // Title and prompt are read, but not the margin behind them: the read goes one step further.
        let first = reader.summary(sessionId: "s", modified: modified)
        #expect(tail.utf8.count == RecentSessionReader.step - 10)
        #expect(first.aiTitle == "Summary" && first.customTitle == nil && !reader.isComplete)
        #expect(summary(data).customTitle == "Mine")
    }

    @Test func aMissingPromptTitleOrTimeIsNoError() {
        let replyOnly = L.user(at: now - 30) + assistantLine("msg_1", at: now - 20) + "\n"
        let untitled = summary(replyOnly)
        #expect(untitled.aiTitle == nil && untitled.customTitle == nil && untitled.lastPrompt.isEmpty)
        #expect(isSession(replyOnly) && untitled.lastActivity == now - 20)
        // No line with a time: the file's own.
        let timeless = summary(L.aiTitle("Only a title"))
        #expect(timeless.lastActivity == modified && timeless.cwd == nil)
        #expect(isSession(L.aiTitle("Only a title")) && !isSession(""))
        #expect(summary("not json\n{\"type\":\"ai-title\"}\n[1,2]\n").aiTitle == nil)
    }

    @Test func aLineStillBeingWrittenIsLeftOut() {
        let whole = L.user(at: now - 60) + L.aiTitle("Kept") + L.lastPrompt("kept")
        let s = summary(whole + L.aiTitle("Half written").dropLast(12))
        #expect(s.aiTitle == "Kept" && s.lastPrompt == "kept" && s.lastActivity == now - 60)
    }

    @Test func aTitleFurtherBackThanOneStepTakesASecond() {
        let text = L.user(at: now - 900) + L.aiTitle("Far back") + L.lastPrompt("asked long ago") + filler(RecentSessionReader.step + 5000)
        let data = Data(text.utf8)
        var reader = RecentSessionReader()
        reader.add(earlier: data.subdata(in: data.count - RecentSessionReader.step ..< data.count), atStart: false)
        #expect(!reader.isComplete && reader.summary(sessionId: "s", modified: modified).aiTitle == nil)
        let s = summary(text)
        #expect(s.aiTitle == "Far back" && s.lastPrompt == "asked long ago" && s.lastActivity == now - 60)
    }

    @Test func aLongLineBeforeTheTitleDoesNotHoldTheReadOpen() {
        // A pasted image is one line of megabytes; the read does not follow it back to its start.
        let image = L.user(at: now - 900, text: String(repeating: "x", count: 3 * RecentSessionReader.step))
        let data = Data((image + L.aiTitle("After the image") + L.lastPrompt("p") + L.user(at: now - 60)).utf8)
        var tailReads = 0
        let reader = RecentSessionReader.read(size: data.count) { range in
            if range.lowerBound > 0 { tailReads += 1 }
            return data.subdata(in: range)
        }
        #expect(tailReads == 1 && reader.summary(sessionId: "s", modified: modified).aiTitle == "After the image")
    }

    @Test func pastTheCapTheSessionShowsWithoutItsTitle() {
        let text = L.user(at: now - 900, cwd: "/Users/example/launch") + L.aiTitle("Out of reach") + L.lastPrompt("p")
            + assistantLine("msg_1", at: now - 800) + "\n" + filler(RecentSessionReader.cap + 5000, cwd: "/Users/example/later")
        let s = summary(text)
        #expect(s.aiTitle == nil && s.lastPrompt.isEmpty)
        // The time comes from the end, the folder from the start, and the filler's lines are prompts, not replies.
        #expect(s.lastActivity == now - 60 && s.cwd == "/Users/example/launch")
        #expect(!isSession(text))
        #expect(isSession(text + assistantLine("msg_2", at: now - 10) + "\n"))
    }

    @Test func theFolderIsTheOneTheSessionWasStartedIn() {
        let s = summary(
            L.user(at: now - 900, cwd: "/Users/example/Dev") + L.user(at: now - 60, cwd: "/Users/example/Dev/clawbar")
                + L.aiTitle("t") + L.lastPrompt("p")
        )
        #expect(s.cwd == "/Users/example/Dev")
        // A first line too long for the head read: the last folder named stands in.
        let long = L.user(at: now - 900, cwd: "/Users/example/Dev", text: String(repeating: "y", count: RecentSessionReader.step + 100))
        #expect(summary(long + L.user(at: now - 60, cwd: "/Users/example/Dev/clawbar")).cwd == "/Users/example/Dev/clawbar")
    }

    @Test func aClearAloneOrAPrintModeRunIsNoSession() {
        // What `/clear` leaves: a command line, an empty last prompt, no reply.
        let cleared = L.user(at: now, text: "<command-name>/clear</command-name>") + L.lastPrompt("")
        #expect(summary(cleared).lastPrompt.isEmpty && !isSession(cleared))
        #expect(!isSession(L.user(at: now, entrypoint: "sdk-cli") + assistantLine("msg_1", at: now) + "\n" + L.aiTitle("t") + L.lastPrompt("p")))
        #expect(isSession(L.user(at: now, entrypoint: "claude-desktop") + L.aiTitle("t") + L.lastPrompt("p")))
    }

    @Test func thePromptIsOneLineCutShort() {
        let long = "fix   the\n\nlogin\ttest " + String(repeating: "word ", count: 100)
        let s = summary(L.lastPrompt(long) + L.aiTitle("  Spaced\n title "))
        #expect(s.lastPrompt.hasPrefix("fix the login test word word"))
        #expect(s.lastPrompt.count == RecentSessionReader.promptLimit + 1 && s.lastPrompt.hasSuffix("…"))
        #expect(s.aiTitle == "Spaced title")
        #expect(RecentSessionReader.clean("  \n ", limit: 10) == nil && RecentSessionReader.clean(12, limit: 10) == nil)
    }
}

/// The scanner against real files in a temporary config dir.
@Suite struct RecentSessionScannerTests {
    typealias L = TranscriptLine
    let dir = TempDir("cb-rs")
    let now = Date()
    var root: String { dir.url.appendingPathComponent("projects").path }

    @discardableResult
    func write(_ relative: String, _ text: String) -> URL { dir.write("projects/" + relative, text) }

    func session(_ title: String, prompt: String = "p", ago: TimeInterval = 600, entrypoint: String = "cli") -> String {
        L.user(at: now - ago, entrypoint: entrypoint) + L.aiTitle(title) + L.lastPrompt(prompt)
    }

    func titles(_ scan: RecentScan) -> [String: String] {
        Dictionary(uniqueKeysWithValues: scan.sessions.map { ($0.sessionId, $0.aiTitle ?? "") })
    }

    @Test func onlyAProjectFoldersOwnSessionTranscriptsCount() async {
        write("-Users-example-api/\(sessionID(1)).jsonl", session("Rate limiter"))
        write("-Users-example-web/\(sessionID(2)).jsonl", session("Login page"))
        // A subagent's transcript, a file not named by a session id, and one outside a project folder.
        write("-Users-example-api/\(sessionID(1))/subagents/agent-a1.jsonl", session("Subagent"))
        write("-Users-example-api/\(sessionID(1))/subagents/\(sessionID(7)).jsonl", session("Nested"))
        write("-Users-example-api/notes.jsonl", session("Notes"))
        write("\(sessionID(8)).jsonl", session("Stray"))
        // A print-mode run and a `/clear` alone.
        write("-Users-example-api/\(sessionID(3)).jsonl", session("Probe", entrypoint: "sdk-cli"))
        write("-Users-example-api/\(sessionID(4)).jsonl", L.user(at: now) + L.lastPrompt(""))
        let scan = await RecentSessionScanner().scan(root: root, now: now)
        #expect(titles(scan) == [sessionID(1): "Rate limiter", sessionID(2): "Login page"])
        #expect(scan.files == 4 && scan.read == 4 && scan.unreadable == 0)
    }

    @Test func aTranscriptUntouchedForAWeekIsLeftOut() async throws {
        let old = write("-Users-example-api/\(sessionID(1)).jsonl", session("Old"))
        try FileManager.default.setAttributes([.modificationDate: now - 8 * 86400], ofItemAtPath: old.path)
        write("-Users-example-api/\(sessionID(2)).jsonl", session("New", ago: 3 * 86400))
        let scan = await RecentSessionScanner().scan(root: root, now: now)
        #expect(titles(scan) == [sessionID(2): "New"] && scan.files == 1)
        // Its last line's time, not the file's.
        #expect(abs(scan.sessions[0].lastActivity.timeIntervalSince(now - 3 * 86400)) < 0.01)
    }

    @Test func anUnchangedFileIsNotReadAgainAGrownOrReplacedOneIs() async throws {
        let url = write("-Users-example-api/\(sessionID(1)).jsonl", session("First"))
        write("-Users-example-api/\(sessionID(2)).jsonl", session("Other"))
        let scanner = RecentSessionScanner()
        #expect(await scanner.scan(root: root, now: now).read == 2)
        let again = await scanner.scan(root: root, now: now)
        #expect(again.read == 0 && titles(again) == [sessionID(1): "First", sessionID(2): "Other"])
        // Grown: the conversation went on.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(L.aiTitle("Second").utf8))
        try handle.close()
        let grown = await scanner.scan(root: root, now: now)
        #expect(grown.read == 1 && titles(grown)[sessionID(1)] == "Second")
        // Replaced by a file of the same size: a new inode.
        let same = session("Third!").utf8.count == session("Second").utf8.count
        try Data((session("First") + L.aiTitle("Third!")).utf8).write(to: url, options: .atomic)
        let replaced = await scanner.scan(root: root, now: now)
        #expect(same && replaced.read == 1 && titles(replaced)[sessionID(1)] == "Third!")
        // Another config dir is another set of transcripts.
        #expect(await scanner.scan(root: root + "-other", now: now) == RecentScan())
        #expect(await scanner.scan(root: root, now: now).read == 2)
    }

    @Test func aFileThatCannotBeOpenedIsCountedAndTriedAgain() async {
        let url = write("-Users-example-api/\(sessionID(1)).jsonl", session("Locked"))
        chmod(url.path, 0)
        let scanner = RecentSessionScanner()
        let locked = await scanner.scan(root: root, now: now)
        #expect(locked.unreadable == 1 && locked.sessions.isEmpty && locked.files == 1)
        chmod(url.path, 0o644)
        let opened = await scanner.scan(root: root, now: now)
        #expect(opened.unreadable == 0 && titles(opened) == [sessionID(1): "Locked"])
    }

    @Test func aLongTranscriptIsReadFromItsEndOnly() async {
        // 3 MB of conversation before the title: one step from the end finds it.
        let line = L.user(at: now - 900, text: String(repeating: "x", count: 4000))
        write("-Users-example-api/\(sessionID(1)).jsonl", String(repeating: line, count: 750) + session("At the end", prompt: "last one"))
        let scan = await RecentSessionScanner().scan(root: root, now: now)
        #expect(scan.sessions.map(\.aiTitle) == ["At the end"] && scan.sessions[0].lastPrompt == "last one")
        #expect(scan.sessions[0].cwd == "/Users/example/api")
    }
}
