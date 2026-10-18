import Foundation
import Synchronization
import ClawBarShared
@testable import ClawBarData

/// Stands in for every child: answers by kind at once, or holds a child until the test releases it.
final class FakeRunner: ProcessRunning {
    enum Kind: String { case usage, account, version, update, other }

    enum Reply {
        case now(ProcessResult)
        case hold
    }

    private struct State {
        var calls: [ProcessSpec] = []
        var held: [(spec: ProcessSpec, cont: CheckedContinuation<ProcessResult, Never>)] = []
        var replies: [Kind: Reply] = [:]
        var own: Set<Int32> = []
        var shutdowns = 0
    }

    private let state = Mutex(State())

    static func kind(_ s: ProcessSpec) -> Kind {
        switch s.arguments.first {
        case "-p": .usage
        case "auth": .account
        case "--version": .version
        case "update": .update
        default: .other
        }
    }

    func reply(_ kind: Kind, _ r: Reply) { state.withLock { $0.replies[kind] = r } }
    func reply(_ kind: Kind, stdout: String, exit: Int32 = 0) {
        reply(kind, .now(.success(ProcessOutcome(pid: 900, termination: .exit(exit), stdout: Data(stdout.utf8)))))
    }
    func reply(_ kind: Kind, data: Data, exit: Int32 = 0, stderr: String = "") {
        reply(kind, .now(.success(ProcessOutcome(pid: 900, termination: .exit(exit), stdout: data, stderr: Data(stderr.utf8)))))
    }

    var calls: [ProcessSpec] { state.withLock { $0.calls } }
    func count(_ kind: Kind) -> Int { calls.filter { Self.kind($0) == kind }.count }
    var heldCount: Int { state.withLock { $0.held.count } }
    var shutdowns: Int { state.withLock { $0.shutdowns } }

    /// Finishes the oldest held child of this kind.
    func release(_ kind: Kind, _ result: ProcessResult) {
        let c = state.withLock { s -> CheckedContinuation<ProcessResult, Never>? in
            guard let i = s.held.firstIndex(where: { Self.kind($0.spec) == kind }) else { return nil }
            return s.held.remove(at: i).cont
        }
        c?.resume(returning: result)
    }

    func release(_ kind: Kind, data: Data, exit: Int32 = 0) {
        release(kind, .success(ProcessOutcome(pid: 900, termination: .exit(exit), stdout: data)))
    }

    func setOwn(_ pids: Set<Int32>) { state.withLock { $0.own = pids } }

    var childPIDs: Set<Int32> { state.withLock { $0.own } }

    func run(_ spec: ProcessSpec) async -> ProcessResult {
        let reply = state.withLock { s -> Reply in
            s.calls.append(spec)
            return s.replies[Self.kind(spec)] ?? .hold
        }
        switch reply {
        case .now(let r):
            return r
        case .hold:
            return await withCheckedContinuation { c in
                state.withLock { $0.held.append((spec, c)) }
            }
        }
    }

    func shutdown() {
        let held = state.withLock { s -> [CheckedContinuation<ProcessResult, Never>] in
            s.shutdowns += 1
            let h = s.held.filter { !$0.spec.survivesQuit }.map(\.cont)
            s.held.removeAll { !$0.spec.survivesQuit }
            return h
        }
        for c in held { c.resume(returning: .success(ProcessOutcome(pid: 900, termination: .signal(SIGTERM)))) }
    }
}

/// The login shell's answers in turn, the last one again once they run out.
final class FakeLoginShell: Sendable {
    private let answers: [LoginEnvironment?]
    private let count = Mutex(0)

    init(_ answers: [LoginEnvironment?]) { self.answers = answers }

    var runs: Int { count.withLock { $0 } }

    func answer() -> LoginEnvironment? {
        let n = count.withLock { n in
            n += 1
            return n
        }
        return answers[min(n, answers.count) - 1]
    }
}

/// A clock the test moves by hand.
final class TestClock: Sendable {
    private let time: Mutex<Date>

    init(_ start: Date) { time = Mutex(start) }

    var now: Date {
        get { time.withLock { $0 } }
        set { time.withLock { $0 = newValue } }
    }

    var read: @Sendable () -> Date { { [self] in now } }
}
