import Foundation
import Testing
@testable import ClawBar
import ClawBarShared

@MainActor
@Suite struct SnapshotModeTests {
    @Test func theStatesCoverEveryIssueAndEveryRowSwitch() {
        let names = Set(SnapshotCases.all().map(\.name))
        #expect(names.count == SnapshotCases.all().count, "state names are unique")
        for required in [
            "sample", "expanded", "loading", "no-data", "warn", "crit", "limit", "claude-not-found", "no-limits",
            "flag-rejected", "model-reached", "update-available", "updating", "update-failed", "status-issues",
            "maintenance", "status-offline", "logged-out", "stale", "tick-error", "model-weeks", "rows-hidden", "no-mascot",
        ] {
            #expect(names.contains(required), "\(required)")
        }
    }

    @Test func theIssueStatesCarryTheirIssue() throws {
        func data(_ name: String) throws -> DataSnapshot {
            try #require(SnapshotCases.all().first { $0.name == name }).data
        }
        #expect(try data("claude-not-found").usageIssue == .claudeNotFound)
        #expect(try data("no-limits").usageIssue == .noLimits)
        #expect(try data("loading").usageProbeCompleted == false)
        #expect(try data("update-failed").version.updateFailure != nil)
        #expect(try data("logged-out").account?.loggedIn == false)
    }

    @Test(arguments: [1.0, 1.2, 2.0])
    func everyStateRendersAtEveryScale(k: Double) throws {
        for c in SnapshotCases.all() {
            for lang in Lang.allCases {
                let image = try #require(SnapshotMode.renderCard(c, lang: lang, scale: k), "\(c.name) \(lang) \(k)")
                // 262 × k points at 2 pixels per point.
                #expect(abs(Double(image.width) - 262 * k * 2) <= 1, "\(c.name)")
                #expect(image.height > Int(100 * k * 2))
            }
        }
    }

    @Test func expandingTheDetailsMakesTheCardTaller() throws {
        let all = SnapshotCases.all()
        let sample = try #require(all.first { $0.name == "sample" })
        let expanded = try #require(all.first { $0.name == "expanded" })
        let a = try #require(SnapshotMode.renderCard(sample, lang: .en, scale: 1))
        let b = try #require(SnapshotMode.renderCard(expanded, lang: .en, scale: 1))
        #expect(b.height > a.height)
    }

    @Test func aRunWritesCardsStatusItemsAndMenuDumps() throws {
        let tmp = TempDir()
        let files = try SnapshotMode.write(to: tmp.url)
        let names = Set(files.map(\.lastPathComponent))
        for k in ["1.0", "1.2", "2.0"] {
            #expect(names.contains("sample-en-k\(k).png"))
            #expect(names.contains("sample-de-k\(k).png"))
        }
        for text in ["none", "7", "42", "42-stale", "100"] {
            #expect(names.contains("status-item-\(text)-light.png"))
            #expect(names.contains("status-item-\(text)-dark.png"))
        }
        #expect(names.contains("menus-en.txt") && names.contains("menus-de.txt"))
        let menus = try String(contentsOf: tmp.url.appendingPathComponent("menus-en.txt"), encoding: .utf8)
        #expect(menus.contains("Quit ClawBar"))
        #expect(menus.contains("Developer menu"))
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}
