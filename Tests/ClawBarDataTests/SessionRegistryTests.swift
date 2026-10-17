import Foundation
import Synchronization
import Testing
import ClawBarShared
@testable import ClawBarData

/// Records every file the registry opens.
final class ReadSpy: Sendable {
    private let opened = Mutex<[String]>([])

    var names: [String] { opened.withLock { $0.map { ($0 as NSString).lastPathComponent } } }

    var reader: @Sendable (URL) throws -> Data {
        { [self] url in
            opened.withLock { $0.append(url.path) }
            return try Data(contentsOf: url)
        }
    }
}

/// Every listed pid is alive and started at the given time; others are dead.
struct FakeTable: ProcessTable {
    var starts: [Int32: ProcessStart]

    func isAlive(_ pid: Int32) -> Bool { starts[pid] != nil }
    func startTime(_ pid: Int32) -> ProcessStart { starts[pid] ?? .gone }
}

@Suite struct SessionRegistryTests {
    let dir = TempDir("cb-sessions")
    let started = utc("2026-10-16T21:30:01Z")

    func session(_ pid: Int32, _ extra: [String: Any] = [:], file: String? = nil) {
        var j: [String: Any] = [
            "pid": pid, "sessionId": "00000000-0000-4000-8000-00000000000\(pid % 10)",
            "cwd": "/Users/example/Dev/project\(pid)", "startedAt": 1_792_186_204_842,
            "procStart": "Fri Oct 16 21:30:01 2026", "version": "2.1.302", "kind": "interactive",
            "entrypoint": "cli", "name": "project\(pid)", "status": "idle",
        ]
        for (k, v) in extra { j[k] = v }
        let data = try! JSONSerialization.data(withJSONObject: j)
        try! data.write(to: dir.url.appendingPathComponent(file ?? "\(pid).json"))
    }

    func registry(_ table: some ProcessTable, spy: ReadSpy = ReadSpy()) -> SessionRegistry {
        SessionRegistry(directory: dir.url, table: table, readFile: spy.reader)
    }

    func table(_ pids: Int32...) -> FakeTable {
        FakeTable(starts: Dictionary(uniqueKeysWithValues: pids.map { ($0, ProcessStart.started(started)) }))
    }

    @Test func aPrintModeRunCountsOnlyOnceItHasOutlivedAUsageCheck() {
        // The fixture's startedAt.
        let start = Date(timeIntervalSince1970: 1_792_186_204.842)
        session(4301, ["entrypoint": "sdk-cli"])
        session(4302, ["entrypoint": "sdk-cli", "startedAt": 1_792_186_184_842])
        session(4303)
        session(4304, ["entrypoint": "sdk-cli", "startedAt": NSNull()])
        let pids = registry(table(4301, 4302, 4303, 4304)).read(excluding: [], now: start + 5).map(\.pid)
        #expect(pids == [4302, 4303, 4304])
        #expect(registry(table(4301)).read(excluding: [], now: start + 20).map(\.pid) == [4301])
    }

    @Test func onlyPidJSONFilesAreOpenedAndKeyFilesNever() throws {
        session(4242)
        try Data("secret".utf8).write(to: dir.file("4242.0f3a9c.key"))
        try Data("secret".utf8).write(to: dir.file("4242.json.key"))
        session(4243, file: "04243.json")
        session(4244, file: "notes.json")
        session(4245, file: "4245.json.bak")
        session(4246, file: "4246.JSON")
        let spy = ReadSpy()
        let found = registry(table(4242, 4243, 4244, 4245, 4246), spy: spy).read(excluding: [])
        #expect(spy.names == ["4242.json"])
        #expect(found.map(\.pid) == [4242])
    }

    @Test func aSessionCarriesItsFields() {
        session(4242, ["status": "waiting", "waitingFor": "permission", "name": "clawbar", "cwd": "/Users/example/Dev/clawbar"])
        let s = registry(table(4242)).read(excluding: [])
        #expect(s == [SessionInfo(
            pid: 4242, sessionId: "00000000-0000-4000-8000-000000000002", name: "clawbar", cwd: "/Users/example/Dev/clawbar",
            state: .waiting, waitingFor: "permission", kind: "interactive", startedAt: Date(timeIntervalSince1970: 1_792_186_204.842)
        )])
    }

    @Test func busyAndShellAreBusyWaitingIsWaitingTheRestIdle() {
        session(11, ["status": "busy"])
        session(12, ["status": "Shell"])
        session(13, ["status": "waiting"])
        session(14, ["status": "idle"])
        session(15, ["status": "compacting"])
        let states = registry(table(11, 12, 13, 14, 15)).read(excluding: []).map(\.state)
        #expect(states == [.busy, .busy, .waiting, .idle, .idle])
    }

    @Test func deadOwnSpareAndDaemonSessionsAreDropped() {
        session(21)
        session(22, ["spare": true])
        session(23, ["kind": "daemon"])
        session(24, ["kind": "bg"])
        session(25, ["kind": "daemon-worker"])
        session(26)
        session(27)
        session(1)
        var noKind: [String: Any] = [:]
        noKind["kind"] = NSNull()
        session(28, noKind)
        let s = registry(table(1, 21, 22, 23, 24, 25, 27, 28)).read(excluding: [27])
        #expect(s.map(\.pid) == [21, 24, 25, 28])
        #expect(s.map(\.kind) == ["interactive", "bg", "daemon-worker", nil])
    }

    @Test func theNameFallsBackToTheCwdLeaf() {
        session(31, ["name": "", "cwd": "/Users/example/Dev/clawbar/"])
        session(32, ["name": NSNull(), "cwd": "/Users/example/notes"])
        #expect(registry(table(31, 32)).read(excluding: []).map(\.name) == ["clawbar", "notes"])
    }

    @Test func aReusedPidIsDroppedByItsStartTime() {
        session(41)
        session(42, ["procStart": "Fri Oct 16 21:30:05 2026"])
        session(43, ["procStart": "Fri Oct 16 21:30:07 2026"])
        session(44, ["procStart": "Thu Oct  1 06:40:22 2026"])
        let s = registry(table(41, 42, 43, 44)).read(excluding: [])
        #expect(s.map(\.pid) == [41, 42])
    }

    @Test func anUnparseableOrMissingProcStartKeepsTheSession() {
        session(51, ["procStart": "yesterday-ish"])
        session(52, ["procStart": NSNull()])
        session(53, ["procStart": true])
        #expect(registry(table(51, 52, 53)).read(excluding: []).map(\.pid) == [51, 52, 53])
    }

    @Test func aFiletimeProcStartIsUnderstood() {
        // 2026-10-16T21:30:01Z as 100 ns ticks since 1601
        let ft: Int64 = (1_792_186_201 * 10_000_000) + 116_444_736_000_000_000
        session(61, ["procStart": NSNumber(value: ft)])
        session(62, ["procStart": String(ft + 60 * 10_000_000)])
        #expect(registry(table(61, 62)).read(excluding: []).map(\.pid) == [61])
    }

    @Test func zombiesAndUnreadableFilesAreSkippedAndAnUnknownStartIsKept() throws {
        session(71)
        session(72)
        try Data("{broken".utf8).write(to: dir.file("73.json"))
        let t = FakeTable(starts: [71: .gone, 72: .unknown, 73: .started(started)])
        #expect(registry(t).read(excluding: []).map(\.pid) == [72])
    }

    @Test func aMissingFolderIsNoSessions() {
        let r = SessionRegistry(directory: dir.url.appendingPathComponent("absent"), table: table(), readFile: ReadSpy().reader)
        #expect(r.read(excluding: []).isEmpty)
    }

    @Test func theConfigDirectoryDecidesTheFolder() {
        #expect(SessionRegistry.directory(configDir: "/Users/example/.claude-work", home: "/Users/example").path
            == "/Users/example/.claude-work/sessions")
        #expect(SessionRegistry.directory(configDir: nil, home: "/Users/example").path == "/Users/example/.claude/sessions")
    }

    @Test func aLiveProcessKeepsItsRealStartAndAShiftedOneIsDropped() async throws {
        let runner = ProcessRunner()
        let sleeper = Task { await runner.run(ProcessSpec(
            executable: "/bin/sleep", arguments: ["30"], environment: [:], directory: "/", timeout: 20
        )) }
        defer { runner.shutdown() }
        var pid: Int32 = 0
        for _ in 0 ..< 200 where pid == 0 {
            pid = runner.childPIDs.first ?? 0
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(pid > 0)
        let ps = try await runner.run(ProcessSpec(
            executable: "/bin/ps", arguments: ["-o", "lstart=", "-p", String(pid)],
            environment: ["LC_ALL": "C", "TZ": "UTC"], directory: "/"
        )).get()
        let lstart = ps.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(!lstart.isEmpty)

        let live = SessionRegistry(directory: dir.url, table: LiveProcessTable(), readFile: ReadSpy().reader)
        session(pid, ["procStart": lstart])
        #expect(live.read(excluding: []).map(\.pid) == [pid])
        #expect(live.read(excluding: [pid]).isEmpty)

        let start = try #require(SessionRegistry.procStart(lstart))
        let shifted = Date(timeInterval: 3600, since: start)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        session(pid, ["procStart": f.string(from: shifted)])
        #expect(live.read(excluding: []).isEmpty)

        runner.shutdown()
        _ = await sleeper.value
        #expect(!LiveProcessTable().isAlive(pid))
    }
}
