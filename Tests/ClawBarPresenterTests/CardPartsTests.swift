import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

/// Which parts of the card show, and what each one's tooltip says.
@Suite struct CardPartsTests {
    @Test func theSampleShowsItsPartsInTheCardsOrder() {
        let v = render()
        #expect(v.parts.map(\.id) == [.details, .hide, .exit, .reset, .sessions, .status, .account])
        #expect(v.tooltip(.details) == "Details" && v.tooltip(.hide) == "Hide" && v.tooltip(.exit) == "Quit")
        #expect(v.tooltip(.reset) == "")
        #expect(v.tooltip(.sessions) == "▶ clawbar — ~/Dev/clawbar\n? notes [permission] — ~/notes")
        #expect(v.tooltip(.status) == "Open status.claude.com")
        #expect(v.tooltip(.account) == "Max  ·  user@example.com")
    }

    @Test func aReachedLimitShowsThePlayButton() {
        let v = render(sample { $0.sessionPercent = 100 })
        #expect(v.parts.map(\.id) == [.details, .hide, .exit, .reset, .play, .sessions, .status, .account])
        #expect(v.tooltip(.play) == L10n.t(.uiPlayTip, .en))
    }

    @Test func theVersionLinesShowWithTheDetails() {
        #expect(!render().shows(.version) && !render().shows(.appVersion))
        let v = render(config: Config(expanded: true))
        #expect(v.parts.map(\.id).suffix(3) == [.version, .appVersion, .account])
        #expect(v.tooltip(.version) == "Click for the Claude Code changelog")
        // No local version: the ClawBar line stays, alone.
        let unknown = render(sample(data: { $0.version = VersionState(latest: "2.1.302") }), config: Config(expanded: true))
        #expect(!unknown.shows(.version) && unknown.shows(.appVersion))
    }

    @Test func loggedOutShowsTheAccountWithoutATooltip() {
        let v = render(sample(data: { $0.account = AccountInfo(loggedIn: false) }))
        #expect(v.tooltip(.account) == "")
        // Logged in with neither plan nor email, the line is empty and leaves the part out.
        #expect(!render(sample(data: { $0.account = AccountInfo(loggedIn: true) })).shows(.account))
    }

    @Test func rowsTurnedOffLeaveTheirPartsOut() {
        var config = Config()
        config.showSessions = false
        config.showStatus = false
        config.showAccount = false
        #expect(render(config: config).parts.map(\.id) == [.details, .hide, .exit, .reset])
    }

    @Test func anIssueThatStopsTheNumbersExplainsItselfOnTheResetLine() {
        var noLimits = DataSnapshot.sample
        noLimits.usageIssue = .noLimits
        #expect(render(noLimits).tooltip(.reset) == "/usage shows no plan limits. Signed in with an API key?")
        var missing = DataSnapshot.sample
        missing.usageIssue = .claudeNotFound
        let v = render(missing)
        #expect(v.tooltip(.reset) == v.resetText && !v.resetText.isEmpty)
    }

    @Test func theProjectsShowTheLabelThenARowEach() {
        let chart = Config(expanded: true, showHistory: true)
        let counting = render(sample(data: { $0.projects = nil }), config: chart)
        #expect(counting.shows(.projectsLabel) && !counting.shows(.project(0)))
        let v = render(sample(data: { $0.projects = Samples.projects }), config: chart)
        #expect(v.parts.map(\.id) == [
            .details, .hide, .exit, .reset, .sessions, .status, .projectsLabel,
            .project(0), .project(1), .project(2), .project(3), .version, .appVersion, .account,
        ])
        #expect(v.tooltip(.project(0)) == "~/code/api")
        // A week without usage hides the block, label and all.
        #expect(!render(sample(data: { $0.projects = ProjectUsage() }), config: chart).shows(.projectsLabel))
    }

    @Test func showingAPartAgainReplacesItInPlace() {
        var v = WidgetViewState()
        v.show(.account)
        v.show(.details, tooltip: "a")
        v.show(.project(1))
        v.show(.project(0))
        v.show(.details, tooltip: "b")
        #expect(v.parts == [CardPart(.details, tooltip: "b"), CardPart(.project(0)), CardPart(.project(1)), CardPart(.account)])
    }
}
