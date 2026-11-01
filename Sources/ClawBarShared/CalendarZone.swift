import Foundation

extension Calendar {
    /// A Gregorian calendar in `zone`, so a day or hour never falls back to the machine's own zone.
    public static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
