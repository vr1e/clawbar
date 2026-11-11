import Foundation
import ClawBarShared

/// One pass over the week's transcripts.
struct ProjectScan: Sendable, Hashable {
    var usage = ProjectUsage()
    /// Transcripts changed this week, and their size in bytes.
    var files = 0
    var bytes = 0
    /// Transcripts that could not be opened.
    var unreadable = 0
    var unpricedModels: [String] = []
}

/// Reads the week's Claude Code transcripts in `<config dir>/projects/<folder>/**/*.jsonl` into a `ProjectLedger`. Each
/// pass reads only what was appended since the last; a line still being written waits for the next pass.
actor TranscriptScanner {
    private struct Mark {
        var inode: UInt64
        /// Just past the last whole line read.
        var offset: UInt64
    }

    private var root: String?
    private var marks: [String: Mark] = [:]
    private var ledger = ProjectLedger()

    static let chunk = 1 << 20
    /// Where the marker's `y` sits: `"` is on every other byte of JSON, `y` is not.
    private static let anchor = 2

    func scan(root: String, now: Date) -> ProjectScan {
        // Another config dir is another set of transcripts.
        if root != self.root {
            self.root = root
            marks = [:]
            ledger = ProjectLedger()
        }
        let cutoff = now.addingTimeInterval(-TranscriptFiles.window)
        // The week starts on a whole UTC hour, as the original's does.
        let first = UsageSample.minute(of: cutoff)
        let since = first - first % 60
        var scan = ProjectScan()
        var seen: Set<String> = []
        for file in TranscriptFiles.ofTheWeek(root: root, now: now) {
            seen.insert(file.path)
            scan.files += 1
            scan.bytes += Int(file.size)
            if !read(file, since: since) { scan.unreadable += 1 }
        }
        // Transcripts that left the week are forgotten; their replies age out with their hours.
        marks = marks.filter { seen.contains($0.key) }
        ledger.prune(before: since)
        scan.usage = ledger.usage
        scan.unpricedModels = ledger.unpricedModels
        return scan
    }

    /// Reads one file from its mark; false when it cannot be opened.
    private func read(_ file: TranscriptFile, since: Int) -> Bool {
        let path = file.path, folder = file.folder, inode = file.inode, size = file.size
        // A replaced or truncated file starts over; its replies already counted stay counted once.
        var mark = marks[path].flatMap { $0.inode == inode && $0.offset <= size ? $0 : nil } ?? Mark(inode: inode, offset: 0)
        defer { marks[path] = mark }
        guard mark.offset < size else { return true }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: mark.offset) } catch { return false }
        var pending = Data()
        var more = true
        while more, !Task.isCancelled {
            // The chunks and JSON temporaries are autoreleased; without a pool a first pass holds every byte it read.
            autoreleasepool {
                guard let chunk = try? handle.read(upToCount: Self.chunk), !chunk.isEmpty else { return more = false }
                pending.append(chunk)
                let used = lines(in: pending) { line in
                    if let reply = TranscriptReply(line: line) { ledger.add(reply, folder: folder, since: since) }
                }
                mark.offset += UInt64(used)
                pending = pending.subdata(in: used ..< pending.count)
            }
        }
        return true
    }

    /// Calls `body` with each whole line that carries the marker; returns the bytes up to the last newline.
    private func lines(in data: Data, _ body: (Data) -> Void) -> Int {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var start = 0
            while start < buffer.count, let newline = memchr(base + start, 0x0A, buffer.count - start) {
                let end = base.distance(to: UnsafeRawPointer(newline))
                if Self.hasMarker(base + start, end - start) { body(Data(bytes: base + start, count: end - start)) }
                start = end + 1
            }
            return start
        }
    }

    /// memmem crawls JSON, where its first byte `"` is everywhere; seeking the rarer `y` is five times faster.
    private static func hasMarker(_ line: UnsafeRawPointer, _ count: Int) -> Bool {
        TranscriptReply.marker.withUnsafeBytes { m in
            var at = anchor
            while at < count, let y = memchr(line + at, Int32(m[anchor]), count - at) {
                let start = line.distance(to: UnsafeRawPointer(y)) - anchor
                if start + m.count <= count, memcmp(line + start, m.baseAddress, m.count) == 0 { return true }
                at = start + anchor + 1
            }
            return false
        }
    }
}
