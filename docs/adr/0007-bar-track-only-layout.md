# Bar track is the only layout

Status: accepted (2026-10-13). Supersedes the layout choice in ADR-0005
and ADR-0006; their placement rules stand.

Bar track (ADR-0006) is the layout the addon ships, and the only one.
Single lane and Detailed, and the Layout setting that chose between them,
are removed.

Single lane's rules (ADR-0005) are not removed: they are how the bar
places its marks - every lane kind but the sink lanes on one shared track,
the hands on its edges, casts and returning cooldowns on it, the ready
row's fixed slots, the 1-deep cadence chain, the highlight as the urgency
cue. Bar track was always "Single lane in one framed bar"; with no other
layout left, those rules are simply the bar's. `SingleLane.lua` keeps its
name and holds them; `BarTrack.lua` draws the bar.

## Why

- The in-game tuning of M9 made Bar track the layout worth finishing: it
  reads like the cast bar players already watch, holds Auto Shot as a
  cast, and needs no backdrop or line shadow for contrast.
- Three layouts tripled the by-eye encoding check, the harness and the
  docs for every visual change, and each fix had to be argued for each
  layout. Detailed and Single lane had no player asking for them.
- Everything Single lane offered that Bar track lacked was a variant of
  the same idea (a thinner track, growth instead of a flash, a backdrop),
  not a different reading.

## What goes

- Settings: Layout, Urgency cue (Growth), Lane background (Detailed),
  Backdrop and Line shadow (Single lane), and the per-layout windows and
  length - one past window, future window and length remain, defaulting
  to Single lane's 1.5 s, 10 s and 700 px. Saved values of the removed
  keys are ignored.
- Detailed's lane-per-kind rows, its track lines and line breaks, the
  motion trail, the weapon-icon swing marks, the Cooldown Manager icon
  frame and Blizzard's pause and queued overlays on icons (every icon in
  the bar is plain, as the cast bar's is), the Detailed cast mark on the
  now line.
- Single lane's thin track, its growth, its stepping of overlapping
  cooldown icons (the card stack replaces it), its backdrop and its line
  shadow.

## Consequences

- One geometry: `Layout` has no layout flags; the scroll-out margin is the
  bar's own (the widening for the ready row), never Detailed's 1 s.
- The harness's M1-M7 suite, written against Detailed, now runs on the
  bar: its behavior checks (store, predictions, calibration, effects,
  settings) hold, read through the bar's widgets.
- Bringing back a second layout means a new ADR: the mark descriptor
  contract (`Layout.lua`) still separates what a lane says from where it
  is drawn, so a layout remains a placement over the same descriptors.
