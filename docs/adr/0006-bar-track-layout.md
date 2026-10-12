# Bar track layout, and Auto Shot as a cast

Status: accepted (2026-10-12).

A third layout, **Bar track**, condenses Single lane into one framed bar
the height of a lane, read like a cast bar: the ready spells in a cap at
the bar's start, casts filling the bar's height, every icon riding inside
the frame, the swing diamonds on its edges. It sits beside Single lane and
Detailed in the Layout dropdown and draws from the same lane descriptors;
only the placement differs, as ADR-0005 set out. The look is in
`VISUAL.md` (Layouts, Bar track).

The same session settled how ranged reads: Auto Shot is a cast (a windup
of about 0.5 s, scaled by ranged haste, that needs the hunter standing
still, then the reload; forever-hunter wiki, Shot Mechanics). In both
Single lane and Bar track, ranged becomes that cast - the windup drawn as
a cast bar ending at the Auto Shot icon - in place of the hollow diamond,
its windup computed from the weapon's base speed (probe H3).

## Considered options

Explored in the layout study mock-up (2026-10-12):

- Blizzard's Bars view (a sorted list of timer bars): rejected - a list
  loses the shared time axis that lines swings, casts and the GCD up, and
  Lua cannot sort the engine-drawn cooldowns, which are secret.
- **Cycle bar** (a still bar spanning one main-hand swing, the fill
  moving): rejected - its time scale changes with every swing speed, haste
  change and reset, nothing past the next landing has a position, and a
  caster has no swing to span.
- **Paged bar** (a fixed 10 s page, a cursor moving along it, the page
  turning at three quarters): rejected - the eye has to follow the
  cursor, and every turn moves every mark at once.
- Bar track with the swings as segments of the bar: rejected - it carried
  more ink than diamonds and read as a swing timer bolted to a timeline.
- Bar track drawn on Single lane's open track (diamonds above and below,
  icons stepping off the line): rejected - too close to Single lane to be
  worth a layout.

## Consequences

- The renderer gains a third placement path. Bar track has no step room
  inside its frame, so overlapping icons need a new rule, the **card
  stack** (`VISUAL.md`); a linked set draws as one icon with a link mark.
- The ready cap holds four slots: each slot comes out of the timeline's
  length.
- Auto Shot as a cast needs the windup value. The swing library computes
  it (0.52 s x ranged speed / base speed) but does not expose it; the
  weapon's base speed reads plain from its tooltip (probe H3), so the
  addon computes it, as the library does. Exposing it in the library stays
  a nice-to-have API ask (`SPEC.md`, Out of Scope).
- Engine-drawn lanes stay outside the bar, as thin rows under the frame:
  Lua cannot read their icon's position (ADR-0001).
- The frame's border needs art not yet seen in game (Blizzard's cast bar
  atlases, `ASSETS.md` To probe; `PROBE_SESSION.md` Part H); the link
  mark is a small badge drawn with `WHITE8X8`, since no link atlas exists.
