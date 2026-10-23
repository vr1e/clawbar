import AppKit
import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

/// The widget's one-line texts in their worst case, measured with the system font at widget.xaml's sizes.
/// SF Pro runs wider than Segoe UI, so what fits here fit the original too.
@MainActor
@Suite struct LayoutFitTests {
    /// The card's content column: 262 − 2 × 1 border − 2 × 12 padding.
    static let column: CGFloat = 236

    private struct Piece {
        var text: String
        var size: CGFloat
        var weight: NSFont.Weight = .regular
    }

    private static let label = { (s: String) in Piece(text: s, size: 9, weight: .semibold) }
    private static let value = { (s: String) in Piece(text: s, size: 10) }

    private static func width(_ p: Piece) -> CGFloat {
        let font = NSFont.systemFont(ofSize: p.size, weight: p.weight)
        return ceil((p.text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Pieces sharing one line with `gap` between them must fit the column.
    private static func expectFits(_ pieces: [Piece], gap: CGFloat = 0, in room: CGFloat = column, _ what: String) {
        let total = pieces.map(width).reduce(0, +) + gap * CGFloat(max(0, pieces.count - 1))
        #expect(total <= room, "\(what): \(pieces.map(\.text)) is \(total) pt, room \(room) pt")
    }

    /// How many lines `text` takes in the column.
    private static func lineCount(_ text: String, size: CGFloat) -> Int {
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: column, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        var lines = 0, glyph = 0
        while glyph < layout.numberOfGlyphs {
            var range = NSRange()
            layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
            glyph = NSMaxRange(range)
            lines += 1
        }
        return lines
    }

    /// Spans that can stand next to a percentage or after "resets in".
    private static let spans: [TimeInterval] = [59 * 60, 4 * 3600 + 59 * 60, 23 * 3600 + 59 * 60, 6 * 86_400 + 23 * 3600]

    @Test(arguments: Lang.allCases)
    func rowLabelsAndValues(lang: Lang) {
        Self.expectFits([Self.label(L10n.t(.uiDay, lang))], "24 h label")
        Self.expectFits([Self.label(L10n.t(.uiWeek7, lang))], "7 d label")
        for span in Self.spans {
            let d = sample {
                $0.weekPercent = 100
                $0.weekReset = Samples.now.addingTimeInterval(span)
                $0.modelWeeks = [ModelWeek(name: "Sonnet", percent: 100, reset: Samples.now.addingTimeInterval(span))]
            }
            let v = render(d, lang: lang)
            Self.expectFits([Self.label(v.week.label), Self.value(v.week.value)], gap: 8, "week row")
            Self.expectFits([Self.label(v.modelWeeks[0].label), Self.value(v.modelWeeks[0].value)], gap: 8, "model week row")
        }
        let none = render(sample { $0.weekPercent = nil }, lang: lang)
        Self.expectFits([Self.label(none.week.label), Self.value(none.week.value)], gap: 8, "week row without data")
    }

    /// Up to 19 sessions with single-digit working and waiting counts: the envelope the original's own English fits.
    /// Beyond it the line ends in an ellipsis, as LineSessions' CharacterEllipsis does.
    @Test(arguments: Lang.allCases)
    func theLongestSessionsLine(lang: Lang) {
        let sessions = (0 ..< 19).map { i in
            SessionInfo(pid: Int32(1000 + i), name: "s\(i)", state: i < 9 ? .busy : i < 18 ? .waiting : .idle)
        }
        let v = render(sample(data: { $0.sessions = sessions }), lang: lang)
        #expect(v.sessionsText.hasPrefix("19 ") && v.sessionsText.contains("9 "))
        // LineSessions sits right of its label, 8 apart.
        Self.expectFits([Self.label(v.sessionsLabel), Self.value(v.sessionsText)], gap: 8, "sessions row")
        let none = render(sample(data: { $0.sessions = [] }), lang: lang)
        Self.expectFits([Self.label(none.sessionsLabel), Self.value(none.sessionsText)], gap: 8, "sessions row, none")
    }

    @Test(arguments: Lang.allCases)
    func theResetLine(lang: Lang) {
        var texts = Self.spans.map { span in render(sample { $0.sessionReset = Samples.now.addingTimeInterval(span) }, lang: lang).resetText }
        texts.append(render(sample { $0.sessionReset = Samples.now.addingTimeInterval(-60) }, lang: lang).resetText)
        texts.append(render(.empty, lang: lang).resetText)
        texts.append(L10n.t(.noData, lang))
        for text in texts {
            Self.expectFits([Piece(text: text, size: 11)], "reset line")
        }
    }

    /// The issue texts replace the reset line and may take two lines, no more.
    @Test(arguments: Lang.allCases)
    func issueTextsWrapToAtMostTwoLines(lang: Lang) {
        let issues: [UsageIssue] = [
            .claudeNotFound, .flagRejected("--no-session-persistence"),
            .modelReached(turns: 12, costUSD: 1.2345, tokens: 99_999),
        ]
        for issue in issues {
            let text = render(sample(data: { $0.usageIssue = issue }), lang: lang).resetText
            let lines = Self.lineCount(text, size: 11)
            #expect(lines <= 2, "\(lang) \(issue): \(lines) lines: \(text)")
        }
    }

    @Test(arguments: Lang.allCases)
    func statusTexts(lang: Lang) {
        // The 7 pt dot and its 6 pt margin come first.
        let room = Self.column - 7 - 6
        for key in [L10nKey.stLoading, .stOffline, .stOk, .stMaint, .stIssues] {
            Self.expectFits([Piece(text: L10n.t(key, lang), size: 10.5)], in: room, "status \(key.rawValue)")
        }
    }

    /// LineVersion shares its row with the ClawBar line, 8 apart. With an update, or after a failed one, it wraps
    /// there as in the original but must still fit the column alone; every other state fits beside the ClawBar line.
    @Test(arguments: Lang.allCases)
    func versionLines(lang: Lang) {
        let clawBar = render(lang: lang).appVersionText
        let beside: [VersionState] = [
            VersionState(local: "2.10.300", latest: "2.10.300"),
            VersionState(local: "2.10.300"),
            VersionState(local: "2.10.300", latest: "2.10.310", updating: true),
        ]
        for state in beside {
            let v = render(sample(data: { $0.version = state }), lang: lang)
            Self.expectFits([Self.value(v.versionText), Self.value(clawBar)], gap: 8, "version row")
        }
        let update = render(sample(data: { $0.version = VersionState(local: "2.10.300", latest: "2.10.310") }), lang: lang)
        Self.expectFits([Self.value(update.versionText)], "version line with an update")
        let failure = UpdateFailure(exitCode: 1, outputTail: "")
        let failed = render(sample(data: { $0.version = VersionState(local: "2.10.300", latest: "2.10.310", updateFailure: failure) }), lang: lang)
        Self.expectFits([Self.value(failed.versionText)], "version line after a failed update")
    }

    @Test(arguments: Lang.allCases)
    func statsCountLines(lang: Lang) {
        let d = sample { $0.day = UsagePeriod(requests: 88_888, sessions: 888) }
        Self.expectFits([Piece(text: render(d, lang: lang).dayMain, size: 10.5)], "24 h counts")
    }

    /// The chart's label, its legend with the four-space gap between entries, and the empty week's caption.
    @Test(arguments: Lang.allCases)
    func theChartTexts(lang: Lang) throws {
        let config = Config(expanded: true, showHistory: true)
        let h = try #require(render(sample(data: { $0.history = Samples.history }), config: config, lang: lang).history)
        Self.expectFits([Self.label(h.label)], "chart label")
        let legend = [h.sessionName, h.weekName].flatMap { [Self.value("━ "), Self.value($0)] }
        Self.expectFits(legend, in: Self.column - 11, "chart legend")
        let empty = try #require(render(config: config, lang: lang).history)
        Self.expectFits([Self.value(empty.caption)], "empty chart caption")
    }

    /// The projects' label, the text before the first scan, and a whole week's share in its 34-wide column.
    @Test(arguments: Lang.allCases)
    func theProjectsTexts(lang: Lang) throws {
        let config = Config(expanded: true, showHistory: true)
        let counting = try #require(render(sample(data: { $0.projects = nil }), config: config, lang: lang).projects)
        Self.expectFits([Self.label(counting.label)], "projects label")
        Self.expectFits([Self.value(counting.caption)], "projects counting")
        let one = ProjectUsage(projects: [ProjectWeight(path: "/a", weight: 1)])
        let row = try #require(render(sample(data: { $0.projects = one }), config: config, lang: lang).projects?.rows.first)
        #expect(row.share == "100%")
        Self.expectFits([Self.value(row.share)], in: ProjectsView.shareWidth, "a project's share")
    }

    /// The hover's readout with both limits at 100%, on every weekday.
    @Test(arguments: Lang.allCases)
    func theChartReadout(lang: Lang) {
        var config = Config(expanded: true, showHistory: true)
        config.language = lang.rawValue
        let now = UsageSample.minute(of: Samples.now)
        for day in 0 ..< 7 {
            let minute = now - day * 1440
            let data = sample(data: { $0.history = [UsageSample(minute: minute, session: 100, week: 100)] })
            let input = PresenterInput(config: config, now: Samples.now, timeZone: Samples.timeZone, data: data)
            let chart = HistoryView(label: "", start: minute, end: minute + 236)
            Self.expectFits([Self.value(HistoryReadout.hover(x: 0, chart: chart, input: input).caption)], "chart readout")
        }
    }

    /// A weekday is centred in its slot: it fits a whole day, and in the narrowest slot that shows one it spills no
    /// further than the card's 12-pt padding.
    @Test(arguments: Lang.allCases)
    func weekdaysUnderTheChart(lang: Lang) {
        for n in 0 ... 6 {
            let w = Self.width(Piece(text: L10n.weekday(n, lang), size: 8))
            #expect(w <= Self.column / 7, "\(lang) \(n): \(w) pt")
            #expect((w - 14) / 2 <= 12, "\(lang) \(n): \(w) pt")
        }
    }

    @Test(arguments: Lang.allCases)
    func theFooter(lang: Lang) {
        let late = Samples.now.addingTimeInterval(3600)
        let loggedOut = render(sample(data: { $0.account = AccountInfo(loggedIn: false) }), lang: lang, now: late)
        #expect(loggedOut.stampText.contains(" · "))
        // LineAccount keeps 8 pt to the stamp.
        Self.expectFits([Piece(text: loggedOut.accountText, size: 9), Piece(text: loggedOut.stampText, size: 9)], gap: 8, "footer")
        Self.expectFits([Piece(text: render(lang: lang, tickError: true).stampText, size: 9)], "error stamp")
    }
}
