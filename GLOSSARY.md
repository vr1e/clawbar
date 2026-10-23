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

**Latch**:
The usage probe stopped for good under one Claude Code version, because a run reached the model or had a flag rejected. A new version lifts it.
_Avoid_: lock, block

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

**Play area**:
The strip of the percent row right of the number where Clawd walks: as wide as the number leaves it, reaching 3 below the row to the ground line he stands on. The sky spans the whole row behind it.
_Avoid_: mascot area, stage
