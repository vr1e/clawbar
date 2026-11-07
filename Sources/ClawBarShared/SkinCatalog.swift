import Foundation

/// Every skin there is to pick, in order: skins.ps1's `Get-Skins`, Classic and the built-in ones, then the user's own.
public struct SkinCatalog: Sendable, Hashable {
    public let skins: [Skin]
    /// The built-in ids a file of the user's took over.
    private let replaced: Set<String>

    public static let builtIn = SkinCatalog(own: [])

    /// `own` in file-name order; one with a built-in skin's id, Classic's too, takes that skin's place.
    public init(own: [Skin]) {
        var skins = BuiltInSkin.allCases.map(\.skin)
        var replaced: Set<String> = []
        for s in own {
            if let i = skins.firstIndex(where: { $0.id == s.id }) {
                skins[i] = s
                replaced.insert(s.id)
            } else {
                skins.append(s)
            }
        }
        self.skins = skins
        self.replaced = replaced
    }

    /// Set-Skin: config.json's `skin` in any case; anything unknown is the original Classic, never the user's file.
    public func skin(for configValue: String?) -> Skin {
        let id = configName(configValue)
        return skins.first { $0.id == id } ?? .classic
    }

    /// The built-in skin under this id, unless a file of the user's took it over: only a built-in one is translated.
    public func untouchedBuiltIn(_ skin: Skin) -> BuiltInSkin? {
        replaced.contains(skin.id) ? nil : BuiltInSkin(rawValue: skin.id)
    }
}
