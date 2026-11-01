import Foundation
import ClawBarShared

/// hearts.ps1: halves of the main limit left, and the health tiers they select.
enum ClawdHealth {
    /// Get-Halves: forced hearts, else 0 for a forced 'dead', else from the main limit's %; nil hides the hearts.
    static func halves(forceHearts: Int?, force: Mood?, pct: Int?) -> Int? {
        let h: Int
        if let forceHearts {
            h = forceHearts
        } else if force == .dead {
            h = 0
        } else if let pct {
            h = Int((Double(max(0, 100 - pct) * 6) / 100).rounded(.up))
        } else {
            return nil
        }
        return min(6, max(0, h))
    }

    /// No data counts as tier 5, "fine".
    static func tierNumber(_ halves: Int?) -> Int { halves ?? 5 }

    static func tier(_ number: Int) -> HealthTier { ClawdTables.healthTiers[min(6, max(0, number))] }
}

/// Step-Hearts' memory: the halves shown last tick and the lost-heart blink.
struct HeartsTracker {
    private(set) var halves: Int?
    private var lostT = -1
    private var lostFrom = 0

    /// The play area was hidden: the next value is new, not a loss.
    mutating func forget() { halves = nil }

    mutating func step(_ now: Int?, pct: Int?, limit: MainLimit, forced: Bool, tick: Int, lang: Lang) -> HeartsFrame {
        guard let now else {
            halves = nil
            return .hidden
        }
        var tip = L10n.health(now, lang)
        if let pct, !forced { tip = L10n.t(limit == .week ? .heartsLeftWeek : .heartsLeft, lang, tip, 100 - pct) }

        // A lost heart blinks for 16 ticks: the old value on the first two of every four.
        if let before = halves, now < before {
            lostT = 0
            lostFrom = before
        }
        halves = now
        var shown = now
        if lostT >= 0 {
            if lostT % 4 < 2 { shown = lostFrom }
            lostT += 1
            if lostT >= 16 { lostT = -1 }
        }

        // The last bit of health: all three beat together.
        var beat = 1.0
        if now > 0, now <= 2 {
            switch tick % 12 {
            case 0: beat = 1.3
            case 1: beat = 1.15
            default: break
            }
        }
        return HeartsFrame(visible: true, shownHalves: shown, beatScale: beat, tooltip: tip)
    }
}

/// One of the 12 confetti pieces: position in play-area coordinates (y up from the ground), fall speed and drift.
struct ConfettiPiece {
    var x = 0.0
    var y = 0.0
    var v = 0.0
    var d = 0.0
    var shown = false
    var width = 2.0
}
