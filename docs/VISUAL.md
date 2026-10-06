# 4everActionTimeline — Visual Design

Companion to `SPEC.md` (behavior and mark semantics). This document decides
what the timeline looks like: art family, chrome, now line, mark framing,
tints, animation. Maintained round-by-round from the visual grilling
session (started 2026-10-06). Shared language: the repo's root
`GLOSSARY.md`.

Reference sources: Blizzard's UI source on the Forever branch
(`Gethe/wow-ui-source`, branch `forever`) — chiefly
`Blizzard_EncounterTimeline` (a native horizontal/vertical event timeline)
and `Blizzard_CooldownViewer` (the Cooldown Manager icon frame and state
tints) — and 4everSwingTimer's asset catalog (its
`docs/ASSET_LIBRARY.md`).

## Decisions

### Skins

- **Native skin (default)** — the Encounter Timeline + Cooldown Manager
  family: the `combattimeline-*` track art (line ends, pip, icon trail,
  highlight) and Cooldown Manager–framed icons
  (`UI-HUD-CoolDownManager-Mask` + `UI-HUD-CoolDownManager-IconOverlay`).
  The timeline reads as a native 12.x HUD element beside the player's
  Cooldown Manager.
- **Flat skin (option)** — `WHITE8X8` lines, square-cropped icons, 1 px
  borders; no atlas dependency.
- A Settings dropdown chooses the skin. Every Native atlas is guarded with
  an atlas-exists check at load; a missing atlas falls back to the Flat
  equivalent for that element only, never an error.
- The reposition pop colors (teal, amber, red) come from 4everSwingTimer's
  effect colors in both skins.

### Orientation

- Three choices: **horizontal** (default: past left, future right),
  **horizontal flipped** (future left), and **vertical** (with its own
  flip). All lanes, window bars, edge clamp and the sink follow the
  orientation.
- The sink stays possible in every orientation: `StatusBar` supports
  `SetOrientation("VERTICAL")` and `SetReverseFill`, so the fill — and the
  icon anchored to its leading edge — runs from the now line toward the
  future edge whichever way that is. Each orientation's sink layout joins
  the by-eye encoding check.
- Orientation-dependent art (line ends, trail, divider) is rotated through
  texture coordinates, the way `EncounterTimelineOrientedTextureMixin`
  does.

### Lanes and tracks

- Every lane draws its own track line through its middle. Native: the
  `combattimeline-line-left` / `-right` pair, the line broken where a mark
  sits (`combattimeline-line-break-mask`, as Blizzard does). Flat: a 1 px
  line.
- A **lane background alpha** slider (default 0, Blizzard's
  `BackgroundAlpha` default) adds a faint band behind each lane for players
  who want it.
- Lane order runs along the cross-axis: top to bottom when horizontal
  (hands on top), left to right when vertical (hands on the left). A flip
  mirrors the time axis only, never the lane order.

### Now line

- Native: `combattimeline-cooldown-divider` stretched across every lane,
  with the `combattimeline-pip` diamond at the lane-start end. Flat: a 2 px
  white line at 0.6 alpha. The divider art is built as a short section
  divider, so its look at full frame height is a by-eye check item.

### Marks

- Native: Blizzard's event icon — the icon masked by
  `UI-HUD-CoolDownManager-Mask`, `UI-HUD-CoolDownManager-IconOverlay` on
  top, the overlay overhanging the icon by a few pixels (Blizzard anchors
  it at −7/+6/+7/−7 on a 35 px icon), so lane spacing must clear the
  overhang. Flat: the icon edge-cropped with a 1 px black border.
- Icon size = lane height − 2 px. The lane height setting is the icon size
  control; no separate icon scale.

### State tints

Saturation encodes source certainty (`SPEC.md`); tints encode usability,
using Blizzard's own action-bar values so nothing new is learned:

| Mark | Look |
|---|---|
| ready | plain full color, no outline (the Cooldown Manager's ready look) |
| unusable, resource-short | blue tint `0.5, 0.5, 1.0` |
| unusable, other | grey tint `0.4, 0.4, 0.4` |
| unknown-cooldown | desaturated |
| parked (hand) | dimmed weapon icon |

No outline anywhere in the idle family: blue keeps Blizzard's
not-enough-mana meaning. Out-of-range red (`0.64, 0.15, 0.15`) is not used
in v1 — range is an unprobed read and leans toward press-this-next advice.

### Reposition pop

- Both skins reuse 4everSwingTimer's pip glow (`cast_standard_pipglow`,
  `ADD` blend), tinted teal, amber or red, flashed once and faded over
  ~0.3 s — one feedback language across both addons, already verified on
  Forever.

### Stopped casts

- A stopped, failed or interrupted cast's happened mark is the icon at
  full color with a **red border** — Native: the Cooldown Manager overlay
  tinted red; Flat: the 1 px border in red. The icon stays readable (which
  spell failed); red stays the cast-failure color shared with the bar
  addon and avoids Blizzard's out-of-range red tint.
- The red border **animates in**: it flashes bright to steady and the mark
  shakes once (~0.25 s, ±3 px) **across the lane only** — never along the
  time axis, which would briefly place the mark at a wrong instant. The
  border then stays steady; it is part of the happened mark's meaning.
  The vanishing predicted mark plays the red reposition pop with
  Blizzard's `CancelAnimation` treatment (0.2 s alpha fade).
- The shake is computed inside the renderer as an offset, never via
  `ScriptAnimationUtil.ShakeFrame` — that helper re-anchors the region on a
  ticker and restores its start position at the end, which fights a
  scrolling mark (the repo's anchor rule) — and it honors the game's
  `ShakeStrengthUI` CVar (0 disables it), as Blizzard's helper does.

### Hand-lane effects

- **Jump, never glide**: a repositioned mark moves in one frame (Blizzard's
  0.45 s icon translation would show wrong instants mid-glide).
- **Correction streak**: from the old position to the new, in the pop's
  color, fading within ~0.3 s — Native: `combattimeline-line-icontrail`
  stretched over the jump; Flat: a `WHITE8X8` streak. The timeline's
  equivalent of the bar addon's directional burst (teal lunge, amber
  flinch). Also drawn from an early-landing happened mark back to the
  abandoned prediction.
- **Pop budget**: teal once per correction; amber once per retry chain
  (later sawtooth jumps get the streak only); red once per reset.
- **Held**: the ranged predicted mark's frame border turns amber (Native:
  the Cooldown Manager overlay tinted; Flat: the 1 px border) for the
  whole retry chain, cleared when the shot fires.
- **Delay span**: an amber window bar along the ranged lane's track, same
  geometry as the GCD window bar (elapsed full color), from the first
  retry to the fired shot.
- **Clip mark**: a small red tick (~⅓ lane height, 2 px wide) on the track
  at the reset instant — a tick, not an icon, so it never reads as a
  landed swing. The reset also plays the red pop and the across-lane shake
  on the predicted mark, as for stopped casts.
- **Overdue**: the next-landing mark pinned at the now line, unchanged in
  look (still full color: the library's expiry was fact-grade; it is
  late, not wrong).
- Bar addon colors: teal `0.10, 0.95, 0.65`, amber `1.0, 0.60, 0.10`, red
  `1.0, 0.25, 0.20` (`HASTE_TINT`, `DELAY_TINT`, `CLIP_TINT` in
  4everSwingTimer's `Bars.lua`).

### Color-blind safety

- Every effect is distinct by **shape** first, color second: clip mark =
  tick, delay span = bar, held = border, stopped cast = bordered icon +
  shake. Correction streaks carry **direction**: the streak tapers from
  bright at the mark's new position to transparent at the old one, so a
  teal correction visibly points toward the now line (earlier) and an
  amber one away from it (later) — the bar addon's lunge and flinch.
- No alternate palette in v1. The encoding check views the test-mode
  effect previews through a color-blindness simulator once.

### Edge clamp cue

- A readable predicted mark pinned by the edge clamp shows a small
  **chevron** on its outer side ("further than this"). The sink icon gets
  no chevron — Lua cannot tell whether it is pinned — so a pinned sink
  icon and a pinned readable mark look different; accepted.
- Asset: a Native arrow atlas chosen by an in-game atlas search during the
  probe session (probe 14); fallback in both skins is a small triangle of
  two rotated `WHITE8X8` strokes in the track color. Size ~⅓ of the icon,
  just outside the icon's outer edge so it never covers the icon.

### GCD window bar

- Native: the Cooldown Manager bar art (`UI-HUD-CoolDownManager-Bar`,
  `-Bar-BG`). Flat: `WHITE8X8`.
- Color: a pale, whitish blue (near the swing timer's GCD tint) — kept
  clear of Blizzard's not-enough-mana blue `0.5, 0.5, 1.0`.
- The full-color/desaturated split at the now line needs no extra divider;
  the now line already draws it.

### Paused and queued

- Native adds Blizzard's own timeline overlays on top of the SPEC
  treatment: `combattimeline-fx-pause` (+ `-pause-icon`) on a paused hand's
  frozen, dimmed marks; `combattimeline-fx-queued` on the main-hand
  predicted mark while it shows the queued ability's icon.
- Flat keeps the SPEC treatment alone: dim for paused, icon swap for
  queued. Both join the by-eye encoding check.

### Text

- No text on readable marks: a number on a calibrated estimate would give
  a guess a number's authority, which desaturation exists to deny.
- **Sink countdown** (Settings toggle, off by default): the sink icon may
  show the engine's true remaining time as text — `SetText` accepts the
  secret (build 70205 smoke test). It is the only mark whose number is
  true in combat, and it offsets the sink's missing chevron and
  linear-only scale.

### Mouse

- The frame never takes the mouse (click-through, no tooltips): the icons
  already identify each mark, the timeline is read at a glance, and a
  mouse-enabled HUD frame mid-screen would block world clicks. Placement
  happens in Edit Mode, which handles its own mouse.

### Frame chrome

- None. The lanes and tracks are the frame, as in Blizzard's Encounter
  Timeline; the lane background alpha slider covers players who want a
  band. Edit Mode's selection highlight shows the bounds while placing.

### Settings window

- Mirrors the Cooldown Manager settings layout: icon rows, drag to
  reorder, side tabs. Built on Blizzard's **generic** shared templates
  (`LargeSideTabButtonTemplate`, `ResizeLayoutFrame`, ScrollBox lists)
  with the addon's own mixins — **not** by inheriting
  `CooldownViewerSettingsItemTemplate` and friends, whose mixins are wired
  to Blizzard's Cooldown Manager data and settings store.
- The "overridden" and "new" states are small tags on the row.

### Motion trail

- The **next** predicted mark on each lane — whatever its source — draws a
  motion trail during its last **1.5 s** before the now line (one GCD:
  "lands within your next GCD"). Deeper cadence-chain marks never trail.
  The onset is a constant, not a setting.
- Native: `combattimeline-line-icontrail`, `ADD` blend. Flat: a `WHITE8X8`
  streak in the lane's track color, fading to transparent, the length of
  the Native trail art.
- The sink icon never trails: Lua cannot read its position, so the 1.5 s
  onset cannot be timed honestly. Happened marks and now-line marks never
  trail.

## Verified facts (Forever branch source)

- Action bar and Cooldown Viewer icon tints: usable `1,1,1`; not enough
  mana `0.5,0.5,1.0` (blue); not usable `0.4,0.4,0.4`; out of range
  `0.64,0.15,0.15` (`ActionButton.lua` `UpdateUsable`,
  `CooldownViewerConstants`).
- The Cooldown Viewer desaturates an icon while its spell is on actual
  cooldown — the same language as the timeline's desaturated predicted
  mark.
- Encounter Timeline defaults: 5 s highlight time, 55 px cross-axis extent,
  20 px start/end padding, 0.35–0.45 s intro/outro/translation animations.
