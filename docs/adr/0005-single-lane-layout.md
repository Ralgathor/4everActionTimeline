# Single lane layout beside Detailed

Status: accepted (2026-10-11).
Its layout choice is superseded by ADR-0007 (2026-10-13): Single lane is no longer a layout; its placement rules are the bar's.

After in-game sessions on M7, the lane-per-kind layout read well when
looked at but poorly in peripheral view: two or three hand lanes, the GCD
and cast lanes and one lane per spell put 25-30 marks on screen, and the
cadence chains and 5 s of past marks carry little a glance needs. A second
layout, **Single lane**, folds every lane kind onto one track around the
now line. A Settings dropdown picks the layout: **Single lane** (the
default) or **Detailed** (the M7 layout, unchanged). Both draw from the
same lane descriptors; only the renderer's placement differs. The Single
lane design is recorded in `VISUAL.md` (Layouts) and `SPEC.md`.

## Considered options

- Replace Detailed with Single lane: rejected - Detailed is built and
  verified in game, and a lane per spell suits players who look at the
  timeline directly.
- **Compact** (a swing row and a shared cooldown row, ready spells in a
  dock): explored in the layout study mock-up and dropped - Single lane
  took over its ideas (casts on the swing row, next landing only, one
  shared cooldown row, urgency growth) with one row fewer.
- Detailed kept only as a debug view: rejected for the same reason as
  replacing it.

## Consequences

The renderer gains a second placement path for the same descriptors.
Every Single lane rule must keep the honesty rule (desaturated means a
prediction) and the sink constraint: engine-drawn lanes cannot join the
shared track, since Lua cannot read their icon's position.
