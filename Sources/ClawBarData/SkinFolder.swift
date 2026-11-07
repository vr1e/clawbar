import Foundation
import ClawBarShared

/// The user's own skins in `<root>/skins`, read on every call as Set-Skin does, so even an edit that keeps a file's
/// size within its mtime tick shows.
public final class SkinFolder {
    public let url: URL
    private var last: SkinCatalog?

    public init(paths: AppPaths) {
        url = paths.skinsFolder
    }

    /// The catalogue with the folder's skins when they differ from the last call's, else nil; the first call always gives one.
    public func reloadIfChanged() -> SkinCatalog? {
        let fresh = SkinCatalog(own: Self.files(in: url).compactMap(Self.read))
        guard fresh != last else { return nil }
        last = fresh
        return fresh
    }

    /// Created when missing, so Finder has a folder to open.
    public func ensureExists() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// `Get-ChildItem -File -Filter *.txt | Sort-Object Name`: visible files only, by name ignoring case.
    static func files(in dir: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let all = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []
        return all
            .filter { $0.pathExtension.lowercased() == "txt" && (try? $0.resourceValues(forKeys: Set(keys)).isRegularFile) == true }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .caseInsensitive) == .orderedAscending }
    }

    /// `Read-SkinFile`: the id is the file's name, lowercased; .NET's UTF-8 read drops a BOM and replaces bad bytes.
    static func read(_ file: URL) -> Skin? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let text = String(decoding: JSONFile.withoutBOM(data), as: UTF8.self)
        return Skin.parse(text, id: file.deletingPathExtension().lastPathComponent.lowercased())
    }
}
