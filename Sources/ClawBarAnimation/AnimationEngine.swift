import Foundation
import ClawBarClawd
import ClawBarScenes
import ClawBarShared
import ClawBarSky

/// The widget's moving parts on one tick, as mascot-menu.ps1's timer runs them: Clawd first, then the theme's scene
/// or else the sky while it shows, on one generator. The data, a click and the developer menu reach them through here.
public final class AnimationEngine {
    private let clawd: ClawdEngine
    private let sky: SkyEngine
    private let scenes: SceneEngine
    private var config: Config
    /// Where the 20:77 secret finds the Netrunner.
    private var skins: SkinCatalog
    /// The theme's scene as of the last data tick or animation tick.
    private var sceneID: SceneID?
    private(set) var skyDev = SkyDevState()
    private var weather: WeatherSnapshot?
    private var place: Place?
    /// The last frame: Clawd's half empty while he is hidden, the sky's kept while it is hidden.
    public private(set) var frame = AnimationFrame.empty

    /// Clawd's entrance act draws first, then the sky's stars, clouds and fog: one generator, like the original's
    /// shared $script:Rnd.
    public init(random: any RandomSource, config: Config, skins: SkinCatalog, now: Date) {
        clawd = ClawdEngine(random: random, now: now)
        sky = SkyEngine(random: random)
        scenes = SceneEngine(random: random)
        self.config = config
        self.skins = skins
        clawd.wear(skins.skin(for: config.skin))
    }

    /// showMascot: the play area, Clawd and the hearts.
    public var mascotVisible: Bool { config.showMascot }
    /// The sky goes with Clawd: the original's Sync-Mascot collapses it when he hides.
    public var skyVisible: Bool { config.showMascot && config.showSky }
    /// Milliseconds to the next tick: 60 while a Claude Code sequence plays, else 90, also for a scene alone with Clawd
    /// hidden; nil while nothing moves.
    public var tickMilliseconds: Int? {
        mascotVisible ? clawd.tickMilliseconds : sceneID != nil ? SceneEngine.stepMilliseconds : nil
    }

    /// A data tick or a changed setting. Clawd waits for the first registry read, so he starts idle instead of
    /// burrowing; hidden, he forgets the hearts, so showing him again is no loss.
    public func apply(_ data: DataSnapshot, config: Config, skins: SkinCatalog, now: Date, timeZone: TimeZone) {
        self.config = config
        self.skins = skins
        weather = data.weather
        place = data.place
        // Leaving the scene clears it now: with Clawd hidden no tick may follow to do it.
        syncScene(now: now, timeZone: timeZone)
        guard mascotVisible else {
            clawd.resetHearts()
            frame.clawd = .empty
            return
        }
        clawd.wear(skins.skin(for: config.skin))
        if data.sessionsRead { clawd.apply(ClawdDataInput(data, mainLimit: config.mainLimit, critPercent: config.critPercent), now: now) }
    }

    /// A left click on Clawd.
    public func click(now: Date) { clawd.click(now: now) }

    /// record-gif.ps1's drain, which does not stop a demo.
    public func startDrain() { clawd.startDrain() }

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

    /// One animation tick. Clawd steps before the scene or the sky, as the original loads them: all draw from one
    /// generator. A scene steps even with Clawd hidden, where upstream's freezes.
    @discardableResult
    public func step(_ inputs: AnimationInputs) -> AnimationFrame {
        syncScene(now: inputs.now, timeZone: inputs.timeZone)
        if mascotVisible {
            frame.clawd = clawd.step(ClawdStepEnv(
                areaWidth: PlayArea.width(numberWidth: inputs.numberWidth), mouseOverWindow: inputs.mouseOverWindow,
                mouseX: inputs.mouseX, now: inputs.now, lang: config.lang
            ))
        }
        if let id = sceneID {
            // The weather's sky waits, its state kept, until the theme has no scene.
            let row = skyVisible ? CGRect(origin: inputs.skyOrigin, size: PlayArea.skySize) : nil
            let scene = SceneInputs(
                now: inputs.now, timeZone: inputs.timeZone, size: inputs.backdropSize, skyRow: row, lang: config.lang,
                clawdAsleep: mascotVisible && clawd.asleep
            )
            if let f = scenes.step(id, inputs: scene) {
                frame.scene = f
                for cue in f.secret?.cues ?? [] { perform(cue) }
            }
        } else if skyVisible {
            frame.sky = sky.step(size: PlayArea.skySize, inputs: skyInputs(now: inputs.now, timeZone: inputs.timeZone))
        }
        return frame
    }

    /// By season changes the theme at midnight, so the scene follows the clock as the presenter's colours do.
    private func syncScene(now: Date, timeZone: TimeZone) {
        let id = config.theme.theme(at: now, in: timeZone).scene
        if id != sceneID { endSecret() }
        sceneID = id
        if sceneID == nil { frame.scene = nil }
    }

    /// A scene's cue. Hidden, Clawd misses the act, as upstream's scene would have stopped with him, but not the
    /// skin or the mood that must be put back.
    private func perform(_ cue: SceneCue) {
        switch cue {
        case .act(let a): if mascotVisible { clawd.cue(a) }
        case .wake: clawd.wake()
        case .letSleep: clawd.letSleep()
        case .jack(let on): clawd.jack(on ? skins.skin(for: BuiltInSkin.netrunner.rawValue) : nil)
        }
    }

    /// The theme changed or the widget hid: a secret halfway through ends at once, its layer gone, the sky lit and
    /// Clawd himself again.
    public func endSecret() {
        scenes.endSecret()
        frame.scene?.secret = nil
        perform(.jack(false))
        perform(.letSleep)
    }

    /// Starts a scene's secret at `step` on the next scene step: for snapshot mode and the tests.
    public func play(_ secret: SceneSecret, at step: Int = 0) { scenes.play(secret, at: step) }

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
