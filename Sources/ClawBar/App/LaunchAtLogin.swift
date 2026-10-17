import Foundation
import ServiceManagement
import ClawBarShared

/// SMAppService.Status, as a plain value the decision can be tested on.
enum LoginItemStatus: String, Equatable {
    case notRegistered, enabled, requiresApproval, notFound

    init(_ s: SMAppService.Status) {
        switch s {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        default: self = .notRegistered
        }
    }
}

enum LoginItemAction: Equatable {
    case register, unregister, none
}

enum LaunchAtLogin {
    /// What brings the login item in line with `launchAtLogin`. A pending approval is left to the user.
    static func action(desired: Bool, status: LoginItemStatus) -> LoginItemAction {
        switch (desired, status) {
        case (true, .notRegistered), (true, .notFound): .register
        case (false, .enabled), (false, .requiresApproval): .unregister
        default: .none
        }
    }

    /// Only ClawBar.app in ~/Applications or /Applications registers itself: a build in the repo
    /// or a bare `swift run` must not leave a login item pointing at it.
    static func isInstalledApp(bundleURL: URL, bundleID: String?, home: URL) -> Bool {
        guard bundleURL.pathExtension == "app", bundleID == AppInfo.bundleID else { return false }
        let parent = bundleURL.standardizedFileURL.deletingLastPathComponent().path
        let allowed = [home.appendingPathComponent("Applications").standardizedFileURL.path, "/Applications"]
        return allowed.contains(parent)
    }

    /// The login item belongs to the bundle, not the root: a sandbox `CLAWBAR_HOME` run of the installed app
    /// must not register or remove the user's.
    static func managesLoginItem(installed: Bool, paths: AppPaths) -> Bool {
        installed && paths.isDefault()
    }

    static var runsFromInstalledApp: Bool {
        isInstalledApp(
            bundleURL: Bundle.main.bundleURL, bundleID: Bundle.main.bundleIdentifier,
            home: URL(fileURLWithPath: NSHomeDirectory())
        )
    }
}

protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// The real login item: this app, via SMAppService.
final class MainAppLoginItem: LoginItemService {
    var status: LoginItemStatus { LoginItemStatus(SMAppService.mainApp.status) }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Keeps the login item in line with config.launchAtLogin.
final class LoginItemController {
    private let service: LoginItemService
    let installed: Bool
    private let log: ErrorLog

    init(service: LoginItemService, installed: Bool, log: ErrorLog) {
        self.service = service
        self.installed = installed
        self.log = log
    }

    var status: LoginItemStatus { service.status }

    /// Does what `LaunchAtLogin.action` says and returns it; failures go to the error log.
    @discardableResult
    func reconcile(desired: Bool) -> LoginItemAction {
        guard installed else { return .none }
        let action = LaunchAtLogin.action(desired: desired, status: service.status)
        do {
            switch action {
            case .register: try service.register()
            case .unregister: try service.unregister()
            case .none: break
            }
        } catch {
            log.append("launch at login: \(action == .register ? "register" : "unregister") failed: \(error)")
        }
        return action
    }
}
