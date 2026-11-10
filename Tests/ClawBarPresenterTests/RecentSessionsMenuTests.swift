import Foundation
import Testing
@testable import ClawBarPresenter
import ClawBarShared

/// The Recent sessions submenu's items over the sample: two live sessions, then three that ended.
@Suite struct RecentSessionsMenuTests {
    func items(_ data: DataSnapshot = .sample, lang: Lang = .en, terminal: Bool = true, home: String = Samples.home) -> [RecentSessionItem] {
        RecentSessionsMenu.items(
            PresenterInput(
                config: Config(language: lang.rawValue), now: Samples.now, timeZone: Samples.timeZone, data: data, homeDirectory: home
            ),
            terminal: terminal
        )
    }

    func ended(_ n: Int, title: String = "Title", cwd: String = "/Users/example/api", ago: TimeInterval = 300) -> RecentSession {
        RecentSession(
            sessionId: String(format: "00000000-0000-4000-8000-%012d", n), title: title, titleSource: .ai, cwd: cwd,
            lastActivity: Samples.now - ago, lastPrompt: "prompt \(n)"
        )
    }

    func ago(_ seconds: TimeInterval, _ lang: Lang = .en) -> String {
        Ago.text(since: Samples.now - seconds, now: Samples.now, timeZone: Samples.timeZone, lang: lang)
    }

    @Test func anItemSaysWhatWhereAndHowLongAgo() {
        #expect(items().map(\.title) == [
            "● Menu bar tooltip wording · ~/Dev/clawbar · now",
            "● Reading list · ~/notes · 12m",
            "○ Rate limiter for the API · ~/code/api · 2h",
            "○ Release notes draft · ~/code/docs · yesterday",
            "○ infra · ~/code/infra · 3d",
        ])
        #expect(items(lang: .de).map(\.title) == [
            "● Menu bar tooltip wording · ~/Dev/clawbar · jetzt",
            "● Reading list · ~/notes · 12min",
            "○ Rate limiter for the API · ~/code/api · 2h",
            "○ Release notes draft · ~/code/docs · gestern",
            "○ infra · ~/code/infra · 3d",
        ])
        #expect(items().map(\.sessionId) == DataSnapshot.sample.recentSessions.map(\.sessionId))
    }

    @Test func thePromptShowsInTheTooltipAloneAboveWhatAClickDoes() {
        let all = items()
        #expect(all[0].tooltip == """
            Shorten the stale line in the tooltip and keep the reset times

            Running in ~/Dev/clawbar
            Click to bring its Ghostty tab forward
            """)
        #expect(all[2].tooltip == "Add a token bucket per API key and a test for the refill\n\nClick to resume in a new Ghostty tab")
        #expect(all.map(\.click) == [.focus, .focus, .resume, .resume, .resume])
        for (item, session) in zip(all, DataSnapshot.sample.recentSessions) {
            #expect(!item.title.contains(session.lastPrompt))
        }
        let de = items(lang: .de)
        #expect(de[1].tooltip == "Sort the reading list by topic\n\nLäuft in ~/notes\nKlicken, um den Ghostty-Tab nach vorn zu holen")
        #expect(de[3].tooltip.hasSuffix("\n\nKlicken, um in einem neuen Ghostty-Tab fortzusetzen"))
    }

    @Test func withoutATerminalAClickCopiesAndALiveSessionOnlyInforms() {
        let all = items(terminal: false)
        #expect(all.map(\.click) == [nil, nil, .resume, .resume, .resume])
        #expect(all[0].tooltip == "Shorten the stale line in the tooltip and keep the reset times\n\nRunning in ~/Dev/clawbar")
        #expect(all[2].tooltip.hasSuffix("\n\nClick to copy the command that resumes it"))
        #expect(items(lang: .de, terminal: false)[2].tooltip.hasSuffix("\n\nKlicken, um den Befehl zum Fortsetzen zu kopieren"))
    }

    @Test func theNewestFifteenShow() {
        var data = DataSnapshot.sample
        data.recentSessions = (1 ... 20).map { ended($0, title: "Session \($0)", ago: TimeInterval($0 * 60)) }
        let all = items(data)
        #expect(all.count == RecentSessionsMenu.limit && all.count == 15)
        #expect(all.first?.title == "○ Session 1 · ~/api · 1m" && all.last?.title == "○ Session 15 · ~/api · 15m")
        data.recentSessions = []
        #expect(items(data).isEmpty)
    }

    @Test func aLongTitleIsCutAndAMissingFolderOrPromptLeftOut() {
        var data = DataSnapshot.sample
        var bare = ended(1, title: String(repeating: "word ", count: 30), cwd: "")
        bare.lastPrompt = ""
        data.recentSessions = [bare, ended(2, cwd: "/opt/work")]
        let all = items(data)
        #expect(all[0].title == "○ " + String(repeating: "word ", count: 12).dropLast() + "… · 5m")
        #expect(all[0].tooltip == "Click to resume in a new Ghostty tab")
        // Outside the home folder, and with no home at all, the path is whole.
        #expect(all[1].title == "○ Title · /opt/work · 5m")
        #expect(items(home: "")[1].title == "● Reading list · /Users/example/notes · 12m")
    }

    @Test func theTimeGoesFromNowToMinutesHoursYesterdayAndDays() {
        #expect([0, 59].map { ago($0) } == ["now", "now"])
        #expect([60, 3599].map { ago($0) } == ["1m", "59m"])
        #expect([3600, 86_399].map { ago($0) } == ["1h", "23h"])
        // The sample is 14:05 in Berlin: a day ago is yesterday, and so is yesterday's first minute, 38 hours ago.
        #expect([86_400, 38 * 3600].map { ago($0) } == ["yesterday", "yesterday"])
        #expect([39 * 3600, 6 * 86_400].map { ago($0) } == ["2d", "6d"])
        // A clock that ran ahead is now, not a negative time.
        #expect(ago(-30) == "now")
        #expect([30, 300, 7200, 90_000, 200_000].map { ago($0, .de) } == ["jetzt", "5min", "2h", "gestern", "2d"])
    }

    @Test func theWidgetsHoverListNamesALiveSessionByItsTitle() {
        #expect(render().tooltip(.sessions) == "▶ Menu bar tooltip wording — ~/Dev/clawbar\n? Reading list [permission] — ~/notes")
        // A title that is only the folder's leaf says less than the registry's name; so does none at all.
        var data = DataSnapshot.sample
        data.recentSessions[0].title = "clawbar"
        data.recentSessions[0].titleSource = .folder
        data.recentSessions.remove(at: 1)
        #expect(render(data).tooltip(.sessions) == "▶ clawbar — ~/Dev/clawbar\n? notes [permission] — ~/notes")
        #expect(render(data, config: Config(showSessions: false)).tooltip(.sessions) == nil)
    }
}
