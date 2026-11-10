import Foundation
import ClawBarShared

/// What one transcript says about its session. Of what was said only the last prompt is kept, cut short.
struct TranscriptSummary: Sendable, Hashable {
    var sessionId: String
    /// Set by `/rename` or `claude -n`.
    var customTitle: String?
    var aiTitle: String?
    var lastPrompt = ""
    /// The folder the session was started in, else the last one a line named.
    var cwd: String?
    /// The newest line's time, else the file's.
    var lastActivity: Date
    /// `cli`, `claude-desktop`, or `sdk-cli` for a `claude -p` run.
    var entrypoint: String?
    /// Claude answered at least once.
    var replied = false

    /// Something was asked, by a person: a `/clear` alone leaves no title, prompt or reply, and a `claude -p` run
    /// belongs to another tool. A transcript without title lines still counts once Claude replied.
    var isSession: Bool {
        entrypoint != "sdk-cli" && (customTitle != nil || aiTitle != nil || !lastPrompt.isEmpty || replied)
    }
}

/// Reads a transcript's lines that title its session, backwards from the end, where Claude Code appends them again as
/// the conversation goes on. The lines are Claude Code's internal format, so every field is optional and a missing or
/// malformed one is no error.
struct RecentSessionReader: Sendable {
    /// One backward step.
    static let step = 64 << 10
    /// The most a transcript is read back from its end.
    static let cap = 1 << 20
    /// How far past the title and the prompt the read goes on: a `custom-title` is written just before its `ai-title`.
    static let margin = 4 << 10
    static let promptLimit = 300
    static let titleLimit = 120

    private var customTitle: String?
    private var aiTitle: String?
    /// Empty once a `last-prompt` line was seen without text.
    private var lastPrompt: String?
    private var lastCwd: String?
    private var firstCwd: String?
    private var entrypoint: String?
    private var lastActivity: Date?
    private var replied = false
    /// The end of a line that starts in a chunk not read yet; it holds no newline.
    private var carry = Data()
    /// The bytes read past the line that settled title and prompt; nil until one did.
    private var pastSettled: Int?

    private static let customNeedle = Data(#""type":"custom-title""#.utf8)
    private static let aiNeedle = Data(#""type":"ai-title""#.utf8)
    private static let promptNeedle = Data(#""type":"last-prompt""#.utf8)
    private static let stampNeedle = Data(#""timestamp":""#.utf8)
    private static let cwdNeedle = Data(#""cwd":""#.utf8)
    private static let originNeedle = Data(#""entrypoint":""#.utf8)
    private static let replyNeedle = Data(TranscriptScanner.marker)

    /// The title and the last prompt are both read, with the margin behind them; a long line's read part counts too.
    var isComplete: Bool { pastSettled.map { $0 + carry.count >= Self.margin } ?? false }

    /// Takes the chunk that ends where the last one began; `atStart` when it begins the file.
    mutating func add(earlier chunk: Data, atStart: Bool) {
        let data = chunk + carry
        var end = data.endIndex
        // Lines from the last to the first, so the first one found of a kind is the file's current one.
        while end > data.startIndex {
            // Only the chunk is searched: a long line's carry is not gone through again at every step.
            let newline = data[..<min(end, chunk.count)].lastIndex(of: 0x0A)
            guard newline != nil || atStart else { break }
            let start = newline.map { $0 + 1 } ?? data.startIndex
            if start < end { read(data[start ..< end]) }
            if let past = pastSettled {
                pastSettled = past + end - start + 1
            } else if customTitle != nil || aiTitle != nil, lastPrompt != nil {
                pastSettled = 0
            }
            end = newline ?? data.startIndex
        }
        carry = Data(data[..<end])
    }

    /// The file's first bytes, for what only its start tells: the folder it was started in, and a name given with
    /// `claude -n`. `whole` when they are the whole file, so the last line counts without its newline.
    mutating func addHead(_ data: Data, whole: Bool) {
        var start = data.startIndex
        var custom: String?
        while start < data.endIndex {
            let newline = data[start...].firstIndex(of: 0x0A)
            guard newline != nil || whole else { break }
            let end = newline ?? data.endIndex
            let line = data[start ..< end]
            if firstCwd == nil, line.range(of: Self.cwdNeedle) != nil, let j = Self.object(line) {
                firstCwd = Self.text(j["cwd"])
            }
            if line.range(of: Self.customNeedle) != nil, let j = Self.object(line), j["type"] as? String == "custom-title" {
                custom = Self.clean(j["customTitle"], limit: Self.titleLimit) ?? custom
            }
            start = end + 1
        }
        // A later rename sits in the tail and outranks it.
        customTitle = customTitle ?? custom
    }

    /// What was read, for the transcript `sessionId` last modified at `modified`.
    func summary(sessionId: String, modified: Date) -> TranscriptSummary {
        TranscriptSummary(
            sessionId: sessionId, customTitle: customTitle, aiTitle: aiTitle, lastPrompt: lastPrompt ?? "",
            cwd: firstCwd ?? lastCwd, lastActivity: lastActivity ?? modified, entrypoint: entrypoint, replied: replied
        )
    }

    /// Reads a transcript of `size` bytes backwards from its end, then its first bytes. `bytes` gives a range of it,
    /// or nil when it cannot, which ends the read.
    static func read(size: Int, bytes: (Range<Int>) -> Data?) -> RecentSessionReader {
        var reader = RecentSessionReader()
        var end = size
        while end > 0, !reader.isComplete, size - end < cap {
            let start = max(0, end - step)
            // The chunks and JSON temporaries are autoreleased; without a pool a first pass holds every byte it read.
            let more = autoreleasepool { () -> Bool in
                guard let chunk = bytes(start ..< end) else { return false }
                reader.add(earlier: chunk, atStart: start == 0)
                return true
            }
            guard more else { break }
            end = start
        }
        autoreleasepool {
            if let head = bytes(0 ..< min(step, size)) { reader.addHead(head, whole: size <= step) }
        }
        // The scanner keeps the reader for the week; an unfinished line's bytes are of no more use.
        reader.carry = Data()
        return reader
    }

    /// A whole transcript in memory, as the scanner reads one from disk.
    static func summary(of data: Data, sessionId: String, modified: Date) -> TranscriptSummary {
        read(size: data.count) { data.subdata(in: $0) }.summary(sessionId: sessionId, modified: modified)
    }

    /// One whole line, parsed only when it can still tell something.
    private mutating func read(_ line: Data) {
        if !replied, line.range(of: Self.replyNeedle) != nil { replied = true }
        let wantsCustom = customTitle == nil && line.range(of: Self.customNeedle) != nil
        let wantsAI = aiTitle == nil && line.range(of: Self.aiNeedle) != nil
        let wantsPrompt = lastPrompt == nil && line.range(of: Self.promptNeedle) != nil
        let wantsStamp = lastActivity == nil && line.range(of: Self.stampNeedle) != nil
        let wantsOrigin = entrypoint == nil && line.range(of: Self.originNeedle) != nil
        guard wantsCustom || wantsAI || wantsPrompt || wantsStamp || wantsOrigin, let j = Self.object(line) else { return }
        switch j["type"] as? String {
        case "custom-title":
            if wantsCustom { customTitle = Self.clean(j["customTitle"], limit: Self.titleLimit) }
        case "ai-title":
            if wantsAI { aiTitle = Self.clean(j["aiTitle"], limit: Self.titleLimit) }
        case "last-prompt":
            if wantsPrompt { lastPrompt = Self.clean(j["lastPrompt"], limit: Self.promptLimit) ?? "" }
        default:
            // Most lines carry a time; only the conversation's own say how the session was started, and where it is.
            if wantsStamp, let text = j["timestamp"] as? String {
                lastActivity = TranscriptReply.date(text)
            }
            if wantsOrigin, let origin = Self.text(j["entrypoint"]) {
                entrypoint = origin
                lastCwd = Self.text(j["cwd"])
            }
        }
    }

    private static func object(_ line: Data) -> NSDictionary? {
        (try? JSONSerialization.jsonObject(with: line)) as? NSDictionary
    }

    private static func text(_ value: Any?) -> String? {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// One line of text: whitespace runs become a space, and past `limit` characters it ends in `…`. nil when empty.
    static func clean(_ value: Any?, limit: Int) -> String? {
        guard let s = value as? String else { return nil }
        let words = s.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        let line = words.joined(separator: " ")
        return line.count > limit ? line.prefix(limit).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}

/// One pass over the recent transcripts.
struct RecentScan: Sendable, Hashable {
    /// The sessions that asked something, in no order.
    var sessions: [TranscriptSummary] = []
    /// Session transcripts changed this week, and those read this pass because they were new or had changed.
    var files = 0
    var read = 0
    /// Transcripts that could not be opened.
    var unreadable = 0
}

/// Finds the week's session transcripts, `<config dir>/projects/<folder>/<session id>.jsonl`, and reads each one's
/// tail. An unchanged file is never read twice.
actor RecentSessionScanner {
    private struct Cached {
        var inode: UInt64
        var size: UInt64
        var reader: RecentSessionReader
    }

    private var root: String?
    private var cache: [String: Cached] = [:]

    func scan(root: String, now: Date) -> RecentScan {
        // Another config dir is another set of transcripts.
        if root != self.root {
            self.root = root
            cache = [:]
        }
        let cutoff = now.addingTimeInterval(-TranscriptScanner.window).timeIntervalSince1970
        var scan = RecentScan()
        var seen: Set<String> = []
        let fm = FileManager.default
        for folder in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let dir = root + "/" + folder
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".jsonl") {
                // A session's own transcript is named by its id; subagent transcripts sit in subfolders under other names.
                let sessionId = String(name.dropLast(".jsonl".count))
                guard RecentSession.isSessionId(sessionId) else { continue }
                guard !Task.isCancelled else { break }
                let path = dir + "/" + name
                var st = stat()
                guard stat(path, &st) == 0, st.st_mode & S_IFMT == S_IFREG else { continue }
                let modified = TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9
                guard modified >= cutoff else { continue }
                seen.insert(path)
                scan.files += 1
                let inode = UInt64(st.st_ino), size = UInt64(st.st_size)
                // A grown or replaced file is read again; one that cannot be opened is tried again next pass.
                if cache[path]?.inode != inode || cache[path]?.size != size {
                    cache[path] = Self.read(path, size: Int(st.st_size)).map { Cached(inode: inode, size: size, reader: $0) }
                    scan.read += 1
                }
                guard let reader = cache[path]?.reader else {
                    scan.unreadable += 1
                    continue
                }
                let summary = reader.summary(sessionId: sessionId, modified: Date(timeIntervalSince1970: modified))
                if summary.isSession { scan.sessions.append(summary) }
            }
        }
        // Transcripts that left the week are forgotten.
        cache = cache.filter { seen.contains($0.key) }
        return scan
    }

    /// Switched off: the titles and prompts leave memory.
    func forget() {
        root = nil
        cache = [:]
    }

    /// One file's reader; nil when it cannot be opened.
    private static func read(_ path: String, size: Int) -> RecentSessionReader? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return RecentSessionReader.read(size: size) { range in
            guard !Task.isCancelled, (try? handle.seek(toOffset: UInt64(range.lowerBound))) != nil else { return nil }
            let data = try? handle.read(upToCount: range.count)
            // Short when the file was cut meanwhile: the next pass sees its new size.
            return data.flatMap { $0.count == range.count ? $0 : nil }
        }
    }
}
