import Foundation
import Testing
@testable import ClawBar
import ClawBarShared

/// Only the channel names: a test never posts a real notification, which an installed copy would act on.
@Suite struct IPCChannelTests {
    let def = URL(fileURLWithPath: "/tmp/cb-ipc-\(UUID().uuidString)/ClawBar")

    @Test func theDefaultRootKeepsTheBareBundleIDSoOlderBuildsStillHearIt() {
        #expect(IPC.channel(AppPaths(root: def), defaultRoot: def) == AppInfo.bundleID)
    }

    @Test func anyOtherRootHasAChannelOfItsOwn() {
        let sandbox = def.deletingLastPathComponent().appendingPathComponent("sandbox")
        let channel = IPC.channel(AppPaths(root: sandbox), defaultRoot: def)
        #expect(channel == AppInfo.bundleID + ":/private" + sandbox.path)
        #expect(IPC.channel(AppPaths(root: URL(fileURLWithPath: "/private" + sandbox.path + "/")), defaultRoot: def) == channel)
        #expect(IPC.channel(AppPaths(root: sandbox.appendingPathComponent("other")), defaultRoot: def) != channel)
    }
}
