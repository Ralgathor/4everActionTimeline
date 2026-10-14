# GLOSSARY.md — 4everActionTimeline (the ubiquitous language)

The planned action-timeline addon: a live timeline of what you did and what
is about to happen, laid out around a now line. This glossary is canonical
for the 4everActionTimeline repo; the spec and research live in `docs/`.

Shared swing and secrecy vocabulary (hand, anchor, expiry, parked, cast
reset, parry haste; secret, plain, restriction flip) is canonical in
4everSwingTimer's glossary and used unchanged here:
<https://github.com/Ralgathor/4everSwingTimer/blob/master/GLOSSARY.md>.

## Timeline

- **lane** — the marks of one subject: a hand, the GCD, the player's
  casts, a tracked spell, or a tracked spell's engine-drawn overlay. Every
  subject shares one track, the **bar** (except engine-drawn lanes, which
  keep thin rows of their own under it), but each stays a lane in the code
  and the docs. _Avoid_: row (the **ready stack** is not a lane).
- **mark** — a positioned glyph on a lane. A **happened mark** records an
  event that occurred; a **predicted mark** places an event expected to
  occur. A hand lane's marks are swing diamonds on the bar's edges (a
  queued ability shows its icon; ranged, the Auto Shot cast); spell lanes'
  marks render the spell's icon. The marks are the
  lane's identity — no static lane-start glyphs. Saturation follows
  **source-certainty saturation**: full color when the mark's source is
  engine-verified fact-grade (a happened event, the library's next-landing
  expiry, a plain live cast-time read, the sink's true remaining time),
  desaturated when the source is extrapolation (deeper cadence-chain marks,
  calibration-sourced predictions).
- **ready mark** — the mark a tracked spell shows while ready: off cooldown
  and usable (resource and reactive conditions met) where the game reports
  usability readably in combat, off cooldown alone where it does not. The
  spell's icon, plain full color with no outline, filling the spell's
  place in the **ready stack** (a long cooldown shows none) — vivid because it is ready now, matching the game's own
  gray-while-on-cooldown icon language. Idle lanes do not collapse; they
  show the ready mark. The engine-drawn sink arrives here naturally when
  the secret remaining time hits zero, which is why the sink needs no
  hide-on-complete.
- **unusable mark** — the mark a tracked spell shows while off cooldown but
  not usable (resource short, a reactive condition unmet, or the wrong
  druid form or warrior stance): the spell's icon in the ready stack,
  tinted
  the way the game tints an unusable action button (blue when
  resource-short, grey otherwise). Exists only where the condition is
  readable in combat.
- **unknown-cooldown mark** — the mark a tracked spell shows while it is
  known to be cooling but the timeline does not know until when (never
  calibrated, or reloaded mid-cooldown in combat): the spell's icon in its
  the ready stack, desaturated, no outline. Held until a plain read settles it or
  the spell's next completed cast proves it was ready.
- **parked mark** — a hand lane's mark while its hand is parked: a dim,
  desaturated diamond on the now line. _Avoid_: ready mark (that
  is the spell lanes' term).
- **delayed-start cooldown** — a cooldown that begins when the spell's
  effect breaks or is consumed, not when it is cast (Stealth, Nature's
  Swiftness). Its spell lane shows happened marks only — no predicted mark.
- **linked cooldown** — two or more spells that share one cooldown (the
  shaman shocks, hunter traps): casting one starts the cooldown on all.
- **cooldown reset** — a spell whose cast ends other spells' cooldowns
  (Preparation, Cold Snap); the reset spells return to ready.
- **predictor** — a rule that converts a readable anchor (a cast event, or
  the library's swing expiry) plus a known duration into predicted marks. Deterministic arithmetic; never tentative,
  unlike the library's candidate.
- **calibration** — reading a plain value out of combat (cooldown, duration, cast offset)
  and caching it per spell ID for in-combat inference; driven by the lane set.
  A cached value is **stale** after a talent change, or when combat shows
  it wrong (the spell cast before its predicted ready, or its mark stuck
  overdue): it still predicts, but is flagged for a re-read.
- **engine-drawn** — a mark whose position Lua cannot compute because the
  value is secret; the layout engine places it via a widget fed the secret
  (the StatusBar sink). Display-only, linear scale, leaf frame, Lua-blind
  geometry. Its icon renders full color — engine truth, like any
  fact-grade source. A spell with an engine-drawn lane shows no
  calibrated predicted mark on its own lane — the engine-drawn icon is
  that spell's only future mark.
- **lane set** — the user-chosen list of spells the timeline tracks and
  calibrates. _Avoid_: watch list (that is SwingTestLog's aura list).
- **cadence chain** — a swing lane's predicted marks beyond the next landing:
  equal-interval desaturated marks derived from the latest anchor's expiry
  and speed, one mark deep,
  re-derived at every anchor. Plain
  payload arithmetic only — the library stays the sole source of swing
  state; marks beyond the first are visibly forecast and are corrected at
  each re-anchor.
- **reposition pop** — the transient effect on a predicted mark when it
  repositions (UPDATE or CLIPPED): teal for a shortened landing (parry or
  dynamic haste), amber for the ranged movement retry, red for a cast reset
  — the bar addon's effect colors, imported. The mark jumps; it never
  glides. No ghost mark stays behind and no accent persists on the
  happened mark: the abandoned prediction never happened.
- **correction streak** — the brief fading streak from a predicted mark's
  old position to its new one when it jumps (or from an early happened
  mark back to where the prediction stood): shows how far the prediction
  moved. Transient, never a mark.
- **early landing** — a swing that lands before its predicted instant
  because haste changed mid-swing and Forever does not rescale it.
- **overdue** — a predicted mark whose instant has reached the now line
  before its event is confirmed; it pins at the now line ("due now"). A
  next-landing mark holds until the swing lands or the hand parks; a
  cooldown mark holds until the spell reads ready (only where that read is
  plain in combat).
- **held** — a ranged hand's state while the engine keeps retrying a shot
  cancelled by movement; its predicted mark wears an amber border.
- **delay span** — an amber window bar on the ranged lane from the first
  retry of a held chain to the shot that fires: the time lost to movement.
- **clip mark** — a small red tick on a hand lane at the instant a swing
  was reset (by a cast or a weapon swap): a happened mark recording lost
  swing time. _Avoid_: interrupt mark (casts are interrupted; swings are
  clipped).
- **outcome-agnostic** — happened marks (swing and cast) carry no outcome
  annotation (hit, crit, miss, dodge, parry; landed, avoided). Swing
  outcomes exist only in the combat log, which Forever refuses for the
  whole session; a cast mark means "cast completed", never "landed". The
  mark structure keeps an unrendered outcome slot should an outcome API
  ever ship, and v1 draws nothing there.
- **now-line icon** — a lane's identity icon parked at the now line instead
  of a static lane-start glyph, riding the current instant: the in-flight
  cast's spell icon on the cast lane (absent when nothing is being cast),
  rendered full color — the in-flight cast is present tense, a fact in
  progress. The lane's identity is what is happening now, not a fixed
  label.
- **window bar** — a span glyph covering an event's full window (start to
  end) rather than a point in time: the GCD lane's light-blue GCD windows.
  The elapsed span renders full color (the triggering cast and the passage
  of time are facts); the unelapsed span renders desaturated (its end is
  inferred). Nothing renders when idle, and windows never chain into the
  future.
- **now line** — the dividing instant of the timeline; one side of it is
  past, the other future. Which side is which, and whether the line runs
  vertically or horizontally, follows the **orientation**.
- **orientation** — the timeline's axis and direction: horizontal (past
  left, future right), horizontal flipped, or vertical (and its flip).
  _Avoid_: direction (ambiguous with a mark's travel).
- **skin** — the timeline's art family: **Native** (Blizzard's cast bar
  and swing timer art) or **Flat** (a plain dark bar, thin borders). The same term and choice as 4everSwingTimer's skins.
- **past window / future window** — the visible time span either side of the
  now line (defaults 1.5 s / 10 s; user-configurable).
- **edge clamp** — a predicted mark whose event time lies beyond the future
  window renders pinned at the far edge instead of off-window: the sink's
  engine-drawn icon and readable predicted marks alike, so every distant
  return reads as "far away". A pinned readable mark also shows a
  chevron; a pinned engine-drawn icon cannot.
- **bar** — the one track every lane but the engine-drawn lanes shares: a
  framed bar read like a cast bar (the **Bar track** layout, ADR-0006, the
  only one since ADR-0007). _Avoid_: layout (there is one), Single lane and
  Detailed (removed layouts).
- **card stack** — how the bar shows icons closer than an icon's width:
  the front one (a fact first, else the soonest) at its place, the others
  peeking out behind it, three at most, then "+n".
- **ready stack** — the ready, unusable and unknown-cooldown marks parked
  on the bar at the now line, three at most, each behind the
  front peeking out toward the future along the bar (ADR-0009). _Avoid_: ready row (the fixed
  slots under the bar it replaced).
- **long cooldown** — a tracked spell kept out of the ready stack: a cooldown
  of 30 s or more by default, or tagged in class data or flagged in the spell
  window.
  _Avoid_: major cooldown (implies a judgement about the spell's value).

## Settings

- **spell window** — `/actiontimeline config`: every class spell as an icon
  in one of four **sections**, as the Cooldown Manager's settings window
  does: **Timeline**, **Long cooldowns**, **Engine lanes** (the sink
  spells) and **Not displayed**. A section is derived from a spell's flags
  at the edited layer; dropping an icon on a section writes them. _Avoid_:
  "lane window", "lane list".
- **Edit Mode panel** — the settings panel that opens beside the timeline
  when it is clicked in Edit Mode: scale, opacity, length, bar height,
  visibility, orientation, ready spells (ADR-0008, ADR-0009).
- **shipped defaults / class layer / player layer** — the three settings
  layers, lowest to highest. Each stores only what was changed at its level;
  an unset key falls through to the layer below (ADR-0002). _Avoid_:
  "profile".
- **starter set** — the curated per-class spells the shipped defaults enable.

## Project

- **the timeline** — 4everActionTimeline (planned): separate addon, second
  consumer of the library; a live action timeline of lanes around a now line.
- **the library** — LibClassicSwingTimerAPI: owns all swing state and math
  (defined in the 4everSwingTimer glossary).
