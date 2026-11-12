import Foundation

/// JSONSerialization values read the forgiving way PowerShell did: "false" is false, "12" is 12.
public enum Lenient {
    public static func isBool(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    public static func bool(_ v: Any?) -> Bool? {
        switch v {
        case let n as NSNumber:
            return isBool(n) ? n.boolValue : (n.doubleValue.isFinite ? n.doubleValue != 0 : nil)
        case let s as String:
            switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "on": return true
            case "false", "0", "no", "off", "": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    public static func double(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber where !isBool(n):
            return n.doubleValue.isFinite ? n.doubleValue : nil
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let d = Double(t), d.isFinite else { return nil }
            return d
        default:
            return nil
        }
    }

    /// Whole numbers; halves round to even like PowerShell's [int].
    public static func int(_ v: Any?) -> Int? {
        guard let d = double(v), abs(d) < 1e15 else { return nil }
        return Int(d.rounded(.toNearestOrEven))
    }

    public static func string(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s
        case let n as NSNumber where !isBool(n): return n.stringValue
        default: return nil
        }
    }
}
