import CoreGraphics
import Foundation
import Testing
import ClawBarAnimation
import ClawBarClawd
import ClawBarData
import ClawBarPresenter
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

private func pinDiagnostics(_ paths: AppPaths) async {
    let report: DiagnosticsReport = await Diagnostics.run(config: Config(), paths: paths)
    let _: String = report.text
}

private func pinPresenter() {
    let input = PresenterInput(config: Config(), now: Date(), timeZone: .gmt, data: .empty, tickError: false, appVersion: AppInfo.version)
    let _: WidgetViewState = WidgetPresenter.make(input)
    let _: HistoryHover = HistoryReadout.hover(x: 118, chart: HistoryView(label: ""), input: input)
}

private func pinClawd() {
    let engine = ClawdEngine(random: SeededRandomSource(seed: 1), now: Date())
    engine.apply(ClawdDataInput(busy: 0, waiting: 0, sessionCount: 0, limit: .session, pct: nil, reset: nil, critPercent: 85), now: Date())
    engine.click(now: Date())
    let _: ClawdFrame = engine.step(ClawdStepEnv(areaWidth: 180, mouseOverWindow: false, mouseX: nil, now: Date(), lang: .en))
    let _: Int = engine.tickMilliseconds
    let _: ClawdDevState = engine.devState
    engine.resetHearts()
    engine.startDrain()
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
    let engine = AnimationEngine(random: SeededRandomSource(seed: 1), config: Config(), now: Date())
    engine.apply(.empty, config: Config(), now: Date())
    engine.click(now: Date())
    engine.perform(.skyPhase(.night))
    let _: AnimationFrame = engine.step(AnimationInputs(now: Date(), timeZone: .gmt, numberWidth: 32, mouseOverWindow: false, mouseX: nil))
    let _: AnimationFrame = engine.frame
    let _: Int? = engine.tickMilliseconds
    let _: Bool = engine.mascotVisible
    let _: Bool = engine.skyVisible
    let _: [DevMenuNode] = engine.developerMenu()
    let _: String = engine.skyTooltip(now: Date(), timeZone: .gmt)
    let run = ScenarioRun(.tour, seed: 42)
    let _: ScenarioFrame? = run.next(numberWidth: 32)
    let _: Config = run.config
    let _: DataSnapshot = run.data
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
