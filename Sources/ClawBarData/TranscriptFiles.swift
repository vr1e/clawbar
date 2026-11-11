import Foundation
import ClawBarShared

/// One transcript on disk, as a scanner's pass finds it.
struct TranscriptFile {
    /// The project folder it sits under, and its path below that.
    var folder: String
    var name: String
    var path: String
    var inode: UInt64
    var size: UInt64
    var modified: Date
}

/// Where Claude Code keeps its transcripts, `<config dir>/projects/<folder>/**/*.jsonl`, and which of them count.
enum TranscriptFiles {
    static let window: TimeInterval = 7 * 86400

    static func root(configDir: String) -> String { configDir + "/projects" }

    /// Every transcript changed in the week before `now`, subagents' among them. A cancelled task gets what was found
    /// so far.
    static func ofTheWeek(root: String, now: Date) -> [TranscriptFile] {
        walk(root: root, now: now, deep: true)
    }

    /// The week's session transcripts with their session ids: a session's own transcript sits at the top of its
    /// folder, named by its id, and subagents' sit in subfolders under other names.
    static func sessionsOfTheWeek(root: String, now: Date) -> [(sessionId: String, file: TranscriptFile)] {
        walk(root: root, now: now, deep: false).compactMap { file in
            let id = String(file.name.dropLast(".jsonl".count))
            return RecentSession.isSessionId(id) ? (id, file) : nil
        }
    }

    private static func walk(root: String, now: Date, deep: Bool) -> [TranscriptFile] {
        let cutoff = now.addingTimeInterval(-window)
        var files: [TranscriptFile] = []
        let fm = FileManager.default
        for folder in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let dir = root + "/" + folder
            let names = deep
                ? fm.enumerator(atPath: dir)?.compactMap { $0 as? String } ?? []
                : (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            for name in names where name.hasSuffix(".jsonl") {
                guard !Task.isCancelled else { return files }
                let path = dir + "/" + name
                var st = stat()
                guard stat(path, &st) == 0, st.st_mode & S_IFMT == S_IFREG else { continue }
                let modified = Date(
                    timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9
                )
                guard modified >= cutoff else { continue }
                files.append(TranscriptFile(
                    folder: folder, name: name, path: path, inode: UInt64(st.st_ino), size: UInt64(st.st_size), modified: modified
                ))
            }
        }
        return files
    }
}
