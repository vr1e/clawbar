# ClawBar

Your Claude plan limits, kept in the macOS menu bar by a very small crab. ClawBar shows the session % up there and
floats a widget where Clawd, the pixel crab from Claude Code's welcome screen, goes about his day under a sky that
matches yours. It is a native Swift port of
[clawd-usage-winwidget](https://github.com/Enhed/clawd-usage-winwidget) by Enhed, based on 1.3.0 with some features of
later releases.

<img src="assets/preview.png" width="339" alt="The ClawBar widget with its details open">

- **Menu bar item:** a mini Clawd beside the session %, coloured by how close you are to the limit: green, amber
  from 60%, red from 85%.
- **Widget:** the session % and the time until the window resets, the week and each model's week (Fable, Sonnet),
  the Claude Code sessions running right now with a hover list, Anthropic's service status, your last 24 hours and
  7 days in detail, the Claude Code version with a one-click update, and your plan and account.
- **Clawd** lives by your numbers. He works while a session is busy, hops up with a "?" when one waits for you,
  wanders and dozes when things are quiet, and burrows in to sleep when nothing runs. Near the limit he sweats; at
  100% he lies belly-up. Three hearts show how much of the session is left, and a click gets you a trick.
- **Clawd Run:** once the session limit is used up, the widget and the menu offer a game to pass the wait, after the
  Chrome dinosaur's: Clawd jumps cacti and ducks under bugs while the corner counts down to the reset.
- **The sky** behind him keeps your real time of day and your real weather: the sun and the moon on their true
  course, the moon in its true phase, stars, clouds, fog, rain, snow and the odd thunderstorm. Hover it for the
  weather, the sun times and the moon.
- **English and German**, switchable while it runs.

The numbers come from Claude Code's own `/usage` command, run locally in a mode that never reaches the model. It
costs no tokens, and ClawBar makes sure of that on every run.

## Install

ClawBar needs macOS 14 or later and [Claude Code](https://claude.ai/code) installed and logged in. Building it takes
a Swift 6.2 toolchain (Xcode or the Command Line Tools), which needs macOS 15.6 or later; on an older macOS, download
the app from [Releases](https://github.com/vr1e/clawbar/releases) instead. To build it:

```sh
git clone https://github.com/vr1e/clawbar && cd clawbar
scripts/build-app.sh --install
open /Applications/ClawBar.app
```

The script builds a release binary, wraps it in an ad-hoc-signed `ClawBar.app` and copies it to `/Applications`,
quitting a running copy first. ClawBar registers itself to open at login; untick **Launch at login** in its menu if
you would rather it waited to be asked.

To update, pull and run the last two commands again. `config.json` and ClawBar's other files stay where they are.

## Use

- **Left-click** the menu bar item to show or hide the widget; **right-click** (or ctrl-click) it for the menu:
  Refresh now, Larger, Smaller, Always on top, Launch at login, Clawd in menu bar, Open config.json, Show in widget
  (which blocks the widget shows), Language, Quit. Untick Clawd in both places for the numbers alone.
- **Drag** the widget by anything but Clawd and the buttons. ▾ opens the details, – hides the widget, ✕ quits.
- **Click** the status line to open status.claude.com, the version line to run `claude update` when one is out
  (otherwise it opens the changelog), and the ClawBar line to visit the original project.
- **Right-click Clawd or the sky** for the developer menu: force a mood, play any animation, set the hearts, pick a
  time of day or weather, or sit back and watch everything in turn.
- **Play Clawd Run** while the session limit is used up: click the orange *Play Clawd Run while you wait* button
  under the reset time, or pick it from the menu. Space, ↑ or a click jumps (hold for higher), ↓ ducks, Esc closes.
  The round pauses while the window is in the background and goes on at the next press; the high score lasts until
  ClawBar quits.
- Only one ClawBar runs at a time; opening it again simply brings the widget back.

## Configuration

`~/Library/Application Support/ClawBar/config.json` appears on the first change, or with every key when you pick
**Open config.json**. Edits take effect on the next refresh (10 s by default). ClawBar writes only the keys it
changes, so your edits and unknown keys survive, and a value it cannot read falls back to that key's default. While
the file is not valid JSON, ClawBar runs on the defaults and the widget's last-update stamp says *error*.

| Key | Default | Meaning |
|---|---|---|
| `language` | `en` | `en` or `de` |
| `scale` | `1.2` | widget size, 0.6–4.0 |
| `opacity` | `1.0` | 0.2–1.0 |
| `topmost` | `false` | keep the widget above other windows |
| `warnPercent`, `critPercent` | `60`, `85` | level colour thresholds, 1–100 |
| `expanded` | `false` | details open |
| `showStats`, `showStatus`, `showSessions`, `showAccount`, `showMascot`, `showSky` | `true` | blocks to show, also under **Show in widget** |
| `weatherLat`, `weatherLon` | unset | weather for these coordinates instead of your IP's location |
| `refreshSeconds` | `10` | UI refresh, 2–300 |
| `usageIntervalSeconds` | `60` | `/usage` probe, 30–3600 |
| `statusIntervalSeconds` | `120` | service status, 30–3600 |
| `accountIntervalSeconds` | `600` | account, 60–86400 |
| `versionIntervalSeconds` | `3600` | Claude Code version, 600–86400 |
| `weatherIntervalSeconds` | `900` | weather, 300–86400 |
| `left`, `top` | unset | widget position, saved when you move it |
| `claudePath` | unset | a `claude` executable to use first |
| `launchAtLogin` | `true` | open at login |
| `menuBarMascot` | `true` | Clawd beside the % in the menu bar |

## What it reads and sends

Everything ClawBar touches, so you know there is nothing else:

- **Claude Code:** `claude -p /usage` (with safe mode and no session persistence), `claude auth status`,
  `claude --version`, and `claude update` when you click it. It reads `~/.claude/sessions/<pid>.json` to list
  sessions (never the `.key` files next to them) and `settings.json` for the update channel; `~/.claude` stands for
  Claude Code's folder, or `CLAUDE_CONFIG_DIR` when that is set.
- **Your login shell:** run once at start (`$SHELL -ilc`) to learn claude's path, `PATH` and `CLAUDE_CONFIG_DIR`,
  which a GUI app does not inherit. If it gives no answer within 5 seconds and claude is nowhere to be found,
  ClawBar asks again every usage interval, at most three more times.
- **Network:** status.claude.com (status), downloads.claude.ai (latest version), raw.githubusercontent.com (the
  changelog, only while an update is out), ipwho.is (your approximate location, unless coordinates are set),
  api.open-meteo.com (weather) and api.met.no (weather fallback). Each request names ClawBar, its version and its
  GitHub page in the User-Agent.
- **Its own files** live in `~/Library/Application Support/ClawBar/`: `config.json`, `state.json`, `error.log`,
  `update.log`, `usage-history.json` (the session and week percentages of the last 8 days, from its own `/usage`
  checks), `clawbar.lock` (keeps a second copy from starting) and `state-dump.txt` (written for `--dump-state`).

## Command line

`/Applications/ClawBar.app/Contents/MacOS/ClawBar` takes one mode:

| Mode | Does |
|---|---|
| `--diagnose` | runs every probe once and prints what it found |
| `--snapshot <dir>` | renders every widget state in both languages at three sizes, plus the menu bar item; writes the menu bar text, its tooltip and the menus as text |
| `--record <scenario> <gif>` | records an animated scenario: `tour`, `sleep`, `limit`, `reset`, `hearts`, `weather`, `clicks` |
| `--dump-state` | prints the running app's state |
| `--command <cmd>` | sends `toggle`, `show`, `larger`, `smaller`, `refresh`, `quit` or `lang <en\|de>` to the running app |
| `--make-icon <dir>` | writes the app icon set |
| `--version` | prints the version |

## Troubleshooting

- **No menu bar item:** a crowded menu bar hides items behind the notch, and on macOS 26 and later System Settings
  › Menu Bar can switch an app's item off. The widget opens at every start, and opening ClawBar again brings it back.
- **Nothing appears at all:** ClawBar exits when it cannot lock `clawbar.lock`, and leaves a note saying why on
  stderr, in `error.log` when it can write there, and in the unified log:
  `log show --last 1h --predicate 'subsystem == "dev.vr1e.clawbar"'`.
- **No numbers or reset times:** the widget says why they are missing. `ClawBar --diagnose` runs every probe once
  and prints what it found, and `error.log` gets a line whenever a probe starts failing or Claude Code prints a
  reset time ClawBar cannot read.
- **A crash:** macOS keeps the report in Console under Crash Reports.

## Differences from the original

<!-- parity-table: begin; generated from a private feature map, so edits here are overwritten -->
ClawBar ports clawd-usage-winwidget 1.3.0 and has been checked against every release up to 1.18.0.
*Ported differently* has its gist in the notes and its details in the bullets below.

| Feature | In ClawBar | Notes |
|---|---|---|
| Usage limits | ✅ Ported differently | A stricter token-free check, more reset-time formats and a row for every model's week. |
| Sessions | ✅ Ported differently | Refreshed every 2 s, and stricter about what counts as a session. Not yet: Sessions from other machines. |
| Clawd and his hearts | ✅ Ported | |
| Sky and weather | ✅ Ported differently | The sky keeps the weather location's time zone, and its moon is closer to the real one. |
| Service status | ✅ Ported | |
| Account and plan | ✅ Ported | |
| Claude Code version and update | ✅ Ported differently | The update runs in the background and explains a failure. |
| Widget window | ✅ Ported differently | On every Space, and opens at login by itself. |
| Menu bar item | ✅ Ported differently | It replaces the tray icon, and its tooltip lists every limit with its reset. Not yet: A shorter menu with Settings. |
| Languages | ✅ Ported differently | English is worded for macOS and German is added. Not ported: Russian; French. |
| The widget's own version and updates | ✅ Ported differently | It shows ClawBar's version and links to the original. Not ported: Self-update from GitHub releases. |
| 7-day history | ✅ Ported | Not yet: Chart of the session and week limits; The week's top projects. |
| Themes and skins | ⏳ Not yet | |
| Settings window | ⏳ Not yet | Not ported: A tab for Claude Code's own settings. |
| Clawd's panel: chat, reminders, lists and tasks | ➖ Not ported | ClawBar keeps to usage, sessions and Clawd. |
| PC tips | ➖ Not ported | They look over a Windows PC. |
| Clawd's Remote Control session | ➖ Not ported | It belongs with the chat. |
| Run as administrator | ➖ Not ported | Windows-only. |
<!-- parity-table: end -->

- A menu bar item replaces the tray icon; the default size is 1.2, which suits Retina points. Its menu adds always
  on top and launch at login, and a Show in widget submenu stands in for the original's Settings window.
- The menu bar item's tooltip gives every limit a line of its own, each model's week included, with the time left
  and the clock time of its reset: `34% of session · 2h 05m (16:10)`. The original's tray stops at 63 characters and
  shows clock times (since 1.5.3) only in place of the countdowns, behind a setting. Stale numbers turn the item grey,
  and its tooltip says when they are from. Its last line counts the sessions, so a waiting one shows with the widget
  hidden.
- The usage probe runs Claude Code in safe mode with JSON output, stops for good (until the next Claude Code
  version) if it ever reaches the model or a flag is rejected, and says so on the widget.
- `/usage` parsing also reads the reset stamps Claude Code 2.1.302 prints (with *at*, a year, or a time only),
  honours the time zone in brackets, gives every model's week its own row, and reads singular headers and
  comma-grouped counts.
- Every probe has a timeout. `claude update` runs in the background for up to 15 minutes and reports a failure with
  its output, plus how to update a Homebrew or npm install. A clean exit that leaves the old version counts as a
  failure, and a failure clears once Claude Code has updated anyway or a newer release is out.
- The widget shows why numbers are missing: Claude Code not found (with the install command), a login without a
  Claude subscription, or a stopped probe.
- Sessions refresh every 2 seconds. A `claude -p` run counts only once it is 20 seconds old, so another tool's
  `/usage` check does not show up as a session or wake Clawd.
- A session in the `shell` state counts as working, spare sessions and the daemon are not counted, and the hover
  list shows folders relative to `~`. A session whose `procStart` is no Windows time between 1990 and 2100 is kept
  rather than dropped.
- The ClawBar line and the menu header carry ClawBar's own version. Hovering the line names the original release it
  ports and clicking it opens the original project, where the original shows and opens its changelog.
- The sky uses the weather location's time zone, retries Open-Meteo hourly after falling back to met.no, and draws
  polar days and nights as day and night. Its moon phase corrects three signs in the original's formula, which
  brings it to within about an hour of the real moon, where the original can be six hours off.
- ClawBar opens at login as a login item, on by default, where the original's README shows how to set up a
  scheduled task.
- The widget stays on all Spaces, pauses its animation while hidden or covered, and moves back on screen if its
  saved position lies on a display that is gone.
- Clawd picks his walks inside his play area instead of heading for the edge, and the bars span exactly the
  widget's width.
- Clawd Run, the game for a used-up session limit, is ClawBar's own; the original has nothing like it.

## Development

```sh
swift build
swift test
.build/debug/ClawBar --snapshot /tmp/clawbar-snap
```

The package has one target per concern: `ClawBarShared` (every type the others share, and the English and German
string tables), `ClawBarData` (probes, sessions, config, weather), `ClawBarPresenter` (every display rule),
`ClawBarClawd`, `ClawBarSky`, `ClawBarGame` (Clawd Run) and the `ClawBar` app. `AGENTS.md` lists the toolchain quirks
and rules.

`CLAWBAR_HOME=<dir>` runs ClawBar on that folder instead of Application Support, so a build can run next to the
installed app. Each folder has its own single copy, `--command` and `--dump-state` reach the copy on the same
`CLAWBAR_HOME`, and only the installed app on the default folder manages the login item.

## License

MIT. ClawBar includes the original's copyright notice (© 2026 Venger Sergey); see [LICENSE](LICENSE).

---

Not affiliated with Anthropic. Clawd and Claude are Anthropic's.
