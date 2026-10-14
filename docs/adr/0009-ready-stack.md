# ADR-0009: Ready spells park on the now line, stacked

Status: accepted (2026-10-13)

Supersedes the ready row (`VISUAL.md`, Layouts: Ready row, Ready row side;
the Ready row side setting of ADR-0008).

## Context

The ready row put one 12 px slot per rotation spell in a strip under the
bar: an empty outline while the spell cooled, its icon once ready. In game it
read as a footnote: half the bar's icon size, a separate strip the eye had to
drop to, outlines that were noise, and a frame that widened on its past side
to fit the slots. A mockup (four live variants of one simulated fight)
compared it with a ready track over the bar's past side (the Encounter
Timeline's Queued track, Cooldown Timeline 3's ready zone), the row without
outlines, a stack hanging under the now line, a fan, and no ready display
(the Cooldown Manager already shows what is ready on Forever).

## Decision

- **Stack** (default): a returning rotation spell stops on the now line and
  stays there. Ready spells park on the bar, centred on the now line, at 75 %
  of the bar's icon size (so the now line still shows above and below the
  front icon), in an accordion along the bar: each one behind the front
  peeking out 5 px (at bar height 26, the card stack's peek) toward the
  future, the front centred on the now line. (Folding down across
  the bar as well was tried first and did not read.)
- Order: usable spells first, then unusable ones (the resource and unusable
  tints), then spells whose cooldown is not known yet (desaturated); lane
  order inside each group. Lane order is the player's own, so the front icon
  is not advice, and it gets no highlight (the honesty rule).
- Three show; the rest are hidden, with no "+n" (it crowded the bar for a
  number the stack does not need to give). The stack stays
  inside the room the now line's reach already keeps across the bar, so the
  frame never changes size for it.
- A cooling spell shows nothing in the stack (no outline). The ring flashes
  on the spell's place in the stack when it returns. A used spell's icon
  grows and fades where it stood (Blizzard's finish, 0.2 s); the icons
  whose place changes glide there (0.15 s: places, not instants).
- **None**: no ready marks. A returning cooldown's icon stays on the now line
  for 0.5 s, fading, under the ring. Blizzard's Cooldown Manager shows what
  is ready.
- A return with no place in the stack (a long cooldown, or any spell under
  None) lingers the same way.
- The Edit Mode panel's "Ready row" (Past side / Future side) becomes "Ready
  spells" (Stack / None). Schema 3 drops the old setting.

## Consequences

- The frame no longer widens on its past side; the strip and its box (the
  cast bar's name box) under the bar are gone, and the engine-drawn rows move
  up under the bar. Flat's now line keeps its diamond on both ends.
- The front icon covers the now line inside the bar; the scale-down keeps a
  few pixels of it visible above and below.
- Only the front icon is whole: the stack tells how many are ready more than
  which, past the first.
- Under None the timeline no longer answers "what can I press now".
