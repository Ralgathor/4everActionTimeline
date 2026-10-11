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

### Layouts

- Two layouts, picked in a Settings dropdown (ADR-0005): **Single lane**
  (default) folds every lane kind onto one track around the now line, for
  peripheral reading; **Detailed** is the M7 layout, one lane per kind.
  The rest of this document describes Detailed unless a rule says
  otherwise.
- Single lane design: settled round by round in the Single lane session
  (2026-10-11), from the layout study mock-up. The lane mapping is in
  `SPEC.md` (Layouts); the look is below.
- Single lane, hands: the main hand above the track, the off hand below
  it. Ranged shares the main hand's side as a hollow diamond (an outline,
  not filled) in a pale green - filled for melee, hollow for ranged, so
  shape tells them apart first (melee and auto shot do not run together in practice; when both are
  live, ranged sits a step further out so neither covers the other).
  Without an off hand the space below stays empty: the lane never changes
  height mid-session.
- Single lane, swing marks: one shape from future to past, so a landing
  never changes look as it crosses the now line. The next landing is a
  full-color diamond (Native: `combattimeline-pip`; Flat: a drawn
  diamond) - the library's expiry is fact-grade. The cadence chain is
  1 deep: one smaller, desaturated diamond after the next landing.
  Landed swings stay diamonds and fade over the past window. A queued
  ability replaces the next landing's diamond with its own small icon
  (about 14 px), and the landed swing keeps that icon. A paused hand's
  diamonds freeze and dim; a parked hand (auto-attack off) shows a dim,
  desaturated diamond on the now line. The next landing's diamond grows
  (about 5 to 8 px at the default height) over its last 1.5 s, the same
  urgency rule as a returning cooldown.
- Single lane, casts: a bar about 6 px thick on the track, in a warm gold
  kept clear of the GCD's blue - solid where elapsed, lighter where still
  to run - from cast start to completion, the spell icon at its
  completion end. The icon is full color during the cast (the cast time
  is a plain read, `PROBES.castTimePlain`, as for Detailed's completion
  mark). Once complete, bar and icon fade over the past window. A
  stopped, failed or interrupted cast cuts the bar where it stopped and
  moves the icon there with the red border and the across-lane shake; the
  unrun part vanishes with the red pop (Stopped casts). Pushback jumps the
  bar's end and icon with the amber pop. A channel draws the same bar to
  its end; one stopped early follows the stopped-cast rule. An instant
  ability leaves its icon on the track at the moment of use, fading the
  same way.
- Single lane, returning cooldowns: a desaturated icon on the track at
  the predicted return, 16 px, growing to about 24 px and full opacity
  over its last 1.5 s (still desaturated). The growth replaces the motion
  trail, which would overlap the mark before it on a shared track.
  Overlapping icons step 8 px off the track, up then down (clear of the
  swing diamonds); past three levels they overlap slightly. Linked
  cooldowns draw one icon per spell, stepped as a pair. An overdue icon
  pins on the now line until the engine confirms the spell is ready; past
  the far edge the edge clamp and chevron apply.
- Single lane, ready row: under the track, on the past side, ending at
  the now line. Each rotation ability has a fixed slot in lane-window
  order; a slot shows a faint empty outline while its spell cools down and
  fills when it is ready, so the row never reorders or changes width. The
  slots keep Detailed's state tints (blue resource-short, grey unusable,
  desaturated unknown cooldown), so the row reads "pressable now". A
  return flashes a ring on the slot.
- Single lane, ready row side: a Settings dropdown, **Past side**
  (default) or **Future side**. Past side keeps a returning cooldown moving
  one way (it crosses the now line into its slot) and leaves the future
  side to what is arriving; the row's width follows its slot count, not
  the past window - the frame widens on its past side to fit the slots.
  Future side starts the slots at the now line, for players who keep their
  eyes ahead of it. Either side follows the orientation.
- Single lane, long cooldowns: a spell whose cooldown is not yet known
  (uncalibrated, no class-data tag) counts as a rotation ability and keeps
  a slot until its cooldown is learned - the one case where the ready row
  changes width. Long cooldowns get no slot. While cooling they ride the track
  like any returning cooldown, clamped at the far edge with the chevron
  while beyond the future window; on their return a ring flashes on the
  now line and the icon leaves the track.
- Single lane, GCD: a faint band across the lane's full height, behind
  every mark (Native: the Cooldown Manager bar art; Flat: `WHITE8X8`),
  in Detailed's pale whitish blue. Where the GCD still has to run the band
  is at its full faint strength; the elapsed part is dimmer and fades with
  age over the past window, so idle gaps between GCDs show. No edge strip.
  An off-GCD ability opens no band. The band is a tint behind the marks,
  not a mark: source-certainty saturation applies to marks only, so the
  part still to run may be the stronger one (Detailed's window bar, a mark,
  keeps elapsed full color and unelapsed desaturated).
- Single lane, hand effects (Hand-lane effects, Color-blind safety): the
  reposition pop flashes on the diamond unchanged; the correction streak
  runs on the hand's side of the track from old to new diamond, tapered
  as before. Held: the ranged diamond's outline turns amber (ranged is
  the only hollow diamond, so held is one outline, not two). Delay span: a thin amber
  line (about 2 px) on the ranged side of the track, clear of the cast
  bar. Clip mark: a small red tick on the hand's side - the lane's only
  tick shape, so it never reads as a landing. The across-lane shake moves
  only the affected diamond or icon, across the track.
- Single lane, engine-drawn lanes: one thin row each (18 px, 16 px
  icons) under the ready row, on the same time axis. The sink rules hold:
  the spell's predicted mark leaves the track while its sink is on, the
  pinned icon shows no chevron, the countdown text stays optional. Its
  ready-row slot (or, for a long cooldown, the now-line ring) still
  follows the plain off-cooldown read.
- Single lane, settings: each layout keeps its own past and future window
  (Single lane default 1.5 s / 10 s); the Settings sliders edit the active
  layout's pair. The lane height setting sizes the track and everything on
  it scales with it - the pixel sizes above are those at the default
  height. Edit Mode, visibility and skin are shared. Lane spacing is the
  gap between the track, the ready row and the engine-drawn rows; the lane
  background alpha draws its band behind the track only.
- Single lane, orientation: all four orientations. The main hand takes the
  lane-start side across the track (top when horizontal, left when
  vertical); the ready row, then the engine-drawn rows, stack on the other
  side. A flip mirrors only the time axis.

### Lanes and tracks

- Every lane draws its own track line through its middle. Native: the
  `combattimeline-line-left` / `-right` pair — the left segment over the
  past window, the right one over the future window, meeting at the now
  line. Flat: a 1 px line.
- As built (M7): no line breaks. Blizzard's `combattimeline-line-break-mask`
  breaks its line at fixed time intervals, not under its icons, and a
  texture takes at most three masks; the Native icon frame covers the line
  under a mark anyway. Revisit if the unbroken line reads poorly.
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
  it at −7/+6/+7/−7 on a 35 px icon, scaled with the icon), so lane
  spacing must clear the overhang. Flat: the icon edge-cropped with a 1 px
  black border. The sink icon wears the same frame.
- The frame clips its children, so in Native it pads the outer lanes by the
  overlay's overhang (and half the pip) across the axis.
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
- Asset (probe 14, build 70235): `uitools-icon-chevron-right` (20×20,
  white, so it takes the track color), turned through tex coords for every
  orientation — mirrored when flipped, rotated when vertical — so
  `-left` is not needed. The other
  candidates seen (`common-icon-forwardarrow`, `NPE_ArrowRight`) are
  pre-colored yellow and were passed over. Fallback in both skins is a
  small triangle of two rotated `WHITE8X8` strokes in the track color.
  Size ~⅓ of the icon, just outside the icon's outer edge so it never
  covers the icon.

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
  mouse-enabled HUD frame mid-screen would block world clicks. The one
  exception is placement: while Edit Mode is open (and out of combat) the
  frame enables the mouse for dragging, ForeverCDM's pattern (probe 9),
  and turns it off again when Edit Mode closes.

### Frame chrome

- None. The lanes and tracks are the frame, as in Blizzard's Encounter
  Timeline; the lane background alpha slider covers players who want a
  band. The frame is not an Edit Mode system, so Blizzard's selection
  highlight does not draw for it: while Edit Mode is open the frame shows
  its own placement handle — a translucent band over its bounds and a
  "4everActionTimeline — drag" label — hidden again on exit.

### Settings window

- Mirrors the Cooldown Manager settings layout: icon rows, drag to
  reorder. Never built by inheriting `CooldownViewerSettingsItemTemplate`
  and friends, whose mixins are wired to Blizzard's Cooldown Manager data
  and settings store.
- As built (M6): plain frames and the basic templates only
  (`BasicFrameTemplateWithInset`, `UICheckButtonTemplate`,
  `InputBoxTemplate`, `UIPanelButtonTemplate`) — a clipped row list
  scrolled by the mouse wheel instead of a ScrollBox, and two layer
  buttons (Class / This character) instead of side tabs: the ScrollBox and
  side-tab templates could not be verified outside the game. Revisit if
  the plain list reads poorly.
- The "overridden" and "new" states are small tags on the row.

### Motion trail

- The **next** predicted mark on each lane — whatever its source — draws a
  motion trail during its last **1.5 s** before the now line (one GCD:
  "lands within your next GCD"). Deeper cadence-chain marks never trail.
  The onset is a constant, not a setting.
- Native: `combattimeline-line-icontrail`, `ADD` blend, at its atlas
  size. Flat: a `WHITE8X8` streak in the lane's track color, fading to
  transparent toward the now line, 64 px long. Either lies on the mark's
  now-facing side, its end 10 px into the icon (Blizzard's
  `UpdateTrailLayout`), and fades in over the 1.5 s.
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
