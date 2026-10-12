# 4everActionTimeline — Visual Design

Companion to `SPEC.md` (behavior and mark semantics). This document decides
what the timeline looks like: art family, chrome, now line, mark framing,
tints, animation. Maintained round-by-round from the visual grilling
session (started 2026-10-06). Shared language: the repo's root
`GLOSSARY.md`.

Reference sources: Blizzard's UI source (`Gethe/wow-ui-source`; the
`forever` branch, and the live 12.1.0.69933 tree re-read on 2026-10-12) —
chiefly `Blizzard_EncounterTimeline` (a native horizontal/vertical event
timeline, the closest built-in relative of this addon),
`Blizzard_CooldownViewer` (the Cooldown Manager icon frame and state
tints), `Blizzard_ActionBar` (usability tints), the casting bar
(`Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua`) and `PixelUtil` —
and 4everSwingTimer's asset catalog (its `docs/ASSET_LIBRARY.md`).
Facts read from that source are listed at the end (Verified facts); the
sections below cite the Blizzard convention each rule follows or departs
from.

## Principles

What the Blizzard source does consistently, and this addon follows unless
a section says otherwise:

- **Reuse the player's learned language.** Usability tints, desaturation
  for "not available", red for a failed cast, gold for a cast in progress,
  green for a channel: values copied from Blizzard's own frames, so
  nothing new is learned.
- **State by shape and overlay, color second.** Paused, queued and deadly
  events get an overlay or a glyph, never a tint alone (Color-blind
  safety).
- **Contrast from the marks, not from chrome.** The Encounter Timeline
  ships no frame and no background (alpha 0); its line carries its own
  shadow, its icons their own border, its text a drop shadow.
- **Far is quieter than near.** Distant events are dimmer (60 % on the
  Long track) and squeezed; the near future gets the length.
- **Urgency is one moment, then a steady cue.** An event crossing the
  highlight time flashes once, then pulses; nothing ramps continuously.
- **Moving art is not pixel-snapped; still art is.** Snapping a texture
  that travels about a pixel per frame makes it step.
- **Appear and leave with a short animation.** Events fade in (0.2 s),
  finish with a burst (0.2 s), and a cancelled one fades out (0.2 s) —
  nothing pops in or vanishes, except a correction, which jumps (Hand-lane
  effects).

## Decisions

### Skins

- **Native skin (default)** — the Encounter Timeline + Cooldown Manager
  family: the `combattimeline-*` track art (line ends, pip, icon trail,
  highlight) and Cooldown Manager–framed icons
  (`UI-HUD-CoolDownManager-Mask` + `UI-HUD-CoolDownManager-IconOverlay`).
  The timeline reads as a native 12.x HUD element beside the player's
  Cooldown Manager and the boss timeline.
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
- Orientation-dependent art (line ends, trail, divider, shadow) is rotated
  through texture coordinates, the way `EncounterTimelineOrientedTextureMixin`
  does; its turns keep the line art's shadow on the bottom edge when
  horizontal and the right edge when vertical.

### Layouts

- Two layouts, picked in a Settings dropdown (ADR-0005): **Single lane**
  (default) folds every lane kind onto one track around the now line, for
  peripheral reading; **Detailed** is the M7 layout, one lane per kind.
  The rest of this document describes Detailed unless a rule says
  otherwise.
- Single lane visual values, taken from the layout study mock-up (the
  target look; sizes at lane height 26, which scale with it):

  | Element | Value |
  |---|---|
  | Length | its own setting, default 700 px (10 s at about 58 px/s; the mock-up drew about 87 px/s); linear (open: a squeezed far future) |
  | Backdrop | one dark panel behind everything, 0.05 / 0.06 / 0.05 at 20 % (Settings: Backdrop; 60 % before the line shadow) |
  | Line shadow | black, 70 % at the track fading to none half the track's extent out, both sides (Settings: Line shadow) |
  | Track | 2 px white at 28 % (Flat) |
  | Now line | warm 0.91 / 0.85 / 0.66 at 75 %, 2 px, a diamond at its lane-start end (Native: the pip; Flat: 1-3-5-3-1 line widths, as wide as tall) |
  | Hand diamonds | half diagonal 5, on a dark outline 1.5 px out; main hand 0.91 / 0.93 / 0.96, off hand 0.79 / 0.69 / 0.54, ranged hollow 0.62 / 0.86 / 0.66 |
  | Next landing | 75 % while far, 100 % and one highlight flash from its last 1.5 s (Urgency cue: Growth grows it 5 to 8 and ramps the alpha instead) |
  | Chain, parked | half diagonal 4 at 55 %, parked 5 at 50 %; grey at 80 % of the color's luminance |
  | Cast bar | 6 px; elapsed 0.88 / 0.67 / 0.35 at 95 %, still to run 0.67 / 0.63 / 0.57 at 60 %; its icon 16; a channel 0.55 / 0.82 / 0.30, still to run 0.58 / 0.66 / 0.50 |
  | GCD band | 0.67 / 0.78 / 1.0, 20 % still to run, 10 % elapsed (fading) |
  | Returning cooldown | icon 16, 60 % while far (the Encounter Timeline's Long-track alpha), 100 % and one highlight flash from its last 1.5 s (Growth: 16 to 24 and an alpha ramp) |
  | Ready row | slots 18, 2 apart, the nearest 12 from the now line; a cooling slot is an empty outline (1 px, 30 %) |

- As built (M8): a few things differ from the rules below. The swing
  diamonds are drawn in both skins - a tinted square on a dark outline, the
  hollow ranged one on a dark translucent diamond - not Blizzard's pip, whose
  color, shape and missing outline read poorly over a bright scene. A paused
  hand's next diamond wears a pause glyph (Native: Blizzard's pause icon;
  Flat: two bars), because a frozen diamond alone reads as stuck. The Flat
  track is 2 px in Single lane (a lone 1 px line could straddle two screen
  pixels and vanish; Pixel grid has the general rule). The Long flag in the
  lane window only forces a spell long: it
  cannot make a cooldown of 30 s or more count as rotation. A texture's
  alpha is one value on this client (SetAlpha replaces SetVertexColor's):
  colors go in opaque and the alpha is set after them.
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
  full-color diamond (drawn in both skins, on a dark outline) - the
  library's expiry is fact-grade. The cadence chain is
  1 deep: one smaller, desaturated diamond after the next landing.
  Landed swings stay diamonds and fade over the past window. A queued
  ability replaces the next landing's diamond with its own small icon
  (about 14 px), and the landed swing keeps that icon. A paused hand's
  diamonds freeze and dim; a parked hand (auto-attack off) shows a dim,
  desaturated diamond on the now line. The next landing's diamond grows
  (about 5 to 8 px at the default height) over its last 1.5 s, the same
  urgency rule as a returning cooldown (Urgency has the open alternative).
- Single lane, casts: a bar about 6 px thick on the track, in a warm gold
  kept clear of the GCD's blue - solid where elapsed, lighter where still
  to run - from cast start to completion, the spell icon at its
  completion end. Gold is Blizzard's casting color (the classic cast bar
  fills yellow). The icon is full color during the cast (the cast time
  is a plain read, `PROBES.castTimePlain`, as for Detailed's completion
  mark). Once complete, bar and icon fade over the past window. A
  stopped, failed or interrupted cast cuts the bar where it stopped and
  moves the icon there with the red border and the across-lane shake; the
  unrun part vanishes with the red pop (Stopped casts) - red is
  Blizzard's interrupted color. Pushback jumps the
  bar's end and icon with the amber pop. A channel draws the same bar to
  its end, in green, as Blizzard fills a channel - a yellow green, clear
  of the ranged diamond's pale green and the teal pop (and a bar on the
  track, not a diamond on the main-hand side); one stopped early follows
  the stopped-cast rule. An instant
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
  return flashes a ring on the slot. The row is the Encounter Timeline's
  sorted-track idea - fixed slots, not time positions - applied to what
  is ready.
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
  (Single lane default 1.5 s / 10 s) and length; the Settings sliders edit
  the active layout's values. The lane height setting sizes the track and
  everything on it scales with it - the pixel sizes above are those at the
  default height. Edit Mode, visibility and skin are shared. Lane spacing
  is the gap between the track, the ready row and the engine-drawn rows;
  the lane background alpha is Detailed's (Single lane has the backdrop).
- Single lane, orientation: all four orientations. The main hand takes the
  lane-start side across the track (top when horizontal, left when
  vertical); the ready row, then the engine-drawn rows, stack on the other
  side. A flip mirrors only the time axis.

### Time axis

- Linear in both layouts: one pixel rate from the past edge to the future
  edge, so a gap between two marks is a duration the eye can compare.
- Blizzard's Encounter Timeline is not linear. Its track is split by
  remaining time: a **Short** track near the now end, drawn to scale over
  the length of the line art; a **Medium** track, a fixed 55 px holding a
  longer span; a **Long** track and a **Queued** track of fixed slots
  (38 px each), events sorted rather than placed by time, Long-track icons
  at 60 % alpha, each slotted track behind a `combattimeline-cooldown-divider`.
  An event slides from slot to linear track as its time comes.
- Open (needs an ADR-0005 amendment): squeeze the far future the same
  way - the near 4-5 s to scale over most of the length, the rest of the
  window in a short compressed stretch - so a 10 s window stops costing
  700 px. Against it: a non-linear axis breaks "equal gaps, equal time"
  for distant marks, and the edge clamp, chevron and sinks (a linear
  StatusBar) would need the same split. Today the edge clamp and chevron
  play the Long track's part.

### Lanes and tracks

- Every lane draws its own track line through its middle. Native: the
  `combattimeline-line-left` / `-right` pair — the left segment over the
  past window, the right one over the future window, meeting at the now
  line. Flat: a 1 px line (2 px in Single lane), its width rounded to
  whole screen pixels (Pixel grid).
- Line breaks: Blizzard cuts gaps into its line with
  `combattimeline-line-break-mask` at 1, 3, 5, 7, 9 and 11 s (one every
  2 s from 1 s) - not under its icons. The gaps are its only time scale:
  no ticks, no numbers, nothing added. A texture takes at most three
  masks, so they are shared between the two line segments.
- Here the line breaks 1, 3 and 5 s either side of the now line (in the
  window), in both layouts: the timeline's seconds scale, the one cue that
  lets the eye read "about 2 s away" without counting pixels. Native: the
  mask, three per line segment (past breaks on the start segment, future
  ones on the end segment); Flat: the line drawn in segments with a 3 px
  gap. No break sits under the now line.
- A **lane background alpha** slider (default 0, Blizzard's
  `BackgroundAlpha` default) adds a faint band behind each lane for players
  who want it. Blizzard's background is not a band: it is the line's
  shadow atlas (`combattimeline-line-shadow`, `-vertical`) behind the line,
  at that alpha. Single lane draws a line shadow of its own instead (Layouts):
  two black gradient bands fading out from the track, in both skins - the
  atlas, stretched to the track's extent, read as a dark block (build 70235).
- Lane order runs along the cross-axis: top to bottom when horizontal
  (hands on top), left to right when vertical (hands on the left). A flip
  mirrors the time axis only, never the lane order.

### Pixel grid

- Still art is sized and placed on whole screen pixels: line widths go
  through `PixelUtil.GetNearestPixelSize` (`Util.PixelSize`), and a shape
  that must line up with a line is built from the line's width (the Flat
  now-line diamond is bars of 1, 3, 5, 3 and 1 line widths, so it sits on
  the same pixels as the line at any UI scale). A turned square is drawn
  centred on a pixel and an even-width line between two, so the two never
  share a centre.
- Moving art is not snapped. Blizzard's event textures inherit
  `texelSnappingBias="0.0" snapToPixelGrid="false"`, which "makes the
  translations visually smoother": at the default length a mark moves about
  one pixel per frame, and a snapped one steps. Every texture that scrolls -
  the icon art, the diamonds, ticks, bars, the trail, the chevron - is made
  by `Util.MovingTexture` (unsnapped); a ready-row slot's outline stays
  snapped.
- The thin still lines (Flat tracks, the now line) are unsnapped too,
  because a snapped 1 px line was drawn or dropped depending on where it
  fell between pixels (build 70235). With line widths rounded to whole
  pixels they could return to snapping; untried.

### Now line

- Native: `combattimeline-cooldown-divider` stretched across every lane,
  with the `combattimeline-pip` diamond at the lane-start end. Flat: a 2 px
  white line at 0.6 alpha (Single lane: warm, 75 %, with a drawn diamond).
  The divider art is built as a short section divider, so its look at full
  frame height is a by-eye check item.
- On Blizzard's timeline the pip is not the now point: it sits on the line
  at the highlight time (5 s), with that number under it. Here it caps the
  now line. Players of the boss timeline may read a pip as "the warning
  point"; accepted while no highlight time is drawn (Urgency).

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
  control; no separate icon scale. (Blizzard's timeline has one - Edit
  Mode's Icon Size, apart from the frame's size; Frame chrome.)
- **Stacking**: what matters more draws on top. Blizzard raises event
  frames by severity in steps of 10 and puts paused events below active
  ones. Here: the next landing above its chain, an active hand above a
  paused one, a mark about to return above a distant one, every mark above
  the GCD band and the cast bar.

### Mark motion

- Marks scroll every frame; their set changes on events. How a mark comes
  and goes, after the Encounter Timeline's animations:

  | Moment | Blizzard | Here |
  |---|---|---|
  | Appears | fade in 0.2 s, sliding 25 px in across the track over 0.35 s | at the far edge, already dim; a prediction that appears inside the window fades in over 0.2 s in place |
  | Reaches zero | grows to 1.35× and fades over 0.2 s, its glow at full | landings and returns: the pop or ring at the now line |
  | Cancelled | fades over 0.2 s, sliding 25 px out | fades over 0.2 s in place (below); a stopped cast adds the red pop (Stopped casts) |
  | Moved | glides 0.45 s between slots | jumps (Hand-lane effects) |

- A withdrawn prediction - a cadence chain dropped, a return cleared by a
  reset, a queued icon swapped back - fades over 0.2 s where it stood,
  instead of vanishing (Blizzard's `CancelAnimation`). On each rebuild the
  renderer pairs the predicted marks and diamonds on screen with the new
  ones of the same kind at the same instant; an unpaired old one is kept
  for 0.2 s as leaving - the mark itself, in its own art, fading - unless
  an unpaired new one of its kind shows it only moved - a jump stays a jump:
  a correction moves the mark, a withdrawal removes it. One within 0.1 s
  of the now line was used up, not withdrawn; a layout pass fades nothing.
- The same pairing finds the arrivals: an unpaired new prediction fades in
  over 0.2 s from where it first stands.

### Urgency

- Built: the next landing, a queued ability's icon and a returning
  cooldown change once as they cross 1.5 s (one GCD) - Settings, Urgency
  cue (Single lane):
  - **Highlight** (default): the mark steps from its far alpha to full and
    plays one flash - the pop's glow in the return ring's color, rising to
    0.9 and falling over 0.4 s (Blizzard's HighlightGlow timing, a little
    stronger), around an icon at 1.5× its size, around a diamond at 2.6×.
    The mark does not grow, so stepped cooldown icons are spaced for 16 px.
  - **Growth**: the M8 ramp - it grows (diamond 5 to 8, icon 16 to 24) and
    brightens over the 1.5 s.
- The motion trail (Detailed) fades in over the same 1.5 s.
- Blizzard's rule is a moment, not a ramp: at a highlight time (5 s by
  default, a player setting, marked on the line by the pip and its number)
  the icon plays one glow and swirl (0.6 s), then pulses (1.0 → 1.1 → 0.9,
  about once a second) until it fires - on the Short track only, never
  while paused or queued. Peripheral vision catches an onset better than
  slow growth.
- No pulse: on swing diamonds it would flicker at swing speed, and the
  busy-now-line feedback from the layout study argues for the single flash.
  Blizzard's highlight art (`combattimeline-fx-highlight`) drew a blank
  square in its place (build 70235), so both skins use the pop's glow.

### State tints

Saturation encodes source certainty (`SPEC.md`); tints encode usability,
using Blizzard's own action-bar and Cooldown Manager values so nothing new
is learned:

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

In the Cooldown Manager a grey icon means "on cooldown" (under a black
swipe at 70 %). Here grey means "predicted" - and every predicted icon is
a spell still cooling, so both readings agree. Keep it so: a happened mark
is never desaturated.

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
  addon and Blizzard's cast bar (interrupted: red), and avoids Blizzard's
  out-of-range red tint.
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
  shake, ranged = hollow diamond, paused = glyph. Correction streaks carry
  **direction**: the streak tapers from
  bright at the mark's new position to transparent at the old one, so a
  teal correction visibly points toward the now line (earlier) and an
  amber one away from it (later) — the bar addon's lunge and flinch.
- No alternate palette in v1. The encoding check views the test-mode
  effect previews through a color-blindness simulator once (the client
  has one: the `colorblindSimulator` CVar). Blizzard's own colorblind
  mode (`colorblindMode`) adds words and shapes, not new colors - the
  route this addon already takes, so it changes nothing here.

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
- The clamp is this addon's Long track (Time axis): Blizzard parks distant
  events in dimmed slots behind a divider; here they wait at the far edge,
  dimmed by the far-alpha ramp.

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
- Blizzard's versions of the same states: the pause icon is 16 px in the
  icon's bottom-right corner, with a small bump (1 → 1.1 → 1 over 0.5 s)
  when it appears; queued adds three bouncing dots
  (`combattimeline-fx-queued-icon`) under the icon; a paused event draws
  behind active ones and never pulses (Stacking, Urgency).

### Text

- No text on readable marks: a number on a calibrated estimate would give
  a guess a number's authority, which desaturation exists to deny.
  (Blizzard's timeline keeps names and status text off by default, and
  shows them only when vertical.)
- **Sink countdown** (Settings toggle, off by default): the sink icon may
  show the engine's true remaining time as text — `SetText` accepts the
  secret (build 70205 smoke test). It is the only mark whose number is
  true in combat, and it offsets the sink's missing chevron and
  linear-only scale.
- Any text the frame draws uses one of Blizzard's shadowed system fonts
  (`SystemFont_Shadow_*`, as the timeline's pip number and event names do),
  never a plain one: the shadow is what keeps it readable over the world.

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
  band. Single lane is the exception: its backdrop panel (Layouts), the
  mock-up's dark ground. Blizzard gets the same contrast with no panel - a
  shadow under the line, a border on each icon, a dark outline on each
  diamond - so with the line shadow in, the backdrop default drops to 20 %.
- The frame is not an Edit Mode system, so Blizzard's selection
  highlight does not draw for it: while Edit Mode is open the frame shows
  its own placement handle — a translucent band over its bounds and a
  "4everActionTimeline — drag" label — hidden again on exit.
- The boss timeline's Edit Mode settings are the set players know: size,
  opacity, orientation, icon direction, background alpha, icon size,
  countdown, text, highlight time. This addon has the size (scale),
  opacity (a Settings slider, 0.1 to 1, the whole frame), orientation and
  flips, background alpha and countdown; it has no icon size apart from
  the lane height.

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
  The onset is a constant, not a setting. Detailed only: Single lane's
  growth replaces it.
- Native: `combattimeline-line-icontrail`, `ADD` blend, at its atlas
  size. Flat: a `WHITE8X8` streak in the lane's track color, fading to
  transparent toward the now line, 64 px long. Either lies on the mark's
  now-facing side, its end 10 px into the icon (Blizzard's
  `UpdateTrailLayout`), and fades in over the 1.5 s. (Blizzard fades it in
  over the first 10 % of the Short track and out quickly when the event
  leaves it.)
- The sink icon never trails: Lua cannot read its position, so the 1.5 s
  onset cannot be timed honestly. Happened marks and now-line marks never
  trail.

## Open from the Blizzard review (2026-10-12)

Built and checked in game (2026-10-12): moving marks unsnapped, line
breaks, withdrawn predictions fading, green channels, the opacity slider.
Built, in-game check pending: the highlight moment (Urgency), predictions
fading in (Mark motion), the line shadow with the backdrop at 20 %
(Layouts). Still open - each described in its section, none decided:

| Item | Section | Cost |
|---|---|---|
| Still lines snapped again | Pixel grid | small, untried |
| Squeezed far future | Time axis | large, an ADR-0005 amendment |

## Verified facts (Forever branch source; live 12.1.0.69933 re-read 2026-10-12)

- Action bar and Cooldown Viewer icon tints: usable `1,1,1`; not enough
  mana `0.5,0.5,1.0` (blue); not usable `0.4,0.4,0.4`; out of range
  `0.64,0.15,0.15` (`ActionButton.lua` `UpdateUsable`,
  `CooldownViewerConstants`).
- The Cooldown Viewer desaturates an icon while its spell is on actual
  cooldown — the same language as the timeline's desaturated predicted
  mark. Its cooldown swipe is black at 70 %, an aura's swipe
  `1, 0.95, 0.57` at 70 %.
- Encounter Timeline defaults: 5 s highlight time, 55 px cross-axis extent,
  20 px start/end padding, 0.35–0.45 s intro/outro/translation animations,
  background alpha 0 (`EncounterTimelineConstants.lua`).
- Encounter Timeline tracks: Short (linear, the line art's length), Medium
  (linear, 55 px), Long and Queued (sorted, 38 px slots); icon alpha by
  track 0.6 Long, 1.0 elsewhere; frame level by severity +10 / +20 / +30,
  paused +1 (`EncounterTimelineTrackLayout.lua`,
  `EncounterTimelineTrackView.lua`, `EncounterTimelineTrackEvent.lua`).
- Encounter Timeline event animations: intro alpha 0 → 1 in 0.2 s plus a
  25 px cross-axis slide in 0.35 s; finish scale 1.35 and alpha → 0 in
  0.2 s; cancel alpha → 0 in 0.2 s plus a 25 px slide out; pulse 1.0 → 1.1
  → 0.9 looping (0.2 + 0.2 + 0.6 s) under the highlight time on the Short
  track only; highlight glow to 0.7 and a 180° swirl in 0.6 s
  (`EncounterTimelineTrackEvent.xml`, `EncounterTimelineTemplates.xml`).
- Encounter Timeline line breaks: six `combattimeline-line-break-mask`
  masks at 1 s + 2 s steps, at most three per line segment; the pip at the
  highlight time with its number in `SystemFont_Shadow_Large`; event
  textures unsnapped (`texelSnappingBias 0`, `snapToPixelGrid false`).
- Casting bar (classic colors): cast fills yellow and finishes green;
  channel green; uninterruptible grey; interrupted red
  (`CastingBarFrame.lua` `CastingBarTypeInfo`).
- `PixelUtil.GetNearestPixelSize` rounds a size to whole physical pixels
  through `768 / physical screen height` and the region's effective scale.
- Accessibility CVars in the source: `colorblindMode`,
  `colorblindSimulator`, `colorblindWeaknessFactor`, `ShakeStrengthUI`;
  no UI-wide reduce-motion CVar was found.
