Design research · WoW: Forever (interface 16001)

# Forever Combat Timeline

A live timeline of what you did and what is about to happen: swings, casts, cooldowns and buffs, laid out left to right around a "now" line. This page covers what WoW: Forever lets an addon see, lane by lane, and how to draw it under the secret-value rules.

2026-10-05Status: exploration, nothing builtBuilds on 4everSwingTimer + LibClassicSwingTimerAPI 2.2.0

## The short answer

It is buildable, but each half of the timeline gets its data from a different place, and some lanes from a simulator timeline cannot exist on Forever at all.

- **Past side**: your own cast events plus the swing library. Both stay readable in combat, including a dungeon fight (verified 2026-10-05, build 70205).
- **Future side**: mostly *inferred* from your own cast time plus a known duration. True cooldown numbers are secret in combat, but the engine can still draw them.
- **Missing**: proc buffs (Flurry, Holy Strength, weapon procs), target debuff ticks, extra attacks, crits and damage. The combat log is refused and aura data is hidden mid-combat.

Readable in combat Inferred from own casts Secret, engine-drawn Unverified Blocked

Mock of a live Forever timeline for a dual-wield Fury warrior, 5 s of past and 5 s of future. Full-color marks are things that happened; desaturated marks are predictions. Lane colors follow the legend. The two hatched lanes show what a simulator would draw but Forever never reports.

## What each lane can draw on

| Lane | Data source | Readable in combat? | Verdict |
| --- | --- | --- | --- |
| Melee MH / OH / Ranged | LibClassicSwingTimerAPI, built on the `PLAYER_SWING` payload | Yes. The payload stays readable mid-fight in a dungeon while `UnitAttackSpeed` reads secret. | Best row |
| Your casts (past) | `UNIT_SPELLCAST_SUCCEEDED / START / STOP` on `player` | Spell ID readable in open-world and dungeon combat (paladin run, 2026-10-05: Judgement, Holy Strike, Consecration all plain mid-fight). A target's `START` spell ID went secret in a dungeon, so this holds for `player` only. | Readable |
| Cooldowns (future) | Cast time + known cooldown (learned out of combat) | Yes: it is your own arithmetic on readable inputs. | Main path |
| Cooldowns, exact | `C_Spell.GetSpellCooldownDuration` → DurationObject | Secret, but `StatusBar` and `Cooldown` widgets accept it and draw it. | Display only |
| Cooldowns, numbers | `C_Spell.GetSpellCooldown` | start and duration are secret. Reports disagree on whether `isActive` stays readable. | Not as numbers |
| GCD | Cast event + fixed 1.5 s (1.0 s for energy users) | Yes | Inferred |
| Self buffs | Your cast + known duration; `UNIT_AURA` fires at the edges | Aura reads return nil in combat (`ContextuallySecret`); the event still fires. | Inferred |
| Proc buffs | None. Procs fire no cast event, and aura data is hidden. | No | Impossible today |
| Target debuffs | Your casts only (Sunder count) | Partly. Misses, dodges and other players' applications are invisible. | Partial |
| Extra attacks, crits, damage | Combat log only | No. `COMBAT_LOG_EVENT_UNFILTERED` registration silently returns false for the whole session. | Blocked |
| Rage / energy | `UnitPower("player")` | Untested. A StatusBar can display it either way. | Probe |
| Heroic Strike queue | `IsCurrentSpell`, `ACTIONBAR_UPDATE_STATE` | Yes. `C_Spell.IsCurrentSpell` returns plain booleans in combat (probe 6). | Readable |

The working rule, as the forever-addon-kit notes put it: time what you cast yourself from your own `UNIT_SPELLCAST_SUCCEEDED`, plus a duration learned out of combat. Classic-ruleset cooldowns are mostly fixed, which makes this rule accurate for most lanes.

## Three ways to place a mark

Every mark sits at `x = nowX + (eventTime − GetTime()) × pxPerSec`. The question is whether Lua is allowed to know `eventTime`.

### Readable times, positioned in Lua Default

Swings from the library, your casts, and inferred cooldowns and buffs are plain numbers. Use one `OnUpdate` and pooled textures per lane, and drop entries once they scroll past the left edge. Any scale works, including the logarithmic one SexyCooldown and Cooldown Timeline use.

### Secret durations, positioned by the engine Smoke-tested

Lua cannot compute `x` from a secret. Instead, give each exact-cooldown lane a transparent StatusBar that spans the future window, with min/max set to the window length in seconds, and feed it the secret remaining time each frame. `StatusBar:SetValue` takes the secret without error and the client draws the fill from it, though your code never sees the number. Anchor the icon to the fill texture's right edge, and the engine moves it. Anything past the window clamps at the far edge.

```
-- future window: 10 s wide, lane bar spans it
local bar = CreateFrame("StatusBar", nil, lane)
bar:SetPoint("TOPLEFT", lane, "TOPLEFT", nowX, 0)
bar:SetSize(10 * pxPerSec, rowHeight)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:GetStatusBarTexture():SetAlpha(0.25)
bar:SetMinMaxValues(0, 10)

local icon = bar:CreateTexture(nil, "OVERLAY")
icon:SetSize(rowHeight, rowHeight)
icon:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")

-- per frame: DurationObject getters return secrets; SetValue accepts them.
-- ignoreGCD = true, or every other cast drags the icon to 1.5 s and back;
-- the GCD gets its own lane.
local dur = C_Spell.GetSpellCooldownDuration(spellID, true)
bar:SetValue(dur:GetRemainingDuration())
```

**Tested on Forever (build 70205, 2026-10-05).** The swing library's oracle probe passed a secret `UnitAttackSpeed` into `SetValue` mid-combat:

- Confirmed `SetValue` accepts the secret. This is the first direct proof on Forever.
- Closed Every way back out is secret: `GetValue`, the fill texture's width, and the position of a frame anchored to the fill (its `GetLeft` reads secret, while the bar's own `GetLeft` stays plain). The secret follows the value through the layout engine into anything anchored to it.
- Confirmed The icon renders in the right place. A follow-up visual test (`/stl sinkview`, same day) fed `C_Spell.GetSpellCooldownDuration(1776):GetRemainingDuration()` into the bar mid-combat on a rogue: the icon tracked a full 10 s Gouge cooldown while the value was secret. `SetText` and `Cooldown:SetCooldownFromDurationObject` also accepted the secret, with no errors. The value turned plain at the exact moment combat ended.
- Confirmed In a dungeon, past the window. A second run on a paladin cast Blessing of Freedom (20 s cooldown) mid-fight in a dungeon: the icon waited at the right edge for the first 10 s, then slid to the left edge, again with no errors. The value went secret on the first frame of combat and plain on the last.
- Not yet covered Precision beyond a by-eye pass, and a boss encounter (the dungeon run may have been trash).

Limits that follow: the lane is display-only. Linear scale only. Lua cannot hide the icon when the cooldown ends, because `IsActive` is secret too. Lua also cannot read where the icon is, so no code can depend on its position: no overlap avoidance between icons, no labels placed next to it, and nothing anchored to it that needs readable geometry. Keep the icon a leaf frame.

### Mirror the Cooldown Manager Optional upgrade

EventHorizon_Infall does this on retail 12.x: it reads Blizzard's Cooldown Manager and draws timeline lanes from it. On Forever the manager covered five classes (Druid, Mage, Priest, Warrior, Warlock) as of build 70009, is off by default, and does not support spell ranks. Use it to sharpen accuracy where it exists, not as the foundation.

## Proposed structure

```
Events      ring buffer {t = GetTime(), kind, spellID, lane}
            fed by library swing callbacks + player UNIT_SPELLCAST_*
            (expire past window + 2 s, hard cap 512 entries)
Predictors  one per lane type:
              swing     next expiration from UnitSwingTimerInfo
              cooldown  cast time + calibrated cooldown
              gcd       cast time + power-type default (1.5 s, 1.0 s
                        energy; user-overridable)
              buff      post-v1, held out: inferred-buff accuracy is
                        weak while aura data is hidden mid-combat
Calibrate   out of combat, plain C_Spell.GetSpellCooldown, cache per
            spell ID: read pass on PLAYER_REGEN_ENABLED, /calibrate
            command, per-spell manual override (ranks have distinct IDs;
            base cooldowns ignore talents — claim itself probe-listed)
Renderer    lanes, now line, past/future window (defaults 5 s / 5 s,
            configurable), pooled marks, linear scale in v1, optional
            engine-drawn sink lane per spell
Config      spellbook-derived lane set (toggles over every known class
            spell, curated per-class starter defaults), own settings
            window (per-spell enable, sink opt-in, manual override,
            drag order), 12.x Settings category for globals (windows,
            heights, spacing, scale, GCD), Edit Mode-anchored frame
```

Build it as a **separate addon** that embeds the same swing library. 4everSwingTimer keeps its narrow scope (no swing math, bars only), and the timeline becomes a second consumer of the library's swing state.

## Decisions applied (2026-10-05)

Design tree settled via the grilling session; shared language lives in the timeline glossary (the repo's root `GLOSSARY.md`) and the shared swing/secrecy vocabulary in 4everSwingTimer's glossary; the cooldown decision in `adr/0001-inferred-cooldowns-with-engine-drawn-overlay.md`.

- **Name**: 4everActionTimeline — separate repo, created after the probe session passes. Saved-variable global `FourEverActionTimelineDB`, namespace `FourEverActionTimeline`, slash `/actiontimeline` plus a short alias (uniqueness checked before publish, not before coding). Same `.pkgmeta` externals trio, GPLv3, tag-triggered packager pipeline.
- **v1 lanes**: swings (MH/OH/ranged), player casts, inferred cooldowns, GCD. Buffs, Sunder stacks, debuffs and resources wait on their probes; queued abilities are answered (probe 6) and handled by the MH mark-swap. Proc buffs are impossible today.
- **Lane geometry**: one lane per tracked spell, EventHorizon style — no overlap logic, consistent with the sink lane's Lua-blind geometry. Order: hands/ranged, then GCD, then the cast lane, then spells/cooldowns. Idle lanes never collapse: an idle tracked spell parks a ready mark on the now line, so frame height is stable and no hide-idle toggle exists. The sink needs no hide-on-complete for the same reason — its icon comes to rest at the now line when the remaining time hits zero.
- **Cooldown marks**: inferred from calibration (ADR-0001); the engine-drawn sink stays as an opt-in per-lane overlay. Uncalibrated spells draw happened marks only.
- **Mark encoding**: desaturation alone — predicted marks desaturated, happened marks full color. No dashed outline.
- **GCD**: power-type default at login, user-overridable; whether Forever honors the 1.0 s energy GCD joins the probe list.
- **Test mode**: `/actiontimeline test` seeds fake events on a running clock (layout, pooling and encoding verifiable without a fight).
- **Configuration** (settled 2026-10-05, configuration round): the lane set is spellbook-driven — every known class spell is a toggle, a curated per-class starter set ships enabled, rank churn resolves via the spellbook scan (config shows names, marks and calibration key on resolved IDs). Per-spell state (enable, sink opt-in, manual override, drag order) lives in the addon's own settings window; globals (windows, heights, spacing, scale, GCD dropdown plus custom slider) live in the 12.x Settings category, which supports checkbox/slider/dropdown only. The frame anchors in Blizzard's Edit Mode (ForeverCDM's proven pattern — no custom unlock overlay, no lock checkbox). No capture mode, no typed spell input.
- **Storage** (settled 2026-10-05): versioned saved variables in two layers — class layer (shared lane set, seeded from starter defaults) and player layer (overrides, frame settings, calibration cache). Player overrides win; unset keys fall through to the class layer (inheritance, not copy-on-first-use). The calibration cache is a separate sub-table, wipeable without touching the lane set.
- **Hand lanes** (settled 2026-10-05, hand-lane round): marks only — happened marks at past landings, predicted mark at the next landing, no period bar; parked hands show a dim ready mark at the now line. The swing predictor draws a **cadence chain**: equal-interval desaturated marks from the latest anchor's expiry and speed, filling the future window, re-derived at every anchor (plain payload arithmetic; the library stays the sole source of swing state). No ghosts on correction — the predicted mark repositions with a **reposition pop** (teal = shortened landing, amber = ranged retry, red = cast reset, the bar addon's effect colors) and nothing persists on the happened mark. PAUSED freezes and dims the lane's marks. A queued next-melee ability swaps the MH predicted mark's icon to the queued spell (`IsCurrentSpell` verified plain). Lane identity: every swing mark renders the equipped weapon's icon (happened full color, predicted desaturated, parked dim) — the marks are the lane's identity, no left-edge glyph, no text labels, no delta indicator (the two lanes show it). Presence is equipment-driven (no off-hand weapon, no OH lane; no ranged weapon, no ranged lane) with per-hand toggles in the Settings globals.
- **Swing outcomes** (settled 2026-10-05, outcome round): happened marks are **outcome-agnostic** — hit, crit, miss, dodge and parry of your own swings are combat-log-only, and the log is refused for the whole session (nothing left to probe). The happened-mark structure keeps an unrendered outcome slot for a future outcome API; v1 draws nothing there. No early-landing accent either: the pop and correction streak are transient (refined in the effects round, below). The README carries the FAQ entry explaining the limit.
- **Cast lane** (settled 2026-10-05, cast-lane round): happened marks are cast completions (instants included) — full color, spell icon, meaning "cast completed", never "landed" (outcome-agnostic; probe 2 decides only Sunder counting). In-flight casts and channels draw a predicted mark at the expected end (saturation per the encoding round below), and the in-flight spell's icon **rides the now line** (a **now-line icon**) — the lane's identity is what is happening now, no static left-edge glyph, absent when idle. Stopped, failed and interrupted casts leave a red happened mark at the stop instant while the predicted mark pops red and vanishes (no ghost). Every player cast appears, unfiltered — a "combat only" toggle is post-v1. The cast duration comes from a live read when plain, event-arithmetic calibration when secret (probe 11).
- **Mark encoding** (settled 2026-10-05, encoding rounds): desaturation alone, governed by **source-certainty saturation** — saturation tracks the certainty of the mark's source, not the side of the now line. Full color: happened marks; ready marks (usable now, matching the game's own gray-while-on-cooldown icon language — the inversion was considered and declined); the hand lanes' next-landing mark (the library's engine-verified expiry, plain even in restricted content); the cast lane's in-flight completion mark when fed by a plain live read; the sink's icon (engine truth); and the now-line icon (present tense, a fact in progress). Desaturated: deeper cadence-chain marks and calibration-sourced predictions — cooldowns, and the cast lane's in-flight mark when the live read is secret (the saturation flips with probe 11's verdict). Parked hand marks dim. The whole encoding family is confirmed by-eye in test mode before it ships.
- **Edge behaviors** (settled 2026-10-05, edge round): the engine-drawn sink is its own lane per opted-in spell — one mark per lane per source, Lua-blind geometry never shares a lane with readable marks (mock-consistent). A login/reload re-seed pass rebuilds predicted marks from plain cooldown reads when loading out of combat; loading in combat skips (values secret) and unseeded spells show no future marks — happened-marks-only, the honest fallback — with the sink lane the only in-combat truth after a reload. Predicted marks beyond the future window clamp at the far edge — readable marks and sink icon alike (the **edge clamp**). Hidden-frame convergence follows the repo's proven pattern: event capture never depends on visibility, expiry sweep and pruning run on a low-frequency ticker, and the renderer fully relayouts on show. Charge-count spells are out of scope for v1; the Auto Shot windup window stays a library API ask (the ranged lane shows landing marks only).
- **GCD lane** (settled 2026-10-05, mock round): renders **window bars**, not point marks — a light-blue span per GCD window, from the triggering cast to the GCD's end (power-type default, user-overridable). Past GCD windows draw at full color while inside the past window; the active window renders desaturated until it completes; nothing when idle (the GCD parks no ready mark); no future chain — one cast deep. The window draws on the GCD lane only in v1 (EventHorizon-style per-spell-lane GCD shading is post-v1). The mock's Heroic Strike queue row was illustrative only — the queue keeps the mark-swap treatment, no dedicated queue lane — and its "WF proc window" row reads as the spell's cast mark plus its GCD window; proc windows have no data feed today.
- **Probe gating**: no probe blocks the v1 core; probes 2/5/7 gate their own lanes (probe 6 is answered), probes 10 and 11 gate only their lane's duration source, probe 8 gates only the optional Cooldown Manager mirror, probe 9 (Edit Mode anchor registration) gates only the frame-anchoring mechanism.
- **Gap review** (settled 2026-10-06): "ready" means off cooldown and usable when `IsSpellUsable` reads plain in combat (probe 12), off cooldown only otherwise; an **unusable mark** and an **unknown-cooldown mark** join the now-line family, and parked hands show a **parked mark**. Cooldowns anchor on SUCCEEDED; **linked cooldowns** are learned during calibration over a curated seed; **delayed-start cooldowns** (Stealth, Nature's Swiftness) show happened marks only. Calibration reads automatically after out-of-combat casts and at combat end; the slash command reports, GCD-length reads are rejected, talent changes mark the cache stale, retired rank IDs are pruned. Cast lane: pushback repositions with an amber pop, a channel stopping early is red only when its expected end is known, Auto Shot and Shoot are excluded, on-next-swing abilities ride the main-hand happened mark (probe 13). Window bars split at the now line (elapsed full color, unelapsed desaturated). Storage is three layers, shipped defaults → class → player (ADR-0002). Settings gain width and a visibility dropdown (In combat / Always / Active); Edit Mode owns position and scale. A secret guard at ingestion drops and counts unexpected secrets, reporting once after combat. With a spell's sink on, its spell lane drops the calibrated predicted mark (the sink is its only future mark); sink lanes group at the bottom of the frame; the ready mark and the resting sink icon sharing the now line is accepted. A player's lane order replaces the class order whole (later class additions append, flagged new). Cooldown resets come from a curated per-class table. A spell's next completed cast clears its unknown-cooldown mark. Curated data ships for all nine classes (3–5 starter spells each); the by-eye check covers the probed classes.
- **Hand-lane effects** (settled 2026-10-06, effects round): corrections jump (never glide) with a pop and a fading **correction streak**. Parry haste and ranged dynamic haste: teal jump. Melee haste (no rescale on Forever) surfaces as an **early landing**: teal pop and streak on the happened mark, nothing persisting. An **overdue** next-landing mark pins at the now line. Ranged retry: honest sawtooth jumps, an amber **held** border for the chain, a **delay span** recording time lost, one amber pop per chain. Cast reset and weapon swap: red pop, across-lane shake, streak and a **clip mark** (red tick). A swing cut short just parks. Classification: a library reason field is the API ask; until then, 4everSwingTimer's rules are copied with identical thresholds. While overdue, the cadence chain derives from the now line. `/actiontimeline test effects` replays real library event signatures above the classifier (Seam 1b).
- **Forms and calibration truth** (settled 2026-10-06): shapeshifting leaves the swing alone on Forever (play-observed; probe 15 confirms), so no form classification exists. Shifted swing marks render the form's icon. Spells needing another form or stance show the grey unusable mark from the form read (probe 15), independent of probe 12. With `isActive` plain (probe 3), a cooldown mark reaching now pins **overdue** until the spell reads ready; otherwise it trusts calibration. A cast before the predicted ready, or a stuck overdue mark, marks that cache entry stale for the combat-end read. Effects are shape- and direction-distinct for color-blind players (no alternate palette in v1). Performance budget: per-frame work limited to positions, transients and sink feeds; sink lanes capped at 6; under 0.3 ms per frame for 15 lanes as the starting target. Pet lanes are out of scope for v1.

## Probes to run before writing code

Each answer changes the design. Most fit into the existing SwingTestLog harness.

1. **Player cast IDs in a dungeon.** Answered: readable mid-fight (2026-10-05). The past side can key on spell IDs. A boss pull is the remaining check.
2. **Cast events on avoided attacks.** Does SUCCEEDED fire for a dodged or parried Sunder or Heroic Strike? Gates the cast lane (happened marks for avoided ability casts) and Sunder-count inference — it has no bearing on white-swing outcomes, which are combat-log-only and refused.
3. **`isActive` in combat.** Is `C_Spell.GetSpellCooldown(...).isActive` readable? Sources disagree.
4. **Engine-drawn icon.** Answered: the icon tracks a secret cooldown on screen, including past the window and in a dungeon (Gouge and Blessing of Freedom runs, 2026-10-05, build 70205). Still open: a precision measurement and a boss pull.
5. **Resource secrecy.** Is `UnitPower("player")` secret in combat?
6. **Queued swing abilities.** Answered: `C_Spell.IsCurrentSpell` returns plain booleans on the beta (probe-verified in 4everSwingTimer's queued-highlight poll, running every 0.2 s in combat). The queue mark-swap on the MH lane is unblocked.
7. **Extra attacks.** Do Windfury, Sword Specialization and Hand of Justice fire `PLAYER_SWING` through the library?
8. **Cooldown Manager coverage.** Which classes does it support on the current build (70205 or later)?
9. **Edit Mode anchoring.** Can the timeline frame register, drag and scale as an Edit Mode-anchored frame on the current beta build (ForeverCDM's pattern)? Fallback: a custom unlock overlay.
10. **Energy GCD duration.** Does Forever honor the 1.0 s energy GCD? Feeds the GCD lane's power-type default.
11. **Cast duration readability in combat.** Is the player's own cast time plain mid-fight (the START payload / casting info), in open world and a dungeon? Gates only the cast lane's duration source: a live read if plain, event-arithmetic calibration (`SUCCEEDED − START` out of combat) if secret. The lane is buildable either way.
12. **Spell usability readability in combat.** Is `C_Spell.IsSpellUsable` (usable, insufficient power) plain mid-fight, in open world and a dungeon? Gates only what the ready mark means: off cooldown and usable if plain (reactive abilities and resource included), off cooldown only if secret.
13. **On-next-swing SUCCEEDED timing.** Does `UNIT_SPELLCAST_SUCCEEDED` for Heroic Strike / Cleave fire when the swing lands, not when pressed? Gates only where the queued ability's happened mark sits (on the main-hand swing it rode).
14. **Native skin atlas check.** Does every `source` entry in `ASSETS.md` exist on the current build (`C_Texture.GetAtlasInfo`), and which arrow/chevron atlas suits the edge-clamp cue? Gates only the Native look per element; each missing atlas falls back to its Flat equivalent.
15. **Shapeshift and stance.** Confirm a druid shift neither stops nor re-speeds an in-flight swing (no library STOP/START/UPDATE on shift; play-observed, unlogged), and whether `GetShapeshiftFormID` reads plain in combat. Gates only the wrong-form unusable mark's source.

### Where the policy line sits

Blizzard's restrictions target combat-decision automation, not display. A timeline of your own actions and predicted cooldowns is display. A "press this next" recommender in the style of Hekili is what the secret-value system exists to stop, so it stays out of scope.

## Prior art

| Addon | What it shows | Relevance |
| --- | --- | --- |
| EventHorizon_Infall | One bar per spell, now line, past sliding left, cooldowns, casts and buffs ahead | Closest match to this concept; proves the layout works under 12.x secrets via the Cooldown Manager |
| Cooldown Timeline (CDTL2 / CDTL3) | Cooldowns on a shared, scalable timeline | CDTL3 handles Midnight's talent-blind base cooldowns |
| SexyCooldown | Logarithmic single-bar cooldown timeline | Reference for a compact, single-row layout |
| TrufiGCD, Spell History | Recently used abilities | The "past" half on its own, updated for 12.0 |
| WoWSims timeline | Full post-fight timeline with procs, debuffs and resources | The ideal a live addon can only partly reach |

## Sources

- [forever-addon-kit: Forever API findings](https://github.com/Thunderz96/forever-addon-kit)
- [WoW Forever: restricted addon APIs](https://wowforever.one/guides/addons/)
- [WoW Forever addons: what works and what is blocked](https://wowforeverclassic.com/guides/addons)
- [warcraft.wiki.gg: DurationObject](https://warcraft.wiki.gg/wiki/ScriptObject_DurationObject)
- [warcraft.wiki.gg: C_Spell.GetSpellCooldownDuration](https://warcraft.wiki.gg/wiki/API:C_Spell.GetSpellCooldownDuration)
- [warcraft.wiki.gg: Patch 12.0.1 API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes)
- [EventHorizon_Infall](https://www.curseforge.com/wow/addons/eventhorizon-infall)
- [CDTL3](https://www.curseforge.com/wow/addons/cdtl3) and [CDTL2](https://www.curseforge.com/wow/addons/cooldown-timeline)
- [SexyCooldown](https://www.wowace.com/projects/sexycooldown)
- [TrufiGCD](https://wowinterface.com/downloads/info21820-TrufiGCD.html) and [Spell History](https://www.curseforge.com/wow/addons/spell-history)
- LibClassicSwingTimerAPI haste findings, section 7.1: the value-sink oracle probe (2026-10-05, build 70205, `/stl oracle`)
- 4everSwingTimer in-game findings report (builds 70009–70205): swing payload, aura secrecy, combat log refusal, spellcast payload secrecy

Findings marked readable or blocked come from in-game probes on the Forever beta or the cited sources. Lanes marked unverified need the probes above before anyone relies on them.