import Testing
@testable import ClawBar
import ClawBarShared

@Suite struct CLIArgumentsTests {
    private func parse(_ args: String...) -> Result<CLIMode, CLIError> { CLI.parse(args) }

    @Test func noArgumentsRunsTheApp() {
        #expect(parse() == .success(.run))
    }

    @Test func launchServicesNoiseStillRunsTheApp() {
        // Finder and Xcode pass AppKit defaults such as -psn_0_1234 or -NSDocumentRevisionsDebugMode YES.
        #expect(parse("-psn_0_12345") == .success(.run))
        #expect(parse("-NSDocumentRevisionsDebugMode", "YES") == .success(.run))
    }

    @Test func everyModeParses() {
        #expect(parse("--version") == .success(.version))
        #expect(parse("--diagnose") == .success(.diagnose))
        #expect(parse("--snapshot", "out") == .success(.snapshot(dir: "out")))
        #expect(parse("--record", "tour", "tour.gif") == .success(.record(.tour, gif: "tour.gif")))
        #expect(parse("--dump-state") == .success(.dumpState))
        #expect(parse("--make-icon", "icons") == .success(.makeIcon(dir: "icons")))
    }

    @Test func everyRemoteCommandParses() {
        #expect(parse("--command", "toggle") == .success(.command(.toggle)))
        #expect(parse("--command", "show") == .success(.command(.show)))
        #expect(parse("--command", "larger") == .success(.command(.larger)))
        #expect(parse("--command", "settings") == .success(.command(.settings)))
        #expect(parse("--command", "smaller") == .success(.command(.smaller)))
        #expect(parse("--command", "refresh") == .success(.command(.refresh)))
        #expect(parse("--command", "quit") == .success(.command(.quit)))
        #expect(parse("--command", "lang", "de") == .success(.command(.lang(.de))))
        #expect(parse("--command", "lang", "EN") == .success(.command(.lang(.en))))
    }

    @Test func everyRecorderScenarioParses() {
        for name in ["tour", "sleep", "limit", "reset", "hearts", "weather", "clicks"] {
            guard case .success(.record(let s, gif: "x.gif")) = parse("--record", name, "x.gif") else {
                Issue.record("\(name) did not parse")
                continue
            }
            #expect(s.rawValue == name)
        }
    }

    @Test func mistakesAreReportedNotGuessed() {
        #expect(isFailure(parse("--snapshot")))
        #expect(isFailure(parse("--record", "tour")))
        #expect(isFailure(parse("--record", "party", "x.gif")))
        #expect(isFailure(parse("--command")))
        #expect(isFailure(parse("--command", "dance")))
        #expect(isFailure(parse("--command", "lang")))
        #expect(isFailure(parse("--command", "lang", "ru")))
        #expect(isFailure(parse("--frobnicate")))
        #expect(isFailure(parse("--version", "extra")))
        #expect(isFailure(parse("--make-icon")))
    }

    @Test func remoteCommandsRoundTripThroughTheirWireForm() {
        let all: [RemoteCommand] = [.toggle, .show, .larger, .smaller, .refresh, .settings, .quit, .lang(.en), .lang(.de)]
        for c in all {
            #expect(RemoteCommand(wire: c.wire) == c)
        }
        #expect(RemoteCommand(wire: "lang:xx") == nil)
        #expect(RemoteCommand(wire: "") == nil)
    }

    private func isFailure(_ r: Result<CLIMode, CLIError>) -> Bool {
        if case .failure = r { return true }
        return false
    }
}
