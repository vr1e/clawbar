import Foundation
import ClawBarAnimation
import ClawBarPresenter
import ClawBarShared

/// What the card shows: the presenter's view state and the animation frame, with the haywire and the chart's readout
/// laid over them. The live app, `--snapshot` and `ScenarioRun` bring the clock, the generator, the pointer and what
/// the card measured.
public final class CardEngine {
    let animation: AnimationEngine
    private var input: PresenterInput?
    private var chartX: Double?
    /// The haywire `shown` carries now.
    private var haywire: SceneHaywire?

    /// The presenter's view state: what every reader but the card's drawing takes.
    public private(set) var presented = WidgetViewState.placeholder
    /// What the card draws: `presented`, scrambled while the 20:77 secret goes haywire.
    public private(set) var shown = WidgetViewState.placeholder
    /// The chart's readout under the pointer, or nil for the legend.
    public private(set) var historyHover: HistoryHover?

    public init(random: any RandomSource, config: Config, skins: SkinCatalog, now: Date) {
        animation = AnimationEngine(random: random, config: config, skins: skins, now: now)
    }

    public var frame: AnimationFrame { animation.frame }
    public var mascotVisible: Bool { animation.mascotVisible }
    public var skyVisible: Bool { animation.skyVisible }
    /// Milliseconds to the next animation tick; nil while nothing moves.
    public var tickMilliseconds: Int? { animation.tickMilliseconds }

    /// A data tick or a changed setting: update.ps1's Update-Widget, the same data into the card and the animation.
    public func present(_ input: PresenterInput, skins: SkinCatalog) {
        self.input = input
        presented = WidgetPresenter.make(input)
        animation.apply(input.data, config: input.config, skins: skins, now: input.now, timeZone: input.timeZone)
        show(changed: true)
        readOut()
    }

    /// One animation tick; `pointerX` is the pointer's x in card space while it is over the widget window.
    public func step(now: Date, timeZone: TimeZone, measure: CardMeasure, pointerX: Double? = nil) {
        animation.step(AnimationInputs(
            now: now, timeZone: timeZone, numberWidth: measure.numberWidth, mouseOverWindow: pointerX != nil,
            mouseX: pointerX.map(measure.mouseX), backdropSize: measure.backdropSize, skyOrigin: measure.skyOrigin
        ))
        show()
    }

    /// The pointer `chartX` base units into the 7-day chart, or nil off it.
    public func hover(chartX: Double?) {
        self.chartX = chartX
        readOut()
    }

    /// The widget hid: a secret halfway through ends at once.
    public func hide() {
        animation.endSecret()
        show()
    }

    /// A left click on Clawd.
    public func click(now: Date) { animation.click(now: now) }

    public func perform(_ action: DevAction) { animation.perform(action) }

    /// Starts a scene's secret at `step` on the next scene step: for snapshot mode and the tests.
    public func play(_ secret: SceneSecret, at step: Int = 0) { animation.play(secret, at: step) }

    public func developerMenu() -> [DevMenuNode] { animation.developerMenu() }

    public func skyTooltip(now: Date, timeZone: TimeZone) -> String { animation.skyTooltip(now: now, timeZone: timeZone) }

    func startDrain() { animation.startDrain() }

    /// Scrambles only when the view state or the haywire changed: the scramble is the same for the same haywire.
    private func show(changed: Bool = false) {
        let next = frame.scene?.secret?.haywire
        guard changed || next != haywire else { return }
        haywire = next
        shown = Haywire.scramble(presented, next)
    }

    /// From the presented chart, so the readout stays true under a haywire and goes when the chart does.
    private func readOut() {
        guard let x = chartX, let chart = presented.history, let input else {
            historyHover = nil
            return
        }
        historyHover = HistoryReadout.hover(x: x, chart: chart, input: input)
    }
}
