# ClawBar

A native macOS port of Enhed's Windows widget clawd-usage-winwidget 1.3.0: a menu bar item with the Claude
session %, and a floating widget where the pixel mascot Clawd lives over a time-of-day sky. Behaviour follows the
original unless README.md's "Differences from the original" says otherwise; when in doubt, the original's source
wins. Before changing how something behaves or looks, read it in `docs.local/` (git-ignored, may be absent):
`original/` is the 1.3.0 PowerShell source, read as data and never executed; `port-spec/` describes its modules.
For what is left from upstream, or whether a feature is ported, read `upstream-features.md` (one row per upstream
feature and its status); when a feature lands or a review moves on, update its rows and run
`swift docs.local/parity-table.swift`, which rebuilds README's parity table.

A change is one branch, named from its title (`extract-the-probe-schedule-into-a-pure-dataengine`), squash-merged
to `main` by PR; it leaves the version alone. Releases are cut from `main` by the `release` skill
(`.claude/skills/release/`), which bumps it.

## Toolchain

- The package builds with the Command Line Tools alone: no `xcodebuild`, `actool`, string catalogs or XCTest
  (tests use Swift Testing). Shipped targets carry no resources either, since `Bundle.module` breaks in the
  hand-assembled .app: strings are the Swift tables in `Sources/ClawBarShared/I18n/`.
- Their SwiftUI lacks its macro plugin, so `@State`, `@Entry`, `@Animatable` and `#Preview` do not compile. State
  lives in `@Observable` classes (that macro works) passed into views; environment values use a hand-written
  `EnvironmentKey` (see `uiScale` in `Sources/ClawBar/Views/Metrics.swift`).

## Rules

- Every value the modules pass each other is a type in `Sources/ClawBarShared/`; each other target owns one concern
  and exports only its entry points. The libraries depend on `ClawBarShared` alone, except `ClawBarAnimation`, which
  composes `ClawBarClawd` and `ClawBarSky` through their entry points.
- Before naming a type or writing about the data, the moving side or the card, read `GLOSSARY.md`: the words for
  probe, data snapshot, data engine, latch, recipe, snapshot mode (the `--snapshot` render, not a data snapshot),
  animation tick, animation engine, animation frame, play area, theme palette, part, region and role, and the ones to
  avoid.
- `AnimationEngine`, `ClawdEngine`, `DataEngine`, `RunnerEngine`, `SkyEngine`, `SkyInfo` and `WidgetPresenter` are
  pure: time, time zone and randomness arrive as inputs (`SeededRandomSource` in tests), and statics are `let`.
  `CommandRecipes` carries out the `DataEngine` commands that reach processes, the network and disk, one recipe each,
  and returns their answer events; `DataController` (Tasks, the error log, `onChange`) and `--diagnose` (one pass at
  one instant, until a tick asks for nothing) are its two adapters. The live app drives `AnimationEngine` with the
  wall clock, `SystemRandomSource` and the pointer, while `--snapshot` and `ScenarioRun` (behind `--record` and the
  tests) use a virtual clock and a seeded generator, with no pointer.
- The `ClawBar` target is MainActor by default: Timer and notification blocks run inside `MainActor.assumeIsolated`.
- Regular expressions are statics built with `Rx.make` (`Sources/ClawBarShared/Rx.swift`).
- The original rounds half to even (`[int]`, `[byte]`, `[math]::Round`): use `.rounded(.toNearestOrEven)`.
- Comments say why, in one line where one suffices.

## Safety

Tests run against fake executables, fixtures and a temporary `AppPaths(root:)`, and drive the login item through a
fake `LoginItemService`, so `SMAppService` never runs in a test. `claude update` runs only against the fake `claude`
in tests, since a real run updates the user's Claude Code. Sessions are read from `<pid>.json` alone; the `*.key`
files beside them in `~/.claude/sessions/` are secrets and stay unopened.

## Checking a change

- `swift build && swift test`; no CI runs them.
- Anything visible: `.build/debug/ClawBar --snapshot <dir>` renders every widget state in both languages at three
  sizes, the menu bar item, and the menus as text; open the PNGs to look.
- Probes: `.build/debug/ClawBar --diagnose` runs the engine once against the real `claude` and network, through the
  app's recipes; its `log:` lines are what error.log would get.
- The running app: start `CLAWBAR_HOME=<any dir> .build/debug/ClawBar` in the background; with no mode the binary
  is the app and never exits. Without `CLAWBAR_HOME` it runs on the user's real files, or, when the installed app is
  running, only tells it to show its widget and exits. `--dump-state` and `--command <cmd>` reach the copy on the
  same `CLAWBAR_HOME`; `--command quit` ends it.
- `scripts/build-app.sh --install` replaces the user's installed ClawBar, quitting the running copy; run it only
  when the user asks to install.
