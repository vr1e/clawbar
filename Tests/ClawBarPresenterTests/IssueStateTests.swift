import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

// The plan's "Issue states" table: what the user sees for each UsageIssue.
@Suite struct IssueStateTests {
    private func issue(_ issue: UsageIssue, usage: UsageSnapshot? = nil, lang: Lang = .en) -> WidgetViewState {
        var d = DataSnapshot.empty
        d.usage = usage
        d.usageAt = usage == nil ? nil : Samples.now.plus(seconds: -25)
        d.usageProbeCompleted = true
        d.usageIssue = issue
        return render(d, lang: lang)
    }

    private static let noClaudeEN = "Claude Code was not found. Install it:\ncurl -fsSL https://claude.ai/install.sh | bash"

    @Test func claudeNotFoundShowsTheInstallHintInRedAndGreyDashesInTheMenuBar() {
        let v = issue(.claudeNotFound)
        #expect(v.resetText == Self.noClaudeEN && v.resetColor == Palette.crit && v.tooltip(.reset) == Self.noClaudeEN)
        #expect(v.pctText == "--" && v.pctColor == Palette.dead && v.sessionFraction == 0)
        #expect(v.trayText == "--" && v.trayColor == Palette.dead && v.trayTooltip == Self.noClaudeEN)
        let de = issue(.claudeNotFound, lang: .de)
        #expect(de.resetText == "Claude Code nicht gefunden. Installieren:\ncurl -fsSL https://claude.ai/install.sh | bash")
        #expect(de.trayTooltip == de.resetText)
    }

    @Test func claudeNotFoundOutranksOldNumbers() {
        let v = issue(.claudeNotFound, usage: DataSnapshot.sample.usage)
        #expect(v.pctText == "--" && v.trayText == "--" && v.trayColor == Palette.dead)
        #expect(v.resetText == Self.noClaudeEN)
        // The weekly rows keep their last value; the stamp says how old it is.
        #expect(v.week.value == "59%  ·  4d 15h")
    }

    @Test func noLimitsIsNoDataWithAnExplanation() {
        let v = issue(.noLimits)
        #expect(v.resetText == "no data" && v.resetColor == Palette.secondary)
        #expect(v.tooltip(.reset) == "/usage shows no plan limits. Signed in with an API key?")
        #expect(v.trayText == "--" && v.trayColor == Palette.dead)
        #expect(v.trayTooltip == "ClawBar: no data\n/usage shows no plan limits. Signed in with an API key?")
        // Numbers from an earlier subscription login no longer apply.
        let old = issue(.noLimits, usage: DataSnapshot.sample.usage)
        #expect(old.pctText == "--" && old.resetText == "no data" && old.trayText == "--")
        #expect(issue(.noLimits, lang: .de).tooltip(.reset) == "/usage zeigt keine Planlimits. Mit einem API-Schlüssel angemeldet?")
    }

    @Test func aRejectedFlagStopsTheProbeAndSaysWhyInRed() {
        let text = "claude rejects --no-session-persistence\nChecks paused until Claude Code updates"
        let v = issue(.flagRejected("--no-session-persistence"), usage: DataSnapshot.sample.usage)
        #expect(v.resetText == text && v.resetColor == Palette.crit && v.tooltip(.reset) == text)
        // The last numbers stay up, as with any stale probe; the menu bar says why they no longer move.
        #expect(v.pctText == "34" && v.trayText == "34" && v.trayColor == Palette.ok)
        #expect(v.trayTooltip == "34% of session · 2h 05m (16:10)\nweek 59% · 4d 15h (Thu 06:00)\nFable 8% · 4d 15h (Thu 06:00)\n" + text)
        let none = issue(.flagRejected("--no-session-persistence"))
        #expect(none.pctText == "--" && none.resetText == text)
        #expect(none.trayTooltip == "ClawBar: no data\n" + text)
        #expect(issue(.flagRejected("--safe-mode"), lang: .de).resetText
            == "claude lehnt --safe-mode ab\nAbfrage pausiert bis zum nächsten Update")
    }

    @Test func reachingTheModelStopsTheProbeWithTurnsAndCost() {
        let v = issue(.modelReached(turns: 1, costUSD: 0.0123, tokens: 1285))
        let text = "/usage called the model (turns: 1, $0.0123)\nChecks paused until Claude Code updates"
        #expect(v.resetText == text && v.resetColor == Palette.crit && v.tooltip(.reset) == text)
        #expect(v.trayTooltip.hasSuffix("\n" + text))
        #expect(issue(.modelReached(turns: 0, costUSD: 0, tokens: 12)).resetText.contains("(turns: 0, $0.0000)"))
        #expect(issue(.modelReached(turns: 2, costUSD: 1.5, tokens: 9)).resetText.contains("(turns: 2, $1.5000)"))
        #expect(issue(.modelReached(turns: 1, costUSD: 0.0123, tokens: 1285), lang: .de).resetText
            == "/usage: Modell erreicht (Turns: 1, 0,0123 $)\nAbfrage pausiert bis zum nächsten Update")
    }

    @Test(arguments: [UsageIssue.probeFailed("exit 1"), .timedOut, .launchFailed("EACCES")])
    func transientFailuresChangeNothingVisible(failure: UsageIssue) {
        var withData = DataSnapshot.sample
        withData.usageIssue = failure
        #expect(differences(render(withData), .sample) == [])
        var without = DataSnapshot.empty
        without.usageIssue = failure
        #expect(differences(render(without), .placeholder) == [])
        without.usageProbeCompleted = true
        #expect(render(without).resetText == "no data")
    }
}
