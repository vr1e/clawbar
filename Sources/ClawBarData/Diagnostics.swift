import Foundation
import ClawBarShared

/// `ClawBar --diagnose`: the data engine run once at one instant with every block on, one redacted line per finding.
public enum Diagnostics {
    /// Runs every probe once in the live environment and reports what it found, redacted.
    public static func run(config: Config, paths: AppPaths) async -> DiagnosticsReport {
        await run(config: config, paths: paths, deps: .live())
    }

    static func run(config: Config, paths: AppPaths, deps: CommandRecipes.Dependencies) async -> DiagnosticsReport {
        defer { deps.runner.shutdown() }
        var pass = Pass(config: config, paths: paths, deps: deps)
        await pass.run()
        return DiagnosticsReport(lines: pass.lines)
    }

    /// One pass of the engine, driven as the app drives it: a tick, its commands in order, then a sessions poll,
    /// until a tick asks for nothing. At one instant, so a slot that started is never due again.
    private struct Pass {
        let deps: CommandRecipes.Dependencies
        let recipes: CommandRecipes
        let now: Date
        let latch: UsageLatch?
        var engine: DataEngine
        var lines = ["\(AppInfo.title) · diagnostics"]
        var probedUsage = false

        init(config: Config, paths: AppPaths, deps: CommandRecipes.Dependencies) {
            self.deps = deps
            recipes = CommandRecipes(deps: deps, paths: paths)
            now = deps.clock()
            latch = recipes.savedLatch()
            engine = DataEngine(
                config: config.everyBlockOn(), environment: deps.environment, home: deps.home, latch: latch, history: []
            )
        }

        mutating func run() async {
            while true {
                let asked = engine.handle(.tick, now: now)
                if asked.isEmpty { break }
                await drive(asked)
                await drive(engine.handle(.pollSessions, now: now))
            }
            say("config dir: \(engine.configDirectory)")
            let sessions = engine.snapshot.sessions
            let names = sessions.map { s in
                let state = s.state == .waiting && s.waitingFor != nil ? "waiting: \(s.waitingFor!)" : s.state.rawValue
                return "\(s.name) (\(state))"
            }
            say("sessions: \(sessions.count)" + (names.isEmpty ? "" : " · " + names.joined(separator: ", ")))
            if !probedUsage, let latch, let issue = engine.snapshot.usageIssue, issue.isLatched {
                say("usage: latched for \(latch.version): \(DataEngine.describe(issue))")
            }
            await weather()
        }

        /// Depth-first: an answer's commands run before the next command of the batch, as the app would have them.
        private mutating func drive(_ commands: [DataCommand]) async {
            for command in commands {
                switch command {
                case .log(let line):
                    say("log: \(line)")
                case .saveHistory:
                    // A look, not a sample: usage-history.json is the app's record of what it showed.
                    break
                default:
                    // At the clock, not the pass instant: a session started during the pass is as old as it is by then.
                    let started = ContinuousClock.now
                    guard let event = await recipes.answer(command) else { continue }
                    let next = engine.handle(event, now: now)
                    report(event, took: ContinuousClock.now - started)
                    await drive(next)
                }
            }
        }

        /// One answer in the report's words.
        private mutating func report(_ event: DataEvent, took: Duration) {
            switch event {
            case .loginShell(let login):
                guard let login else { return say("login shell: no answer") }
                let folders = (login.path ?? "").split(separator: ":").count
                say("login shell: \(LoginShell.shell(environment: deps.environment)) · PATH \(folders) folders · CLAUDE_CONFIG_DIR \(login.claudeConfigDir ?? "unset")")
            case .located(let found, let hint):
                guard let found else { return say("claude: not found") }
                say("claude: \(found.path) (\(found.source.rawValue))")
                say("install hint: \(hint?.rawValue ?? "none")")
            case .version(let local, let latest, let channel):
                let state = VersionState(local: local, latest: latest)
                say("version: \(local ?? "unknown") · channel \(channel) · latest \(latest ?? "unknown") · \(state.updateAvailable ? "update available" : "up to date")")
            case .changelog(let body):
                guard body != nil else { return say("changelog: no answer from \(AppInfo.changelogRaw.host ?? "")") }
                say("changelog: \(engine.snapshot.version.changes?.items.count ?? 0) items")
            case .usage(let report):
                probedUsage = true
                switch report.outcome {
                case .usage(let u):
                    say("usage: " + Self.usageLine(u, zone: deps.timeZone))
                    if !report.unreadStamps.isEmpty {
                        say("usage stamps without a date: " + report.unreadStamps.map { "\"\($0)\"" }.joined(separator: ", "))
                    }
                    if let d = u.day { say("usage 24h: \(d.requests) requests · \(d.sessions) sessions · \(d.lines.count) lines") }
                    if let w = u.week7 { say("usage 7d: \(w.requests) requests · \(w.sessions) sessions · \(w.lines.count) lines") }
                case .issue(let issue):
                    say("usage: \(DataEngine.describe(issue))")
                }
                if let e = report.envelope {
                    let cost = e.costUSD == 0 ? "0" : "\(e.costUSD)"
                    say("usage guard: num_turns \(e.numTurns) · total_cost_usd \(cost) · tokens \(e.tokens) · modelUsage \(e.modelUsageCount) · \(e.spentNothing ? "ok" : "TRIPPED")")
                }
            case .account(let account):
                guard let account else { return say("account: no answer from claude auth status") }
                let who = account.loggedIn ? [account.plan, Redact.email(account.email)].filter { !$0.isEmpty }.joined(separator: " · ") : "not logged in"
                say("account: \(who)")
            case .status(let status):
                guard let s = status else { return say("status: no answer from \(AppInfo.statusSummary.host ?? "")") }
                say("status: \(s.indicator) · incidents \(s.incidents.count) · broken \(s.broken.count)")
            case .projects(let scan):
                // Counts only: which projects ran this week is the user's business.
                var parts = [
                    "\(scan.files) transcripts", String(format: "%.0f MB", Double(scan.bytes) / 1_048_576), "\(scan.usage.projects.count) projects",
                    String(format: "%.1f s", took / .seconds(1)),
                ]
                if scan.usage.unpriced > 0 {
                    parts.append("\(scan.usage.unpriced) replies without a list price (\(scan.unpricedModels.joined(separator: ", ")))")
                }
                if scan.unreadable > 0 { parts.append("\(scan.unreadable) unreadable") }
                say("projects: " + parts.joined(separator: " · "))
            default:
                break
            }
        }

        /// The weather is not an engine slot yet: one lookup outside the pass.
        private mutating func weather() async {
            let config = engine.config
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

        private mutating func say(_ s: String) { lines.append(Redact.text(s, home: deps.home)) }

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
}

extension Config {
    /// Every block shown and the details open, whatever config.json says: `--diagnose` looks at hidden rows too.
    func everyBlockOn() -> Config {
        var c = self
        c.showStats = true
        c.showStatus = true
        c.showSessions = true
        c.showAccount = true
        c.showMascot = true
        c.showSky = true
        c.showHistory = true
        c.expanded = true
        return c
    }
}
