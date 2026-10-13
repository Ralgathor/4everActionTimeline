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

- **Native skin (default)** — Blizzard's cast bar family: its background,
  fills, spark and glow, the swing timer's border, the cast bar's name box
  behind the ready row, the Cooldown Manager bar art for the GCD (Layouts).
  The bar reads as the cast bar and swing timer players already watch.
  (Until ADR-0007 it was the Encounter Timeline + Cooldown Manager family:
  the `combattimeline-*` track art and Cooldown Manager–framed icons; the
  divider and pip remain as the now line's fallback.)
- **Flat skin (option)** — a `WHITE8X8` body, border and lines,
  square-cropped icons, 1 px borders; no atlas dependency.
- Icons are plain in both skins: edge-cropped in a 1 px dark border, as
  the cast bar shows its icon.
- A Settings dropdown chooses the skin. Every Native atlas is guarded with
  an atlas-exists check at load; a missing atlas falls back to the Flat
  equivalent for that element only, never an error.
- The reposition pop colors (teal, amber, red) come from 4everSwingTimer's
  effect colors in both skins.

### Orientation

- Three choices: **horizontal** (default: past left, future right),
  **horizontal flipped** (future left), and **vertical** (with its own
  flip). The bar, its marks, the ready row, edge clamp and the sink follow
  the orientation.
- The sink stays possible in every orientation: `StatusBar` supports
  `SetOrientation("VERTICAL")` and `SetReverseFill`, so the fill — and the
  icon anchored to its leading edge — runs from the now line toward the
  future edge whichever way that is. Each orientation's sink layout joins
  the by-eye encoding check.
- Orientation-dependent art (the bar's body, border and fills, the spark
  and glow, the chevron) is rotated through texture coordinates, the way
  `EncounterTimelineOrientedTextureMixin` does.

### Layouts

- One layout, **Bar track** (ADR-0006; the only one since ADR-0007): every
  lane kind but the sink lanes on one framed bar read like a cast bar,
  placed by Single lane's rules (ADR-0005) - the hands on its edges, casts
  and returning cooldowns in it, the ready spells in a row under it.
  Single lane and Detailed, the two other layouts built in M7 and M8, were
  removed on 2026-10-13; where a section below keeps a note about them it
  is history.
- The bar's values, from the layout study mock-up and the M9 in-game
  tuning, at bar height 26 (they scale with it):

  | Element | Value |
  |---|---|
  | Length | the Length setting, default 700 px (10 s at about 58 px/s); linear |
  | Frame | the bar height. Native: the cast bar's background as the body under Blizzard's swing timer border, stretched over the bar whole (drawn for a bar of any size, where the cast bar's frame is drawn for one), casts and channels filling it with the cast bar's own fills, the art at its own proportions from the cast's start (a short cast shows its first part, cropped; a long one stretches it) and revealed up to now as Blizzard's cast bar reveals it, Auto Shot with its grey fill tinted teal, the GCD the Cooldown Manager bar art tinted blue. Flat: a body dark at 88 %, a 1 px light border at 38 % over a dark outline, cut where the now line and the seconds scale cross it |
  | Ready row | under the bar, as Blizzard's cast bar shows the spell's name in the box under its bar: a box behind the bar reaching 16 px below it, the bar's width less 2 px at each end so it meets the inside of the border's rounded ends (Native: the cast bar's name box, `ui-castingbar-textbox`; Flat: a dark box at 60 %), the ready row in it with padding (slots of 12, 4 apart, the nearest 12 from the now line, 2 px clear above and below, at least 5 px from the box's end - the frame and bar widen for a long row, bars such as a cast running on to the bar's start and every happened element fading over all the past the bar shows, at one rate), a cooling slot an empty outline (1 px, 30 %). (First built as a four-slot cap inside the bar at its start; moved under it, 2026-10-13, giving the bar its whole length back.) |
  | Icons | filling the bar inside its border, plain in both skins (edge-cropped, a 1 px dark border), as Blizzard's cast bar shows its icon; no Cooldown Manager frame. Flat: 24 inside its 1 px border. Native: 18, inside the swing timer border by what 4everSwingTimer keeps clear inside it (4 px across); casts and the GCD tint keep the same inset |
  | Casts | the bar's full height inside the border: elapsed gold 0.88 / 0.67 / 0.35 at 95 %, still to run 0.67 / 0.63 / 0.57 at 60 % (Flat; Native: the cast bar's own fills, untinted); a channel green 0.55 / 0.82 / 0.30, still to run 0.58 / 0.66 / 0.50; the icon at the end |
  | GCD | Settings: GCD - **Tint** (default; Native: the Cooldown Manager bar art tinted pale blue 0.67 / 0.78 / 1.0, 60 % still to run, 30 % elapsed fading; Flat: the same tint plain - a fainter band vanished over the bar's grey body) or **Strip** (4 px inside the bottom edge, 75 % / 30 %) |
  | Swing diamonds | half diagonal 5, on a dark outline 1.5 px out, on the frame's edges: main hand (and ranged) on the top edge, off hand on the bottom edge; main hand 0.91 / 0.93 / 0.96, off hand 0.79 / 0.69 / 0.54, ranged hollow 0.62 / 0.86 / 0.66; next landing 75 % while far, then full with one flash; one chain diamond (half diagonal 4 at 55 %), landed ones fading, a parked hand dim (50 %) on the now line; grey at 80 % of the color's luminance |
  | Queued ability | its icon in the bar at the next landing; the diamond stays on the edge; the landed swing leaves the icon in the bar, fading |
  | Returning cooldowns | icons only, desaturated, 60 % while far (the Encounter Timeline's Long-track alpha); beyond the window they park at the far edge, each further one tucked 5 px to the left (a stack's peek), one chevron for all |
  | Card stack | every icon ahead of the now line (a cast's end, a queued ability, Auto Shot, the cooldowns): icons closer than an icon's width group; facts in front of predictions, else the soonest; the others keep their own place when that already shows them, else peek out 5 px further each (about 0.08 s, too little to mislead); three show, then "+n" |
  | Linked set | one icon with a link mark (a small corner badge; no link atlas exists) on the bar; in the ready row a slot per spell, each wearing the link mark |
  | Now line | Native: the cast bar's spark (`ui-castingbar-pip`, additive) across the bar and 6 px beyond, no pip; the border art is not cut. While a cast runs through it, the glow Blizzard's cast bar trails behind its spark (a channel: its shadow), its height scaled to the bar, its width Blizzard's 37 px (the casts here are shorter than its cast bar), masked to the cast's elapsed fill, so it never shows outside the art. Flat: 2 px warm 0.91 / 0.85 / 0.66 at 75 %, 6 px beyond the frame on both sides, a stepped diamond (1-3-5-3-1 line widths, as wide as tall) on its top end, and on its bottom end too while no ready row sits under the bar; the border cut 8 px around it, so the frame itself marks now |
  | Seconds scale | Settings: Seconds scale, off by default: the border cut 4 px at 1, 3 and 5 s either side on both edges, a 5 px tick under the frame, the seconds under the future ticks |
  | Urgency | the highlight: a step from the far alpha to full and one flash at 1.5 s (Urgency) |
  | Auto Shot | the Auto Shot cast (below): the windup fills the bar's height in teal, ending at the Auto Shot icon |
  | Engine-drawn lanes | thin rows (18 px, 16 px icons) under the ready row |

- Hands. Filled for melee, hollow for ranged, so shape tells them apart
  first. Without an off hand the bottom edge stays empty: the frame never
  changes height mid-session. One shape from future to past, so a landing
  never changes look as it crosses the now line; the next landing is full
  color - the library's expiry is fact-grade. A paused hand's diamonds
  freeze and dim, its next diamond wearing a pause glyph (Native:
  Blizzard's pause icon; Flat: two bars), because a frozen diamond alone
  reads as stuck. The diamonds are drawn in both skins - a tinted square on
  a dark outline, the hollow ranged one on a dark translucent diamond - not
  Blizzard's pip, whose color, shape and missing outline read poorly over a
  bright scene.
- Auto Shot (ADR-0006): ranged is the **Auto Shot cast** - the windup
  (0.52 s x ranged speed / the weapon's base speed, read plain from its
  tooltip, probe H3; the hunter standing still) drawn as a cast in the bar
  in teal 0.47 / 0.78 / 0.82, ending at the Auto Shot icon (full color for
  the next shot, desaturated for the one after, fired ones fading); the
  reload between windups stays empty, the time the hunter may move. Held
  (moving keeps cancelling the shot) borders its icon amber; the delay
  span is an amber line on the bar's bottom edge, clear of the casts; the
  clip tick sits on the hand's edge. Without a ranged weapon's base speed (no
  tooltip line), the hollow diamond stays on the top edge.
- Casts: from cast start to completion, the spell icon at its completion
  end. Gold is Blizzard's casting color (the classic cast bar fills
  yellow); a channel is green, as Blizzard fills one - a yellow green,
  clear of the ranged diamond's pale green and the teal pop. The icon is
  full color during the cast (the cast time is a plain read,
  `PROBES.castTimePlain`). Once complete, bar and icon fade over the past.
  A stopped, failed or interrupted cast cuts the bar where it stopped and
  moves the icon there with the red border and the across-lane shake; the
  unrun part vanishes with the red pop (Stopped casts) - red is Blizzard's
  interrupted color. Pushback jumps the bar's end and icon with the amber
  pop. An instant ability leaves its icon in the bar at the moment of use,
  fading the same way.
- Returning cooldowns: an overdue icon pins on the now line until the
  engine confirms the spell is ready; past the far edge the edge clamp and
  chevron apply.
- Ready row: each rotation ability has a fixed slot in lane-window order; a
  slot shows a faint empty outline while its spell cools down and fills
  when it is ready, so the row never reorders or changes width. The slots
  keep the state tints (blue resource-short, grey unusable, desaturated
  unknown cooldown), so the row reads "pressable now". A return flashes a
  ring on the slot. The row is the Encounter Timeline's sorted-track idea -
  fixed slots, not time positions - applied to what is ready.
- Ready row side: a Settings dropdown, **Past side** (default) or **Future
  side**. Past side keeps a returning cooldown moving one way (it crosses
  the now line into its slot) and leaves the future side to what is
  arriving; the row's width follows its slot count, not the past window -
  the frame widens on its past side to fit the slots. Future side starts
  the slots at the now line, for players who keep their eyes ahead of it.
  Either side follows the orientation.
- Long cooldowns: a spell whose cooldown is not yet known (uncalibrated, no
  class-data tag) counts as a rotation ability and keeps a slot until its
  cooldown is learned - the one case where the ready row changes width.
  Long cooldowns get no slot; while cooling they ride the bar like any
  returning cooldown; on their return a ring flashes on the now line and
  the icon leaves the bar. The Long flag in the lane window only forces a
  spell long: it cannot make a cooldown of 30 s or more count as rotation.
- GCD: behind every mark; where the GCD still has to run it is at its full
  strength, the elapsed part dimmer and fading with age, so idle gaps
  between GCDs show. An off-GCD ability opens nothing. The tint is not a
  mark: source-certainty saturation applies to marks only, so the part
  still to run may be the stronger one.
- Hand effects (Hand-lane effects, Color-blind safety): the reposition pop
  flashes on the diamond; the correction streak runs on the hand's edge
  from old to new diamond. Held: the Auto Shot icon's border, or the
  hollow diamond's outline, turns amber. The across-lane shake moves only
  the affected diamond or icon, across the bar.
- Engine-drawn lanes: the sink rules hold - the spell's predicted mark
  leaves the bar while its sink is on, the pinned icon shows no chevron,
  the countdown text stays optional. Its ready-row slot (or, for a long
  cooldown, the now-line ring) still follows the plain off-cooldown read.
- Edit Mode panel: one past and future window (default 1.5 s / 10 s) and one
  length. The bar height setting sizes the bar and everything on it scales
  with it - the pixel sizes above are those at the default height. Engine
  lane spacing is the gap above each engine-drawn row.
- Orientation: all four. The main hand takes the lane-start edge (top when
  horizontal, left when vertical); the ready row, then the engine-drawn
  rows, stack on the other side. A flip mirrors only the time axis. Text
  (the "+n" and the scale's seconds) stays upright.
- As built: the card stack's offsets are fixed at each rebuild. The past
  window starts a pixel in from the bar's start, not half an icon: a mark
  has faded out by then. A texture's alpha is one value on this client
  (SetAlpha replaces SetVertexColor's): colors go in opaque and the alpha
  is set after them.

### Time axis

- Linear: one pixel rate from the past edge to the future edge, so a gap between two marks is a duration the eye can compare.
- Blizzard's Encounter Timeline is not linear. Its track is split by
  remaining time: a **Short** track near the now end, drawn to scale over
  the length of the line art; a **Medium** track, a fixed 55 px holding a
  longer span; a **Long** track and a **Queued** track of fixed slots
  (38 px each), events sorted rather than placed by time, Long-track icons
  at 60 % alpha, each slotted track behind a `combattimeline-cooldown-divider`.
  An event slides from slot to linear track as its time comes.
- Open (needs an ADR): squeeze the far future the same
  way - the near 4-5 s to scale over most of the length, the rest of the
  window in a short compressed stretch - so a 10 s window stops costing
  700 px. Against it: a non-linear axis breaks "equal gaps, equal time"
  for distant marks, and the edge clamp, chevron and sinks (a linear
  StatusBar) would need the same split. Today the edge clamp and chevron
  play the Long track's part.

### Lanes and tracks

- Every lane but the sink lanes draws on the one bar (Layouts); the sink
  lanes keep a thin row each under the ready row, in lane order.
- The bar has no track line: the frame and its border carry the time axis.
  Its seconds scale (optional) cuts the border at 1, 3 and 5 s either side
  of the now line - Blizzard's line breaks moved onto the frame
  (Blizzard cuts gaps into its own line with
  `combattimeline-line-break-mask` at 1, 3, 5, 7, 9 and 11 s; the gaps are
  its only time scale).
- History: Detailed and Single lane drew a line per track
  (`combattimeline-line-left` / `-right`, Flat a 1 or 2 px line) broken
  at 1, 3 and 5 s, a lane background band, and in Single lane a line
  shadow and a backdrop panel; all removed with those layouts (ADR-0007).
- Rows run along the cross-axis: top to bottom when horizontal, left to
  right when vertical. A flip mirrors the time axis only, never the rows.

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
  the icon art, the diamonds, ticks, bars, the chevron - is made
  by `Util.MovingTexture` (unsnapped); a ready-row slot's outline stays
  snapped.
- The thin still lines (the now line) are unsnapped too,
  because a snapped 1 px line was drawn or dropped depending on where it
  fell between pixels (build 70235). With line widths rounded to whole
  pixels they could return to snapping; untried.

### Now line

- Native: the cast bar's spark across the bar (Layouts); where its atlas
  is missing, `combattimeline-cooldown-divider` with the
  `combattimeline-pip` diamond at the lane-start end. Flat: a 2 px warm
  line at 75 % with a drawn diamond.
- On Blizzard's timeline the pip is not the now point: it sits on the line
  at the highlight time (5 s), with that number under it. In the fallback
  it caps the now line.

### Marks

- Both skins: the icon edge-cropped with a 1 px black border, filling the
  bar inside its border, as the cast bar shows its icon. The sink icon
  wears the same frame. (Until ADR-0007, Native framed icons as
  Blizzard's event icon: the Cooldown Manager mask and overlay.)
- The frame clips its children, so it pads the bar across the axis by the
  now line's reach past it.
- Icon size follows the bar height setting; no separate icon scale.
  (Blizzard's timeline has one - Edit Mode's Icon Size, apart from the
  frame's size; Frame chrome.)
- **Stacking**: what matters more draws on top. Blizzard raises event
  frames by severity in steps of 10 and puts paused events below active
  ones. Here: the next landing above its chain, an active hand above a
  paused one, a mark about to return above a distant one, every mark above
  the GCD tint and the cast fills; a card stack's front above the icons it
  covers.

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

- Built: the next landing, a queued ability's icon, the next Auto Shot and
  a returning cooldown change once as they cross 1.5 s (one GCD): the mark
  steps from its far alpha to full and plays one flash - the pop's glow in
  the return ring's color, rising to 0.9 and falling over 0.4 s
  (Blizzard's HighlightGlow timing, a little stronger), around an icon at
  1.5× its size, around a diamond at 2.6×. Nothing grows: an icon filling
  the bar has no room. (Single lane offered a Growth cue and Detailed a
  motion trail over the same 1.5 s; both removed with those layouts.)
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
| parked (hand) | dimmed, desaturated diamond |

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
  full color with a **red border** (its 1 px border, both skins). The icon stays readable (which
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
  color, fading within ~0.3 s — a `WHITE8X8` streak, both skins. The timeline's
  equivalent of the bar addon's directional burst (teal lunge, amber
  flinch). Also drawn from an early-landing happened mark back to the
  abandoned prediction.
- **Pop budget**: teal once per correction; amber once per retry chain
  (later sawtooth jumps get the streak only); red once per reset.
- **Held**: the next Auto Shot icon's border (or the hollow ranged
  diamond's outline) turns amber for the whole retry chain, cleared when
  the shot fires.
- **Delay span**: a thin amber line (2 px) on the bar's bottom edge, from
  the first retry to the fired shot.
- **Clip mark**: a small red tick (~⅓ bar height, 2 px wide) on the hand's
  edge at the reset instant — a tick, not an icon, so it never reads as a
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
- The bar fills its whole height with casts, channels and the Auto Shot
  windup alike, so there the icon at a bar's end is the shape cue: each
  fill ends in its own spell's icon.
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
  white), turned through tex coords for every
  orientation — mirrored when flipped, rotated when vertical — so
  `-left` is not needed. The other
  candidates seen (`common-icon-forwardarrow`, `NPE_ArrowRight`) are
  pre-colored yellow and were passed over. Fallback in both skins is a
  small triangle of two rotated `WHITE8X8` strokes in white.
  Size ~⅓ of the icon, just outside the icon's outer edge so it never
  covers the icon.
- The clamp is this addon's Long track (Time axis): Blizzard parks distant
  events in dimmed slots behind a divider; here they wait at the far edge,
  dimmed by the far-alpha ramp.

### GCD window bar

- Native: the Cooldown Manager bar art (`UI-HUD-CoolDownManager-Bar`),
  tinted, as a tint over the bar or a strip (Layouts). Flat: `WHITE8X8`.
- Color: a pale, whitish blue (near the swing timer's GCD tint) — kept
  clear of Blizzard's not-enough-mana blue `0.5, 0.5, 1.0`.
- The split at the now line needs no extra divider; the now line already
  draws it.

### Paused and queued

- Paused: the hand's diamonds freeze and dim, the next one wearing a pause
  glyph (Native: Blizzard's `combattimeline-fx-pause-icon`; Flat: two
  bars). Queued: the ability's icon rides the bar at the next landing, its
  diamond kept on the edge. No overlay on icons (they are plain); until
  ADR-0007 Native added Blizzard's `combattimeline-fx-pause` and
  `-queued` overlays to Detailed's icon marks. Both join the by-eye
  encoding check.
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
- The card stack's "+n" (a count of stacked icons) and the seconds scale's
  numbers (frame chrome) are the two exceptions: neither puts a number on
  an estimate.
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

- The bar is the frame (Layouts): its body gives the marks their contrast,
  as the cast bar's does. No panel or background behind it. (Detailed had
  none and a lane background slider; Single lane a backdrop panel and a
  line shadow; all removed with them, ADR-0007.)
- The frame is not an Edit Mode system, so Blizzard's selection
  highlight does not draw for it: while Edit Mode is open the frame shows
  its own placement handle — a translucent band over its bounds and a
  "4everActionTimeline — drag" label — hidden again on exit.
- The boss timeline's Edit Mode settings are the set players know: size,
  opacity, orientation, icon direction, background alpha, icon size,
  countdown, text, highlight time. This addon has the size (scale),
  opacity (a Settings slider, 0.1 to 1, the whole frame), orientation and
  flips, and countdown; it has no icon size apart from the bar height.

### Settings window (the spell window)

- Mirrors the Cooldown Manager settings window (M10): a portrait frame, a
  search box with a gear menu (Options, Reset character to class),
  four collapsible sections of 38 px icons seven to a row — Timeline, Long
  cooldowns, Engine lanes (with its n/6 count), Not displayed — a layer
  dropdown (<Class> (all characters) / This character) and Revert at the
  bottom. Never built by inheriting `CooldownViewerSettings*` templates,
  whose mixins are wired to Blizzard's Cooldown Manager data and settings
  store: it uses `ButtonFrameTemplate`, `SearchBoxTemplate`,
  `ListHeaderThreeSliceTemplate`, `ScrollFrameTemplate`,
  `WowStyle1DropdownTemplate` and `MenuUtil` menus, each with a plain
  fallback.
- Icons only; the tooltip is the spell's own plus a line per state (manual
  cooldown, overridden, new, long by itself). A manual cooldown shows as
  seconds at the icon's corner; "new" and "L" (an Engine-lane spell flagged
  long) are small marks at the other; "=" marks a spell long by itself,
  which cannot leave Long cooldowns for Timeline.
- Drag an icon to reorder within a section or drop it on another; a ghost
  icon follows the cursor. Dragging is off while the search box has text.
  Right-click: Set cooldown..., Clear cooldown, Long cooldown (Engine lanes
  only), Move to each section.
- The window sits above Edit Mode (`FULLSCREEN_DIALOG`), so it opens from
  Edit Mode's panel without leaving it.

### Edit Mode

- The timeline in Edit Mode wears Blizzard's selection frame: the
  `editmode-actionbar-highlight` kit while idle, `-selected` once clicked,
  with the label "Action Timeline"; a plain band when the atlases are
  missing.
- Clicking it opens the settings panel under it (over it when there is no
  room): Scale (50–200 %), Opacity (10–100 %), Length (Narrow…Wide, Short…Tall
  when vertical), Bar height (Short…Tall), Visible, Orientation, Ready row,
  and the buttons Reset position and Advanced Combat Timeline Settings (the
  spell window, as the Cooldown Manager's "Advanced Cooldown Settings"), with a line pointing to
  `/actiontimeline options`. It closes
  when the timeline is deselected (Blizzard selecting a system deselects it),
  with its close button, or when Edit Mode closes.

### Motion trail

- Removed with Detailed (ADR-0007). It drew `combattimeline-line-icontrail`
  (Flat: a `WHITE8X8` streak) behind each lane's next predicted mark over
  its last 1.5 s; the flash (Urgency) is the bar's cue for the same moment.

## Open from the Blizzard review (2026-10-12)

Built and checked in game (2026-10-12): moving marks unsnapped, line
breaks, withdrawn predictions fading, green channels, the opacity slider.
Built, in-game check pending: the highlight moment (Urgency), predictions
fading in (Mark motion). (The line breaks and the line shadow went with
Detailed and Single lane, ADR-0007.) Still open - each described in its
section, none decided:

| Item | Section | Cost |
|---|---|---|
| Still lines snapped again | Pixel grid | small, untried |
| Squeezed far future | Time axis | large, a new ADR |

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
