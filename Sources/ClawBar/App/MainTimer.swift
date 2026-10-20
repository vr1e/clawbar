import Foundation

extension Timer {
    /// A repeating main-thread timer in the common modes: .common keeps the ticks running while a menu is open, like
    /// WPF's dispatcher timers.
    static func onMain(every seconds: Double, tolerance: Double? = nil, _ body: @escaping @MainActor () -> Void) -> Timer {
        common(seconds, repeats: true, tolerance: tolerance, body)
    }

    /// `onMain(every:)` firing once.
    static func onMain(after seconds: Double, _ body: @escaping @MainActor () -> Void) -> Timer {
        common(seconds, repeats: false, tolerance: nil, body)
    }

    private static func common(
        _ seconds: Double, repeats: Bool, tolerance: Double?, _ body: @escaping @MainActor () -> Void
    ) -> Timer {
        let t = Timer(timeInterval: seconds, repeats: repeats) { _ in MainActor.assumeIsolated { body() } }
        t.tolerance = tolerance ?? seconds / 10
        RunLoop.main.add(t, forMode: .common)
        return t
    }
}
