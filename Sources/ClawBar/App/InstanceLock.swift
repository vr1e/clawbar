import Foundation

/// One running ClawBar per AppPaths root: an flock the kernel drops when the process dies, so a crash never
/// leaves a stale lock behind.
nonisolated final class InstanceLock {
    private var fd: Int32

    private init(fd: Int32) { self.fd = fd }

    deinit { release() }

    enum Attempt {
        case acquired(InstanceLock)
        /// Another process holds it.
        case held
        /// The folder or the file could not be made or opened; the errno.
        case failed(Int32)
    }

    static func acquire(_ url: URL) -> Attempt {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Read-only: flock needs no write access, so a read-only or root-owned lock file still locks.
        let fd = open(url.path, O_RDONLY | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return .failed(errno) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let e = errno
            close(fd)
            return e == EWOULDBLOCK ? .held : .failed(e)
        }
        return .acquired(InstanceLock(fd: fd))
    }

    /// Whether some process runs ClawBar on this root; never creates the file.
    static func isHeld(_ url: URL) -> Bool {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { return errno == EWOULDBLOCK }
        flock(fd, LOCK_UN)
        return false
    }

    func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }
}
