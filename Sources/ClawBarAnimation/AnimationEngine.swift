import Foundation
import ClawBarClawd
import ClawBarShared
import ClawBarSky

/// The widget's moving parts on one tick, as mascot-menu.ps1's timer runs them: Clawd first, then the sky while it
/// shows, on one generator. The data, a click and the developer menu reach both through here.
public final class AnimationEngine {
    private let clawd: ClawdEngine
    private let sky: SkyEngine
    private var config: Config
    private(set) var skyDev = SkyDevState()
    private var weather: WeatherSnapshot?
    private var place: Place?
    /// The last frame: Clawd's half empty while he is hidden, the sky's kept while it is hidden.
    public private(set) var frame = AnimationFrame.empty

    /// Clawd's entrance act draws first, then the sky's stars, clouds and fog: one generator, like the original's
    /// shared $script:Rnd.
    public init(random: any RandomSource, config: Config, now: Date) {
        clawd = ClawdEngine(random: random, now: now)
        sky = SkyEngine(random: random)
        self.config = config
    }

    /// showMascot: the play area, Clawd and the hearts.
    public var mascotVisible: Bool { config.showMascot }
    /// The sky goes with Clawd: the original's Sync-Mascot collapses it when he hides.
    public var skyVisible: Bool { config.showMascot && config.showSky }
    /// Milliseconds to the next tick: 60 while a Claude Code sequence plays, else 90; nil while nothing moves.
    public var tickMilliseconds: Int? { mascotVisible ? clawd.tickMilliseconds : nil }

    /// A data tick or a changed setting. Clawd waits for the first registry read, so he starts idle instead of
    /// burrowing; hidden, he forgets the hearts, so showing him again is no loss.
    public func apply(_ data: DataSnapshot, config: Config, now: Date) {
        self.config = config
        weather = data.weather
        place = data.place
        guard mascotVisible else {
            clawd.resetHearts()
            frame.clawd = .empty
            return
        }
        if data.sessionsRead { clawd.apply(ClawdDataInput(data, mainLimit: config.mainLimit, critPercent: config.critPercent), now: now) }
    }

    /// A left click on Clawd.
    public func click(now: Date) { clawd.click(now: now) }

    /// record-gif.ps1's drain, which does not stop a demo.
    func startDrain() { clawd.startDrain() }

    /// A developer-menu click. An override shows on the next tick, since the sky's key includes the phase and the code.
    public func perform(_ action: DevAction) {
        switch action {
        case .skyPhase(let phase): skyDev.phase = phase
        case .skyWeather(let code): skyDev.weatherCode = code
        case .auto:
            clawd.perform(.auto)
            skyDev = SkyDevState()
        default: clawd.perform(action)
        }
    }

    /// One animation tick. Clawd steps before the sky, as the original loads them: both draw from one generator.
    @discardableResult
    public func step(_ inputs: AnimationInputs) -> AnimationFrame {
        guard mascotVisible else { return frame }
        frame.clawd = clawd.step(ClawdStepEnv(
            areaWidth: PlayArea.width(numberWidth: inputs.numberWidth), mouseOverWindow: inputs.mouseOverWindow,
            mouseX: inputs.mouseX, now: inputs.now, lang: config.lang
        ))
        if skyVisible {
            frame.sky = sky.step(size: PlayArea.skySize, inputs: skyInputs(now: inputs.now, timeZone: inputs.timeZone))
        }
        return frame
    }

    /// mascot-menu.ps1's developer menu as it opens now, its Sky submenu enabled only while the sky shows.
    public func developerMenu() -> [DevMenuNode] {
        DevMenu.build(dev: clawd.devState, sky: skyDev, skyVisible: skyVisible, lang: config.lang)
    }

    /// The sky's tooltip, on the real sun times at `now`, also where a forced phase draws the fallback sun.
    public func skyTooltip(now: Date, timeZone: TimeZone) -> String {
        SkyInfo.tooltip(
            weather, place: place, sun: skyInputs(now: now, timeZone: timeZone).sun, now: now, dev: skyDev, lang: config.lang
        )
    }

    private func skyInputs(now: Date, timeZone: TimeZone) -> SkyInputs {
        SkyInfo.inputs(weather, place: place, now: now, localZone: timeZone, dev: skyDev)
    }
}
