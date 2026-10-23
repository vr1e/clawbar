import CoreGraphics
import Testing
@testable import ClawBar
import ClawBarShared

@MainActor
@Suite struct TooltipLayoutTests {
    func regions(_ card: LaidOutCard, hearts: Bool = true) -> [TooltipID: CGRect] {
        let list = TooltipLayout.regions(
            rects: card.layout.rects, view: card.app.view, heartsVisible: hearts,
            mascotVisible: card.app.mascotVisible, skyVisible: card.app.skyVisible, scale: card.k
        )
        return Dictionary(list.map { ($0.id, $0.rect) }, uniquingKeysWith: { a, _ in a })
    }

    @Test func theHeaderButtonsTheHeartsTheSessionsAndTheStatusHaveTooltips() throws {
        let card = LaidOutCard()
        let r = regions(card)
        for id in [HitID.details, .hide, .exit, .hearts, .sessions, .status, .account] {
            #expect(r[.hit(id)] == (try card.rect(id)), "\(id)")
        }
        // Collapsed details: no version lines to hover.
        #expect(r[.hit(.version)] == nil && r[.hit(.appVersion)] == nil)
    }

    @Test func emptyTooltipsAndHiddenRowsRegisterNothing() {
        var v = WidgetViewState.sample
        v.sessionsTooltip = ""
        v.statusVisible = false
        v.resetTooltip = ""
        let card = LaidOutCard(v)
        let r = regions(card, hearts: false)
        #expect(r[.hit(.sessions)] == nil)
        #expect(r[.hit(.status)] == nil)
        #expect(r[.hit(.reset)] == nil)
        #expect(r[.hit(.hearts)] == nil)
    }

    @Test func theResetLineAndTheVersionLinesGetTheirsWhenShown() throws {
        var v = WidgetViewState.sample
        v.resetTooltip = "why"
        v.detailsExpanded = true
        let card = LaidOutCard(v)
        let r = regions(card)
        #expect(r[.hit(.reset)] == (try card.rect(.reset)))
        #expect(r[.hit(.version)] == (try card.rect(.version)))
        #expect(r[.hit(.appVersion)] == (try card.rect(.appVersion)))
    }

    @Test func eachProjectRowHasItsPathAndTheLabelSaysHowTheyAreWeighed() throws {
        var v = WidgetViewState.sample
        v.detailsExpanded = true
        v.history = HistoryView(label: "LIMITS · 7 DAYS")
        v.projects = ProjectsView(label: "PROJECTS · 7 DAYS", tooltip: "estimated", rows: ["api", "web", "docs"].map {
            ProjectRow(name: $0, share: "33%", fraction: 0.33, tooltip: "~/code/\($0)")
        })
        let card = LaidOutCard(v)
        let r = regions(card)
        #expect(r[.hit(.projectsLabel)] == (try card.rect(.projectsLabel)))
        let block = try card.rect(.projects)
        let rows = try (0 ..< 3).map { try #require(r[.project($0)], "row \($0)") }
        #expect(rows.allSatisfy { $0.minX == block.minX && $0.width == block.width })
        #expect(rows[0].minY == block.minY && abs(rows[2].maxY - block.maxY) < 0.01)
        #expect(abs(rows[1].minY - rows[0].maxY) < 0.01 && abs(rows[0].height - rows[1].height) < 0.01)
        #expect(r[.project(3)] == nil)
        func text(_ id: TooltipID) -> String { TooltipLayout.text(id, view: v, hearts: .hidden) { "" } }
        #expect(text(.hit(.projectsLabel)) == "estimated")
        #expect((0 ..< 4).map { text(.project($0)) } == ["~/code/api", "~/code/web", "~/code/docs", ""])
    }

    @Test func countingProjectsHaveOnlyTheLabelsTooltip() {
        var v = WidgetViewState.sample
        v.detailsExpanded = true
        v.history = HistoryView(label: "LIMITS · 7 DAYS")
        v.projects = ProjectsView(label: "PROJECTS · 7 DAYS", tooltip: "estimated", caption: "counting...")
        let r = regions(LaidOutCard(v))
        #expect(r[.hit(.projectsLabel)] != nil)
        #expect(r[.project(0)] == nil)
    }

    @Test func theSkysTooltipCoversTheSkyRightOfTheNumber() throws {
        let card = LaidOutCard()
        let row = try card.rect(.percentRow), number = try card.rect(.number)
        let sky = try #require(regions(card)[.sky])
        #expect(sky.minX == number.maxX && sky.maxX == row.maxX)
        #expect(sky.minY == row.minY && abs(sky.height - 43 * card.k) < 0.01)
        #expect(regions(LaidOutCard(sky: false))[.sky] == nil)
    }

    @Test func textsAreTheCurrentStringsAskedForWhenShown() {
        var v = WidgetViewState.sample
        v.resetTooltip = "reset why"
        let hearts = HeartsFrame(visible: true, shownHalves: 4, tooltip: "a bit tired")
        func text(_ id: TooltipID) -> String { TooltipLayout.text(id, view: v, hearts: hearts) { "sky now" } }
        #expect(text(.hit(.details)) == v.detailsTooltip)
        #expect(text(.hit(.hide)) == v.hideTooltip)
        #expect(text(.hit(.exit)) == v.exitTooltip)
        #expect(text(.hit(.hearts)) == "a bit tired")
        #expect(text(.hit(.reset)) == "reset why")
        #expect(text(.hit(.sessions)) == v.sessionsTooltip)
        #expect(text(.hit(.status)) == v.statusTooltip)
        #expect(text(.hit(.version)) == v.versionTooltip)
        #expect(text(.hit(.appVersion)) == v.appVersionTooltip)
        #expect(text(.hit(.account)) == v.accountTooltip)
        #expect(text(.sky) == "sky now")
    }
}
