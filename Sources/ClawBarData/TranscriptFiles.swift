import Foundation

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

enum TranscriptFiles {
    /// The `.jsonl` files under `root/<folder>` changed in the week before `now`. `deep` goes into subfolders, where
    /// subagents' transcripts sit. A cancelled task gets what was found so far.
    static func ofTheWeek(root: String, now: Date, deep: Bool) -> [TranscriptFile] {
        let cutoff = now.addingTimeInterval(-TranscriptScanner.window)
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
