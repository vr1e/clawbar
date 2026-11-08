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
One step of everything that moves: Clawd, his hearts, and the sky or the theme's scene, every 90 ms (60 while a Claude Code sequence plays, though a scene keeps its 90), only while the widget shows and has Clawd or a scene. Not the data tick.
_Avoid_: frame tick, timer tick

**Animation engine**:
The decisions of the moving side: what Clawd, the sky and the scene do on an animation tick, and what the data, a click or a developer action does to them. It takes the data snapshot, the settings and one tick's inputs, and returns the frame and the cadence of the next tick.
_Avoid_: animator, stepper, ticker

**Animation frame**:
Everything one animation tick drew: Clawd with his hearts, the sky, and the theme's scene. Not the scene alone.
_Avoid_: picture

**Theme palette**:
The colours a theme changes, one per role: the background, the text tiers (secondary, muted, label, footer), the accent, the model-week bar and the empty heart. The presenter resolves it into the view state; the levels, Clawd, the sky, the card's border and tracks, and the chart's fill, cursor and session line stay fixed.
_Avoid_: theme (the config's choice of look), colour scheme, skin

**Theme pattern**:
A tile of faint pixel sprites a theme repeats over the card under its content, like a chat wallpaper; it stands still. Not the scene.
_Avoid_: wallpaper, texture

**Scene**:
A theme's animation: a backdrop over the pattern and under the card's content, a layer in the sky row in the weather's place, and for a rare secret such as Halloween's midnight scare, a layer over all the content. It moves on the animation tick at its own steady pace, with or without Clawd.
_Avoid_: animated theme (upstream's name for the feature), backdrop (one of its layers)

**Secret**:
A scene's rare event at a set local time, such as Halloween's midnight scare, drawn on a layer over all the card's content; it ends at once when the theme changes or the widget hides.
_Avoid_: easter egg, event

**Cue**:
What a scene asks of Clawd on one of its steps, such as the scare's jump or the 20:77 secret's wake and Netrunner skin; the animation engine carries it out behind his own guards, and a hidden Clawd misses an act.
_Avoid_: command (that is the data engine's word), trigger

**Haywire**:
The 20:77 secret scrambling the card: its plain texts' digits and characters and its usage bars, every other step from a seed the scene hands out. The presented view state stays as it is underneath and shows again when the haywire stops; the menu bar item is untouched.
_Avoid_: glitch (the Cyberpunk scene's torn bars), scramble (the function, not the state)

**Skin**:
Clawd's body and eye colours and the pixel accessories drawn over him, such as a hat or glasses: Classic, a built-in one or the user's own from the skins folder (`skin`). It dresses the widget's Clawd only.
_Avoid_: costume, outfit, theme (the card's colours)

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
