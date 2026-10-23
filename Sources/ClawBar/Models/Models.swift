import CoreGraphics
import Foundation
import Observation
import ClawBarShared

/// What the card shows between data ticks.
@Observable
final class AppModel {
    var view: WidgetViewState = .placeholder
    /// The global scale k.
    var scale: Double = Config().scale
    /// showMascot: the play area, Clawd and the hearts.
    var mascotVisible = true
    /// showMascot and showSky.
    var skyVisible = true
    /// The pointer over the 7-day chart; only the cursor and the caption read it, so the chart does not redraw.
    var historyHover: HistoryHover?
}

/// The animation tick's output. Only the hearts, sky and mascot views read it, so the card itself
/// does not re-render at 11 Hz.
@Observable
final class AnimationModel {
    var clawd: ClawdFrame = .empty
    var hearts: HeartsFrame = .hidden
    var sky: SkyFrame = .empty

    /// Stores a frame, touching each property only when it changed, so the hearts view sleeps through Clawd's ticks.
    func publish(_ frame: ClawdFrame) {
        var drawn = frame
        drawn.hearts = .hidden
        if drawn != clawd { clawd = drawn }
        if frame.hearts != hearts { hearts = frame.hearts }
    }

    func publish(_ frame: SkyFrame) {
        if frame != sky { sky = frame }
    }
}

/// Everything SwiftUI measures that AppKit needs: hit and tooltip rects, the number's width, the card's size.
enum HitID: String, Hashable, CaseIterable, Sendable {
    case details, hide, exit, hearts, percentRow, number, reset, play, sessions, status, version, appVersion, account, history
}

/// The named coordinate space the card publishes its rects in: points, origin at the card's top-left.
nonisolated enum CardSpace {
    static let name = "card"
}

@Observable
final class LayoutModel {
    /// The number with its `%`, in base units: the play area is 236 − this − 10 wide.
    var numberWidth: Double = 0
    /// Not observed by any view; AppKit reads them on demand.
    @ObservationIgnored private(set) var rects: [HitID: CGRect] = [:]
    @ObservationIgnored private(set) var cardSize: CGSize = .zero
    @ObservationIgnored var onRectsChange: (() -> Void)?
    @ObservationIgnored var onCardSize: ((CGSize) -> Void)?

    func set(_ id: HitID, _ rect: CGRect?) {
        guard rects[id] != rect else { return }
        rects[id] = rect
        onRectsChange?()
    }

    func setNumberWidth(_ w: Double) {
        if w != numberWidth { numberWidth = w }
    }

    func setCardSize(_ size: CGSize) {
        guard size != cardSize else { return }
        cardSize = size
        onCardSize?(size)
    }
}
