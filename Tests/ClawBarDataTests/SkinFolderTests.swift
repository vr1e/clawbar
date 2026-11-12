import Foundation
import Testing
import ClawBarShared
@testable import ClawBarData

/// The user's own skins: `Get-Skins` over `<root>/skins`, given again only when they changed.
@Suite struct SkinFolderTests {
    let dir = TempDir("cb-skins")
    var paths: AppPaths { dir.paths }

    private let hat = "---\nname: My hat\nk: #18181B\n---\nkkkk\n"

    /// A file in the skins folder, which sits under `TempDir.paths`' root.
    @discardableResult
    private func write(_ name: String, _ text: String) -> URL { dir.write("app/skins/\(name)", text) }

    private func ownIds(_ c: SkinCatalog?) -> [String]? {
        c.map { $0.skins.dropFirst(BuiltInSkin.allCases.count).map(\.id) }
    }

    @Test func noFolderGivesTheBuiltInOnesOnceAndCreatesNothing() {
        let folder = SkinFolder(paths: paths)
        #expect(folder.reloadIfChanged() == .builtIn)
        #expect(folder.reloadIfChanged() == nil)
        #expect(!FileManager.default.fileExists(atPath: paths.skinsFolder.path))
    }

    @Test func readsTxtFilesByNameIgnoringCaseWithLowercasedIds() {
        write("b.txt", hat)
        write("A.TXT", hat)
        write("c.json", hat)
        write(".hidden.txt", hat)
        write("broken.txt", "no front matter\nkkkk\n")
        try? FileManager.default.createDirectory(
            at: paths.skinsFolder.appendingPathComponent("dir.txt"), withIntermediateDirectories: true
        )
        let catalog = SkinFolder(paths: paths).reloadIfChanged()
        #expect(ownIds(catalog) == ["a", "b"])
        #expect(catalog?.skin(for: "a").name == "My hat")
    }

    @Test func aByteOrderMarkAndBadBytesStillRead() {
        write("bom.txt", "\u{FEFF}" + hat)
        // An invalid UTF-8 byte; the folder is there since the line above.
        try? (Data(hat.utf8) + Data([0xFF, 0x0A])).write(to: paths.skinsFolder.appendingPathComponent("bad.txt"))
        #expect(ownIds(SkinFolder(paths: paths).reloadIfChanged()) == ["bad", "bom"])
    }

    @Test func anAddedEditedOrRemovedFileReadsAgain() throws {
        let folder = SkinFolder(paths: paths)
        _ = folder.reloadIfChanged()
        let url = write("mine.txt", hat)
        #expect(ownIds(folder.reloadIfChanged()) == ["mine"])
        #expect(folder.reloadIfChanged() == nil)

        write("mine.txt", hat.replacingOccurrences(of: "My hat", with: "My other hat"))
        #expect(folder.reloadIfChanged()?.skin(for: "mine").name == "My other hat")

        try FileManager.default.removeItem(at: url)
        #expect(folder.reloadIfChanged() == .builtIn)
    }

    @Test func aSameSizeEditAtOnceShowsAndAnUnchangedRewriteDoesNot() {
        let folder = SkinFolder(paths: paths)
        write("mine.txt", "---\nk: #111111\n---\nk\n")
        _ = folder.reloadIfChanged()
        // Same size, likely the same mtime tick: only the contents tell them apart.
        write("mine.txt", "---\nk: #222222\n---\nk\n")
        #expect(folder.reloadIfChanged()?.skin(for: "mine").layers.first?.color == RGBA("#FF222222"))
        write("mine.txt", "---\nk: #222222\n---\nk\n")
        #expect(folder.reloadIfChanged() == nil)
    }
}
