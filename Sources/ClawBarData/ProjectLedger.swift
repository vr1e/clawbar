import Foundation
import ClawBarShared

/// One assistant line of a transcript: what the reply cost so far, and where it ran. Nothing it said is kept.
struct TranscriptReply: Sendable, Hashable {
    /// The message id, else the request id; a reply is written as several lines with the same one.
    var id: String
    var model: String
    /// `fast` in fast mode.
    var speed: String?
    var tokens: TokenCounts
    /// Hours since 1970 in UTC.
    var hour: Int
    var cwd: String?

    private static let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSeconds = Date.ISO8601FormatStyle()

    static func hour(of date: Date) -> Int { Int((date.timeIntervalSince1970 / 3600).rounded(.down)) }

    /// nil for any other line, a synthetic reply (Claude Code's own error notes), or a line without usage or time.
    init?(line: Data) {
        // NSDictionary lookups skip bridging every line's content into Swift dictionaries.
        guard let j = (try? JSONSerialization.jsonObject(with: line)) as? NSDictionary, j["type"] as? String == "assistant",
              let message = j["message"] as? NSDictionary, let usage = message["usage"] as? NSDictionary,
              let model = message["model"] as? String, model != "<synthetic>",
              let id = (message["id"] as? String) ?? (j["requestId"] as? String),
              let text = j["timestamp"] as? String,
              let at = (try? Self.stamp.parse(text)) ?? (try? Self.wholeSeconds.parse(text))
        else { return nil }
        self.id = id
        self.model = model
        speed = usage["speed"] as? String
        // Without the 5-minute / 1-hour breakdown every write is taken as a 5-minute one.
        let writes = Lenient.int(usage["cache_creation_input_tokens"]) ?? 0
        let write1h = Lenient.int((usage["cache_creation"] as? NSDictionary)?["ephemeral_1h_input_tokens"]) ?? 0
        tokens = TokenCounts(
            input: Lenient.int(usage["input_tokens"]) ?? 0, write5m: max(0, writes - write1h), write1h: write1h,
            cacheRead: Lenient.int(usage["cache_read_input_tokens"]) ?? 0, output: Lenient.int(usage["output_tokens"]) ?? 0
        )
        hour = Self.hour(of: at)
        cwd = j["cwd"] as? String
    }
}

/// The week's replies per transcript folder. Each reply counts once, with the largest count of each kind any of its
/// lines showed, in the folder where it was first seen: a forked subagent repeats its parent's lines.
struct ProjectLedger: Sendable {
    private struct Counted: Sendable {
        var model: String
        var speed: String?
        var tokens = TokenCounts()
        var dollars = 0.0
        var listed = true
        var folder: String
        var hour: Int
    }

    private var replies: [String: Counted] = [:]
    /// Transcript folder → working folder → lines seen there.
    private var cwds: [String: [String: Int]] = [:]

    /// Merges `reply` into its id's earlier lines; a reply from before `since` (a UTC hour) is left out.
    mutating func add(_ reply: TranscriptReply, folder: String, since: Int) {
        guard reply.hour >= since else { return }
        if let cwd = reply.cwd { cwds[folder, default: [:]][cwd, default: 0] += 1 }
        var c = replies[reply.id] ?? Counted(model: reply.model, folder: folder, hour: reply.hour)
        // A line without a speed does not undo an earlier fast one.
        c.speed = reply.speed ?? c.speed
        c.tokens = c.tokens.merged(reply.tokens)
        (c.dollars, c.listed) = PriceTable.price(model: c.model, speed: c.speed, tokens: c.tokens)
        replies[reply.id] = c
    }

    /// Forgets the replies before `since`, and the folders left without any.
    mutating func prune(before since: Int) {
        replies = replies.filter { $0.value.hour >= since }
        let folders = Set(replies.values.map(\.folder))
        cwds = cwds.filter { folders.contains($0.key) }
    }

    /// Every folder with weight, heaviest first.
    var usage: ProjectUsage {
        let projects = Dictionary(grouping: replies.values, by: \.folder).compactMap { folder, replies -> ProjectWeight? in
            let weight = replies.reduce(0) { $0 + $1.dollars }
            return weight > 0 ? ProjectWeight(path: Self.path(folder: folder, cwds: cwds[folder] ?? [:]), weight: weight) : nil
        }
        return ProjectUsage(
            projects: projects.sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.path < $1.path },
            unpriced: replies.values.count { !$0.listed }
        )
    }

    /// The models priced as another, for the log.
    var unpricedModels: [String] { Set(replies.values.filter { !$0.listed }.map(\.model)).sorted() }

    /// The folder Claude Code was started in, whose name the transcript folder carries; else the one most lines ran in,
    /// since Claude Code may shorten a long name; else the transcript folder's own name.
    static func path(folder: String, cwds: [String: Int]) -> String {
        if let launch = cwds.keys.filter({ encode($0) == folder }).min() { return launch }
        if let most = cwds.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) { return most.key }
        return folder
    }

    /// Claude Code's transcript folder name for a working folder: each UTF-16 unit but an ASCII letter or digit is `-`.
    static func encode(_ path: String) -> String {
        String(decoding: path.utf16.map { u in
            (48 ... 57).contains(u) || (65 ... 90).contains(u) || (97 ... 122).contains(u) ? u : 45
        }, as: UTF16.self)
    }
}
