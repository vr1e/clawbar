# ClawBar

The words ClawBar's code uses for what it shows: Claude Code's usage and sessions, and the world Clawd lives in.

## Language

**Probe**:
One look at a source that answers one question: the usage limits, the account, the Claude Code version, the service status. Each runs on its own cadence.
_Avoid_: check, poll, fetch

**Data snapshot**:
Everything the probes and the session registry last found, as one value the presenter reads.
_Avoid_: state, model, snapshot (alone)

**Data engine**:
The decisions of the data side: which probe runs when, and what each answer does to the data snapshot. It takes an event and the time, and returns the work it wants done.
_Avoid_: scheduler, policy, controller

**Main limit**:
The limit the big number, its bar, the reset line, the menu bar item and Clawd follow: the session by default, or the all-models week (`mainLimit`). The other one takes the row under it.
_Avoid_: primary limit, big limit

**Latch**:
The usage probe stopped for good under one Claude Code version, because a run reached the model or had a flag rejected. A new version lifts it.
_Avoid_: lock, block

**Recipe**:
The steps that carry out one of the data engine's commands against a process, the network or disk and turn what came back into its answer. Written once per command; the app and `--diagnose` run the same ones.
_Avoid_: executor, handler, pipeline

**Snapshot mode**:
The `--snapshot` run that renders every widget state to PNGs for the README and for review. Not a data snapshot.
_Avoid_: screenshot mode

**Animation tick**:
One step of everything that moves: Clawd, his hearts and the sky, every 90 ms (60 while a Claude Code sequence plays), only while the widget shows and has Clawd. Not the data tick.
_Avoid_: frame tick, timer tick

**Animation engine**:
The decisions of the moving side: what Clawd and the sky do on an animation tick, and what the data, a click or a developer action does to them. It takes the data snapshot, the settings and one tick's inputs, and returns the frame and the cadence of the next tick.
_Avoid_: animator, stepper, ticker

**Animation frame**:
Everything one animation tick drew: Clawd with his hearts, and the sky.
_Avoid_: scene (upstream's animated themes), picture

**Theme palette**:
The colours a theme changes, one per role: the background, the text tiers (secondary, muted, label, footer), the accent, the model-week bar and the empty heart. The presenter resolves it into the view state; the levels, Clawd, the sky, the card's border and tracks, and the chart's fill, cursor and session line stay fixed.
_Avoid_: theme (the config's choice of look), colour scheme, skin

**Play area**:
The strip of the percent row right of the number where Clawd walks: as wide as the number leaves it, reaching 3 below the row to the ground line he stands on. The sky spans the whole row behind it.
_Avoid_: mascot area, stage

**Part**:
A piece of the card the pointer can reach, as the presenter names it: a header button, a line or a row, with whether it shows and its tooltip. The card draws it; the window gives it its regions.
_Avoid_: element, item, block, control (a role), the moving parts

**Region**:
A rect of the card, in card space, with one role. The window derives them from the shown parts, the rects the card published, Clawd's sprite and the hearts; clicks, the cursor, the tooltips and the chart's readout all read that one list.
_Avoid_: hit rect, hit map, zone, area (the play area's)

**Role**:
What a region does: a control (a click that is the part's own, not a drag), a tooltip, the chart's readout, the sky (its tooltip, and the developer menu on a secondary click) or Clawd's sprite (a pet, or the developer menu).
_Avoid_: kind, type
