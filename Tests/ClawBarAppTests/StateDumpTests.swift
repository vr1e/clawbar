import CoreGraphics
import Foundation
import Testing
@testable import ClawBar
import ClawBarShared

@Suite struct StateDumpTests {
    func dump(panel: CGRect = CGRect(x: 1178, y: 609, width: 314, height: 340)) -> StateDump {
        StateDump(
            nonce: "N1", pid: 4242, statusItemVisible: true, statusItemFrame: CGRect(x: 1200, y: 949, width: 52, height: 33),
            widgetVisible: true, occluded: false, panelFrame: panel,
            screenFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)], topLeft: CGPoint(x: 1178, y: 33),
            animating: true, tickMilliseconds: 90, config: Config(), loginItemStatus: "enabled", installedApp: true,
            snapshot: .sample, view: .sample, home: Samples.home
        )
    }

    @Test func theDumpReportsTheItemTheWindowTheLoginItemAndTheNumbers() {
        let text = dump().render()
        for line in [
            "nonce: N1", "statusItem.visible: true", "widget.visible: true", "widget.onScreen: true",
            "widget.topLeft: 1178, 33", "loginItem.status: enabled", "usage.session: 34", "usage.week: 59",
            "usage.modelWeeks: Fable 8", "sessions: 2 (busy 1, waiting 1), read: true", "status.indicator: none",
            "view.pct: 34", "view.tray: 34", "config.scale: 1.20",
            "view.trayTooltip: 34% of session · 2h 05m (16:10)\\nweek 59% · 4d 15h (Thu 06:00)\\nFable 8% · 4d 15h (Thu 06:00)\\n2 sessions · 1 working · 1 waiting",
        ] {
            #expect(text.contains(line + "\n"), "\(line)")
        }
    }

    @Test func theHistoryIsReportedByItsSpan() {
        #expect(dump().render().contains("\nusage.history: none\n"))
        var d = dump()
        let m = UsageSample.minute(of: Samples.now)
        d.snapshot.history = [UsageSample(minute: m - 60, session: 30, week: 58), UsageSample(minute: m, session: 34, week: 59)]
        let from = StateDump.iso(Samples.now - 3600), to = StateDump.iso(Samples.now)
        #expect(d.render().contains("\nusage.history: 2 samples, \(from) to \(to)\n"))
    }

    @Test func theProjectsAreReportedByCountNotByName() {
        #expect(dump().render().contains("\nprojects: none\n"))
        var d = dump()
        d.snapshot.projects = ProjectUsage(projects: [ProjectWeight(path: "/Users/example/secret", weight: 1)])
        d.snapshot.projectsAt = Samples.now
        let text = d.render()
        #expect(text.contains("\nprojects: 1, scanned \(StateDump.iso(Samples.now))\n"))
        #expect(!text.contains("secret"))
    }

    @Test func theAppLineEndsInThePidThatBuildAppWaitsOn() {
        // scripts/build-app.sh --install reads the running copy's pid from this line.
        #expect(dump().render().contains("\napp: \(AppInfo.title) (pid 4242)\n"))
    }

    @Test func aWindowOffEveryScreenIsReported() {
        #expect(dump(panel: CGRect(x: 4000, y: 100, width: 314, height: 340)).render().contains("widget.onScreen: false\n"))
    }

    @Test func personalDataIsRedacted() {
        let text = dump().render()
        #expect(!text.contains("user@example.com"))
        #expect(text.contains("account: Max · u…@example.com"))
        #expect(!text.contains(Samples.home))
    }

    @Test func onlyTheAnswerToThisRequestCounts() {
        #expect(RemoteControl.answer("nonce: A\nx: 1\n", nonce: "A") == "x: 1\n")
        #expect(RemoteControl.answer("nonce: B\nx: 1\n", nonce: "A") == nil)
        #expect(RemoteControl.answer("", nonce: "A") == nil)
    }

    @Test func withoutARunningInstanceCommandsFailFast() {
        let tmp = TempDir()
        let paths = AppPaths(root: tmp.url)
        #expect(RemoteControl.send(.toggle, paths: paths) == 1)
        #expect(RemoteControl.dumpState(paths: paths, timeout: 0.2) == 1)
    }
}
