import Foundation
import Testing
import ClawBarPresenter
import ClawBarShared

/// Clawd Run is offered only while the session limit is used up.
@Suite struct PlayButtonTests {
    @Test(arguments: [100, 101])
    func aUsedUpLimitOffersTheGame(pct: Int) {
        let v = render(sample { $0.sessionPercent = pct })
        #expect(v.limitReached)
        #expect(v.playText == "Play Clawd Run while you wait")
        #expect(v.tooltip(.play)?.isEmpty == false)
        // The reset line keeps saying when the wait ends.
        #expect(v.resetText.hasPrefix("resets in"))
    }

    @Test(arguments: [0, 60, 99])
    func belowTheLimitNothingIsOffered(pct: Int) {
        let v = render(sample { $0.sessionPercent = pct })
        #expect(!v.limitReached)
        #expect(v.playText.isEmpty && !v.shows(.play))
    }

    @Test func withoutNumbersNothingIsOffered() {
        var noLimits = sample { $0.sessionPercent = 100 }
        noLimits.usageIssue = .noLimits
        var notFound = sample { $0.sessionPercent = 100 }
        notFound.usageIssue = .claudeNotFound
        for data in [DataSnapshot(), noLimits, notFound] {
            let v = render(data)
            #expect(!v.limitReached && !v.shows(.play))
            #expect(v.playText.isEmpty)
        }
    }

    @Test func theGameCaptionTellsWhenTheLimitResets() {
        #expect(render(sample { $0.sessionPercent = 100 }).gameCaption.hasPrefix("resets in"))
        #expect(render(sample { $0.sessionPercent = 40 }).gameCaption == "The limit has reset: back to work!")
    }

    @Test func theButtonIsGerman() {
        let v = render(sample { $0.sessionPercent = 100 }, lang: .de)
        #expect(v.playText == "Clawd Run spielen, bis es weitergeht")
    }
}
