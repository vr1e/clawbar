import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

// update.ps1 step 9, version.ps1 New-ChangesTooltip and events.ps1's click rule, plus the port's update failure.
@Suite struct VersionLineTests {
    /// With the details open, where the line sits.
    private func version(_ ver: VersionState, lang: Lang = .en) -> WidgetViewState {
        render(sample(data: { $0.version = ver }), config: Config(expanded: true), lang: lang)
    }

    private static let update = VersionState(local: "2.1.292", latest: "2.1.302")

    private static func withChanges(_ items: [String], for latest: String = "2.1.302", from local: String = "2.1.292") -> VersionState {
        var v = update
        v.changes = ChangesExcerpt(forVersion: latest, fromVersion: local, items: items)
        return v
    }

    @Test func unknownLocalVersionHidesTheLine() {
        let v = version(VersionState(latest: "2.1.302"))
        #expect(v.versionText == "" && !v.shows(.version) && v.versionAction == .none)
    }

    @Test func aBareVersionWhileTheChannelIsUnknown() {
        let v = version(VersionState(local: "2.1.302"))
        #expect(v.versionText == "v2.1.302" && v.versionColor == Palette.muted)
        #expect(v.tooltip(.version) == "Click for the Claude Code changelog")
        #expect(v.versionAction == .open(AppInfo.changelogPage))
    }

    @Test func aLocalBuildAheadOfItsChannelIsLatest() {
        let v = version(VersionState(local: "2.1.302", latest: "2.1.292"))
        #expect(v.versionText == "v2.1.302  ·  latest" && v.versionAction == .open(AppInfo.changelogPage))
        #expect(version(VersionState(local: "2.1.302", latest: "2.1.292"), lang: .de).versionText == "v2.1.302  ·  aktuell")
    }

    @Test func anUpdateIsAmberAndClickingRunsIt() {
        let v = version(Self.update)
        #expect(v.versionText == "v2.1.292  ·  2.1.302 available  ·  what's new?")
        #expect(v.versionColor == Palette.warn)
        #expect(v.versionAction == .runUpdate)
        #expect(version(Self.update, lang: .de).versionText == "v2.1.292  ·  2.1.302 verfügbar  ·  was ist neu?")
    }

    @Test func theChangelogTooltipLoadsUntilAnExcerptForThisPairArrives() {
        let loading = "What's new: 2.1.292 → 2.1.302\n\nloading the changelog...\n\nClick to update"
        #expect(version(Self.update).tooltip(.version) == loading)
        #expect(version(Self.withChanges(["old"], for: "2.1.301")).tooltip(.version) == loading)
        #expect(version(Self.withChanges(["old"], from: "2.1.290")).tooltip(.version) == loading)
        #expect(version(Self.update, lang: .de).tooltip(.version)
            == "Neuerungen: 2.1.292 → 2.1.302\n\nÄnderungsprotokoll wird geladen …\n\nKlicken zum Aktualisieren")
    }

    @Test func theChangelogTooltipListsTheItems() {
        #expect(version(Self.withChanges(["Faster startup", "Fixed --resume"])).tooltip(.version)
            == "What's new: 2.1.292 → 2.1.302\n\n• Faster startup\n• Fixed --resume\n\nClick to update")
        #expect(version(Self.withChanges([])).tooltip(.version)
            == "What's new: 2.1.292 → 2.1.302\n\nnothing in the CHANGELOG yet\n\nClick to update")
    }

    @Test func atMost25ItemsThenHowManyMore() {
        let items = (1 ... 27).map { "item \($0)" }
        let lines = (version(Self.withChanges(items)).tooltip(.version) ?? "").components(separatedBy: "\n")
        #expect(lines.count == 1 + 1 + 25 + 1 + 1 + 1)
        #expect(lines[2] == "• item 1" && lines[26] == "• item 25")
        #expect(lines[27] == "…and 2 more")
        #expect(lines.last == "Click to update")
        let exactly = version(Self.withChanges(Array(items.prefix(25)))).tooltip(.version) ?? ""
        #expect(!exactly.contains("more") && exactly.contains("• item 25"))
        #expect(version(Self.withChanges(items), lang: .de).tooltip(.version)?.contains("\n… und 2 weitere\n") == true)
    }

    @Test func whileUpdatingTheLineSaysSoAndAClickDoesNotStartAnother() {
        var ver = Self.withChanges(["Faster startup"])
        ver.updating = true
        ver.updateFailure = UpdateFailure(exitCode: 1, outputTail: "old failure")
        let v = version(ver)
        #expect(v.versionText == "v2.1.292  ·  updating..." && v.versionColor == Palette.warn)
        #expect(v.versionAction == .none)
        #expect(v.tooltip(.version) == "What's new: 2.1.292 → 2.1.302\n\n• Faster startup\n\nClick to update")
        #expect(version(ver, lang: .de).versionText == "v2.1.292  ·  wird aktualisiert …")
        // Without an update out, the click still opens the changelog, as in events.ps1.
        let current = VersionState(local: "2.1.302", latest: "2.1.302", updating: true)
        #expect(version(current).versionText == "v2.1.302  ·  updating...")
        #expect(version(current).versionAction == .open(AppInfo.changelogPage))
        #expect(version(current).tooltip(.version) == "Click for the Claude Code changelog")
    }

    @Test func aFailedUpdateIsRedAndExplainsItself() {
        var ver = Self.update
        ver.updateFailure = UpdateFailure(exitCode: 1, outputTail: "Error: cannot update\nmanaged by Homebrew")
        ver.installHint = .homebrew
        let v = version(ver)
        #expect(v.versionText == "v2.1.292  ·  update failed" && v.versionColor == Palette.crit)
        #expect(v.tooltip(.version) == """
            claude update exited with code 1

            Error: cannot update
            managed by Homebrew

            Installed with Homebrew: update with brew upgrade claude-code
            """)
        #expect(v.versionAction == .runUpdate)
        #expect(version(ver, lang: .de).tooltip(.version) == """
            claude update endete mit Code 1

            Error: cannot update
            managed by Homebrew

            Mit Homebrew installiert: Update mit brew upgrade claude-code
            """)
    }

    @Test func aTimedOutUpdateWithoutOutputOrHint() {
        var ver = Self.update
        ver.updateFailure = UpdateFailure(exitCode: nil, outputTail: " \n")
        #expect(version(ver).tooltip(.version) == "claude update did not finish in 15 minutes")
        ver.installHint = .npm
        #expect(version(ver).tooltip(.version)
            == "claude update did not finish in 15 minutes\n\nInstalled with npm: update with npm install -g @anthropic-ai/claude-code")
    }

    @Test func aCleanExitThatLeftTheVersionSaysSo() {
        var ver = Self.update
        ver.updateFailure = UpdateFailure(exitCode: 0, outputTail: "Done", from: "2.1.292", to: "2.1.302")
        let v = version(ver)
        #expect(v.versionText == "v2.1.292  ·  update failed" && v.versionColor == Palette.crit)
        #expect(v.tooltip(.version) == "claude update finished, but Claude Code is still 2.1.292\n\nDone")
        #expect(v.versionAction == .runUpdate)
        #expect(version(ver, lang: .de).tooltip(.version) == "claude update ist fertig, aber Claude Code ist noch 2.1.292\n\nDone")
    }

    @Test func aFailureOutranksAnUpdateAndTheLatestState() {
        var ver = VersionState(local: "2.1.302", latest: "2.1.302")
        ver.updateFailure = UpdateFailure(exitCode: 2, outputTail: "")
        let v = version(ver)
        #expect(v.versionText == "v2.1.302  ·  update failed")
        #expect(v.versionAction == .open(AppInfo.changelogPage))
    }
}
