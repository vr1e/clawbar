import Foundation

/// Appends one line per error: `<yyyy-MM-ddTHH:mm:ss>\t<message>` in local time, the original's format.
/// Messages are redacted and flattened to one line; the file rolls over to `.1` past `maxBytes`.
public struct ErrorLog: Sendable {
    public let url: URL
    public static let maxBytes = 512 * 1024

    public init(url: URL) { self.url = url }

    public func append(_ message: String, now: Date = Date(), timeZone: TimeZone = .current) {
        let line = Self.line(Redact.text(message), at: now, timeZone: timeZone) + "\n"
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber, size.intValue > Self.maxBytes {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let bytes = Array(line.utf8)
        _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    }

    public static func line(_ message: String, at date: Date, timeZone: TimeZone) -> String {
        let cal = Calendar.gregorian(in: timeZone)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
        let flat = message
            .replacingOccurrences(of: "\r\n", with: " | ")
            .replacingOccurrences(of: "\n", with: " | ")
            .replacingOccurrences(of: "\r", with: " | ")
        return "\(stamp)\t\(flat)"
    }
}
