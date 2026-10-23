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

**Recipe**:
The steps that carry out one of the data engine's commands against a process, the network or disk and turn what came back into its answer. Written once per command; the app and `--diagnose` run the same ones.
_Avoid_: executor, handler, pipeline

**Snapshot mode**:
The `--snapshot` run that renders every widget state to PNGs for the README and for review. Not a data snapshot.
_Avoid_: screenshot mode
