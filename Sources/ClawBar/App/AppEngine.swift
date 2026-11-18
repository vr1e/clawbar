import CoreGraphics
import Foundation
import ClawBarShared

/// Anything the user or another process asks of the app.
enum AppAction: Equatable {
    case card(CardClick)
    case menu(StatusMenuAction)
    case settings(SettingsAction)
    case remote(RemoteCommand)
}

/// A settings change as a value, so a test can see which setting an action touches.
enum ConfigEdit: Equatable {
    case toggle(WritableKeyPath<Config, Bool>)
    case step(SteppedSetting, up: Bool)
    case otherMainLimit
    case language(Lang)
    case theme(ThemeChoice)
    case skin(String)

    func apply(to c: inout Config) {
        switch self {
        case .toggle(let flag): c[keyPath: flag].toggle()
        case .step(let s, let up): if let v = s.next(from: c[keyPath: s.key], up: up) { c[keyPath: s.key] = v }
        case .otherMainLimit: c.mainLimit = c.mainLimit.other
        case .language(let l): c.language = l.rawValue
        case .theme(let t): c.theme = t
        case .skin(let id): c.skin = id
        }
    }
}

/// What the app carries out for an action.
enum AppEffect: Equatable {
    case edit(ConfigEdit)
    case showWidget, hideWidget
    case refresh
    case showSettings
    case showGame
    case open(URL)
    case startClaudeUpdate
    /// A recent session, by its id.
    case resumeSession(String)
    case openConfig, openSkinsFolder
    case quit
}

/// A reloaded or edited config as it takes effect, and what it changes beyond the card.
struct ConfigReload: Equatable {
    var config: Config
    var rescheduleDataTimer: Bool
    var reconcileLoginItem: Bool
}

/// The app's decisions around the card: what an action does, what a new config changes, when a position is written.
enum AppEngine {
    static func effect(of action: AppAction, widgetVisible: Bool) -> AppEffect? {
        switch action {
        case .card(let click):
            switch click {
            case .toggleDetails: .edit(.toggle(\.expanded))
            case .hide: .hideWidget
            case .quit: .quit
            case .play: .showGame
            case .open(let url): .open(url)
            case .runUpdate: .startClaudeUpdate
            case .nothing: nil
            }
        case .menu(let item):
            switch item {
            case .toggleWidget: widgetVisible ? .hideWidget : .showWidget
            case .refresh: .refresh
            case .settings: .showSettings
            case .play: .showGame
            case .recent(let id): .resumeSession(id)
            case .quit: .quit
            }
        case .settings(let change):
            switch change {
            case .step(let s, let up): .edit(.step(s, up: up))
            case .toggleTopmost: .edit(.toggle(\.topmost))
            case .toggleMainWeek: .edit(.otherMainLimit)
            case .toggleLaunchAtLogin: .edit(.toggle(\.launchAtLogin))
            case .toggleMenuBarMascot: .edit(.toggle(\.menuBarMascot))
            case .toggleRecentSessions: .edit(.toggle(\.showRecentSessions))
            case .language(let l): .edit(.language(l))
            case .theme(let t): .edit(.theme(t))
            case .skin(let id): .edit(.skin(id))
            case .toggleBlock(let b): .edit(.toggle(b.flag))
            case .openConfig: .openConfig
            case .openSkinsFolder: .openSkinsFolder
            }
        case .remote(let command):
            switch command {
            case .toggle: widgetVisible ? .hideWidget : .showWidget
            case .show: .showWidget
            case .larger: .edit(.step(.size, up: true))
            case .smaller: .edit(.step(.size, up: false))
            case .refresh: .refresh
            case .settings: .showSettings
            case .quit: .quit
            case .lang(let l): .edit(.language(l))
            }
        }
    }

    /// The config as read at launch: the saved left/top place the window, and nothing is running yet to reschedule.
    static func load(_ config: Config) -> ConfigReload {
        ConfigReload(config: config.clamped(), rescheduleDataTimer: false, reconcileLoginItem: false)
    }

    /// Sync-Config: the window owns its position, so the current left/top survive a reload.
    static func reload(_ fresh: Config, over current: Config) -> ConfigReload {
        var c = fresh.clamped()
        c.left = current.left
        c.top = current.top
        return ConfigReload(
            config: c,
            rescheduleDataTimer: c.refreshSeconds != current.refreshSeconds,
            reconcileLoginItem: c.launchAtLogin != current.launchAtLogin
        )
    }

    /// The top-left to write, rounded like the original's [math]::Round; nil when the widget has not moved.
    static func position(of topLeft: CGPoint, saved: Config) -> (left: Double, top: Double)? {
        let left = topLeft.x.rounded(.toNearestOrEven), top = topLeft.y.rounded(.toNearestOrEven)
        return saved.left == left && saved.top == top ? nil : (left, top)
    }
}
