import CoreGraphics
import Foundation

/// Hand-made, consistent sample values for tests, snapshots and recordings. No real person, path, address or location.
public enum Samples {
    /// 2026-10-17 12:05:00 UTC.
    public static let now = Date(timeIntervalSince1970: 1_792_238_700)
    public static let timeZone = TimeZone(identifier: "Europe/Berlin")!
    public static let home = "/Users/example"
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
        week: BarRow(label: "WEEK", value: "no data", fraction: 0, color: Palette.weekBar),
        sessionsText: "none running",
        statusText: "status: loading...", statusTooltip: "Open status.claude.com",
        dayLabel: "LAST 24 HOURS · THIS COMPUTER", dayMain: "no data",
        week7Label: "LAST 7 DAYS", week7Main: "no data",
        appVersionTooltip: "macOS port of clawd-usage-winwidget 1.3.0 (MIT)",
        trayTooltip: "ClawBar: no data"
    )

    /// `DataSnapshot.sample` at `Samples.now` in Berlin, rendered by hand.
    public static let sample = WidgetViewState(
        detailsTooltip: "Details", hideTooltip: "Hide", exitTooltip: "Quit",
        pctText: "34", pctColor: Palette.ok, sessionFraction: 0.34, sessionBarColor: Palette.ok,
        resetText: "resets in 2h 05m",
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
        appVersionTooltip: "macOS port of clawd-usage-winwidget 1.3.0 (MIT)",
        accountText: "Max  ·  user@example.com", accountTooltip: "Max  ·  user@example.com",
        stampText: "14:04:35",
        trayText: "34", trayColor: Palette.ok,
        trayTooltip: "34% of session · 2h 05m\nweek 59% · Fable 8%\n2 sessions · 1 working · 1 waiting"
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
