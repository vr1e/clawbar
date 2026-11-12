import Foundation
import ClawBarShared

/// config.json: lenient per-key reads, patch-style atomic writes that keep unknown keys, reload by mtime.
public final class ConfigStore {
    public let url: URL
    private let log: ErrorLog
    /// The config as last loaded or written: what an update changes and diffs against.
    private var current = Config()
    private var stamp: Stamp?
    /// The file exists but the last load could not parse it, so the defaults are in force.
    public private(set) var isUnreadable = false

    public init(paths: AppPaths) {
        url = paths.configFile
        log = ErrorLog(url: paths.errorLog)
    }

    /// The file's values over the defaults, clamped; defaults when it is missing or unreadable.
    public func load() -> Config {
        stamp = Self.stamp(url)
        isUnreadable = false
        guard let data = try? Data(contentsOf: url) else {
            current = Config()
            return current
        }
        guard let j = JSONFile.object(from: data) else {
            log.append("config.json is unreadable, using defaults")
            isUnreadable = true
            current = Config()
            return current
        }
        current = Config(json: j)
        return current
    }

    /// A freshly loaded config when the file's mtime changed since the last load or write, else nil.
    public func reloadIfChanged() -> Config? {
        guard let s = Self.stamp(url), s != stamp else { return nil }
        return load()
    }

    /// Applies `change` and writes only the keys it changed, over the file as it is now.
    @discardableResult
    public func update(_ change: (inout Config) -> Void) throws -> Config {
        var next = current
        change(&next)
        next = next.clamped()
        let changed = ConfigKey.allCases.filter { $0.setting.value(current) != $0.setting.value(next) }
        guard !changed.isEmpty else { return current }
        let j: [String: Any]
        if FileManager.default.fileExists(atPath: url.path) {
            // Never clobber a file the user is in the middle of editing.
            guard let data = try? Data(contentsOf: url), var file = JSONFile.object(from: data) else {
                throw ConfigUnreadable(url: url)
            }
            for k in changed { file[k.rawValue] = Self.json(next, k) }
            j = file
        } else {
            // Only what changed, so a later release can still move the defaults (Open config.json writes them all).
            j = Dictionary(uniqueKeysWithValues: changed.map { ($0.rawValue, Self.json(next, $0)) })
        }
        try JSONFile.write(j, to: url.resolvingSymlinksInPath())
        stamp = Self.stamp(url)
        current = Config(json: j)
        return current
    }

    /// Writes every key when the file does not exist yet (Open config.json).
    public func ensureExists() throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try JSONFile.write(Self.allKeys(current), to: url)
        stamp = Self.stamp(url)
    }

    // MARK: - Encoding

    static func allKeys(_ c: Config) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: ConfigKey.allCases.map { ($0.rawValue, json(c, $0)) })
    }

    /// The JSON value of one key; null for an unset optional.
    static func json(_ c: Config, _ k: ConfigKey) -> Any { k.setting.value(c)?.base ?? NSNull() }

    // MARK: - Change detection

    /// mtime, size and inode: an editor's atomic save changes the inode even within one mtime tick.
    struct Stamp: Equatable {
        var mtime: Date?
        var size: Int?
        var inode: Int?
    }

    static func stamp(_ url: URL) -> Stamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return Stamp(
            mtime: a[.modificationDate] as? Date,
            size: (a[.size] as? NSNumber)?.intValue,
            inode: (a[.systemFileNumber] as? NSNumber)?.intValue
        )
    }
}

struct ConfigUnreadable: Error, CustomStringConvertible {
    var url: URL
    var description: String { "\(url.lastPathComponent) is not valid JSON; not overwriting it" }
}
