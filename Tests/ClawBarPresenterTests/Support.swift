import Foundation
import ClawBarPresenter
import ClawBarShared

/// The sample's world: Berlin at `Samples.now`, the example home directory.
func render(
    _ data: DataSnapshot = .sample, config: Config = Config(), lang: Lang = .en,
    now: Date = Samples.now, tickError: Bool = false
) -> WidgetViewState {
    var config = config
    config.language = lang.rawValue
    return WidgetPresenter.make(PresenterInput(
        config: config, now: now, timeZone: Samples.timeZone, data: data, tickError: tickError,
        homeDirectory: Samples.home
    ))
}

/// The sample with its usage changed.
func sample(_ change: (inout UsageSnapshot) -> Void) -> DataSnapshot {
    var d = DataSnapshot.sample
    change(&d.usage!)
    return d
}

/// The sample with something else changed.
func sample(data change: (inout DataSnapshot) -> Void) -> DataSnapshot {
    var d = DataSnapshot.sample
    change(&d)
    return d
}

/// Every field where two view states differ, so a failure names what broke.
func differences(_ a: WidgetViewState, _ b: WidgetViewState) -> [String] {
    zip(Mirror(reflecting: a).children, Mirror(reflecting: b).children).compactMap { x, y in
        let l = String(describing: x.value), r = String(describing: y.value)
        return l == r ? nil : "\(x.label ?? "?"): \(l)  ≠  \(r)"
    }
}

extension Date {
    func plus(days: Double = 0, hours: Double = 0, minutes: Double = 0, seconds: Double = 0) -> Date {
        addingTimeInterval(days * 86_400 + hours * 3600 + minutes * 60 + seconds)
    }
}

func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
