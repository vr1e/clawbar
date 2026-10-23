import Foundation
import ClawBarShared

/// Every render rule of update.ps1 and format.ps1, as a pure function of its input.
public enum WidgetPresenter {
    public static func make(_ input: PresenterInput) -> WidgetViewState {
        Render(input).state()
    }
}

/// One render: the input, its clamped config and its language, read once.
private struct Render {
    let input: PresenterInput
    let cfg: Config
    let lang: Lang
    let data: DataSnapshot
    let now: Date

    init(_ input: PresenterInput) {
        self.input = input
        cfg = input.config.clamped()
        lang = cfg.lang
        data = input.data
        now = input.now
    }

    func state() -> WidgetViewState {
        var v = WidgetViewState()
        header(&v)
        session(&v)
        weeks(&v)
        sessions(&v)
        status(&v)
        details(&v)
        version(&v)
        footer(&v)
        return v
    }

    // MARK: Sections, in update.ps1's order

    private func header(_ v: inout WidgetViewState) {
        v.title = "CLAUDE USAGE"
        v.detailsGlyph = cfg.expanded ? "▴" : "▾"
        v.detailsTooltip = t(.uiDetails)
        v.hideTooltip = t(.uiHide)
        v.exitTooltip = t(.uiExit)
        v.detailsExpanded = cfg.expanded
    }

    /// The percent row, the session bar, the reset line and the menu bar item.
    private func session(_ v: inout WidgetViewState) {
        sessionNumbers(&v)
        v.trayMascot = cfg.menuBarMascot
        explain(data.usageIssue, &v)
        // The game only opens at the limit, so once it is gone the limit has reset.
        v.gameCaption = v.limitReached ? v.resetText : t(.gameBack)
        // With the widget hidden, the menu bar still tells that a session waits.
        if cfg.showSessions, let counts = sessionCounts() { v.trayTooltip += "\n" + counts.joined(separator: " · ") }
    }

    private func sessionNumbers(_ v: inout WidgetViewState) {
        let usage = data.usageIssue?.voidsLimits == true ? nil : data.usage
        v.resetColor = Palette.secondary
        v.resetTooltip = ""
        guard let usage, let pct = usage.sessionPercent else {
            v.pctText = "--"
            v.pctColor = Palette.dead
            v.sessionFraction = 0
            v.sessionBarColor = Palette.dead
            v.resetText = data.usageProbeCompleted ? t(.noData) : t(.loading)
            v.trayText = "--"
            v.trayColor = Palette.dead
            v.trayTooltip = t(.trayNoData)
            return
        }
        let color = Level.of(pct, warn: cfg.warnPercent, crit: cfg.critPercent).color
        let span = usage.sessionReset.flatMap { Span.text(until: $0, now: now, lang: lang) }
        v.pctText = String(pct)
        v.pctColor = color
        v.sessionFraction = fraction(pct)
        v.sessionBarColor = color
        if let span {
            v.resetText = t(.resetIn, span)
        } else {
            v.resetText = usage.sessionReset == nil ? "" : t(.resetClosed)
        }
        // The widget is often hidden or covered, so the menu bar says stale too; the number tells it from "--".
        let stale = data.usageAt.flatMap(staleStamp)
        v.trayText = String(pct)
        v.trayColor = stale == nil ? color : Palette.dead
        v.trayTooltip = trayTooltip(pct, usage) + (stale.map { "\n" + $0 } ?? "")
        v.limitReached = pct >= 100
        if v.limitReached {
            v.playText = t(.uiPlay)
            v.playTooltip = t(.uiPlayTip)
        }
    }

    /// The plan's issue states. Launch failures, time-outs and failed probes show nothing: the stale stamp covers them.
    private func explain(_ issue: UsageIssue?, _ v: inout WidgetViewState) {
        switch issue {
        case .claudeNotFound:
            stopped(t(.errNoClaude), &v)
            v.trayTooltip = t(.errNoClaude)
        case .noLimits:
            v.resetText = t(.noData)
            v.resetTooltip = t(.issueNoLimits)
            v.trayTooltip = t(.trayNoData) + "\n" + t(.issueNoLimits)
        case .flagRejected(let option):
            paused(t(.issueFlagRejected, option), &v)
        case .modelReached(let turns, let cost, _):
            paused(t(.issueModelReached, turns, money(cost)), &v)
        case .launchFailed, .timedOut, .probeFailed, nil:
            break
        }
    }

    /// An issue that stops the numbers replaces the reset line, in red; the tooltip keeps it whole if the line is cut.
    private func stopped(_ text: String, _ v: inout WidgetViewState) {
        v.resetText = text
        v.resetColor = Palette.crit
        v.resetTooltip = text
    }

    /// A latched probe keeps its last numbers up, so the menu bar also says why they stopped moving.
    private func paused(_ text: String, _ v: inout WidgetViewState) {
        stopped(text, &v)
        v.trayTooltip += "\n" + text
    }

    /// The probe's cost to the hundredth of a cent, with the language's decimal mark.
    private func money(_ usd: Double) -> String {
        let s = String(format: "%.4f", usd)
        return lang == .de ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    /// The session, the week and each model week on lines of their own; no 63-character cap on macOS.
    private func trayTooltip(_ pct: Int, _ usage: UsageSnapshot) -> String {
        var lines = [trayLimit(t(.traySession, pct), usage.sessionReset)]
        if let week = usage.weekPercent { lines.append(trayLimit(t(.trayWeek, week), usage.weekReset)) }
        lines += usage.modelWeeks.map { trayLimit("\($0.name) \($0.percent)%", $0.reset) }
        return lines.joined(separator: "\n")
    }

    /// `week 59% · 4d 15h (Thu 06:00)` while the reset lies ahead, else the label alone.
    private func trayLimit(_ label: String, _ reset: Date?) -> String {
        guard let reset, let span = Span.text(until: reset, now: now, lang: lang) else { return label }
        return "\(label) · \(span) (\(ResetClock.text(reset, now: now, timeZone: input.timeZone, lang: lang)))"
    }

    private func weeks(_ v: inout WidgetViewState) {
        let usage = data.usage
        if let week = usage?.weekPercent {
            v.week = BarRow(
                label: t(.uiWeek), value: limit(week, usage?.weekReset), fraction: fraction(week), color: Palette.weekBar
            )
        } else {
            v.week = BarRow(label: t(.uiWeek), value: t(.noData), fraction: 0, color: Palette.weekBar)
        }
        v.modelWeeks = (usage?.modelWeeks ?? []).map {
            BarRow(
                label: t(.uiModelWeek, $0.name.uppercased()), value: limit($0.percent, $0.reset),
                fraction: fraction($0.percent), color: Palette.modelWeekBar
            )
        }
    }

    /// `59%`, plus `  ·  4d 15h` while the reset lies ahead.
    private func limit(_ pct: Int, _ reset: Date?) -> String {
        guard let reset, let span = Span.text(until: reset, now: now, lang: lang) else { return "\(pct)%" }
        return "\(pct)%  ·  \(span)"
    }

    private func sessions(_ v: inout WidgetViewState) {
        v.sessionsVisible = cfg.showSessions
        v.sessionsLabel = t(.uiSessions)
        v.sessionsText = sessionCounts()?.joined(separator: "  ·  ") ?? t(.sessNone)
        v.sessionsTooltip = data.sessions.map(sessionLine).joined(separator: "\n")
    }

    /// How many sessions, then how many work and wait; nil without any.
    private func sessionCounts() -> [String]? {
        guard !data.sessions.isEmpty else { return nil }
        let busy = data.count(of: .busy), waiting = data.count(of: .waiting)
        var parts = [L10n.count(data.sessions.count, .pluralSession, lang)]
        // Someone waiting matters more than "0 working", and keeps the line short.
        if busy > 0 || waiting == 0 { parts.append(t(.sessBusy, busy)) }
        if waiting > 0 { parts.append(t(.sessWait, waiting)) }
        return parts
    }

    /// `▶ name — ~/cwd`, with ` [what]` for a session that waits for something.
    private func sessionLine(_ s: SessionInfo) -> String {
        let mark = switch s.state {
        case .busy: "▶"
        case .waiting: "?"
        case .idle: "○"
        }
        var line = "\(mark) \(s.name)"
        if s.state == .waiting, let what = s.waitingFor, !what.isEmpty { line += " [\(what)]" }
        if !s.cwd.isEmpty { line += " — " + HomePath.relative(s.cwd, home: input.homeDirectory) }
        return line
    }

    private func status(_ v: inout WidgetViewState) {
        v.statusVisible = cfg.showStatus
        v.statusTooltip = t(.uiOpenStatus)
        v.statusURL = AppInfo.statusPage
        v.statusLine2 = ""
        let stale = DataSnapshot.isStale(data.statusAt, interval: cfg.statusIntervalSeconds, now: now)
        guard let st = data.status, !stale else {
            v.statusDotColor = Palette.dead
            v.statusText = data.status == nil ? t(.stLoading) : t(.stOffline)
            v.statusTextColor = Palette.muted
            return
        }
        // PowerShell's -eq and -in ignore case.
        let indicator = st.indicator.lowercased()
        if indicator == "none", st.broken.isEmpty, st.incidents.isEmpty {
            v.statusDotColor = Palette.ok
            v.statusText = t(.stOk)
            v.statusTextColor = Palette.muted
            return
        }
        v.statusDotColor = ["major", "critical"].contains(indicator) ? Palette.crit : Palette.warn
        v.statusTextColor = Palette.secondary
        if !st.incidents.isEmpty {
            v.statusText = st.incidents.joined(separator: "  ·  ")
        } else {
            v.statusText = indicator == "maintenance" ? t(.stMaint) : t(.stIssues)
        }
        v.statusLine2 = st.broken.map { "\($0.name): \(L10n.component($0.state, lang))" }.joined(separator: "  ·  ")
    }

    private func details(_ v: inout WidgetViewState) {
        v.statsVisible = cfg.showStats
        v.dayLabel = t(.uiDay)
        v.week7Label = t(.uiWeek7)
        (v.dayMain, v.dayExtra) = period(data.usage?.day)
        (v.week7Main, v.week7Extra) = period(data.usage?.week7)
        if cfg.showHistory, cfg.expanded {
            v.history = HistoryChart.view(data, config: cfg, now: now, timeZone: input.timeZone)
            v.projects = TopProjects.view(data.projects, home: input.homeDirectory, lang: lang)
        }
        v.appVersionText = "\(AppInfo.name) v\(input.appVersion)"
        v.appVersionTooltip = t(.uiPortOf, AppInfo.originalVersion)
        v.appVersionURL = AppInfo.originalRepo
    }

    /// update.ps1 Set-Period: the counts, then every stat line translated.
    private func period(_ p: UsagePeriod?) -> (main: String, extra: String) {
        guard let p else { return (t(.noData), "") }
        let counts = t(.period, L10n.count(p.requests, .pluralRequest, lang), L10n.count(p.sessions, .pluralSession, lang))
        return (counts, p.lines.map { StatLine.text($0, lang: lang) }.joined(separator: "  ·  "))
    }

    /// The Claude Code version line, in priority order: updating, failed, update available, latest, bare.
    private func version(_ v: inout WidgetViewState) {
        let ver = data.version
        guard let local = ver.local else {
            v.versionText = ""
            v.versionTooltip = ""
            v.versionAction = .none
            return
        }
        let update = ver.updateAvailable
        // events.ps1: with an update out a click updates (a no-op while one runs), otherwise it opens the changelog.
        if update {
            v.versionAction = ver.updating ? .none : .runUpdate
        } else {
            v.versionAction = .open(AppInfo.changelogPage)
        }
        v.versionTooltip = update ? changesTooltip(local, ver.latest ?? "", ver.changes) : t(.chgOpen)
        if ver.updating {
            v.versionText = "v\(local)  ·  \(t(.verUpdating))"
            v.versionColor = Palette.warn
        } else if let failure = ver.updateFailure {
            v.versionText = "v\(local)  ·  \(t(.verUpdateFailed))"
            v.versionColor = Palette.crit
            v.versionTooltip = failureTooltip(failure, hint: ver.installHint)
        } else if update {
            v.versionText = "v\(local)  ·  \(t(.verAvailable, ver.latest ?? ""))"
            v.versionColor = Palette.warn
        } else {
            v.versionText = ver.latest == nil ? "v\(local)" : "v\(local)  ·  \(t(.verLatest))"
            v.versionColor = Palette.muted
        }
    }

    /// version.ps1 New-ChangesTooltip; an excerpt cut for another pair of versions still counts as loading.
    private func changesTooltip(_ local: String, _ latest: String, _ changes: ChangesExcerpt?) -> String {
        let head = t(.chgHead, local, latest), click = t(.chgClick)
        guard let changes, changes.forVersion == latest, changes.fromVersion == local else {
            return "\(head)\n\n\(t(.chgLoading))\n\n\(click)"
        }
        let shown = 25
        var lines = changes.items.prefix(shown).map { "• \($0)" }
        if changes.items.count > shown { lines.append(t(.chgMore, changes.items.count - shown)) }
        if changes.items.isEmpty { lines.append(t(.chgEmpty)) }
        return "\(head)\n\n\(lines.joined(separator: "\n"))\n\n\(click)"
    }

    /// Why the headless `claude update` failed, its last output, and how this install updates instead.
    private func failureTooltip(_ failure: UpdateFailure, hint: InstallHint?) -> String {
        let head = switch failure.exitCode {
        case nil: t(.verFailTimeout)
        case 0?: t(.verFailUnchanged, failure.from ?? "")
        case let code?: t(.verFailExit, Int(code))
        }
        var parts = [head]
        let tail = failure.outputTail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        switch hint {
        case .homebrew: parts.append(t(.verHintHomebrew))
        case .npm: parts.append(t(.verHintNpm))
        case nil: break
        }
        return parts.joined(separator: "\n\n")
    }

    private func footer(_ v: inout WidgetViewState) {
        v.accountColor = Palette.footer
        if cfg.showAccount, let account = data.account {
            if account.loggedIn {
                let text = [account.plan, account.email].filter { !$0.isEmpty }.joined(separator: "  ·  ")
                v.accountText = text
                v.accountTooltip = text
            } else {
                v.accountText = t(.accOut)
                v.accountColor = Palette.crit
            }
        }
        v.stampColor = Palette.footer
        if input.tickError {
            v.stampText = t(.error)
        } else if let at = data.usageAt {
            v.stampText = staleStamp(at) ?? clockText(at)
        }
    }

    /// "stale · time" once the numbers from `at` are stale, else nil; the footer and the menu bar item share it.
    private func staleStamp(_ at: Date) -> String? {
        DataSnapshot.isStale(at, interval: cfg.usageIntervalSeconds, now: now) ? "\(t(.stale)) · \(clockText(at))" : nil
    }

    // MARK: Helpers

    /// L10n.t in this render's language; its variadic arguments cannot be forwarded, so the template is filled here.
    private func t(_ key: L10nKey, _ args: any L10nArg...) -> String { L10n.format(L10n.t(key, lang), args) }

    /// A bar's share of the content width; past 100% the bar is simply full.
    private func fraction(_ pct: Int) -> Double { Double(min(100, max(0, pct))) / 100 }

    /// HH:mm:ss in the input's zone, never the system's.
    private func clockText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.timeZone
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
