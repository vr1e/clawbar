import CoreGraphics
import Foundation

/// Hand-made, consistent sample values for tests, snapshots and recordings. No real person, path, address or location.
public enum Samples {
    /// 2026-10-17 12:05:00 UTC.
    public static let now = Date(timeIntervalSince1970: 1_792_238_700)
    public static let timeZone = TimeZone(identifier: "Europe/Berlin")!
    public static let home = "/Users/example"

    /// A week of samples every 5 minutes up to `now`, Berlin time: a 5-hour window each morning and weekday afternoon,
    /// the week rising with them, resetting Thursday 06:00 and ending at the sample's 34% and 59%; asleep Tue–Wed night.
    public static let history: [UsageSample] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func minute(_ unix: TimeInterval) -> Int { UsageSample.minute(of: Date(timeIntervalSince1970: unix)) }
        let end = UsageSample.minute(of: now)
        // Thursday 2026-10-15 06:00, a week before the sample's reset; Tuesday 23:40 to Wednesday 07:40.
        let weekReset = minute(1_792_036_800)
        let asleep = minute(1_791_927_600) ..< minute(1_791_956_400)
        // Each weekday's windows from Sunday: the local minute it opens and the percent each minute of work adds.
        // Saturday's opens at 11:10 to reach 34% at 14:05; Tuesday morning hits the limit.
        let morning = 9 * 60 + 10, afternoon = 14 * 60 + 20, late = 11 * 60 + 10
        let windows: [[(start: Int, rate: Double)]] = [
            [(late, 0.15)],
            [(morning, 0.30), (afternoon, 0.24)],
            [(morning, 0.42), (afternoon, 0.30)],
            [(morning, 0.25), (afternoon, 0.20)],
            [(morning, 0.33), (afternoon, 0.26)],
            [(morning, 0.20), (afternoon, 0.16)],
            [(late, 34.0 / 175)],
        ]
        func session(_ minute: Int) -> Int {
            let c = calendar.dateComponents([.weekday, .hour, .minute], from: UsageSample(minute: minute).date)
            let local = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            for w in windows[(c.weekday ?? 1) - 1] {
                let into = local - w.start
                // Four hours of work, then the number stays until the window resets an hour later.
                if (0 ..< 300).contains(into) { return Int(min(100, w.rate * Double(min(into, 240))).rounded(.toNearestOrEven)) }
            }
            return 0
        }
        let minutes = stride(from: end - 7 * 1440, through: end, by: 5).filter { !asleep.contains($0) }
        let sessions = minutes.map(session)
        // The week grows by what the session spends: from 41% to 78% before its reset, then from 0 to 59%.
        func spent(_ r: Range<Int>) -> [Double] {
            var total = 0.0
            return r.map { i in
                if i > 0 { total += Double(max(0, sessions[i] - sessions[i - 1])) }
                return total
            }
        }
        let reset = minutes.firstIndex { $0 >= weekReset }!
        let before = spent(0 ..< reset), after = spent(reset ..< minutes.count)
        let week = before.map { 41 + 37 * $0 / before.last! } + after.map { 59 * $0 / after.last! }
        return minutes.indices.map { i in
            UsageSample(minute: minutes[i], session: sessions[i], week: Int(week[i].rounded(.toNearestOrEven)))
        }
    }()

    /// Five projects of the week, heaviest first, so the top 4 leave one out.
    public static let projects = ProjectUsage(projects: [
        ProjectWeight(path: "\(home)/code/api", weight: 41.6),
        ProjectWeight(path: "\(home)/code/web", weight: 23.4),
        ProjectWeight(path: "\(home)/code/docs", weight: 14.7),
        ProjectWeight(path: "\(home)/code/infra", weight: 12.1),
        ProjectWeight(path: "\(home)/notes", weight: 8.2),
    ])
}

extension DataSnapshot {
    public static let sample = DataSnapshot(
        usage: UsageSnapshot(
            sessionPercent: 34,
            weekPercent: 59,
            sessionReset: Samples.now.addingTimeInterval(2 * 3600 + 5 * 60),
            weekReset: Date(timeIntervalSince1970: 1_792_641_600),
            modelWeeks: [ModelWeek(name: "Fable", percent: 8, reset: Date(timeIntervalSince1970: 1_792_641_600))],
            day: UsagePeriod(requests: 3875, sessions: 23, lines: [
                "87% of your usage came from subagent-heavy sessions",
                "74% of your usage was at max effort",
                "Top plugins: alpha 12%",
            ]),
            week7: UsagePeriod(requests: 7589, sessions: 96, lines: [
                "82% of your usage came from subagent-heavy sessions",
                "70% of your usage was at >150k context",
                "Top subagents: helper 35%, reviewer 7%, +1 more",
            ])
        ),
        usageAt: Samples.now.addingTimeInterval(-25),
        usageProbeCompleted: true,
        sessions: [
            SessionInfo(
                pid: 4242, sessionId: "00000000-0000-4000-8000-000000000001", name: "clawbar",
                cwd: "/Users/example/Dev/clawbar", state: .busy, kind: "interactive",
                startedAt: Samples.now.addingTimeInterval(-3600)
            ),
            SessionInfo(
                pid: 4343, sessionId: "00000000-0000-4000-8000-000000000002", name: "notes",
                cwd: "/Users/example/notes", state: .waiting, waitingFor: "permission", kind: "interactive",
                startedAt: Samples.now.addingTimeInterval(-600)
            ),
        ],
        sessionsRead: true,
        status: ServiceStatus(indicator: "none"),
        statusAt: Samples.now.addingTimeInterval(-40),
        account: AccountInfo(loggedIn: true, plan: "Max", email: "user@example.com"),
        version: VersionState(local: "2.1.302", latest: "2.1.302"),
        weather: WeatherSnapshot(
            code: 2, tempC: 14.6, windKmh: 11.2, sunriseMin: 441, sunsetMin: 1079,
            timeZoneID: "Europe/Berlin", at: Samples.now.addingTimeInterval(-300)
        ),
        place: Place(lat: 52.52, lon: 13.405, city: "Berlin", timeZoneID: "Europe/Berlin")
    )
}

extension WidgetViewState {
    /// Before the first probe answers.
    public static let placeholder = WidgetViewState(
        detailsTooltip: "Details", hideTooltip: "Hide", exitTooltip: "Quit",
        resetText: "loading...",
        gameCaption: "The limit has reset: back to work!",
        week: BarRow(label: "WEEK", value: "no data", fraction: 0, color: Palette.weekBar),
        sessionsText: "none running",
        statusText: "status: loading...", statusTooltip: "Open status.claude.com",
        dayLabel: "LAST 24 HOURS · THIS COMPUTER", dayMain: "no data",
        week7Label: "LAST 7 DAYS", week7Main: "no data",
        appVersionTooltip: "macOS port of clawd-usage-winwidget 1.3.0, with some features of later releases (MIT)",
        trayTooltip: "ClawBar: no data"
    )

    /// `DataSnapshot.sample` at `Samples.now` in Berlin, rendered by hand.
    public static let sample = WidgetViewState(
        detailsTooltip: "Details", hideTooltip: "Hide", exitTooltip: "Quit",
        pctText: "34", pctColor: Palette.ok, sessionFraction: 0.34, sessionBarColor: Palette.ok,
        resetText: "resets in 2h 05m",
        gameCaption: "The limit has reset: back to work!",
        week: BarRow(label: "WEEK", value: "59%  ·  4d 15h", fraction: 0.59, color: Palette.weekBar),
        modelWeeks: [BarRow(label: "FABLE · WEEK", value: "8%  ·  4d 15h", fraction: 0.08, color: Palette.modelWeekBar)],
        sessionsText: "2 sessions  ·  1 working  ·  1 waiting",
        sessionsTooltip: "▶ clawbar — ~/Dev/clawbar\n? notes [permission] — ~/notes",
        statusDotColor: Palette.ok, statusText: "All Claude systems operational", statusTextColor: Palette.muted,
        statusTooltip: "Open status.claude.com",
        dayLabel: "LAST 24 HOURS · THIS COMPUTER", dayMain: "3875 requests  ·  23 sessions",
        dayExtra: "87% subagent-heavy sessions  ·  74% at max effort  ·  plugins: alpha 12%",
        week7Label: "LAST 7 DAYS", week7Main: "7589 requests  ·  96 sessions",
        week7Extra: "82% subagent-heavy sessions  ·  70% at >150k context  ·  subagents: helper 35%, reviewer 7%, +1 more",
        versionText: "v2.1.302  ·  latest", versionColor: Palette.muted,
        versionTooltip: "Click for the Claude Code changelog", versionAction: .open(AppInfo.changelogPage),
        appVersionTooltip: "macOS port of clawd-usage-winwidget 1.3.0, with some features of later releases (MIT)",
        accountText: "Max  ·  user@example.com", accountTooltip: "Max  ·  user@example.com",
        stampText: "14:04:35",
        trayText: "34", trayColor: Palette.ok,
        trayTooltip: "34% of session · 2h 05m (16:10)\nweek 59% · 4d 15h (Thu 06:00)\nFable 8% · 4d 15h (Thu 06:00)\n2 sessions · 1 working · 1 waiting"
    )
}

extension ClawdFrame {
    /// Clawd standing still 60 pt into the play area; 34% used leaves 4 halves.
    public static let sample: ClawdFrame = {
        let origin = CGPoint(x: 60, y: 4.4 - 26.4)
        return ClawdFrame(
            ops: [
                .rects(PixelArt.rects(PixelArt.clawdStanding, value: "#", px: 2.0, py: 2.2, origin: origin), Palette.clawdBody, opacity: 1),
                .rects(PixelArt.rects(PixelArt.clawdStanding, value: "o", px: 2.0, py: 2.2, origin: origin), Palette.clawdEyes, opacity: 1),
            ],
            spriteRect: CGRect(x: origin.x, y: origin.y, width: 36, height: 26.4),
            hearts: HeartsFrame(visible: true, shownHalves: 4, tooltip: "a bit tired · 66% of the session limit left")
        )
    }()
}

extension SkyFrame {
    /// A partly cloudy midday: the sun high on its arc and one cloud.
    public static let sample = SkyFrame(
        top: RGBA("#004A8CCB"),
        bottom: RGBA("#2E6FA8D8"),
        ops: [
            .radialGlow(CGRect(x: 108, y: 5, width: 20, height: 20), inner: RGBA("#40FDE68A"), outer: RGBA("#00FDE68A"), opacity: 0.4),
            .rects(
                PixelArt.rects(["..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###.."],
                               value: "#", px: 1.4, py: 1.4, origin: CGPoint(x: 113.1, y: 10.1)),
                RGBA("#FFFDE68A"), opacity: 0.4
            ),
            .rects(
                PixelArt.rects(["..###...", ".######.", "########"], value: "#", px: 2, py: 2, origin: CGPoint(x: 40, y: 8)),
                RGBA("#FFB4B4BC"), opacity: 0.65
            ),
        ]
    )
}
