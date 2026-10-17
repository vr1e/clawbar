# ClawBar

A native macOS port of Enhed's Windows widget clawd-usage-winwidget 1.3.0: a menu bar item with the Claude
session %, and a floating widget where the pixel mascot Clawd lives over a time-of-day sky. Behaviour follows the
original unless README.md's "Differences from the original" says otherwise; when in doubt, the original's source
wins. Before changing how something behaves or looks, read it in `docs.local/` (git-ignored, may be absent):
`original/` is the 1.3.0 PowerShell source, read as data and never executed; `port-spec/` describes its modules.

## Toolchain

- The package builds with the Command Line Tools alone: no `xcodebuild`, `actool`, string catalogs or XCTest
  (tests use Swift Testing).
- Their SwiftUI lacks its macro plugin, so `@State`, `@Entry`, `@Animatable` and `#Preview` do not compile. State
  lives in `@Observable` classes (that macro works) passed into views; environment values use a hand-written
  `EnvironmentKey` (see `uiScale` in `Sources/ClawBar/Views/Metrics.swift`).

## Rules

- Every value the modules pass each other is a type in `Sources/ClawBarShared/`; each other target owns one concern
  and exports only its entry points.
- `ClawdEngine`, `SkyEngine`, `SkyInfo` and `WidgetPresenter` are pure: time, time zone and randomness arrive as
  inputs (`SeededRandomSource` in tests), and statics are `let`.
- The `ClawBar` target is MainActor by default: Timer and notification blocks run inside `MainActor.assumeIsolated`.
- Regular expressions are statics built with `Rx.make` (`Sources/ClawBarShared/Rx.swift`).
- The original rounds half to even (`[int]`, `[byte]`, `[math]::Round`): use `.rounded(.toNearestOrEven)`.
- Comments say why, in one line where one suffices.

## Safety

Tests run against fake executables, fixtures and a temporary `AppPaths(root:)`, and drive the login item through a
fake `LoginItemService`, so `SMAppService` never runs in a test. Never run `claude update`, and never open
`~/.claude/sessions/*.key` (secrets).

## Checking a change

- `swift build && swift test`; no CI runs them.
- Anything visible: `.build/debug/ClawBar --snapshot <dir>` renders every widget state in English and German at
  k 1.0, 1.2 and 2.0, the menu bar item, and both menus as text; open the PNGs to look.
- Probes: `.build/debug/ClawBar --diagnose` runs each once against the real `claude` and network.
- The running app: start `CLAWBAR_HOME=<any dir> .build/debug/ClawBar` in the background. With no mode the binary is
  the app and never exits; without `CLAWBAR_HOME` it uses the user's real files, or only shows the installed app's
  widget. `--dump-state` and `--command <cmd>` reach it under the same `CLAWBAR_HOME`; `--command quit` ends it.
