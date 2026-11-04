import Foundation

/// Clawd's colours and the pixel accessories drawn over him: skins.ps1's skin, built in or read from a file.
public struct Skin: Sendable, Hashable {
    /// The file's name, lowercased: what config.json's `skin` names.
    public var id: String
    /// The file's `name:`, else the id.
    public var name: String
    public var body: RGBA
    public var eyes: RGBA
    /// One per colour letter; no two share a pixel.
    public var layers: [SkinLayer]

    public init(id: String, name: String, body: RGBA, eyes: RGBA, layers: [SkinLayer]) {
        self.id = id
        self.name = name
        self.body = body
        self.eyes = eyes
        self.layers = layers
    }

    /// Clawd as he comes: skins.ps1's `$SkinDefault`.
    public static let classic = Skin(id: "classic", name: "", body: Palette.clawdBody, eyes: Palette.clawdEyes, layers: [])

    private static let frontMatter = Rx.make(#"(?s)^\s*---\s*\r?\n(.*?)\r?\n---\s*\r?\n?(.*)$"#)
    private static let keyValue = Rx.make(#"^\s*(\w+)\s*:\s*(.*?)\s*$"#)
    private static let integer = Rx.make(#"^-?[0-9]+$"#)
    private static let lineBreak = Rx.make(#"\r?\n"#)
    /// Clawd's grid is 18 pixels wide; art beyond it is cut.
    private static let columns = 18

    /// skins.ps1's `Read-SkinFile`: front matter between `---` lines, then the art; nil without the front matter.
    public static func parse(_ text: String, id: String) -> Skin? {
        guard let m = Rx.first(frontMatter, in: text) else { return nil }
        var skin = Skin(id: id, name: id, body: classic.body, eyes: classic.eyes, layers: [])
        // PowerShell's hashtable ignores case, so `r` and `R` are one letter and its last colour wins.
        var colors: [String: RGBA] = [:]
        var top: Int?
        for line in lines(m[1] ?? "") {
            guard let kv = Rx.first(keyValue, in: line), let k = kv[1] else { continue }
            let v = kv[2] ?? ""
            let color = RGBA.parse(v)
            switch k {
            case "name": skin.name = v.isEmpty ? id : v
            case "body": if let color { skin.body = color }
            case "eyes": if let color { skin.eyes = color }
            case "top": if Rx.matches(integer, v), let n = Int(v) { top = n }
            default: if k.utf16.count == 1, let color { colors[k.lowercased()] = color }
            }
        }
        var rows = lines(m[2] ?? "").map(trimmedAtEnd)
        while rows.last?.isEmpty == true { rows.removeLast() }
        let first = top ?? -rows.count

        var order: [String] = []
        var pixels: [String: [SkinPixel]] = [:]
        for (y, row) in rows.enumerated() {
            for (x, unit) in row.utf16.prefix(columns).enumerated() {
                let letter = String(utf16CodeUnits: [unit], count: 1).lowercased()
                guard colors[letter] != nil else { continue }
                if pixels[letter] == nil { order.append(letter) }
                pixels[letter, default: []].append(SkinPixel(x: x, y: first + y))
            }
        }
        skin.layers = order.map { SkinLayer(color: colors[$0]!, pixels: pixels[$0]!) }
        return skin
    }

    private static func lines(_ s: String) -> [String] {
        Rx.replace(lineBreak, in: s, with: "\n").components(separatedBy: "\n")
    }

    /// .NET's `TrimEnd()`.
    private static func trimmedAtEnd(_ s: String) -> String {
        var t = Substring(s)
        while t.last?.isWhitespace == true { t.removeLast() }
        return String(t)
    }
}

/// The pixels of one accessory colour.
public struct SkinLayer: Sendable, Hashable {
    public var color: RGBA
    public var pixels: [SkinPixel]

    public init(color: RGBA, pixels: [SkinPixel]) {
        self.color = color
        self.pixels = pixels
    }
}

/// A pixel in Clawd's grid: x from his left column, y from his top row, negative above his head.
public struct SkinPixel: Sendable, Hashable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}
