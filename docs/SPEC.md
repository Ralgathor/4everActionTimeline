# 4everActionTimeline — Specification

Synthesized 2026-10-05 from the design-grilling session (maintained
round-by-round; current through the 2026-10-06 gap-review round: ready
semantics, linked and delayed-start cooldowns, calibration mechanics,
three-layer storage, visibility, secret guard); founding research in
`Forever Combat Timeline.md`
(same folder). Shared language: this repo's root `GLOSSARY.md` plus the
swing/secrecy vocabulary canonical in 4everSwingTimer's glossary
(<https://github.com/Ralgathor/4everSwingTimer/blob/master/GLOSSARY.md>).
ADR-0001 (`docs/adr/`) binds the cooldown
decision; ADR-0002 binds the three-layer settings inheritance; ADR-0003
records the separate-addon split; ADR-0004 records the spellbook-driven
lane set over the Cooldown Manager.

Status: v1 draft, decisions applied. Nothing built. The project folder was
split out of 4everSwingTimer on 2026-10-06 (docs only). The probe session
ran on 2026-10-06 (build 70235; verdicts in `PROBE_SESSION.md`, applied
below, gate cleared with the decisions recorded there); remote and
publishing wait on the first release.

## Problem Statement

On WoW: Forever, a player can see individual swing bars, but nothing shows
the whole picture: what just happened and what is about to happen, laid out
in time. The flavor's secrecy system hides true cooldown numbers in combat,
the combat log is refused outright, and aura data is hidden mid-fight, so no
existing addon can lay out a live timeline the way simulators or retail
addons do. The player is left guessing when a swing lands, when a spell
comes back, and where the GCD sits relative to both.

## Solution

4everActionTimeline: a separate addon (a second consumer of
LibClassicSwingTimerAPI) that draws a live timeline of lanes around a now
line. Hands and ranged on top, then the GCD, then the player's casts, then
one lane per tracked spell. Happened marks render at full color; predicted
marks render desaturated; an idle spell parks as a ready mark on the now
line; the GCD lane renders window bars. Cooldown predictions come from
calibration caches learned out of
combat; an opt-in engine-drawn lane shows exact remaining cooldowns that Lua
itself is never allowed to read. The lane set is discovered from the
spellbook with curated per-class starter defaults, configured in its own
settings window, shared by class with per-player overrides, and the frame is
anchored in Blizzard's Edit Mode. Everything the addon shows is honest about
what Forever permits: no invented proc buffs, no combat-log rows, no fake
numbers.

## User Stories

1. As a melee player, I want my main-hand, off-hand and ranged swings shown
   as lanes around a now line, so that I can see what already landed and when
   the next swing lands.
2. As a dual-wield Fury warrior, I want both hand lanes plus the GCD visible
   at once, so that I can time ability presses against both swings.
3. As a rogue, I want the GCD lane to use the energy-user default, so that
   the predicted GCD marks match what I actually experience.
4. As a player, I want my recent casts drawn on a cast lane in the past
   window, so that I can see what I did and in what order.
5. As a player, I want a predicted mark at cast time plus each tracked
   spell's cooldown, so that I can see when a spell becomes ready again.
6. As a player, I want predicted marks desaturated and happened marks at
   full color, so that I can tell fact from forecast at a glance.
7. As a player, I want the windows either side of the now line configurable
   (defaults 5 s past / 5 s future), so that the timeline fits my
   reaction-time preference.
8. As a player, I want an idle tracked spell to park as a ready mark on the
   now line, so that every configured lane always has something to show and
   the frame height never jumps.
9. As a player, I want happened marks to scroll off the past edge and
   vanish, so that the past window stays uncluttered.
10. As a player who wants exact numbers, I want an opt-in engine-drawn lane
    per spell, so that I can see the true remaining cooldown even though Lua
    cannot read it.
11. As a player using the engine-drawn lane, I want its icon to clamp at the
    far edge while its cooldown exceeds the future window, so that I know it
    is still long.
12. As a player using the engine-drawn lane, I want its icon to come to rest
    at the now line when the cooldown ends, so that the engine's
    no-hide-on-complete limit never leaves a stray icon.
13. As a player using the engine-drawn lane, I want its limits documented in
    the config UI (display-only, linear scale), so that I do not mistake
    engine behavior for a bug.
14. As a player, I want the lane list discovered from my spellbook, so that
    every known class spell is available to track without typing or capture
    flows.
15. As a new player, I want a curated per-class starter set on by default, so
    that my first login shows a sensible rotation instead of an empty
    timeline or a wall of lanes.
16. As a player who trains a new rank, I want the lane to keep tracking the
    spell automatically, so that rank churn never breaks my lanes.
17. As a power user, I want a settings window with per-spell enable, sink
    opt-in and manual cooldown override, so that I can tune each lane's
    behavior in one place.
18. As a power user, I want to drag-reorder my spell lanes in the settings
    window, so that the lanes I watch hardest sit where my eyes go.
19. As an alt of the same class, I want the lane set shared at class level,
    so that my class-wide rotation is configured once.
20. As a player, I want per-player overrides that fall through to the class
    layer when unset, so that one character can differ without freezing a
    private copy of the class set.
21. As a player, I want the settings window to show effective state with an
    overridden indicator, so that I can tell class defaults from this
    character's overrides.
22. As a player, I want uncalibrated spells to show happened marks plus an
    unknown-cooldown mark while cooling, so that the timeline never invents
    a cooldown it has not learned and never claims the spell is ready.
23. As a player, I want calibration to happen automatically after any
    out-of-combat cast and when combat ends, so that the spells I use are
    learned without any action from me.
24. As a power user, I want a calibration report command (calibrated,
    stale, delayed-start, uncalibrated), so that I know which predictions
    I can trust before the first fight.
25. As a power user, I want a per-spell manual cooldown override, so that
    spells I cannot safely trigger out of combat still get predicted marks.
26. As a player, I want a GCD override choice (by power type, 1.5 s, 1.0 s,
    custom) with a custom slider, so that the GCD lane matches whatever the
    beta's ruleset actually does.
27. As a player, I want global settings (windows, lane height, spacing,
    scale) in the game's Settings panel, so that they sit where every other
    addon's settings live.
28. As a player, I want to place the frame in Blizzard's Edit Mode, so that
    placement works the same as the rest of my UI.
29. As a player, I want a test command that seeds fake events on a running
    clock, so that I can verify layout and encoding without a fight.
30. As a player in a dungeon, I want the same lanes to keep working in
    restricted content, so that the timeline does not go blank when it
    matters most.
31. As a player on a boss encounter, I want cast spell IDs to stay readable,
    so that the past side keys on real spells (probe-listed verification).
32. As a player, I want the GCD lane separate from cooldown lanes, so that
    the GCD never drags spell icons back and forth.
33. As a player without the library installed, I want the addon to load
    inert with a chat notice, so that I get an explanation, not an error.
34. As a player, I want the addon to stay out of combat decisions entirely
    (no "press this next" output), so that it stays on the right side of the
    restriction policy.
35. As a dual wielder, I want my hand lanes to chain predicted landings at
    the current swing speed across the future window, so that I can see the
    whole cadence, not just the next swing.
36. As a player, I want a repositioned predicted landing to pop briefly
    (teal when it shortens, amber when ranged delays it, red when a cast
    reset restarts it), so that I notice the correction without a ghost mark
    cluttering the lane.
37. As a player with a queued next-melee ability, I want the main-hand
    predicted mark to show that ability's icon, so that I can see what the
    next landing actually is.
38. As a player, I want every swing mark on my hand lanes to render my
    equipped weapon's icon — happened, predicted and parked alike — so that
    the lane identifies itself by its marks, not a label.
39. As a player, I want the README to explain why my happened swings carry
    no hit, crit, miss, dodge or parry annotation, so that I understand the
    timeline's honesty limits instead of reporting them as bugs.
40. As a caster, I want my in-flight cast's spell icon riding the now line,
    so that I always know what I am doing at this instant.
41. As a caster, I want a desaturated predicted mark at my cast's expected
    completion, so that I can see when it finishes even mid-fight.
42. As a caster whose cast is stopped, failed or interrupted, I want a red
    happened mark at the stop instant while the predicted mark pops red and
    vanishes, so that the attempt is on the record without a ghost.
43. As a channeled caster, I want my channel drawn like a cast — now-line
    icon while channeling, predicted end mark, happened mark at its end —
    so that channels read like every other action on the timeline.
44. As a player, I want every cast I make to appear on the cast lane,
    filtered by nothing, so that the lane is an honest record of my actual
    sequence.
45. As a player, I want my GCD lane to draw a light-blue window bar for the
    current GCD plus my recent past GCD windows, so that I can see when the
    GCD ends and the rhythm of my casts at once.
46. As a melee player, I want my next-landing mark rendered at full color
    while the deeper cadence chain stays desaturated, so that the one
    swing prediction I can trust reads as fact and the extrapolation reads
    as forecast.
47. As a caster, I want my in-flight cast's completion mark rendered at
    full color when the engine's own read feeds it and desaturated when a
    learned estimate does, so that the mark's vividness tells me whether
    it is truth or forecast.
48. As a player who relogs mid-session, I want my cooldown predictions
    rebuilt from plain reads when I land out of combat, so that the
    timeline recovers its future side instead of showing a ready mark for
    a spell that is still cooling.
49. As a player with long cooldowns, I want their predicted marks pinned
    at the far edge of the future window until their moment approaches, so
    that "far away" reads consistently on every lane.
50. As a warrior, I want Overpower to show an unusable mark until a dodge
    enables it, so that a ready mark always means I can press it now
    (where usability reads plain in combat).
51. As a shaman, I want casting Earth Shock to predict Frost Shock and
    Flame Shock too, so that linked cooldowns never show a false ready
    mark.
52. As a rogue, I want Stealth's lane to skip the predicted mark, so that a
    cooldown that starts when Stealth breaks is never predicted from the
    cast.
53. As a caster taking hits, I want my in-flight cast's completion mark to
    move with pushback and pop amber, so that the mark keeps telling the
    truth mid-cast.
54. As a player, I want the frame shown in combat by default, with Always
    and Active choices, so that it stays out of the way between fights.
55. As a player, I want a frame width setting, so that I choose how many
    pixels each second gets.
56. As a player in an encounter that turns a payload secret, I want the
    addon to drop those events and tell me once after combat, so that it
    never throws an error mid-fight.
57. As a rogue, I want Preparation to return my reset spells' lanes to
    their ready marks, so that a reset never leaves a stale prediction.

## Implementation Decisions

- **Separate addon, separate repo** (created after the probe session),
  embedding LibClassicSwingTimerAPI via the same externals trio; the timeline
  holds no swing math, all swing state comes from the library's events and
  state reads, exactly like 4everSwingTimer.
- **v1 lanes**: hands (main-hand, off-hand, ranged), GCD, player casts, one
  lane per tracked spell. Fixed order: hands/ranged, then GCD, then the cast
  lane, then spell lanes in lane-set order, then sink lanes grouped at the
  bottom (in the same lane-set order).
- **Layouts** (ADR-0005): that lane order is the **Detailed** layout.
  **Single lane** (the default) maps the same lanes onto one track, look
  in `VISUAL.md` (Layouts):
  - hands: main hand and ranged on the lane-start side of the track, off
    hand on the other; the next landing plus a 1-deep cadence chain;
  - GCD: a band behind the track;
  - cast lane: a bar on the track (instants: an icon at the moment of use);
  - spell lanes: predicted returns on the track; ready spells fill fixed
    slots of the **ready row** in lane-set order; a **long cooldown** gets
    no slot (a ring on the now line marks its return);
  - sink lanes: one thin row each after the ready row.
  A spell is a long cooldown when its cooldown is 30 s or more, unless
  the class data or the lane window says otherwise; a spell whose cooldown
  is not known yet counts as a rotation ability until it is.
- **Event store**: a ring buffer of `{time, kind, spellID, lane}` entries fed
  by library swing callbacks and the player's own spellcast events. Entries
  expire past the past window plus a margin; a hard entry cap backstops
  bursts; nothing renders from the buffer once beyond the past edge.
- **Predictors**: one per lane kind — swing (a **cadence chain** from the
  latest anchor: the next landing, then equal-interval desaturated marks at
  the anchor's speed filling the future window, re-derived at every anchor),
  cast (START plus the live-read or calibrated cast time), cooldown
  (`UNIT_SPELLCAST_SUCCEEDED` time plus calibrated duration, minus the
  calibrated **cast offset** — the cooldown starts on completion, not
  START; the spell lane's happened mark also sits at SUCCEEDED). The cast
  offset exists because SUCCEEDED arrives a server round trip after the
  cooldown actually starts (~0.2 s for instants, probe session G1);
  calibration measures it (cooldown `startTime` minus the SUCCEEDED time)
  on each out-of-combat read and caches a per-player running value, so
  the predicted ready mark lands on the real instant. GCD (cast time plus
  power-type default — 1.5 s, 1.0 s for energy users, both measured
  in the probe session — user-overridable). Predictors are deterministic arithmetic on plain
  payload values, never tentative; the library stays the sole source of
  swing state.
- **Cooldown marks are inferred from calibration; the engine-drawn sink is
  an opt-in overlay, never the foundation** (ADR-0001). Calibration
  sources: an automatic read on `SPELL_UPDATE_COOLDOWN` after any
  out-of-combat cast, a read pass when combat ends (spells just used are
  on cooldown and plain — run 0.2, 0.5 and 1.0 s after the event, since
  values turn plain a moment after it), an **in-combat measurement**
  (M4 decision, 2026-10-06: spells needing a target can only be cast in
  combat, and short ones end before combat does — the SUCCEEDED to the
  instant `isActive`, plain in combat, turns false is the cooldown, to
  ±0.05 s; both edges arrive a server round trip after the engine's
  instants, so no offset is applied (Consecration: 8.2 s with the offset,
  8.0 s without, plain read 8.0 s); ignored when no longer than the GCD or when a GCD
  window ended at the same moment; it fills a gap or replaces a stale
  value, never a current plain read, and the next plain read replaces
  it), and per-spell manual overrides. The slash
  command is a **report** (calibrated, stale, delayed-start,
  uncalibrated), not a reader — out of combat with nothing cooling there
  is nothing to read. A read whose duration is no longer than the GCD is
  rejected unless the spell is known to have so short a cooldown. A
  talent change — a change of the talent ranks, not merely the event,
  which also fires with nothing changed — marks the whole cache **stale** (still predicting,
  flagged for re-read) rather than wiping it; entries for spell IDs absent
  from the current spellbook scan are pruned. In-combat evidence also
  marks a single entry stale: a cast before the predicted ready instant
  (value too long — or an untabled reset), or a cooldown mark stuck
  overdue (value too short); the combat-end read corrects it, and the
  cast-to-cast gap is never written. No login spellbook cooldown
  scan — a ready spell reads zero.
- **Cooldown arrival** (probe 3: `isActive` is plain in combat, build
  70235, boss pull included): a predicted cooldown mark reaching the now
  line pins there **overdue** (as a swing does) until `isActive` reads
  false, and only then becomes the ready mark — a verified ready.
  `isActive` is also true while the GCD runs, so a mark arriving inside a
  GCD releases when the GCD ends — the spell is not pressable before
  that either. (Had `isActive` been secret, the mark would have become
  the ready mark on arrival, trusting calibration.)
- **Linked cooldowns** (shared cooldowns: shaman shocks, hunter traps) are
  learned during calibration — after an out-of-combat cast, every lane
  spell that turned active with the same start and duration is linked and
  the link cached — over a small curated seed covering the first fight.
  GCD-length reads never link: right after any cast every spell reads
  active with the cast's start and the GCD duration, and the real
  cooldown replaces it about 0.2 s later (probe session), so the link
  test runs on the settled read. A cast predicts every linked lane.
- **Cooldown resets** (Preparation, Cold Snap): a curated table maps each
  reset spell to the spells it resets; casting it switches those lanes to
  their ready mark (or unusable mark). The curated data — starter set,
  linked-cooldown seed, delayed-start seed, reset table, form and stance
  requirements, long-cooldown tags overriding the 30 s threshold — is one data
  file per class, all nine classes in v1 (starter sets of 3–5 rotation
  spells; seeds and resets only where known to apply).
- **Delayed-start cooldowns** (Stealth, Nature's Swiftness, Presence of
  Mind, Cold Blood — the cooldown starts when the effect breaks or is
  consumed) are detected during calibration (right after the cast the
  cooldown reads `isEnabled == false` while the effect is active — Stealth,
  probe session) and flagged; their lanes show
  happened marks only, never a predicted mark.
- **Engine-drawn lane constraints** (accepted, from ADR-0001 and the smoke
  tests): display-only, linear scale, the icon is a leaf frame, no
  Lua-readable geometry, no hide-on-complete. The no-hide limit is benign by
  design: the sink's icon comes to rest at the now line when the remaining
  time hits zero, exactly where a ready mark parks. The sink is its own lane
  per opted-in spell — one mark per lane per source; Lua-blind geometry
  never shares a lane with readable marks. The sink's icon renders
  full color — engine truth, like any fact-grade source. GCD reads are
  excluded from the sink feed so the GCD stays on its own lane. While a
  spell's sink is on, its spell lane drops the calibrated predicted mark
  (no guess racing the truth) and keeps happened marks and its now-line
  mark (ready, unusable, unknown-cooldown). Sink lanes group at the bottom
  of the frame. At ready, the spell lane's ready mark and the sink icon
  both sit on the now line in their separate rows — accepted: the engine
  cannot hide the sink icon in combat, and the pair reads as the engine
  confirming ready.
- From the build 70205 smoke test, the sink pattern that carries the
  decision (trimmed to the decision-rich part — a transparent StatusBar
  spanning the future window, icon anchored to the fill's right edge, secret
  fed per frame):

  ```lua
  local bar = CreateFrame("StatusBar", nil, lane)
  bar:SetPoint("TOPLEFT", lane, "TOPLEFT", nowX, 0)
  bar:SetSize(window * pxPerSec, rowHeight)
  bar:SetMinMaxValues(0, window)
  local icon = bar:CreateTexture(nil, "OVERLAY")
  icon:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
  -- per frame; ignoreGCD = true so the GCD keeps its own lane
  local dur = C_Spell.GetSpellCooldownDuration(spellID, true)
  bar:SetValue(dur:GetRemainingDuration())
  ```
- **Mark encoding**: desaturation alone — predicted desaturated, happened
  full color. No dashed outlines (they do not survive arbitrary icon
  textures). An idle tracked spell shows a **ready mark** — the spell's
  icon, plain full color, no outline (the Cooldown Manager's own ready
  look, matching the game's gray-while-on-cooldown icon language; blue is
  reserved for Blizzard's not-enough-mana tint) — parked on the now line.
  **Ready** means off cooldown and usable (`C_Spell.IsSpellUsable`:
  resource and reactive conditions, e.g. Overpower, Execute) — probe 12
  found both returns plain in combat (build 70235, boss pull included;
  the resource case verified, reactive conditions not yet exercised).
  Two further now-line marks complete the idle family: the
  **unusable mark** (off cooldown but not usable — icon tinted with the
  action bar's own values, blue when resource-short and grey otherwise —
  see `VISUAL.md`; the **wrong form or stance** case: a spell whose
  curated data requires another druid form or warrior stance shows the
  grey unusable mark from `GetShapeshiftFormID`, plain in combat for
  warrior stances — probe 15; druid forms unverified) and the
  **unknown-cooldown mark** (known to be cooling, end
  unknown — uncalibrated spell cast in combat, or in-combat reload: icon
  desaturated, no outline, held until a plain read settles it or the
  spell's next SUCCEEDED proves it was ready — that new cast starts a
  fresh unknown-cooldown mark unless calibration has a value by then; the
  gap between two in-combat casts is never cached, being only an upper
  bound). Idle
  lanes never collapse, so frame height is stable and no hide-idle toggle
  exists. Hand-lane marks render the equipped weapon's icon; spell lanes
  render the spell's icon: the marks are the lane identity, with no static
  lane-start glyphs. Saturation follows **source-certainty saturation**: full
  color when the mark's source is engine-verified fact-grade (a happened
  event, the library's next-landing expiry, a plain live cast-time read,
  the sink's true remaining time), desaturated when the source is
  extrapolation (deeper cadence-chain marks, calibration-sourced
  predictions). The whole encoding family — happened, predicted, ready,
  unusable, unknown-cooldown, parked, gradients, window-bar split, sink —
  is confirmed by-eye in test mode before it ships.
- **Renderer**: one OnUpdate pass; pooled marks and pooled window bars sized
  to the visible span; readable lanes positioned in Lua from plain times;
  predicted marks whose event time lies beyond the future window clamp at
  the far edge (the **edge clamp**, matching the sink; readable pinned
  marks add a chevron — `VISUAL.md`); windows 5 s / 5 s by default,
  configurable; linear scale only in v1.
- **Performance budget**: per frame, only readable marks' time-axis
  positions, transient effects (pops, streaks, trails, shake) and sink
  feeds update; layout, tints and the set of marks recompute on events
  only. Sink lanes are capped at **6** (the per-frame
  `GetSpellCooldownDuration` read is the one cost that cannot be
  trimmed). Measured with `debugprofilestop` around the renderer
  (`/actiontimeline perf`, which reports three frame kinds apart). First
  measurement (M1, build 70235, test mode, 7 lanes, ~14 widgets): plain
  frames 0.10–0.11 ms average, 0.23–0.31 ms worst; rebuild frames (one or
  more lanes re-collected) 0.19–0.23 ms average, 0.8–0.9 ms worst; the
  layout frame on first show (lane sizing, widget creation) 2.7 ms, once.
  Budget, for 15 lanes: plain frames under **0.3 ms** average, rebuild
  frames under **1 ms** worst; the one-off layout frame is exempt. Each
  lane owns its widgets and rebuilds only when it changed, so rebuild cost
  scales with what changed, not with the lane count. Re-measured at the
  encoding check.
- **Session re-seed and hidden-frame convergence**: a login/reload re-seed
  pass rebuilds predicted marks from plain cooldown reads when loading out
  of combat; loading in combat skips (values secret) and unseeded spells
  show no future marks — happened marks plus an unknown-cooldown mark
  where the spell is known to be cooling, the honest fallback — with
  the sink lane the only in-combat truth after a reload. Event capture
  never depends on frame visibility; expiry sweep and buffer pruning run
  on a low-frequency ticker; the renderer fully relayouts on show (the
  repo's proven hidden-frame pattern — a hidden frame receives no
  OnUpdate).
- **Hand lanes** (main-hand, off-hand, ranged): marks only — happened marks
  at past landings, a predicted mark at the next landing, a **parked mark**
  (dimmed weapon icon) at the now line when parked; no period bar.
  **Hand-lane effects** (effects round, 2026-10-06):
  - Corrections **jump** the predicted mark to its new instant — never a
    glide, which would show wrong instants — with a reposition pop (teal
    shortened landing, amber ranged retry, red cast reset — the bar
    addon's effect colors) and a **correction streak** from the old to the
    new position, fading within ~0.3 s: the size of the correction made
    visible, with no ghost (the abandoned prediction never happened).
  - **Parry haste** (the melee mid-swing UPDATE) and **ranged dynamic
    haste** (a shortened ranged UPDATE): teal jump.
  - **Melee haste** has no mid-swing rescale on Forever; it surfaces as an
    **early landing** (in-flight STOP, then START at the same speed within
    the stop grace): the happened mark appears early with a teal pop and a
    streak back to where the prediction stood. Nothing persists on it.
  - An **overdue** next-landing mark (the swing slowed, e.g. a haste buff
    dropped, and no rescale exists) pins at the now line — "due now" —
    until the swing lands or the stale sweep parks the hand; a predicted
    mark never scrolls into the past. A late landing gets no pop: nothing
    was corrected. While overdue, the cadence chain derives from the now
    line (now + speed, now + 2 × speed, …) — the earliest the late swing
    can land — and re-anchors at the landing.
  - **Ranged retry** (movement: a ranged UPDATE 0.3–0.7 s ahead): the
    predicted mark jumps out at each retry (the honest sawtooth), wears an
    **amber border** while the retry chain lasts (the **held** state), and
    a **delay span** — an amber window bar from the first retry to the shot
    that fires — records the time lost and scrolls into the past. One
    amber pop per chain (on the first retry); later jumps get the streak
    only.
  - **Cast reset** (START mid-flight, or CLIPPED): red pop, across-lane
    shake (`ShakeStrengthUI`), streak, and a **clip mark** — a small red
    tick at the reset instant, a happened mark recording the lost swing
    time. A **weapon swap** mid-swing gets the same treatment. A swing
    **cut short** by choice or death (STOP with nothing following) just
    parks: no red, nothing went wrong.
  - **Shapeshifting** neither resets nor changes the swing speed on
    Forever (play-observed; probe 15 confirms), so it needs no
    classification rule and can never read as a weapon swap.
  - Classification: the library is asked to report a **reason** on its
    swing events (parry, retry, rescale, reset, swap) — a library API ask.
    Until it ships, the timeline copies 4everSwingTimer's event-signature
    rules with its exact thresholds (0.3–0.7 s retry window, 0.10 s stop
    grace, 0.2 s early-landing epsilon, 2 % speed match), marked for
    removal, so both addons classify the same event the same way.

  A paused hand freezes and
  dims its marks. A queued next-melee ability swaps the main-hand predicted
  mark's icon to the queued spell (`IsCurrentSpell` is probe-verified plain),
  and the swing it lands on carries that icon into the past: an
  on-next-swing ability (Heroic Strike, Cleave) is one happened mark on the
  main-hand lane, never a cast-lane mark (probe 13, confirmed on build
  70235: SUCCEEDED fires at the swing, same timestamp as its
  `PLAYER_SWING` — and also when that swing is dodged, parried or
  missed, probe 2).
  Lane identity is the marks themselves: every swing mark renders the
  equipped weapon's icon — happened full color, predicted desaturated,
  parked dim — with no lane-start glyph, no text labels, and no delta
  indicator (the two lanes' predicted marks show the offset directly).
  While shapeshifted, swing marks render the form's icon (Cat Form, Bear
  Form) instead — the lane shows what is attacking; each happened mark
  keeps the icon it landed with, so the shift instant is visible.
  Presence is equipment-driven with per-hand toggles: no
  off-hand weapon, no off-hand lane; no ranged weapon, no ranged lane.
  Happened marks are **outcome-agnostic**: hit, crit, miss, dodge and parry
  of your own swings are combat-log-only and the log is refused for the
  whole session — nothing left to probe. (`UNIT_COMBAT` on the target does
  report DODGE, PARRY and MISS plainly, but without a source — another
  attacker's miss reads the same — so it cannot annotate the player's own
  swings honestly.) The happened-mark structure keeps
  an unrendered outcome slot should an outcome API ever ship; v1 draws
  nothing there, and no early-landing accent persists (the pop and
  streak are transient). Clip marks and delay spans are not outcomes —
  they record swing timing the library reports. The README documents the
  limit.
- **Cast lane**: happened marks are cast completions (instants included) —
  full color, the spell's icon, meaning "cast completed", never "landed"
  (outcome-agnostic like swing marks). In-flight casts and channels draw a
  predicted mark at the expected end whose saturation follows its source:
  full color when fed by the plain live read (engine fact-grade),
  desaturated when fed by calibration (drifts under haste) — probe 11
  found the live read plain in combat and in a boss pull, so in-flight
  completion marks render full color. The in-flight spell's icon rides the
  now line at full color — a **now-line icon**, present tense, a fact in
  progress: the lane's identity is what is happening now, with no static
  lane-start glyph and nothing shown when idle. Stopped, failed and
  interrupted casts leave a red happened mark at the stop instant while
  the predicted mark pops red and vanishes
  (no ghost — the red carries over from the bar addon's interrupt color).
  Only a cast that started (it had a START, so it was in flight or
  channeling) can fail this way: a `UNIT_SPELLCAST_FAILED` with no START
  is a refused press, not a cast, and leaves no mark (pressing Holy Light
  without mana fired 14 of them in 2.6 s — probe session G2).
  Channels have no interrupt signal (CHANNEL_STOP either way): a channel
  stopping more than ~0.2 s before its expected end gets the red mark; with
  no known expected end it always gets the normal happened mark (no
  unverifiable interrupt claim). Pushback (`UNIT_SPELLCAST_DELAYED`, and
  channel shortening) repositions the completion mark with an amber
  reposition pop when the live read is plain; a calibration-fed mark stays
  put and SUCCEEDED corrects it. Every player cast appears, including
  channels, mounts and hearthstone, except auto-repeat spells (Auto Shot,
  wand Shoot — the ranged lane already shows them) and on-next-swing
  abilities (the main-hand lane carries them); a "combat only" toggle is
  post-v1. The cast duration comes from the live read
  (`UnitCastingInfo` / `UnitChannelInfo` end time), plain in combat
  (probe 11); event-arithmetic calibration (`SUCCEEDED − START` out of
  combat) stays only as the fallback should a later build turn it secret.
  Pushback re-reads the end time on each `UNIT_SPELLCAST_DELAYED`
  (verified within 0.08 s of the actual completion). One cancel can fire
  `UNIT_SPELLCAST_INTERRUPTED` several times (four observed), so the stop
  is recorded once per cast. A channel's spell ID can differ from its
  SUCCEEDED ID (Cannibalize 20577 / 20578), so channel edges key on the
  channel-start ID.
- **GCD lane**: renders **window bars**, not point marks — a light-blue span
  per GCD window, from the triggering cast to the GCD's end (power-type
  default, user-overridable). A window bar's elapsed span renders full
  color (the cast and the passage of time are facts) and its unelapsed
  span desaturated (the end is inferred) — one rule, so past windows read
  full color and the active window splits at the now line; nothing renders
  when idle (the GCD parks no ready mark), and
  windows never chain into the future — one cast deep. The window draws on
  the GCD lane only in v1; EventHorizon-style per-spell-lane GCD shading is
  post-v1. The queue keeps its mark-swap treatment on the main-hand lane —
  no dedicated queue lane. **Which casts start a GCD** is read from the
  engine, never assumed (M3 decision, 2026-10-06): some spells are off the
  GCD (Sprint, Evasion, Stealth, Judgement — probe session), and a window
  for them would invent a fact. Right after a cast — at START for
  cast-time spells, at SUCCEEDED for instants — the lane reads `isActive`
  (plain in combat, probe 3) on a per-class **reference spell**: one with
  no cooldown of its own that is bound to the GCD (Battle Shout, Sinister
  Strike, Holy Light, …; the first known of a short curated list, folded
  into the class data in M4). Active opens a window; inactive (re-read
  once 0.1 s later) opens none; a cast inside a running window cannot
  start another. When a started cast stops, fails or is interrupted, the
  same read decides again: the engine clears an interrupted cast's GCD
  0.04–0.36 s after the interrupt (capture 2026-10-06, four movement
  interrupts: `isActive` false well before the 1.5 s end, while a
  completed cast kept its full 1.5 s), so the reference is polled every
  0.05 s while the window runs; a clear before its natural end cuts the
  window at the stop instant, otherwise it keeps its length. The same
  capture shows the engine's GCD starting ~0.2 s before the START event
  arrives — the cast offset again (M4 calibration can backdate windows).
- **Lane set discovery**: spellbook-driven, following the Blizzard
  tracker pattern as implemented on Forever by ForeverCDM — every known
  class spell is available as a toggle; no capture flows, no typed input. A
  curated per-class starter set ships enabled; everything else is off until
  toggled. Rank churn is invisible: the spellbook scan resolves the current
  rank each session, config shows spell names, marks and the calibration
  cache key on the resolved spell ID. Usable items (trinkets, potions) are
  not tracked in v1 — spell cooldowns only.
- **Settings surface split**: the client's Settings vertical layout supports
  checkbox, slider and dropdown only — it cannot hold a spell list. Globals
  (layout, windows and width per layout, ready row side, Single lane backdrop, scale, lane height, spacing, GCD override, lane-kind
  toggles, visibility, skin, orientation, lane background alpha, sink
  countdown —
  see `VISUAL.md`)
  live in the 12.x Settings category; the lane list (per-spell enable, sink
  opt-in, manual override, long cooldown, drag-reorder) lives in the addon's own settings
  window, opened from the slash command. Nothing dynamic registers in the
  Settings category.
- **Frame anchoring**: placed in Blizzard Edit Mode, following ForeverCDM's
  proven pattern on this client (probe 9 passed, build 70235) — which is
  **not** a registered Edit Mode system: the frame listens for
  `EventRegistry` `EditMode.Enter` / `EditMode.Exit`, becomes draggable
  (with a labelled handle) only while Edit Mode is open, snaps by hand
  against `EditModeManagerFrame.registeredSystemFrames` when Edit Mode's
  snap is on, and stores its own position (UIParent-centred) in the
  player layer. No custom unlock overlay, no lock checkbox, no taint from
  writing into Blizzard's layout tables. Edit Mode's own scale does not
  apply to such a frame, so **scale** is a Settings slider. A **width**
  slider sets the frame width, and the time scale follows from it (pixels
  per second = width ÷ (past window + future window)).
- **Visibility**: a Settings dropdown — **In combat** (default), **Always**,
  **Active** (shown while any mark is inside the visible window) — the bar
  addon's visibility pattern. Test mode forces the frame shown; event
  capture never depends on visibility.
- **Storage model** (ADR-0002): versioned saved variables (`schemaVersion`,
  migrate on load) resolved through three layers — **shipped defaults**
  (the code-side starter set, never written to saved variables), the
  **class layer** (shared lane-set changes) and the **player layer**
  (overrides, width/height/spacing, and the calibration cache). Each layer
  stores only what changed at its level; unset keys fall through to the
  layer below, so starter-set improvements reach every install that has
  not changed that spell, and class-set improvements keep reaching alts.
  Lane order is a list, not a key: a player-layer order replaces the class
  order whole; a spell enabled later at the class layer appends to the
  player's order and is flagged **new** in the settings window; "reset to
  class" deletes the player's order.
  The calibration cache (values, the cast offset, linked-cooldown links, delayed-start
  flags, stale flags) is a separate sub-table so wiping it can never touch
  the lane set.
- **Secret guard**: every payload value is checked for secrecy at
  ingestion (the event-store seam). A secret where plain was expected
  drops the event, counts the drop per event kind, and reports the counts
  once in chat at combat end with a suggestion to file a report — never an
  error, matching the inert-load convention.
- **GCD override control**: Settings dropdown (By power type / 1.5 s /
  1.0 s / Custom) with an always-present custom-value slider (0.5–2.0 s,
  step 0.1) activated by the Custom choice.
- **Identity**: saved-variable global `FourEverActionTimelineDB`, namespace
  `FourEverActionTimeline`, slash `/actiontimeline` plus a short alias;
  platform-name and slash uniqueness checked before publish.
- **Inert load** when the library is missing or its MINOR is too low: chat
  notice, never an error (repo convention).
- **Test mode**: a slash command that seeds fake events (swings, casts,
  cooldown ends) on a running clock at the event-ingestion seam; it doubles
  as the user demo. It includes a secret-injection case that drives the
  secret guard's drop-and-report path.

## Testing Decisions

- A good test exercises external behavior in-game on the Forever beta client
  and records a verdict; implementation details (buffer internals, pooling)
  are never asserted directly. This ecosystem has no automated suite —
  the verdict log is the test record.
- **Seam 1 — event ingestion (layout and encoding).** Test
  mode injects synthetic events into the ring buffer, above every predictor
  and renderer, so layout, pooling, encoding, window bars, expiry-drop and
  ready marks are all verifiable without a fight.
- **Seam 1b — library callbacks (effect classification).**
  `/actiontimeline test effects` replays real library event signatures on a
  fake swing, above the classification rules — parry (mid-swing melee
  UPDATE), early landing (STOP then same-speed START), retry chain
  (repeated ranged UPDATEs ~0.5 s ahead), reset (in-flight START), weapon
  swap (different-speed START), overdue (expiry passing with no landing)
  — so the copied classifier is verified outside combat, as
  4everSwingTimer's effect previews do.
- **Seam 2 — calibration.** The combat-end pass, the on-demand command and
  manual overrides are drivable outside combat; predicted marks are checked
  against them.
- **Seam 3 — the existing capture rig.** SwingTestLog records the open
  facts as probes with verdicts (prior art: the library's oracle and
  sink-view probes, the M1 session-script checklist pattern, the
  swing-timer addon's in-game verification checklist).
- The engine-drawn lane is verified by eye and recorded as a verdict probe
  only — Lua cannot read its geometry, so no scripted assertion is possible.
- The config branch adds one probe (Edit Mode anchor registration on the beta
  build) and retires none of the seams; the Settings re-register probe is
  dead — nothing dynamic registers in the Settings category anymore.
- Prior art: 4everSwingTimer's test-command convention (fake swings, effect
  previews replayed on a running clock) and the library's evidence-capture
  workflow.
- The first in-game pass includes an **encoding check** in test mode:
  happened, predicted, ready, unusable, unknown-cooldown, parked, the
  certainty gradients (hand-lane chain, cast-lane source flip, window-bar
  elapsed/unelapsed split) and the sink icon verified by eye before the
  encoding ships — in both skins and every orientation, together with the
  `VISUAL.md` items (state tints, stopped-cast flash and shake, chevron,
  motion trail, paused/queued overlays, sink countdown). The by-eye check covers the probed classes (Warrior,
  Rogue, Paladin); the other classes' curated data ships unverified in
  game and is release-noted as such.
- The encoding check also measures renderer frame time against the
  performance budget and views the effect previews once through a
  color-blindness simulator.
- The encoding check runs for both layouts. Test mode and `test effects`
  drive whichever layout is active; test mode adds a long cooldown
  returning (the now-line ring). Single lane adds a **peripheral pass**:
  watching test mode with the eyes about 20° off the timeline (on the
  screen centre), a swing landing, a cooldown returning, a cast in flight
  and a running GCD must each be told apart. The color-blindness pass
  covers Single lane's held outline and amber delay line. Both layouts
  meet the same frame-time budget.
- Syntax checks run before every in-game pass (luajit/luac), per the repo
  conventions.

## Out of Scope

- Proc buffs, extra attacks, crits and damage (combat log refused; extra
  attacks probe-listed).
- Swing outcome annotations (hit, crit, miss, dodge, parry of your own
  swings) — combat-log-only, and the log is refused; happened marks are
  outcome-agnostic, with an unrendered outcome slot for a future API.
- Target debuff ticks and Sunder-stack inference (probe-listed).
- Buff lanes in v1 (inferred-buff accuracy is weak while aura data is hidden
  mid-combat).
- Resource (rage/energy) lane — `UnitPower` reads secret even out of combat (probe 5), so only a sink could draw it; post-v1.
- A dedicated queued-ability lane — covered instead by the queued
  mark-swap on the main-hand lane (`IsCurrentSpell` is probe-verified plain).
- Usable item cooldowns (trinkets, potions) — spells only in v1.
- Charge-count spells (charges recharging independently) — the
  calibration model does not express them; revisit with a schema version
  bump if the ruleset grows them.
- A library-reported swing-event **reason** (parry, retry, rescale, reset,
  swap) — a library API ask; v1 copies 4everSwingTimer's classification
  rules until it ships.
- The Auto Shot windup window — the library computes but does not expose
  its internal cast-time value; a library API ask, and the ranged lane
  shows landing marks only in v1.
- Cooldown Manager mirroring (probe-listed optional upgrade, never the
  foundation).
- Logarithmic scale, overlap avoidance, labels or anchors that depend on
  sink-lane geometry.
- Any target-side timeline (Forever provides no target swing API).
- Pet lanes (hunter, warlock pet casts and cooldowns) — `pet` unit event
  readability on Forever is unprobed and the lane model is player-centred;
  revisit after v1, probe first.
- An alternate color-blind palette — effects are shape- and
  direction-distinct instead (`VISUAL.md`); revisit on player demand.
- Any "press this next" recommendation output — the restriction policy
  exists to stop exactly that.
- A public remote, publishing and platform-name registration (gated on
  the probe session; checks happen before publish).

## Further Notes

- No probe blocks the v1 core; probes 2/5/7 gate their own lanes, probes
  10 and 11 gate only their lane's duration source (the energy-GCD default
  and the cast lane's cast time), the Cooldown Manager probe gates only the
  optional mirror, and the Edit Mode probe gates only the frame-anchoring
  mechanism (fallback: a custom unlock overlay like 4everSwingTimer's).
- Probe session done (2026-10-06, build 70235, `PROBE_SESSION.md`):
  plain in combat and in a boss pull — player cast IDs, `isActive`
  (also true during the GCD), `IsSpellUsable`, the live cast time, the
  warrior stance read; SUCCEEDED fires at the swing for Heroic Strike and
  on avoided attacks; `UnitPower` secret even out of combat; every Native
  atlas present; the Cooldown Manager near-empty; Edit Mode placement via
  ForeverCDM's `EventRegistry` pattern passes (scale moves to Settings);
  GCD spell 61304 absent. Not run: extra attacks, druid shifts, sink
  precision by eye, reactive usability, Sunder.
- The probe session script was the deliverable before code: one numbered
  in-game checklist through the capture rig covering the open probes (boss-pull
  cast IDs, avoided-attack casts — gating the cast lane and debuff
  counting, not swing outcomes — `isActive`, sink precision, resource
  secrecy, extra attacks, Cooldown Manager coverage, energy-GCD duration,
  Edit Mode anchor registration, cast duration readability — gating only
  the cast lane's duration source, spell usability readability — gating
  only what "ready" includes, on-next-swing SUCCEEDED timing — gating only
  where Heroic Strike's happened mark sits, Native skin atlas check —
  gating only the Native look per element, with Flat fallbacks,
  shapeshift and stance — confirming shifts leave the swing alone and
  whether the form read is plain), each with a recorded verdict. The
  queued-ability probe is answered: `IsCurrentSpell` is plain (verified in
  4everSwingTimer's queued-highlight poll).
- The "base cooldowns ignore talents" claim is itself probe-listed;
  calibration staleness mitigations are combat-end re-read, manual override,
  and the sink overlay (ADR-0001 consequences).
- The configuration round was settled by pointing at the Blizzard
  tracker pattern as implemented on Forever by ForeverCDM (spellbook-read,
  own settings window, Edit Mode rows); Blizzard's own Cooldown Manager
  remains empty/off/WIP for most classes and was rejected as a foundation
  from the start.
