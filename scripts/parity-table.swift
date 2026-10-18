// Builds README's parity table from docs.local/upstream-features.md, the private map of every upstream feature.
// Usage: swift scripts/parity-table.swift
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let mapURL = root.appendingPathComponent("docs.local/upstream-features.md")
let readmeURL = root.appendingPathComponent("README.md")
let begin = "<!-- parity-table: begin; built by scripts/parity-table.swift, edit its source, not this table -->"
let end = "<!-- parity-table: end -->"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("parity-table: \(message)\n".utf8))
    exit(1)
}

enum Status { case done, differs, todo, undecided, skipped }

struct Row {
    let feature: String
    let since: [Int]?
    let status: Status
}

struct Section {
    let title: String
    var isPublic = true
    var reason: String?
    var rows: [Row] = []
}

func version(_ text: String) -> [Int]? {
    let parts = text.trimmingCharacters(in: .whitespaces).drop { $0 == "v" }.split(separator: ".").compactMap { Int($0) }
    return parts.count == 3 ? parts : nil
}

func status(_ text: String) -> Status? {
    switch text {
    case "🟢 Done": .done
    case "🟢 Done, differs": .differs
    case "🔵 To do": .todo
    case "⚪ Undecided": .undecided
    case "🟡 Skipped": .skipped
    default: nil
    }
}

guard let map = try? String(contentsOf: mapURL, encoding: .utf8) else {
    fail("cannot read \(mapURL.path); docs.local is git-ignored, so only the main checkout has it")
}

var reviewed: [Int]?
var ports: [Int]?
var sections: [Section] = []
var columns: [String] = []
for line in map.components(separatedBy: "\n") {
    if line.hasPrefix("- Reviewed through: ") {
        reviewed = version(String(line.dropFirst("- Reviewed through: ".count)))
    } else if line.hasPrefix("- ClawBar ports: ") {
        ports = version(String(line.dropFirst("- ClawBar ports: ".count)))
    } else if line.hasPrefix("## ") {
        sections.append(Section(title: String(line.dropFirst(3))))
        columns = []
    } else if sections.isEmpty {
        continue
    } else if line == "Public: no" {
        sections[sections.count - 1].isPublic = false
    } else if line.hasPrefix("Not ported because: ") {
        sections[sections.count - 1].reason = String(line.dropFirst("Not ported because: ".count))
    } else if line.hasPrefix("|") {
        let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if columns.isEmpty {
            columns = cells
            continue
        }
        if cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 == "-" } }) { continue }
        let title = sections[sections.count - 1].title
        guard cells.count == columns.count else { fail("\(title): \(cells.count) cells where the header has \(columns.count): \(line)") }
        let cell = Dictionary(uniqueKeysWithValues: zip(columns, cells))
        guard let feature = cell["Feature"], let sinceText = cell["Since"], let statusText = cell["Status"] else {
            fail("\(title): the table needs Feature, Since and Status columns")
        }
        guard let rowStatus = status(statusText) else { fail("\(title): unknown status '\(statusText)' for '\(feature)'") }
        let since = sinceText == "—" ? nil : version(sinceText)
        if since == nil, sinceText != "—" { fail("\(title): Since '\(sinceText)' is no version for '\(feature)'") }
        sections[sections.count - 1].rows.append(Row(feature: feature, since: since, status: rowStatus))
    }
}
guard let reviewed else { fail("the map has no '- Reviewed through: vX.Y.Z' line") }
guard let ports else { fail("the map has no '- ClawBar ports: vX.Y.Z' line") }

func names(_ rows: [Row]) -> String { rows.map(\.feature).joined(separator: "; ") }

var lines = [
    begin,
    "ClawBar ports clawd-usage-winwidget \(ports.map(String.init).joined(separator: ".")) and has been checked against every "
        + "release up to \(reviewed.map(String.init).joined(separator: ".")).",
    "*Ported differently* means a bullet below says how.",
    "",
    "| Feature | In ClawBar | Notes |",
    "|---|---|---|",
]
for section in sections where section.isPublic {
    // Rows from releases not reviewed yet stay out, so the table never claims more than was checked.
    let rows = section.rows.filter { row in row.since.map { !reviewed.lexicographicallyPrecedes($0) } ?? false }
    if rows.isEmpty { continue }
    let done = rows.filter { $0.status == .done || $0.status == .differs }
    let open = rows.filter { $0.status == .todo || $0.status == .undecided }
    let skipped = rows.filter { $0.status == .skipped }
    var notes: [String] = []
    let state: String
    if !done.isEmpty {
        state = done.contains { $0.status == .differs } ? "✅ Ported differently" : "✅ Ported"
        if !open.isEmpty { notes.append("Not yet: \(names(open)).") }
        if !skipped.isEmpty { notes.append("Not ported: \(names(skipped)).") }
    } else if !open.isEmpty {
        state = "⏳ Not yet"
        if !skipped.isEmpty { notes.append("Not ported: \(names(skipped)).") }
    } else {
        guard let reason = section.reason else { fail("\(section.title): every row is skipped, so it needs a 'Not ported because:' line") }
        state = "➖ Not ported"
        notes.append(reason.prefix(1).uppercased() + reason.dropFirst() + ".")
    }
    lines.append("| \(section.title) | \(state) |" + (notes.isEmpty ? " |" : " \(notes.joined(separator: " ")) |"))
}
lines.append(end)

guard let readme = try? String(contentsOf: readmeURL, encoding: .utf8) else { fail("cannot read \(readmeURL.path)") }
guard let from = readme.range(of: begin), let to = readme.range(of: end, range: from.upperBound..<readme.endIndex) else {
    fail("README.md needs the two marker lines:\n\(begin)\n\(end)")
}
let updated = readme.replacingCharacters(in: from.lowerBound..<to.upperBound, with: lines.joined(separator: "\n"))
if updated == readme {
    print("README.md: parity table unchanged")
} else {
    do { try updated.write(to: readmeURL, atomically: true, encoding: .utf8) } catch { fail("cannot write README.md: \(error)") }
    print("README.md: parity table updated")
}
