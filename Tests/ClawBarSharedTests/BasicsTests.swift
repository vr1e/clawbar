import CoreGraphics
import Foundation
import Testing
import ClawBarShared

@Suite struct ColorTests {
    @Test func parsesBothHexForms() {
        #expect(RGBA("#33FFFFFF") == RGBA(a: 0x33, r: 255, g: 255, b: 255))
        #expect(RGBA("4ADE80") == RGBA(r: 74, g: 222, b: 128))
        #expect(RGBA("#nope") == RGBA(a: 0, r: 0, g: 0, b: 0))
        #expect(Palette.crit.hex == "#FFF87171")
    }

    @Test func mixRoundsHalvesToEvenLikePowerShellsByteCast() {
        let m = RGBA.mix(RGBA(a: 0, r: 64, g: 0, b: 1), RGBA(a: 51, r: 224, g: 5, b: 2), 0.5)
        // 25.5 → 26, 144 exactly, 2.5 → 2, 1.5 → 2
        #expect(m == RGBA(a: 26, r: 144, g: 2, b: 2))
    }

    @Test func mixClampsK() {
        let a = RGBA(r: 0, g: 0, b: 0), b = RGBA(r: 200, g: 100, b: 50)
        #expect(RGBA.mix(a, b, 2) == b)
        #expect(RGBA.mix(a, b, -1) == a)
    }

    @Test func dimPullsTowardsGreyAndDarkensButKeepsAlpha() {
        // l = 140.5, f = 0.85: (100 + 40.5 × 0.5) × 0.85 = 102.21, 123.46, 144.71
        let d = RGBA.dim(RGBA(a: 0x2E, r: 100, g: 150, b: 200), 0.5)
        #expect(d == RGBA(a: 0x2E, r: 102, g: 123, b: 145))
    }

    @Test func levelsFollowTheThresholds() {
        #expect(Level.of(59, warn: 60, crit: 85) == .ok)
        #expect(Level.of(60, warn: 60, crit: 85) == .warn)
        #expect(Level.of(85, warn: 60, crit: 85) == .crit)
        #expect(Level.dead.color == RGBA("#FF6B7280"))
    }
}

@Suite struct RandomTests {
    @Test func aSeedReplaysTheSameSequence() {
        let a = SeededRandomSource(seed: 42), b = SeededRandomSource(seed: 42)
        let xs = (0 ..< 5).map { _ in a.nextInt(1000) }
        #expect(xs == (0 ..< 5).map { _ in b.nextInt(1000) })
        #expect(Set(xs).count > 1)
    }

    @Test func doublesStayInTheUnitInterval() {
        let r = SeededRandomSource(seed: 7)
        for _ in 0 ..< 1000 {
            let d = r.nextDouble()
            #expect(d >= 0 && d < 1)
        }
    }

    @Test func degenerateBoundsGiveZero() {
        let r = SeededRandomSource(seed: 1)
        #expect(r.nextInt(1) == 0)
        #expect(r.nextInt(0) == 0)
        #expect(SystemRandomSource().nextInt(-3) == 0)
    }
}

@Suite struct VersionCompareTests {
    @Test func comparesNumericallyNotAsText() {
        #expect(VersionState.isNewer("2.1.10", than: "2.1.9"))
        #expect(!VersionState.isNewer("2.1.9", than: "2.1.10"))
        #expect(!VersionState.isNewer("2.1.302", than: "2.1.302"))
    }

    @Test func unparseableVersionsAreNeverNewer() {
        #expect(!VersionState.isNewer("2.1.x", than: "2.1.0"))
        #expect(!VersionState.isNewer("3", than: "2.1.0"))
    }

    @Test func anUpdateNeedsBothVersions() {
        #expect(VersionState(local: "2.1.292", latest: "2.1.302").updateAvailable)
        #expect(!VersionState(local: "2.1.302", latest: "2.1.292").updateAvailable)
        #expect(!VersionState(local: nil, latest: "2.1.302").updateAvailable)
    }

    @Test func aFailedUpdateHoldsWhileBothVersionsItStartedFromDo() {
        let f = UpdateFailure(exitCode: 1, outputTail: "", from: "2.1.302", to: "2.1.303")
        #expect(f.holds(local: "2.1.302", latest: "2.1.303"))
        #expect(!f.holds(local: "2.1.303", latest: "2.1.303"))
        #expect(!f.holds(local: "2.1.302", latest: "2.1.304"))
        #expect(UpdateFailure(exitCode: 1, outputTail: "").holds(local: "2.1.303", latest: "2.1.304"))
    }
}

@Suite struct StalenessTests {
    @Test func staleAfterThreeIntervalsAndThirtySeconds() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(!DataSnapshot.isStale(now.addingTimeInterval(-210), interval: 60, now: now))
        #expect(DataSnapshot.isStale(now.addingTimeInterval(-211), interval: 60, now: now))
        #expect(DataSnapshot.isStale(nil, interval: 60, now: now))
    }
}

@Suite struct RedactTests {
    @Test func scrubsHomeEmailAddressesAndKeys() {
        let s = "cwd /Users/jane/Dev/x mail jane.doe@corp.example key sk-ant-api03-AbC_d-1 ip 192.168.1.20 v2.1.302"
        #expect(Redact.text(s, home: "/Users/jane") == "cwd ~/Dev/x mail <email> key <secret> ip <ip> v2.1.302")
    }

    @Test func shortensAnEmailForDisplay() {
        #expect(Redact.email("jane@example.com") == "j…@example.com")
        #expect(Redact.email("") == "")
    }
}

@Suite struct AppPathsTests {
    @Test func clawbarHomeOverridesTheLiveRoot() {
        let p = AppPaths.live(environment: ["CLAWBAR_HOME": "/tmp/cb-test"])
        #expect(p.root.path == "/tmp/cb-test")
        #expect(p.configFile.lastPathComponent == "config.json")
    }

    @Test func theLiveRootIsInApplicationSupport() {
        #expect(AppPaths.live(environment: [:]).root.path.hasSuffix("Library/Application Support/ClawBar"))
    }

    @Test func theUserAgentNamesThisVersionAndClawBarsOwnHomeAsItsContact() {
        #expect(AppInfo.userAgent == "ClawBar/\(AppInfo.version) (+https://github.com/vr1e/clawbar)")
        #expect(!AppInfo.userAgent.contains(AppInfo.originalRepo.path))
    }

    @Test func oneRootHasOneCanonicalSpellingEvenBeforeItExists() {
        let name = "cb-canon-\(UUID().uuidString)"
        // /tmp is a symlink to /private/tmp; neither folder below it exists.
        let short = AppPaths(root: URL(fileURLWithPath: "/tmp/\(name)/root"))
        let long = AppPaths(root: URL(fileURLWithPath: "/private/tmp/\(name)/x/../root/"))
        #expect(short.canonicalRoot == "/private/tmp/\(name)/root")
        #expect(long.canonicalRoot == short.canonicalRoot)
    }

    @Test func theDefaultRootIsTheOneWithoutClawbarHomeHoweverItIsSpelled() {
        let base = URL(fileURLWithPath: "/tmp/cb-default-\(UUID().uuidString)")
        let def = base.appendingPathComponent("ClawBar")
        #expect(AppPaths(root: def).isDefault(defaultRoot: def))
        #expect(AppPaths(root: URL(fileURLWithPath: "/private" + def.path)).isDefault(defaultRoot: def))
        #expect(!AppPaths(root: base.appendingPathComponent("sandbox")).isDefault(defaultRoot: def))
        #expect(AppPaths.live(environment: [:]).isDefault())
        #expect(!AppPaths.live(environment: ["CLAWBAR_HOME": "/tmp/cb-test"]).isDefault())
    }
}

@Suite struct ErrorLogTests {
    @Test func linesCarryALocalTimestampAndATab() {
        let line = ErrorLog.line("mascot: boom\nsecond", at: Date(timeIntervalSince1970: 1_792_238_700), timeZone: Samples.timeZone)
        #expect(line == "2026-10-17T14:05:00\tmascot: boom | second")
    }

    @Test func appendsRedactedLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = ErrorLog(url: dir.appendingPathComponent("error.log"))
        log.append("first a@b.example")
        log.append("second")
        let text = try String(contentsOf: log.url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("\tfirst <email>"))
    }
}

@Suite struct PixelArtTests {
    @Test func runsMergeIntoOneRectEach() {
        let r = PixelArt.rects([".##.#"], value: "#", px: 2, py: 2.2, origin: CGPoint(x: 10, y: 1))
        #expect(r == [CGRect(x: 12, y: 1, width: 4, height: 2.2), CGRect(x: 18, y: 1, width: 2, height: 2.2)])
    }

    @Test func aHalfHeartIsTheLeftFourColumns() {
        let r = PixelArt.rects(PixelArt.heart, value: "#", px: 1, py: 1, maxColumn: PixelArt.heartHalfColumns)
        #expect(r.allSatisfy { $0.maxX <= 4 })
        #expect(r.first == CGRect(x: 1, y: 0, width: 2, height: 1))
    }

    @Test func standingClawdIsEighteenByTwelve() {
        #expect(PixelArt.clawdStanding.count == 12)
        #expect(PixelArt.clawdStanding.allSatisfy { $0.count == 18 })
    }
}

@Suite struct SnapshotDerivationTests {
    @Test func sessionsAreCountedByState() {
        #expect(DataSnapshot.sample.count(of: .busy) == 1)
        #expect(DataSnapshot.sample.count(of: .waiting) == 1)
        #expect(DataSnapshot.sample.count(of: .idle) == 0)
    }

    @Test func clawdReadsTheSessionsAndTheMainLimitFromADataSnapshot() {
        let input = ClawdDataInput(DataSnapshot.sample, mainLimit: .session, critPercent: 85)
        #expect(input == ClawdDataInput(
            busy: 1, waiting: 1, sessionCount: 2,
            main: UsageLimit(kind: .session, percent: 34, reset: Samples.now.addingTimeInterval(7500)), critPercent: 85
        ))
        let week = ClawdDataInput(DataSnapshot.sample, mainLimit: .week, critPercent: 85)
        #expect(week.main == UsageLimit(kind: .week, percent: 59, reset: DataSnapshot.sample.usage?.weekReset))
        #expect(ClawdDataInput(.empty, mainLimit: .week, critPercent: 70).main.percent == nil)
    }
}
