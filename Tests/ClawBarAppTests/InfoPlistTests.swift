import Foundation
import Testing
import ClawBarShared

@Suite struct InfoPlistTests {
    /// The package root, found from this file's path.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let plist: [String: Any] = {
        let data = (try? Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))) ?? Data()
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
    }()

    static let platform = Rx.make(#"\.macOS\(\.v(\d+)\)"#)

    @Test func theBundleMatchesTheAppsOwnIdentity() {
        let p = Self.plist
        #expect(p["CFBundleIdentifier"] as? String == AppInfo.bundleID)
        #expect(p["CFBundleShortVersionString"] as? String == AppInfo.version)
        #expect(p["CFBundleVersion"] as? String == AppInfo.version)
        #expect(p["CFBundleExecutable"] as? String == AppInfo.name)
        #expect(p["CFBundleIconFile"] as? String == "AppIcon")
        #expect(p["CFBundlePackageType"] as? String == "APPL")
    }

    // A plist minimum below the package's lets Launch Services open a binary that cannot load.
    @Test func itIsAMenuBarAppForThePackagesMacOS() {
        let package = (try? String(contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)) ?? ""
        let major = Rx.first(Self.platform, in: package)?[1]
        #expect(Self.plist["LSUIElement"] as? Bool == true)
        #expect(Self.plist["LSMinimumSystemVersion"] as? String == major.map { "\($0).0" })
    }
}
