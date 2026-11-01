import Foundation
import ClawBarShared

enum ProcessStart: Sendable, Hashable {
    case started(Date)
    /// Gone between the liveness check and the lookup, or a zombie.
    case gone
    /// The lookup failed; the session is kept, as the original kept it on any error.
    case unknown
}

protocol ProcessTable: Sendable {
    func isAlive(_ pid: Int32) -> Bool
    func startTime(_ pid: Int32) -> ProcessStart
}

struct LiveProcessTable: ProcessTable {
    func isAlive(_ pid: Int32) -> Bool { pid > 1 && kill(pid, 0) == 0 }

    func startTime(_ pid: Int32) -> ProcessStart {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return .unknown }
        guard size > 0, Int32(info.kp_proc.p_stat) != SZOMB else { return .gone }
        let tv = info.kp_proc.p_un.__p_starttime
        return .started(Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000))
    }
}

/// Claude Code's registry of running sessions, `<config dir>/sessions/<pid>.json`, filtered to live, genuine ones.
struct SessionRegistry: Sendable {
    let directory: URL
    let table: any ProcessTable
    /// Every file read goes through here; the sibling `<pid>.<hash>.key` files are secrets and never reach it.
    let readFile: @Sendable (URL) throws -> Data

    init(directory: URL, table: any ProcessTable, readFile: @escaping @Sendable (URL) throws -> Data) {
        self.directory = directory
        self.table = table
        self.readFile = readFile
    }

    static func directory(configDir: String?, home: String) -> URL {
        let base = configDir.flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.claude"
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("sessions", isDirectory: true)
    }

    /// A `claude -p` run younger than this is someone's usage check, gone in seconds; older, it is real work.
    static let printModeGrace: TimeInterval = 20

    /// The registry's sessions in file-name order, minus ClawBar's own children and other tools' fresh checks.
    func read(excluding own: Set<Int32>, now: Date) -> [SessionInfo] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var out: [SessionInfo] = []
        for name in names.sorted() where Rx.matches(Self.fileName, name) {
            guard let data = try? readFile(directory.appendingPathComponent(name)),
                  let j = JSONFile.object(from: data),
                  let n = Lenient.int(j["pid"]), n > 1, n <= Int(Int32.max)
            else { continue }
            let pid = Int32(n)
            guard !own.contains(pid), table.isAlive(pid), Lenient.bool(j["spare"]) != true else { continue }
            let kind = Lenient.string(j["kind"]).flatMap { $0.isEmpty ? nil : $0 }
            // The daemon supervises sessions and is none itself.
            if kind?.lowercased() == "daemon" { continue }
            switch table.startTime(pid) {
            case .gone:
                continue
            case .started(let t):
                // A stale file whose pid was reused: the start times disagree by more than 5 s.
                if let claimed = Self.procStart(j["procStart"]), abs(t.timeIntervalSince(claimed)) > 5 { continue }
            case .unknown:
                break
            }
            let cwd = Lenient.string(j["cwd"]) ?? ""
            var name = Lenient.string(j["name"]) ?? ""
            if name.isEmpty, !cwd.isEmpty { name = (cwd as NSString).lastPathComponent }
            let waitingFor = Lenient.string(j["waitingFor"]).flatMap { $0.isEmpty ? nil : $0 }
            let startedAt = Lenient.double(j["startedAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
            // Another ClawBar's or a feeder's `claude -p /usage` registers like a session and would wake Clawd.
            if Lenient.string(j["entrypoint"]) == "sdk-cli", let startedAt, now.timeIntervalSince(startedAt) < Self.printModeGrace {
                continue
            }
            out.append(SessionInfo(
                pid: pid, sessionId: Lenient.string(j["sessionId"]) ?? "", name: name, cwd: cwd,
                state: Self.state(Lenient.string(j["status"])), waitingFor: waitingFor, kind: kind, startedAt: startedAt
            ))
        }
        return out
    }

    static func state(_ status: String?) -> SessionState {
        switch status?.lowercased() {
        case "busy", "shell": .busy
        case "waiting": .waiting
        default: .idle
        }
    }

    /// `ps -o lstart` text in UTC ("Fri Oct 16 21:30:01 2026", days padded), or a Windows FILETIME number.
    static func procStart(_ v: Any?) -> Date? {
        if Lenient.isBool(v) { return nil }
        if let n = v as? NSNumber { return filetime(n.int64Value) }
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.allSatisfy(\.isNumber), let ft = Int64(s) { return filetime(ft) }
        let parts = s.split(separator: " ")
        guard parts.count == 5, let month = Months.number[parts[1].lowercased()], let day = Int(parts[2]), let year = Int(parts[4])
        else { return nil }
        let clock = parts[3].split(separator: ":").compactMap { Int($0) }
        guard clock.count == 3 else { return nil }
        let cal = Calendar.gregorian(in: TimeZone(identifier: "UTC")!)
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: clock[0], minute: clock[1], second: clock[2]))
    }

    /// 100 ns ticks since 1601-01-01; nil outside 1990–2100, where a number in another unit (epoch milliseconds,
    /// say) would land, so the session is kept on its liveness instead of dropped as a reused pid.
    private static func filetime(_ ft: Int64) -> Date? {
        let seconds = (Double(ft) - 116_444_736_000_000_000) / 10_000_000
        return (631_152_000 ... 4_102_444_800).contains(seconds) ? Date(timeIntervalSince1970: seconds) : nil
    }

    private static let fileName = Rx.make(#"^[1-9][0-9]*\.json$"#)
}
