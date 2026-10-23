import Foundation
import ClawBarShared

/// `ClawBar --diagnose`: every probe once, in the live environment, one redacted line per finding.
public enum Diagnostics {
    /// Runs every probe once in the live environment and reports what it found, redacted.
    public static func run(config: Config, paths: AppPaths) async -> DiagnosticsReport {
        await run(config: config, paths: paths, deps: .live())
    }

    static func run(config raw: Config, paths: AppPaths, deps: DataController.Dependencies) async -> DiagnosticsReport {
        let config = raw.clamped()
        let home = deps.home
        var lines = ["\(AppInfo.title) · diagnostics"]
        func say(_ s: String) { lines.append(Redact.text(s, home: home)) }
        defer { deps.runner.shutdown() }

        let login = await deps.loginShell(deps.runner, deps.environment, home)
        if let login {
            let folders = (login.path ?? "").split(separator: ":").count
            say("login shell: \(LoginShell.shell(environment: deps.environment)) · PATH \(folders) folders · CLAUDE_CONFIG_DIR \(login.claudeConfigDir ?? "unset")")
        } else {
            say("login shell: no answer")
        }

        guard let claude = ClaudeLocator(home: home, candidates: deps.candidates).locate(configPath: config.claudePath, login: login)
        else {
            say("claude: not found")
            await tail(config: config, deps: deps, account: nil, login: login, say: say)
            return DiagnosticsReport(lines: lines)
        }
        say("claude: \(claude.path) (\(claude.source.rawValue))")
        say("install hint: \(UpdateRunner.installHint(claudePath: claude.path)?.rawValue ?? "none")")
        let env = ChildEnv.make(inherited: deps.environment, login: login, claude: claude.path)

        // The account first: its configDirectory decides where settings.json and the sessions live.
        let account = AccountProbe.interpret(await deps.runner.run(AccountProbe.spec(claude: claude.path, environment: env, home: home)))
        let configDir = ClaudeConfigDir.resolve(account: account, login: login, environment: deps.environment, home: deps.home)

        let local = VersionProbe.local(await deps.runner.run(VersionProbe.spec(claude: claude.path, environment: env, home: home)))
        let channel = VersionProbe.channel(settings: try? Data(contentsOf: URL(fileURLWithPath: configDir).appendingPathComponent("settings.json")))
        let body = try? await deps.http.get(VersionProbe.latestURL(channel: channel), timeout: 15)
        let latest = body.flatMap { VersionProbe.latest(String(decoding: $0, as: UTF8.self)) }
        let state = VersionState(local: local, latest: latest)
        say("version: \(local ?? "unknown") · channel \(channel) · latest \(latest ?? "unknown") · \(state.updateAvailable ? "update available" : "up to date")")

        let store = LatchStore(url: paths.stateFile)
        if let latch = store.load(), let local, latch.holds(forVersion: local) {
            say("usage: latched for \(latch.version): \(DataEngine.describe(latch.issue))")
        } else {
            let result = await deps.runner.run(UsageProbe.spec(claude: claude.path, environment: env, home: home))
            let report = UsageProbe.interpret(result, now: deps.clock(), timeZone: deps.timeZone)
            switch report.outcome {
            case .usage(let u):
                say("usage: " + usageLine(u, zone: deps.timeZone))
                if !report.unreadStamps.isEmpty {
                    say("usage stamps without a date: " + report.unreadStamps.map { "\"\($0)\"" }.joined(separator: ", "))
                }
                if let d = u.day { say("usage 24h: \(d.requests) requests · \(d.sessions) sessions · \(d.lines.count) lines") }
                if let w = u.week7 { say("usage 7d: \(w.requests) requests · \(w.sessions) sessions · \(w.lines.count) lines") }
            case .issue(let issue):
                say("usage: \(DataEngine.describe(issue))")
                if let local, let latch = UsageLatch(version: local, issue: issue) { try? store.save(latch) }
            }
            if let e = report.envelope {
                let cost = e.costUSD == 0 ? "0" : "\(e.costUSD)"
                say("usage guard: num_turns \(e.numTurns) · total_cost_usd \(cost) · tokens \(e.tokens) · modelUsage \(e.modelUsageCount) · \(e.spentNothing ? "ok" : "TRIPPED")")
            }
        }

        if let account {
            let who = account.loggedIn ? [account.plan, Redact.email(account.email)].filter { !$0.isEmpty }.joined(separator: " · ") : "not logged in"
            say("account: \(who)")
        } else {
            say("account: no answer from claude auth status")
        }
        await tail(config: config, deps: deps, account: account, login: login, say: say)
        return DiagnosticsReport(lines: lines)
    }

    /// The probes that need no claude: sessions, status, weather.
    private static func tail(
        config: Config, deps: DataController.Dependencies, account: AccountInfo?, login: LoginEnvironment?,
        say: (String) -> Void
    ) async {
        let configDir = ClaudeConfigDir.resolve(account: account, login: login, environment: deps.environment, home: deps.home)
        say("config dir: \(configDir)")
        let registry = SessionRegistry(
            directory: SessionRegistry.directory(configDir: configDir, home: deps.home), table: deps.table, readFile: deps.readFile
        )
        let sessions = registry.read(excluding: deps.runner.childPIDs, now: deps.clock())
        let names = sessions.map { s in
            let state = s.state == .waiting && s.waitingFor != nil ? "waiting: \(s.waitingFor!)" : s.state.rawValue
            return "\(s.name) (\(state))"
        }
        say("sessions: \(sessions.count)" + (names.isEmpty ? "" : " · " + names.joined(separator: ", ")))

        // Counts only: which projects ran this week is the user's business.
        let started = ContinuousClock.now
        let scan = await TranscriptScanner().scan(root: TranscriptScanner.root(configDir: configDir), now: deps.clock())
        var projects = [
            "\(scan.files) transcripts", String(format: "%.0f MB", Double(scan.bytes) / 1_048_576), "\(scan.usage.projects.count) projects",
            String(format: "%.1f s", (ContinuousClock.now - started) / .seconds(1)),
        ]
        if scan.usage.unpriced > 0 {
            projects.append("\(scan.usage.unpriced) replies without a list price (\(scan.unpricedModels.joined(separator: ", ")))")
        }
        if scan.unreadable > 0 { projects.append("\(scan.unreadable) unreadable") }
        say("projects: " + projects.joined(separator: " · "))

        if let body = try? await deps.http.get(AppInfo.statusSummary, timeout: 15), let s = StatusProbe.parse(body) {
            say("status: \(s.indicator) · incidents \(s.incidents.count) · broken \(s.broken.count)")
        } else {
            say("status: no answer from \(AppInfo.statusSummary.host ?? "")")
        }

        let (place, wx, provider) = await WeatherService.fetchOnce(config: config, http: deps.http, now: deps.clock)
        guard let place else { return say("weather: no location") }
        var parts = [config.weatherLat != nil && config.weatherLon != nil ? "configured coordinates" : "IP location"]
        if let city = place.city { parts.append(city) }
        if let provider { parts.append(provider) }
        if let zone = wx?.timeZoneID ?? place.timeZoneID { parts.append(zone) }
        if let wx {
            parts.append("code \(wx.code) (\(WeatherKinds.name(code: wx.code, lang: .en)))")
            parts.append(String(format: "%.1f °C", wx.tempC))
            parts.append(String(format: "wind %.1f km/h", wx.windKmh))
        } else {
            parts.append("no weather")
        }
        say("weather: " + parts.joined(separator: " · "))
    }

    private static func usageLine(_ u: UsageSnapshot, zone: TimeZone) -> String {
        var parts: [String] = []
        if let p = u.sessionPercent { parts.append("session \(p)%") }
        if let r = u.sessionReset { parts.append("resets \(stamp(r, zone))") }
        if let p = u.weekPercent { parts.append("week \(p)%") }
        if let r = u.weekReset { parts.append("resets \(stamp(r, zone))") }
        for m in u.modelWeeks { parts.append("\(m.name) \(m.percent)%") }
        return parts.joined(separator: " · ")
    }

    private static func stamp(_ d: Date, _ zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d-%02d-%02d %02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}
