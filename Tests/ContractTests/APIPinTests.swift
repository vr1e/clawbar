import CoreGraphics
import Foundation
import Testing
import ClawBarAnimation
import ClawBarCard
import ClawBarClawd
import ClawBarData
import ClawBarPresenter
import ClawBarScenes
import ClawBarShared
import ClawBarSky

// These functions are never called: they only have to compile, which pins each agent-owned API.
// Calling them would start real probes.

@MainActor
private func pinDataController(_ paths: AppPaths) {
    let dc = DataController(config: Config(), paths: paths)
    let _: DataSnapshot = dc.snapshot
    dc.onChange = { @MainActor in }
    dc.apply(config: Config())
    dc.tick(now: Date())
    dc.pollSessions(now: Date())
    dc.refreshNow()
    dc.startClaudeUpdate()
    dc.shutdown()
}

private func pinConfigStore(_ paths: AppPaths) throws {
    let store = ConfigStore(paths: paths)
    let _: URL = store.url
    let _: Config = store.load()
    let _: Config? = store.reloadIfChanged()
    let _: Bool = store.isUnreadable
    try store.update { $0.scale = 1.3 }
    let _: Config = try store.update { $0.expanded = true }
    try store.ensureExists()
}

private func pinSkinFolder(_ paths: AppPaths) throws {
    let folder = SkinFolder(paths: paths)
    let _: URL = folder.url
    let _: SkinCatalog? = folder.reloadIfChanged()
    try folder.ensureExists()
}

private func pinDiagnostics(_ paths: AppPaths) async {
    let report: DiagnosticsReport = await Diagnostics.run(config: Config(), paths: paths)
    let _: String = report.text
}

private func pinPresenter() {
    let input = PresenterInput(config: Config(), now: Date(), timeZone: .gmt, data: .empty, tickError: false, appVersion: AppInfo.version)
    let _: WidgetViewState = WidgetPresenter.make(input)
    let _: WidgetViewState = Haywire.scramble(.sample, SceneHaywire(strength: 0.2, seed: 1))
    let _: HistoryHover = HistoryReadout.hover(x: 118, chart: HistoryView(label: ""), input: input)
}

private func pinClawd() {
    let engine = ClawdEngine(random: SeededRandomSource(seed: 1), now: Date())
    engine.apply(ClawdDataInput(busy: 0, waiting: 0, sessionCount: 0, main: UsageLimit(kind: .session), critPercent: 85), now: Date())
    engine.click(now: Date())
    let _: ClawdFrame = engine.step(ClawdStepEnv(areaWidth: 180, mouseOverWindow: false, mouseX: nil, now: Date(), lang: .en))
    let _: Int = engine.tickMilliseconds
    let _: ClawdDevState = engine.devState
    engine.resetHearts()
    engine.startDrain()
    engine.cue(.jump)
    let _: Bool = engine.asleep
    engine.wake()
    engine.letSleep()
    engine.jack(nil)
    engine.perform(.mood(.work))
    let _: [DevMenuNode] = DevMenu.build(dev: ClawdDevState(), sky: SkyDevState(), skyVisible: true, lang: .de)
}

private func pinSky() {
    let sky = SkyEngine(random: SeededRandomSource(seed: 1))
    let inputs = SkyInputs(
        now: Date(), timeZone: .gmt, sun: .fallback, weather: nil, latitude: 50, forcedPhase: nil
    )
    let _: SkyFrame = sky.step(size: PlayArea.skySize, inputs: inputs)
    let _: SkyWeather? = SkyInfo.skyWeather(nil, now: Date(), dev: SkyDevState())
    let (_, _): (SunTimes, TimeZone) = SkyInfo.sunTimes(nil, place: nil, now: Date(), localZone: .gmt)
    let _: Double = SkyInfo.latitude(place: nil)
    let _: SkyInputs = SkyInfo.inputs(nil, place: nil, now: Date(), localZone: .gmt, dev: SkyDevState())
    let _: String = SkyInfo.tooltip(nil, place: nil, sun: .fallback, now: Date(), dev: SkyDevState(), lang: .en)
}

private func pinAnimation() {
    let engine = AnimationEngine(random: SeededRandomSource(seed: 1), config: Config(), skins: .builtIn, now: Date())
    engine.apply(.empty, config: Config(), skins: .builtIn, now: Date(), timeZone: .gmt)
    engine.click(now: Date())
    engine.perform(.skyPhase(.night))
    let _: AnimationFrame = engine.step(AnimationInputs(
        now: Date(), timeZone: .gmt, numberWidth: 32, mouseOverWindow: false, mouseX: nil, backdropSize: CGSize(width: 260, height: 220),
        skyOrigin: CGPoint(x: 12, y: 30)
    ))
    let scenes = SceneEngine(random: SeededRandomSource(seed: 1))
    let _: SceneFrame? = scenes.step(.christmas, inputs: SceneInputs(
        now: Date(), timeZone: .gmt, size: CGSize(width: 260, height: 220), skyRow: CGRect(x: 12, y: 30, width: 236, height: 43)
    ))
    let _: SceneFrame? = scenes.step(.cyberpunk, inputs: SceneInputs(
        now: Date(), timeZone: .gmt, size: CGSize(width: 260, height: 220), skyRow: nil, lang: .de, clawdAsleep: true
    ))
    scenes.play(.scare)
    scenes.play(.relic, at: 60)
    scenes.endSecret()
    engine.play(.scare)
    engine.endSecret()
    let _: Int = SceneEngine.stepMilliseconds
    let _: SceneID? = Theme.christmas.scene
    let _: AnimationFrame = engine.frame
    let _: Int? = engine.tickMilliseconds
    let _: Bool = engine.mascotVisible
    let _: Bool = engine.skyVisible
    let _: [DevMenuNode] = engine.developerMenu()
    let _: String = engine.skyTooltip(now: Date(), timeZone: .gmt)
    engine.startDrain()
}

private func pinCard() {
    let card = CardEngine(random: SeededRandomSource(seed: 1), config: Config(), skins: .builtIn, now: Date())
    card.present(PresenterInput(config: Config(), now: Date(), timeZone: .gmt, data: .empty), skins: .builtIn)
    let measure = CardMeasure(
        numberWidth: 32, cardSize: CGSize(width: 262, height: 222), percentRow: CGRect(x: 13, y: 31, width: 236, height: 40), scale: 1
    )
    let _: CGSize = measure.backdropSize
    let _: CGPoint = measure.skyOrigin
    let _: Double = measure.mouseX(cardX: 100)
    let _: AnimationFrame = card.step(now: Date(), timeZone: .gmt, measure: measure, pointerX: 100)
    card.hover(chartX: 40)
    card.click(now: Date())
    card.perform(.skyPhase(.night))
    card.play(.relic, at: 60)
    card.hide()
    let _: WidgetViewState = card.presented
    let _: WidgetViewState = card.shown
    let _: HistoryHover? = card.historyHover
    let _: AnimationFrame = card.frame
    let _: Int? = card.tickMilliseconds
    let _: Bool = card.mascotVisible
    let _: Bool = card.skyVisible
    let _: [DevMenuNode] = card.developerMenu()
    let _: String = card.skyTooltip(now: Date(), timeZone: .gmt)
    let run = ScenarioRun(.tour, seed: 42)
    let _: ScenarioFrame? = run.next(CardMeasure(numberWidth: 32))
    let _: Config = run.config
    let _: DataSnapshot = run.data
    let _: CardEngine = run.card
    let _: Bool = run.crop
}

@Suite struct APIPinTests {
    @Test func thePinsCompile() {
        // The real check happens at compile time; this keeps the file a test target.
        #expect(Bool(true))
    }

    @Test func samplesAreSelfConsistent() {
        #expect(DataSnapshot.sample.usage?.sessionPercent == 34)
        #expect(WidgetViewState.sample.pctText == "34")
        #expect(ClawdFrame.sample.spriteRect.size == CGSize(width: 36, height: 26.4))
        #expect(ClawdFrame.sample.ops.count == 2)
        #expect(!SkyFrame.sample.ops.isEmpty)
    }
}
