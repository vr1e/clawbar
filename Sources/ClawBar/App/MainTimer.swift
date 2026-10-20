import Foundation

extension Timer {
    /// A main-thread timer in the common modes: .common keeps the ticks running while a menu is open, like WPF's
    /// dispatcher timers.
    static func onMain(
        every seconds: Double, repeats: Bool = true, tolerance: Double? = nil, _ body: @escaping @MainActor () -> Void
    ) -> Timer {
        let t = Timer(timeInterval: seconds, repeats: repeats) { _ in MainActor.assumeIsolated { body() } }
        t.tolerance = tolerance ?? seconds / 10
        RunLoop.main.add(t, forMode: .common)
        return t
    }
}
