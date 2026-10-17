import Foundation
import Testing
import ClawBarShared

@Suite struct InfoPlistTests {
    /// Resources/Info.plist at the package root, found from this file's path.
    static let plist: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let data = (try? Data(contentsOf: url)) ?? Data()
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
    }()

    @Test func theBundleMatchesTheAppsOwnIdentity() {
        let p = Self.plist
        #expect(p["CFBundleIdentifier"] as? String == AppInfo.bundleID)
        #expect(p["CFBundleShortVersionString"] as? String == AppInfo.version)
        #expect(p["CFBundleVersion"] as? String == AppInfo.version)
        #expect(p["CFBundleExecutable"] as? String == AppInfo.name)
        #expect(p["CFBundleIconFile"] as? String == "AppIcon")
        #expect(p["CFBundlePackageType"] as? String == "APPL")
    }

    @Test func itIsAMenuBarAppForMacOS15AndLater() {
        #expect(Self.plist["LSUIElement"] as? Bool == true)
        #expect(Self.plist["LSMinimumSystemVersion"] as? String == "15.0")
    }
}
