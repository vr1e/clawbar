import Foundation
import Synchronization

/// Runs child processes; tests of the controller stand a fake in for it.
protocol ProcessRunning: Sendable {
    func run(_ spec: ProcessSpec) async -> ProcessResult
    /// Children running now, so the session registry can leave them out.
    var childPIDs: Set<Int32> { get }
    /// SIGTERM, then SIGKILL, for every running child except those that survive quitting; later runs are refused.
    func shutdown()
}

/// posix_spawn, so each probe gets its own process group (a timeout ends its grandchildren too), stdin
/// /dev/null, no inherited descriptors, and launch errors that say what went wrong.
final class ProcessRunner: ProcessRunning {
    private struct Registry {
        /// pid → survives quitting.
        var children: [Int32: Bool] = [:]
        var closed = false
    }

    private let registry = Mutex(Registry())

    init() {}

    var childPIDs: Set<Int32> { registry.withLock { Set($0.children.keys) } }

    func run(_ spec: ProcessSpec) async -> ProcessResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ProcessResult, Never>) in
            launch(spec) { cont.resume(returning: $0) }
        }
    }

    func shutdown() {
        let victims = registry.withLock { r -> [Int32] in
            r.closed = true
            return r.children.filter { !$0.value }.map(\.key)
        }
        guard !victims.isEmpty else { return }
        for pid in victims { signal(pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, registry.withLock({ r in victims.contains { r.children[$0] != nil } }) {
            usleep(10_000)
        }
        for pid in victims { signal(pid, SIGKILL) }
    }

    // MARK: - Launch

    private func launch(_ spec: ProcessSpec, _ done: @escaping @Sendable (ProcessResult) -> Void) {
        if let e = Self.check(spec.executable) { return done(.failure(e)) }
        if registry.withLock({ $0.closed }) { return done(.failure(.failed(spec.executable, errno: ECANCELED))) }

        let capture = !spec.survivesQuit
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        if capture {
            guard pipe(&outPipe) == 0 else { return done(.failure(.failed(spec.executable, errno: errno))) }
            guard pipe(&errPipe) == 0 else {
                let e = errno
                close(outPipe[0])
                close(outPipe[1])
                return done(.failure(.failed(spec.executable, errno: e)))
            }
            for fd in outPipe + errPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        switch spec.output {
        case .capture:
            posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
            posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        case .survivesQuit(let log):
            try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            posix_spawn_file_actions_addopen(&actions, 1, log.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            posix_spawn_file_actions_adddup2(&actions, 1, 2)
        }
        posix_spawn_file_actions_addchdir_np(&actions, spec.directory)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // A new session for the update keeps it out of reach of signals sent to our group or terminal.
        let group = spec.survivesQuit ? POSIX_SPAWN_SETSID : POSIX_SPAWN_SETPGROUP
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | group))
        posix_spawnattr_setpgroup(&attr, 0)
        var all = sigset_t()
        sigfillset(&all)
        posix_spawnattr_setsigdefault(&attr, &all)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attr, &none)

        let argv: [UnsafeMutablePointer<CChar>?] = ([spec.executable] + spec.arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = spec.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, spec.executable, &actions, &attr, argv, envp)
        if capture {
            close(outPipe[1])
            close(errPipe[1])
        }
        guard rc == 0 else {
            if capture {
                close(outPipe[0])
                close(errPipe[0])
            }
            return done(.failure(.failed(spec.executable, errno: rc)))
        }

        let spawned = pid
        // Registered before anything else runs, so a session read never mistakes our child for a user's.
        let closedMeanwhile = registry.withLock { r -> Bool in
            r.children[spawned] = spec.survivesQuit
            return r.closed
        }
        if closedMeanwhile && !spec.survivesQuit { signal(spawned, SIGKILL) }

        let child = Child(pid: spawned, cap: spec.outputCap, grace: spec.drainGrace, capture: capture, done: done)
        if capture { child.drain(out: outPipe[0], err: errPipe[0]) }

        Thread.detachNewThread { [registry = self] in
            var status: Int32 = 0
            var r: pid_t
            repeat { r = waitpid(spawned, &status, 0) } while r == -1 && errno == EINTR
            registry.forget(spawned)
            child.exited(r == spawned ? status : nil)
        }

        let killAfter = spec.killAfter
        DispatchQueue.global().asyncAfter(deadline: .now() + spec.timeout) { [self] in
            guard child.markTimedOut() else { return }
            signal(spawned, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + killAfter) { [self] in signal(spawned, SIGKILL) }
        }
    }

    private func forget(_ pid: Int32) {
        registry.withLock { _ = $0.children.removeValue(forKey: pid) }
    }

    /// Missing → notFound; a folder or a file without the x bit → notExecutable.
    static func check(_ path: String) -> LaunchError? {
        var st = stat()
        guard stat(path, &st) == 0 else {
            return errno == ENOENT || errno == ENOTDIR ? .notFound(path) : .failed(path, errno: errno)
        }
        guard st.st_mode & S_IFMT == S_IFREG, access(path, X_OK) == 0 else { return .notExecutable(path) }
        return nil
    }

    /// The child's whole process group, which may outlive it, then the child in case it left the group, but only
    /// while unreaped, since after that its pid is free for reuse.
    private func signal(_ pid: Int32, _ sig: Int32) {
        _ = kill(-pid, sig)
        if registry.withLock({ $0.children[pid] != nil }) { _ = kill(pid, sig) }
    }
}

/// One running child: its drained output, its exit, and the single completion.
private final class Child: Sendable {
    private struct State {
        var out = Data()
        var err = Data()
        var outOpen: Bool
        var errOpen: Bool
        var status: Int32?
        var reaped = false
        var timedOut = false
        var done: (@Sendable (ProcessResult) -> Void)?
        var handles: [FileHandle] = []
    }

    let pid: Int32
    private let cap: Int
    private let grace: TimeInterval
    private let state: Mutex<State>

    init(pid: Int32, cap: Int, grace: TimeInterval, capture: Bool, done: @escaping @Sendable (ProcessResult) -> Void) {
        self.pid = pid
        self.cap = cap
        self.grace = grace
        state = Mutex(State(outOpen: capture, errOpen: capture, done: done))
    }

    func drain(out: Int32, err: Int32) {
        let o = FileHandle(fileDescriptor: out, closeOnDealloc: true)
        let e = FileHandle(fileDescriptor: err, closeOnDealloc: true)
        state.withLock { $0.handles = [o, e] }
        o.readabilityHandler = { [self] h in read(h, stdout: true) }
        e.readabilityHandler = { [self] h in read(h, stdout: false) }
    }

    /// Kept below the cap; the rest is read and dropped so the child never blocks on a full pipe.
    private func read(_ h: FileHandle, stdout: Bool) {
        let data = h.availableData
        if data.isEmpty {
            h.readabilityHandler = nil
            state.withLock { s in
                if stdout { s.outOpen = false } else { s.errOpen = false }
            }
            finish(force: false)
            return
        }
        let cap = cap
        state.withLock { s in
            guard s.done != nil else { return }
            if stdout {
                let room = cap - s.out.count
                if room > 0 { s.out.append(data.prefix(room)) }
            } else {
                let room = cap - s.err.count
                if room > 0 { s.err.append(data.prefix(room)) }
            }
        }
    }

    func exited(_ status: Int32?) {
        state.withLock { s in
            s.status = status
            s.reaped = true
        }
        finish(force: false)
        // A grandchild may still hold the pipe: stop waiting for EOF after the grace.
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [self] in finish(force: true) }
    }

    /// True when the child was still running, so the caller should signal it.
    func markTimedOut() -> Bool {
        state.withLock { s in
            guard !s.reaped else { return false }
            s.timedOut = true
            return true
        }
    }

    private func finish(force: Bool) {
        let ready = state.withLock { s -> (@Sendable (ProcessResult) -> Void, ProcessOutcome, [FileHandle])? in
            guard s.reaped, let done = s.done, force || (!s.outOpen && !s.errOpen) else { return nil }
            s.done = nil
            let outcome = ProcessOutcome(
                pid: pid, termination: Self.termination(s.status), stdout: s.out, stderr: s.err, timedOut: s.timedOut
            )
            let handles = s.handles
            s.handles = []
            // The timeout timer keeps this object alive a while longer; the output is handed off already.
            s.out = Data()
            s.err = Data()
            return (done, outcome, handles)
        }
        guard let (done, outcome, handles) = ready else { return }
        for h in handles { h.readabilityHandler = nil }
        done(.success(outcome))
    }

    /// The wait status as exit code or signal; unknown (already reaped elsewhere) reads as exit -1.
    private static func termination(_ status: Int32?) -> ProcessOutcome.Termination {
        guard let status else { return .exit(-1) }
        let sig = status & 0x7F
        return sig == 0 ? .exit((status >> 8) & 0xFF) : .signal(sig)
    }
}
