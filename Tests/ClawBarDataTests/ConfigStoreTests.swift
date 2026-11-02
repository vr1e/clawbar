import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

@Suite struct ConfigStoreTests {
    let dir = TempDir("cb-config")
    var paths: AppPaths { dir.paths }

    func write(_ text: String) {
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: paths.configFile)
    }

    func json() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: paths.configFile))) as? [String: Any] ?? [:]
    }

    @Test func aMissingFileGivesTheDefaults() {
        #expect(ConfigStore(paths: paths).load() == Config())
    }

    @Test func aBOMIsSkipped() {
        write("\u{FEFF}{\"scale\": 1.5, \"language\": \"de\"}")
        let c = ConfigStore(paths: paths).load()
        #expect(c.scale == 1.5)
        #expect(c.lang == .de)
    }

    @Test func valuesAreReadLeniently() {
        write("""
        {"showSky": "false", "topmost": "true", "showStats": 0, "refreshSeconds": "20", "scale": "1.4",
         "warnPercent": 70.5, "critPercent": "90", "weatherLat": "48.2", "weatherLon": 16.4, "left": 100, "top": "200",
         "language": "DE", "claudePath": " /opt/tools/claude ", "launchAtLogin": false, "menuBarMascot": "false",
         "showHistory": "true", "mainLimit": " Week ", "theme": "Space", "accent": " #F472B6 "}
        """)
        let c = ConfigStore(paths: paths).load()
        #expect(c.showSky == false)
        #expect(c.topmost == true)
        #expect(c.showStats == false)
        #expect(c.refreshSeconds == 20)
        #expect(c.scale == 1.4)
        // PowerShell's [int] rounds half to even
        #expect(c.warnPercent == 70)
        #expect(c.critPercent == 90)
        #expect(c.weatherLat == 48.2 && c.weatherLon == 16.4)
        #expect(c.left == 100 && c.top == 200)
        #expect(c.lang == .de)
        #expect(c.claudePath == "/opt/tools/claude")
        #expect(c.launchAtLogin == false)
        #expect(c.menuBarMascot == false)
        #expect(c.showHistory == true)
        #expect(c.mainLimit == .week)
        #expect(c.theme == .fixed(.space) && c.accent == RGBA("#FFF472B6"))
    }

    @Test func aThemeIsWrittenByItsNameAndABadAccentStaysForTheUserToFix() throws {
        write(#"{"accent": "pink"}"#)
        let store = ConfigStore(paths: paths)
        #expect(store.load().accent == nil)
        _ = try store.update { $0.theme = .bySeason }
        #expect(json()["theme"] as? String == "auto")
        #expect(json()["accent"] as? String == "pink")
        _ = try store.update { $0.theme = .fixed(.oled) }
        #expect(json()["theme"] as? String == "oled")
    }

    @Test func aBadKeyFallsBackToItsOwnDefaultOnly() {
        write("""
        {"scale": "big", "opacity": 0.5, "showStats": [1], "usageIntervalSeconds": null, "weatherLat": "north",
         "weatherLon": "", "language": 5, "claudePath": 7, "topmost": "maybe", "statusIntervalSeconds": true}
        """)
        let c = ConfigStore(paths: paths).load()
        let d = Config()
        #expect(c.scale == d.scale)
        #expect(c.opacity == 0.5)
        #expect(c.showStats == d.showStats)
        #expect(c.usageIntervalSeconds == d.usageIntervalSeconds)
        #expect(c.weatherLat == nil && c.weatherLon == nil)
        #expect(c.language == d.language)
        #expect(c.claudePath == nil)
        #expect(c.topmost == d.topmost)
        #expect(c.statusIntervalSeconds == d.statusIntervalSeconds)
    }

    @Test func loadingAlwaysClamps() {
        write(#"{"refreshSeconds": 1, "warnPercent": 90, "critPercent": 70, "scale": 9}"#)
        let c = ConfigStore(paths: paths).load()
        #expect(c.refreshSeconds == 2)
        #expect(c.warnPercent == 70 && c.critPercent == 70)
        #expect(c.scale == 4.0)
    }

    @Test func aBrokenFileGivesAllDefaults() {
        write(#"{"scale": 1.5, "opacity": "#)
        #expect(ConfigStore(paths: paths).load() == Config())
        write("[1, 2]")
        #expect(ConfigStore(paths: paths).load() == Config())
    }

    @Test func aBrokenFileIsFlaggedUntilItReadsAgain() {
        let store = ConfigStore(paths: paths)
        #expect(!store.isUnreadable)
        write(#"{"scale": 1.5, "opacity": "#)
        _ = store.load()
        #expect(store.isUnreadable)
        write(#"{"scale": 1.5}"#)
        #expect(store.reloadIfChanged()?.scale == 1.5)
        #expect(!store.isUnreadable)
    }

    @Test func aWriteChangesOnlyItsKeysAndKeepsUnknownOnes() throws {
        write(#"{"scale": 1.3, "myNote": "keep me", "nested": {"a": 1}, "advisorDiskGB": 10}"#)
        let store = ConfigStore(paths: paths)
        _ = store.load()
        let c = try store.update { $0.expanded = true }
        #expect(c.expanded && c.scale == 1.3)
        let j = json()
        #expect(Set(j.keys) == ["scale", "myNote", "nested", "advisorDiskGB", "expanded"])
        #expect(j["expanded"] as? Bool == true)
        #expect(j["myNote"] as? String == "keep me")
        #expect((j["nested"] as? [String: Any])?["a"] as? Int == 1)
        #expect(j["scale"] as? Double == 1.3)
    }

    @Test func handEditsSurviveOurOwnSave() throws {
        write(#"{"scale": 1.3}"#)
        let store = ConfigStore(paths: paths)
        _ = store.load()
        write(#"{"scale": 1.6, "x": 1}"#)
        let c = try store.update { $0.topmost = true }
        #expect(c.scale == 1.6 && c.topmost)
        let j = json()
        #expect(j["scale"] as? Double == 1.6)
        #expect(j["x"] as? Int == 1)
        #expect(j["topmost"] as? Bool == true)
    }

    @Test func clearedOptionalsAreWrittenAsNull() throws {
        write(#"{"left": 10, "top": 20}"#)
        let store = ConfigStore(paths: paths)
        _ = store.load()
        try store.update {
            $0.left = nil
            $0.top = nil
        }
        let j = json()
        #expect(j["left"] is NSNull && j["top"] is NSNull)
        #expect(store.load().left == nil)
    }

    @Test func writtenValuesAreClamped() throws {
        let store = ConfigStore(paths: paths)
        _ = store.load()
        let c = try store.update { $0.scale = 7 }
        #expect(c.scale == 4.0)
        #expect(json()["scale"] as? Double == 4.0)
    }

    @Test func theFirstWriteHoldsOnlyTheChangedKeysSoDefaultsCanStillMove() throws {
        let store = ConfigStore(paths: paths)
        _ = store.load()
        try store.update {
            $0.left = 40
            $0.top = 50
        }
        #expect(Set(json().keys) == ["left", "top"])
        #expect(store.load() == Config(left: 40, top: 50))
    }

    @Test func anUnchangedUpdateWritesNothing() throws {
        let store = ConfigStore(paths: paths)
        _ = store.load()
        try store.update { $0.scale = Config().scale }
        #expect(!FileManager.default.fileExists(atPath: paths.configFile.path))
    }

    @Test func anUnreadableFileIsNeverOverwritten() {
        write(#"{"scale": 1.5, oops"#)
        let store = ConfigStore(paths: paths)
        _ = store.load()
        #expect(throws: (any Error).self) { try store.update { $0.expanded = true } }
        #expect((try? String(contentsOf: paths.configFile, encoding: .utf8)) == #"{"scale": 1.5, oops"#)
    }

    @Test func writesAreAtomicReplacements() throws {
        write(#"{"scale": 1.3}"#)
        let store = ConfigStore(paths: paths)
        _ = store.load()
        let before = try FileManager.default.attributesOfItem(atPath: paths.configFile.path)[.systemFileNumber] as? Int
        try store.update { $0.expanded = true }
        let after = try FileManager.default.attributesOfItem(atPath: paths.configFile.path)[.systemFileNumber] as? Int
        #expect(before != after)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.root.path) == ["config.json"])
    }

    @Test func reloadIfChangedSeesHandEditsButNotOurOwnWrites() throws {
        write(#"{"scale": 1.3}"#)
        let store = ConfigStore(paths: paths)
        _ = store.load()
        #expect(store.reloadIfChanged() == nil)
        write(#"{"scale": 1.7}"#)
        #expect(store.reloadIfChanged()?.scale == 1.7)
        #expect(store.reloadIfChanged() == nil)
        try store.update { $0.expanded = true }
        #expect(store.reloadIfChanged() == nil)
        try FileManager.default.removeItem(at: paths.configFile)
        #expect(store.reloadIfChanged() == nil)
    }

    @Test func ensureExistsWritesEveryKeyOnlyWhenTheFileIsAbsent() throws {
        let store = ConfigStore(paths: paths)
        _ = store.load()
        try store.ensureExists()
        let j = json()
        #expect(Set(j.keys) == Set(ConfigKey.allCases.map(\.rawValue)))
        #expect(j["weatherLat"] is NSNull)
        #expect(j["scale"] as? Double == 1.2)
        write(#"{"scale": 2}"#)
        try store.ensureExists()
        #expect(Set(json().keys) == ["scale"])
    }
}
