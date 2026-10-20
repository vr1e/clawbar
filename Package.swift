// swift-tools-version: 6.2
import Foundation
import PackageDescription

// Command Line Tools ship the Swift Testing macros in a subfolder the compiler does not search.
let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])]
    : []

// Linking with only --sysroot stamps the deployment target as the SDK version; -isysroot lets clang read the real one.
let sdkLinkerSettings: [LinkerSetting] = ProcessInfo.processInfo.environment["SDKROOT"].map {
    [.unsafeFlags(["-Xclang-linker", "-isysroot", "-Xclang-linker", $0])]
} ?? []

// One target per owner, so modules built in parallel never share internal names.
// Shipped targets have no resources: Bundle.module breaks in the hand-assembled .app.
let package = Package(
    name: "ClawBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClawBar", targets: ["ClawBar"]),
    ],
    targets: [
        .target(name: "ClawBarShared"),
        .target(name: "ClawBarData", dependencies: ["ClawBarShared"]),
        .target(name: "ClawBarPresenter", dependencies: ["ClawBarShared"]),
        .target(name: "ClawBarClawd", dependencies: ["ClawBarShared"]),
        .target(name: "ClawBarSky", dependencies: ["ClawBarShared"]),
        .target(name: "ClawBarGame", dependencies: ["ClawBarShared"]),
        .executableTarget(
            name: "ClawBar",
            dependencies: ["ClawBarShared", "ClawBarData", "ClawBarPresenter", "ClawBarClawd", "ClawBarSky", "ClawBarGame"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: sdkLinkerSettings
        ),

        .testTarget(name: "ClawBarSharedTests", dependencies: ["ClawBarShared"], swiftSettings: testSettings),
        .testTarget(
            name: "ContractTests",
            dependencies: ["ClawBarShared", "ClawBarData", "ClawBarPresenter", "ClawBarClawd", "ClawBarSky"],
            swiftSettings: testSettings
        ),
        .testTarget(
            name: "ClawBarDataTests",
            dependencies: ["ClawBarData", "ClawBarShared"],
            exclude: ["Fixtures"],
            swiftSettings: testSettings
        ),
        .testTarget(name: "ClawBarPresenterTests", dependencies: ["ClawBarPresenter", "ClawBarShared"], swiftSettings: testSettings),
        .testTarget(name: "ClawBarClawdTests", dependencies: ["ClawBarClawd", "ClawBarShared"], swiftSettings: testSettings),
        .testTarget(name: "ClawBarSkyTests", dependencies: ["ClawBarSky", "ClawBarShared"], swiftSettings: testSettings),
        .testTarget(name: "ClawBarGameTests", dependencies: ["ClawBarGame", "ClawBarShared"], swiftSettings: testSettings),
        .testTarget(
            name: "ClawBarAppTests",
            dependencies: ["ClawBar", "ClawBarShared"],
            swiftSettings: testSettings + [.defaultIsolation(MainActor.self)]
        ),
    ]
)
