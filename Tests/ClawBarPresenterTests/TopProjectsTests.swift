import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

// Expected values follow history.ps1 Show-Projects: the top 4, each a share of all projects, a 70-wide track.
@Suite struct TopProjectsTests {
    static let chartOn = Config(expanded: true, showHistory: true)

    private func projects(_ usage: ProjectUsage?, config: Config = chartOn, lang: Lang = .en) -> ProjectsView? {
        render(sample(data: { $0.projects = usage }), config: config, lang: lang).projects
    }

    private func usage(_ weights: [(String, Double)], unpriced: Int = 0) -> ProjectUsage {
        ProjectUsage(projects: weights.map { ProjectWeight(path: $0.0, weight: $0.1) }, unpriced: unpriced)
    }

    @Test func theProjectsShowOnlyWithTheChart() {
        #expect(projects(Samples.projects) != nil)
        #expect(projects(Samples.projects, config: Config(expanded: true)) == nil)
        #expect(projects(Samples.projects, config: Config(expanded: false, showHistory: true)) == nil)
    }

    @Test(arguments: Lang.allCases)
    func theyCountUntilTheFirstScanHasFinished(lang: Lang) throws {
        let p = try #require(projects(nil, lang: lang))
        #expect(p.rows.isEmpty)
        #expect(p.caption == L10n.t(.histCounting, lang))
        #expect(p.label == L10n.t(.uiProjects, lang))
        #expect(p.tooltip == L10n.t(.histProjTip, lang))
    }

    @Test func aWeekWithoutUsageHidesThem() {
        #expect(projects(ProjectUsage()) == nil)
        #expect(projects(usage([("/Users/example/a", 0)])) == nil)
    }

    @Test func theTopFourShareAllProjects() throws {
        let p = try #require(projects(Samples.projects))
        #expect(p.rows.map(\.name) == ["api", "web", "docs", "infra"])
        // notes' 8.2 is left out of the rows but not of the total.
        #expect(p.rows.map(\.share) == ["42%", "23%", "15%", "12%"])
        #expect(abs(p.rows[0].fraction - 0.416) < 1e-9)
        #expect(p.rows.map(\.tooltip) == ["~/code/api", "~/code/web", "~/code/docs", "~/code/infra"])
        #expect(p.caption.isEmpty)
    }

    /// '{0:0}' rounds half away from zero: 12.5% is 13%, where [math]::Round would give 12%.
    @Test func sharesRoundHalfAwayFromZero() throws {
        let p = try #require(projects(usage([("/a", 1), ("/b", 3), ("/c", 4)])))
        #expect(p.rows.map(\.share) == ["13%", "38%", "50%"])
    }

    /// Math.Max(2, 70 × share) keeps a sliver of bar for the smallest project.
    @Test func aTinyShareKeepsTwoUnitsOfBar() throws {
        let p = try #require(projects(usage([("/big", 999), ("/tiny", 1)])))
        #expect(p.rows[1].fraction == 2 / ProjectsView.trackWidth)
        #expect(p.rows[1].share == "0%")
    }

    @Test func theHomeFolderIsATilde() throws {
        let p = try #require(projects(usage([(Samples.home, 2), ("/srv/work", 1)])))
        #expect(p.rows.map(\.name) == ["~", "work"])
        #expect(p.rows.map(\.tooltip) == ["~", "/srv/work"])
    }

    /// The original sums folders by their last part; ClawBar keeps them apart and names them by their parent too.
    @Test func rowsOfTheSameNameShowTheirParent() throws {
        let p = try #require(projects(usage([
            ("/Users/example/work/app", 3), ("/Users/example/play/app", 2), ("/Users/example/docs", 1),
        ])))
        #expect(p.rows.map(\.name) == ["work/app", "play/app", "docs"])
    }

    /// A folder whose replies named no working folder keeps its transcript folder's name.
    @Test func aTranscriptFolderNameStaysWhole() throws {
        let p = try #require(projects(usage([("-Users-example-gone", 1)])))
        #expect(p.rows.map(\.name) == ["-Users-example-gone"])
    }

    @Test(arguments: Lang.allCases)
    func theLabelSaysHowManyRepliesWereEstimated(lang: Lang) throws {
        let p = try #require(projects(usage([("/a", 1)], unpriced: 3), lang: lang))
        let lines = p.tooltip.components(separatedBy: "\n")
        #expect(lines == [L10n.t(.histProjTip, lang), L10n.t(.histUnpriced, lang, L10n.count(3, .pluralReply, lang))])
        #expect(lines[1].hasPrefix(lang == .en ? "3 replies " : "3 Antworten "))
    }
}
