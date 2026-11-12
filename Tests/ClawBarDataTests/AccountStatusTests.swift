import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

@Suite struct AccountProbeTests {
    func finished(_ data: Data, exit: Int32) -> ProcessResult {
        .success(ProcessOutcome(pid: 7, termination: .exit(exit), stdout: data))
    }

    @Test func theProbeIsAuthStatus() {
        let spec = AccountProbe.spec(claude: "/c/claude", environment: [:], home: "/h")
        #expect(spec.arguments == ["auth", "status"])
        #expect(spec.timeout == 60)
    }

    @Test func aSubscriptionGetsItsPlanNameAndTheConfigDirectoryIsKept() {
        #expect(AccountProbe.interpret(finished(Fixture.data("account/logged-in.json"), exit: 0)) == AccountInfo(
            loggedIn: true, plan: "Team", email: "user@example.com", configDirectory: "/Users/example/.claude"
        ))
    }

    @Test func loggedOutExitsOneAndIsStillRead() {
        let a = AccountProbe.interpret(finished(Fixture.data("account/logged-out.json"), exit: 1))
        #expect(a?.loggedIn == false)
        #expect(a?.configDirectory == "/Users/example/.claude")
    }

    @Test func anAPIKeyLoginIsAPI() {
        #expect(AccountProbe.interpret(finished(Fixture.data("account/api-key.json"), exit: 0))?.plan == "API")
    }

    @Test func planNamesIgnoreCaseAndUnknownOnesShowRaw() {
        func plan(_ json: String) -> String? { AccountProbe.parse(Data(json.utf8))?.plan }
        #expect(plan(#"{"loggedIn": true, "subscriptionType": "MAX"}"#) == "Max")
        #expect(plan(#"{"loggedIn": true, "subscriptionType": "pro"}"#) == "Pro")
        #expect(plan(#"{"loggedIn": true, "subscriptionType": "Enterprise"}"#) == "Enterprise")
        #expect(plan(#"{"loggedIn": true, "subscriptionType": "free"}"#) == "Free")
        #expect(plan(#"{"loggedIn": true, "subscriptionType": "ultra"}"#) == "ultra")
        // claude.ai without a subscription type is not an API login
        #expect(plan(#"{"loggedIn": true, "authMethod": "Claude.AI"}"#) == "")
        #expect(plan(#"{"loggedIn": true}"#) == "")
    }

    @Test func unreadableOutputKeepsTheLastValue() {
        #expect(AccountProbe.interpret(finished(Data("Please log in".utf8), exit: 1)) == nil)
        #expect(AccountProbe.interpret(.failure(.notFound("/c"))) == nil)
        #expect(AccountProbe.interpret(.success(ProcessOutcome(pid: 7, termination: .signal(SIGTERM), timedOut: true))) == nil)
    }
}

@Suite struct StatusProbeTests {
    @Test func allOperational() {
        #expect(StatusProbe.parse(Fixture.data("status/ok.json")) == ServiceStatus(indicator: "none", incidents: [], broken: []))
    }

    @Test func brokenComponentsLoseTheirParentheticalAndGroupsAreSkipped() {
        #expect(StatusProbe.parse(Fixture.data("status/partial.json")) == ServiceStatus(
            indicator: "minor",
            incidents: ["Elevated errors on Claude API", "Slow responses in Claude Code"],
            broken: [
                BrokenComponent(name: "Claude API", state: "partial_outage"),
                BrokenComponent(name: "Claude Code", state: "degraded_performance"),
            ]
        ))
    }

    @Test func badJSONIsNoStatus() {
        #expect(StatusProbe.parse(Data("<html>".utf8)) == nil)
        #expect(StatusProbe.parse(Data("[]".utf8)) == nil)
    }
}
