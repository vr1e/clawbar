import CoreGraphics
import Foundation
import ClawBarShared

/// What `--dump-state` reports about the running instance: enough to check the item, the window,
/// the login item and the numbers against `--diagnose`. Personal data is redacted.
struct StateDump {
    var nonce: String
    var pid: Int32
    var statusItemVisible: Bool
    var statusItemFrame: CGRect?
    var widgetVisible: Bool
    var occluded: Bool
    var panelFrame: CGRect
    var screenFrames: [CGRect]
    var topLeft: CGPoint
    var animating: Bool
    var tickMilliseconds: Int
    var config: Config
    var loginItemStatus: String
    var installedApp: Bool
    var snapshot: DataSnapshot
    var view: WidgetViewState
    var home: String = NSHomeDirectory()

    /// The panel's frame meets some screen.
    var panelOnScreen: Bool { screenFrames.contains { $0.intersects(panelFrame) } }

    func render() -> String {
        var lines = ["nonce: \(nonce)", "app: \(AppInfo.title) (pid \(pid))"]
        // One key: value line each, so line breaks in a value are written as \n.
        func add(_ key: String, _ value: Any) { lines.append("\(key): " + "\(value)".replacingOccurrences(of: "\n", with: "\\n")) }
        add("statusItem.visible", statusItemVisible)
        add("statusItem.frame", statusItemFrame.map(Self.rect) ?? "none")
        add("widget.visible", widgetVisible)
        add("widget.occluded", occluded)
        add("widget.frame", Self.rect(panelFrame))
        add("widget.onScreen", panelOnScreen)
        add("widget.topLeft", "\(Self.num(topLeft.x)), \(Self.num(topLeft.y))")
        add("widget.animating", animating)
        add("widget.tickMs", tickMilliseconds)
        add("config.language", config.lang.rawValue)
        add("config.scale", Self.num(config.scale))
        add("config.opacity", Self.num(config.opacity))
        add("config.topmost", config.topmost)
        add("config.showMascot", config.showMascot)
        add("config.showSky", config.showSky)
        add("config.showHistory", config.showHistory)
        add("config.launchAtLogin", config.launchAtLogin)
        add("config.menuBarMascot", config.menuBarMascot)
        add("loginItem.status", loginItemStatus)
        add("loginItem.installedApp", installedApp)
        let u = snapshot.usage
        add("usage.session", u?.sessionPercent.map(String.init) ?? "none")
        add("usage.week", u?.weekPercent.map(String.init) ?? "none")
        add("usage.modelWeeks", u.map { $0.modelWeeks.map { "\($0.name) \($0.percent)" }.joined(separator: ", ") } ?? "")
        add("usage.sessionReset", Self.iso(u?.sessionReset))
        add("usage.at", Self.iso(snapshot.usageAt))
        add("usage.probeCompleted", snapshot.usageProbeCompleted)
        add("usage.issue", snapshot.usageIssue.map { "\($0)" } ?? "none")
        let h = snapshot.history
        if let first = h.first, let last = h.last {
            add("usage.history", "\(h.count) sample\(h.count == 1 ? "" : "s"), \(Self.iso(first.date)) to \(Self.iso(last.date))")
        } else {
            add("usage.history", "none")
        }
        let busy = snapshot.count(of: .busy), waiting = snapshot.count(of: .waiting)
        add("sessions", "\(snapshot.sessions.count) (busy \(busy), waiting \(waiting)), read: \(snapshot.sessionsRead)")
        add("status.indicator", snapshot.status?.indicator ?? "none")
        add("status.at", Self.iso(snapshot.statusAt))
        if let a = snapshot.account {
            add("account", a.loggedIn ? "\(a.plan) · \(Redact.email(a.email))" : "logged out")
        } else {
            add("account", "none")
        }
        add("version", "\(snapshot.version.local ?? "?") latest \(snapshot.version.latest ?? "?")\(snapshot.version.updating ? " updating" : "")")
        add("weather", snapshot.weather.map { "code \($0.code), \(Self.num($0.tempC)) °C, wind \(Self.num($0.windKmh)) km/h" } ?? "none")
        add("view.pct", view.pctText)
        add("view.tray", view.trayText)
        add("view.trayTooltip", view.trayTooltip)
        add("view.reset", view.resetText)
        add("view.limitReached", String(view.limitReached))
        add("view.week", view.week.value)
        add("view.sessions", view.sessionsText)
        add("view.status", view.statusText)
        add("view.stamp", view.stampText)
        return lines.map { Redact.text($0, home: home) }.joined(separator: "\n") + "\n"
    }

    static func rect(_ r: CGRect) -> String {
        "\(num(r.minX)), \(num(r.minY)), \(num(r.width)) × \(num(r.height))"
    }

    static func num(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.2f", v)
    }

    static func iso(_ d: Date?) -> String {
        guard let d else { return "none" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}
