import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

// Expected values follow history-dedup-final-usage and history-project-identity in the 1.6.0 review.
@Suite struct ProjectLedgerTests {
    let t0 = utc("2026-10-16T22:30:00Z")
    var since: Int { TranscriptReply.hour(of: t0) - 168 }

    func reply(_ line: String) throws -> TranscriptReply {
        try #require(TranscriptReply(line: Data(line.utf8)))
    }

    func add(_ ledger: inout ProjectLedger, _ line: String, in folder: String = "-Users-example-api") throws {
        ledger.add(try reply(line), folder: folder, since: since)
    }

    /// Opus 5.5 output: $20 per million, so 1,000 tokens are 2 cents.
    func weights(_ ledger: ProjectLedger) -> [String: Double] { ClawBarDataTests.weights(ledger.usage) }

    @Test func aReplyCountsOnceWithItsFinalCounts() throws {
        var ledger = ProjectLedger()
        for output in [8, 900, 1477] {
            try add(&ledger, assistantLine("msg_1", at: t0, output: output))
        }
        #expect(weights(ledger) == ["/Users/example/api": 0.02954])
        // A pass that sees the final line later adds only the difference.
        var split = ProjectLedger()
        try add(&split, assistantLine("msg_1", at: t0, output: 8))
        #expect(weights(split) == ["/Users/example/api": 0.00016])
        try add(&split, assistantLine("msg_1", at: t0, output: 1477))
        #expect(weights(split) == weights(ledger))
    }

    @Test func aForkedSubagentsCopyOfAReplyCountsInTheFolderThatHadItFirst() throws {
        var ledger = ProjectLedger()
        try add(&ledger, assistantLine("msg_1", at: t0, output: 1000))
        try add(&ledger, assistantLine("msg_1", at: t0 + 60, cwd: "/Users/example/web", output: 1000), in: "-Users-example-web")
        try add(&ledger, assistantLine("msg_2", at: t0, cwd: "/Users/example/web", output: 500), in: "-Users-example-web")
        #expect(weights(ledger) == ["/Users/example/api": 0.02, "/Users/example/web": 0.01])
        #expect(ledger.usage.projects.map(\.path) == ["/Users/example/api", "/Users/example/web"])
    }

    @Test func aFastLineIsNotUndoneByALaterLineWithoutASpeed() throws {
        var ledger = ProjectLedger()
        try add(&ledger, assistantLine("msg_1", at: t0, output: 100, speed: "fast"))
        try add(&ledger, assistantLine("msg_1", at: t0, output: 1000, speed: nil))
        #expect(weights(ledger) == ["/Users/example/api": 0.04])
    }

    @Test func unpricedRepliesAreCountedAndTheirModelsNamed() throws {
        var ledger = ProjectLedger()
        try add(&ledger, assistantLine("msg_1", at: t0, model: "claude-opus-6", output: 1000), in: "a")
        try add(&ledger, assistantLine("msg_1", at: t0, model: "claude-opus-6", output: 2000), in: "a")
        try add(&ledger, assistantLine("msg_2", at: t0, model: "claude-quill-1", output: 1000), in: "a")
        try add(&ledger, assistantLine("msg_3", at: t0, output: 1000), in: "a")
        #expect(ledger.usage.unpriced == 2)
        #expect(ledger.unpricedModels == ["claude-opus-6", "claude-quill-1"])
    }

    @Test func theWindowKeepsItsHoursAndForgetsOlderOnes() throws {
        var ledger = ProjectLedger()
        let edge = Date(timeIntervalSince1970: TimeInterval(since) * 3600)
        let web = "/Users/example/web"
        try add(&ledger, assistantLine("msg_old", at: edge - 1, output: 1000))
        try add(&ledger, assistantLine("msg_edge", at: edge, output: 1000))
        try add(&ledger, assistantLine("msg_new", at: t0, cwd: web, output: 1000), in: "-Users-example-web")
        #expect(weights(ledger) == ["/Users/example/api": 0.02, web: 0.02])
        // An hour later the edge hour has left the week, and the api folder with it.
        ledger.prune(before: since + 1)
        #expect(weights(ledger) == [web: 0.02])
    }

    @Test func aProjectIsNamedByTheFolderClaudeCodeWasStartedIn() {
        // Sessions that cd elsewhere keep the launch folder, however many lines ran there.
        #expect(ProjectLedger.path(folder: "-Users-example-api", cwds: ["/Users/example/api": 1, "/Users/example/api/web": 9]) == "/Users/example/api")
        // A shortened folder name matches no cwd: the busiest one names it.
        #expect(ProjectLedger.path(folder: "-Users-example-a-very-lo", cwds: ["/Users/example/x": 2, "/Users/example/y": 5]) == "/Users/example/y")
        #expect(ProjectLedger.path(folder: "-Users-example-z", cwds: ["/Users/example/x": 2, "/Users/example/y": 2]) == "/Users/example/x")
        #expect(ProjectLedger.path(folder: "-Users-example-z", cwds: [:]) == "-Users-example-z")
    }

    @Test func twoFoldersWithTheSameLeafStayApart() throws {
        var ledger = ProjectLedger()
        try add(&ledger, assistantLine("msg_1", at: t0, cwd: "/Users/example/work/api", output: 1000), in: "-Users-example-work-api")
        try add(&ledger, assistantLine("msg_2", at: t0, cwd: "/Users/example/home/api", output: 500), in: "-Users-example-home-api")
        #expect(weights(ledger) == ["/Users/example/work/api": 0.02, "/Users/example/home/api": 0.01])
    }

    @Test func claudeCodesFolderNamesAreReproduced() {
        #expect(ProjectLedger.encode("/Users/example/Dev/vr1e.clawbar") == "-Users-example-Dev-vr1e-clawbar")
        #expect(ProjectLedger.encode("/Users/example/Übung 2") == "-Users-example--bung-2")
        // An emoji is two UTF-16 units, as in JavaScript.
        #expect(ProjectLedger.encode("/x/🦀") == "-x---")
    }

    @Test func aLineIsReadInAnyKeyOrderAndOnlyForAssistantReplies() throws {
        let reordered = #"{"timestamp":"2026-10-16T22:30:00.000Z","message":{"usage":{"output_tokens":7,"cache_read_input_tokens":3,"cache_creation":{"ephemeral_1h_input_tokens":4,"ephemeral_5m_input_tokens":1},"cache_creation_input_tokens":5,"input_tokens":2},"model":"claude-opus-5-5","id":"msg_9"},"cwd":"/Users/example/api","type":"assistant"}"#
        let r = try reply(reordered)
        #expect(r.tokens == TokenCounts(input: 2, write5m: 1, write1h: 4, cacheRead: 3, output: 7))
        #expect(r.id == "msg_9" && r.cwd == "/Users/example/api" && r.speed == nil)
        #expect(r.hour == TranscriptReply.hour(of: t0))
        // Without the breakdown every write is a 5-minute one; without a message id the request id stands in.
        let bare = #"{"type":"assistant","requestId":"req_1","timestamp":"2026-10-16T22:30:00Z","message":{"model":"claude-opus-5-5","usage":{"cache_creation_input_tokens":5}}}"#
        let b = try reply(bare)
        #expect(b.id == "req_1" && b.tokens == TokenCounts(write5m: 5))
        // Claude Code's own error notes, a subagent's progress line quoting a reply, and a line without usage.
        for line in [
            assistantLine("msg_1", at: t0, model: "<synthetic>", output: 5),
            #"{"type":"progress","data":{"message":{"type":"assistant","message":{"id":"msg_2","model":"claude-opus-5-5","usage":{"output_tokens":5}}}},"timestamp":"2026-10-16T22:30:00Z"}"#,
            #"{"type":"assistant","timestamp":"2026-10-16T22:30:00Z","message":{"id":"msg_3","model":"claude-opus-5-5"}}"#,
            #"{"type":"assistant","message":{"id":"msg_4","model":"claude-opus-5-5","usage":{}}}"#,
            #"{"type":"assistant","#,
        ] {
            #expect(TranscriptReply(line: Data(line.utf8)) == nil, "\(line)")
        }
    }
}
