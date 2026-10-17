import Foundation
import Testing
@testable import ClawBar
import ClawBarShared

/// Only the channel names: a test never posts a real notification, which an installed copy would act on.
@Suite struct IPCChannelTests {
    @Test func theDefaultRootKeepsTheBareBundleIDSoOlderBuildsStillHearIt() {
        #expect(IPC.channel(AppPaths.live(environment: [:])) == AppInfo.bundleID)
    }

    @Test func anyOtherRootHasAChannelOfItsOwn() {
        let sandbox = URL(fileURLWithPath: "/tmp/cb-ipc-\(UUID().uuidString)/sandbox")
        let channel = IPC.channel(AppPaths(root: sandbox))
        #expect(channel == AppInfo.bundleID + ":/private" + sandbox.path)
        #expect(IPC.channel(AppPaths(root: URL(fileURLWithPath: "/private" + sandbox.path + "/"))) == channel)
        #expect(IPC.channel(AppPaths(root: sandbox.appendingPathComponent("other"))) != channel)
    }
}
