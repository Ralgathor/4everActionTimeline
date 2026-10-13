# Probe Session Script — 4everActionTimeline (probes 1–15)

The numbered in-game checklist SPEC's Further Notes names as the next
deliverable. It answers the open probes in `Forever Combat Timeline.md`
(probes to run before writing code) through the SwingTestLog capture rig. No
timeline code is written until every probe below has a recorded verdict, or
the conservative default is explicitly accepted for a probe that could not be
run.

Client: WoW: Forever beta (`_classic_beta_`, interface 16001). Suggested:
BugSack loaded, `/stl echo` off (the log file is the evidence).

## Setup

1. Copy `LibClassicSwingTimerAPI/docs/tools/SwingTestLog/` over
   `_classic_beta_/Interface/AddOns/SwingTestLog/` (the installed copy is a
   plain copy, not a link; the probe commands below are new).
2. Keep 4everSwingTimer installed: it embeds the library SwingTestLog hooks.
3. `/reload`, then `/stl` — the help must list the "Timeline probes" lines.
4. At login the rig logs on its own: `API` (every function the timeline will
   cache, present or missing, and invalid events), `REGFAIL` (events this
   client refused), `POWER`, `FORM`.
5. Mark each step with `/stl note <probe> <step>` so the log reads in order.

What logs automatically during play, no typing needed:

| Line | When | Feeds |
|---|---|---|
| `CAST` / `CASTSTART` / `CASTEDGE` | every player spellcast edge (stop, failed, delayed, channel start/update/stop) | 1, 2, 11, 13 |
| `CASTINFO` | on START, DELAYED and channel edges: `UnitCastingInfo` / `UnitChannelInfo` length and time left | 11 |
| `CD gcd` + `CD post-cast` | 0.05 s after every SUCCEEDED: the GCD spell (61304) and the cast spell's own cooldown | 3, 10, calibration, delayed-start |
| `SWING` / `START` / `UPDATE` / `STOP` / `QUEUE at-swing` | swing payload and library callbacks | 7, 13, 15 |
| `TGTCOMBAT` | `UNIT_COMBAT` on the target, every action except WOUND | 2 |
| `POWER`, `FORM` | combat enter and leave, form change | 5, 15 |
| `ENCOUNTER` | boss pull start and end | 1 |
| `TALENT` | talent-change events that exist on this client | calibration staleness |

At the end: `/reload` (the file is written then) and hand over
`WTF\Account\<account>\SavedVariables\SwingTestLog.lua` together with the
by-eye notes asked for below.

Spell IDs below are rank 1; any `/stl cd` or `/stl usable` also takes a
spell name the client knows (`/stl cd Overpower`) or no argument (the last
spell you cast).

---

## Part A — out of combat, any character

### Probe 14. Native skin atlas check

1. `/stl atlas` — logs found or MISSING for every `docs/ASSETS.md` atlas,
   plus six edge-clamp chevron candidates.
2. `/stl atlas show` — on-screen preview, numbered cells (the log maps each
   number to its atlas name). Note which chevron looks right for "further
   than this" at about ⅓ of an icon. Try more names with
   `/stl atlas show <name> <name> ...` (an atlas browser addon helps find
   candidates). `/stl atlas show off` to hide.

Expected: all `combattimeline-*` and `UI-HUD-CoolDownManager-*` found.
Gates: the Native look per element; each missing atlas falls back to Flat.
Picks the chevron atlas (else the two-stroke `WHITE8X8` fallback).

Verdict: **Pass (2026-10-06, build 70235).** All 14 ASSETS.md atlases exist (sizes logged; e.g. `combattimeline-line-left` 193×14, `-cooldown-divider` 56×46, `UI-HUD-CoolDownManager-IconOverlay` 86×86). All six chevron candidates exist; `uitools-icon-chevron-right` / `-left` (20×20, white, tintable to the track color) recommended for the edge-clamp cue — the `common-icon-*` and `NPE_Arrow*` candidates are pre-colored yellow.

### Probe 8. Cooldown Manager coverage

1. `/stl cdm` on each class you have (one line per category, with the
   spells it lists).

Gates: only the optional Cooldown Manager mirror (never the foundation).

Verdict: **Near-empty (Paladin, 70235).** Viewer available and enabled, but Essential/TrackedBar are empty; Utility lists only racials (Will of the Forsaken, Cannibalize), TrackedBuff Cannibalize; `HiddenActive`/`HiddenPassive` categories error on read. Confirms ADR-0004: no foundation, mirror stays optional.

### Probe 9. Edit Mode anchoring

Research result (2026-10-06, ForeverCDM 0.8.0 source): ForeverCDM does
**not** register its frames as Blizzard Edit Mode systems and embeds no
library. It subscribes to `EventRegistry` `EditMode.Enter` / `EditMode.Exit`,
makes its own frames draggable while Edit Mode is open, snaps by hand
against `EditModeManagerFrame.registeredSystemFrames`, and saves the
position itself. Edit Mode's own **scale** therefore does not apply to such
a frame — SPEC's "placement and scale native" needs revisiting with this
verdict (scale would become a Settings slider).

1. `/stl editmode` — an orange box appears, locked.
2. Open Edit Mode: the box should read "drag me" and drag. Move it, close
   Edit Mode: it locks again (log: `EDITMODE enter`, `moved`, `exit`).
3. `/reload`: the box comes back where you left it (`EDITMODE built`).
4. Note: did the box drag only inside Edit Mode? Did anything taint
   (BugSack, "interface action blocked")? `/stl editmode off` when done.

Gates: only the frame-anchoring mechanism. Fail: the custom unlock overlay
(4everSwingTimer's), position in the player layer.

Verdict: **Pass (ForeverCDM pattern).** `EditMode.Enter`/`Exit` fire through `EventRegistry` (55 registered system frames, snap API present); the probe frame dragged only inside Edit Mode, locked on exit, and came back at its saved spot after `/reload`; no taint reported. The frame is not an Edit Mode system: Edit Mode's own scale does not apply — scale becomes a Settings slider (SPEC updated).

### API presence

1. Nothing to do — read the login `API` and `REGFAIL` lines; `/stl api`
   repeats them.

Gates: which spellbook functions the lane-set scan uses (`C_SpellBook.*` vs
the legacy globals), and which talent event marks calibration stale.

Verdict: **Recorded.** Present: every `C_SpellBook.*` function checked, `FindBaseSpellByID`, `C_Spell.*` (incl. `GetSpellCooldownDuration`, `IsSpellUsable`, `IsAutoRepeatSpell`), `UnitCastingInfo`/`UnitChannelInfo`, `GetShapeshiftFormID`, `C_Texture.GetAtlasInfo`, `C_CooldownViewer`, Settings, `EventRegistry`, `MenuUtil`, `ScriptAnimationUtil.ShakeFrame`, `debugprofilestop`, `C_EventUtils.IsEventValid`. **Missing:** `GetNumSpellTabs`, `GetSpellTabInfo`, `GetSpellBookItemInfo` — the lane-set scan uses `C_SpellBook`. Events: `LEARNED_SPELL_IN_TAB` invalid; `PLAYER_TALENT_UPDATE` fires on a talent change (the staleness trigger).

---

## Part B — Warrior (dual wield if possible, then sword + shield for Overpower)

### Probe 3. `isActive` in combat

1. `/stl cdwatch 6343 100 2687` (Thunder Clap, Charge, Bloodrage — swap for
   any warrior cooldowns you know).
2. Out of combat: cast each once. Expected: plain `CD post-cast` lines with
   the real duration, `active=true`, then a `CDWATCH` line when it ends.
3. Fight a mob: cast them mid-combat, keep fighting past their cooldowns.
   The `CDWATCH` lines show whether `active=` stays plain while start and
   duration go `<secret>`, and whether it flips to false on time.
4. `/stl cdwatch off`.

Gates: cooldown arrival — plain `isActive` means a cooldown mark pins
**overdue** until the spell reads ready; secret means it turns ready on
arrival, trusting calibration.

Verdict: **Plain (Warrior, Rogue, Paladin incl. the boss pull).** `isActive` stays plain while start, duration and modRate go `<secret>`, and flips false on time (Gouge: cast 18478.87, false at 18488.80 = its 10 s; Thunder Clap 6 s likewise). **Caveat:** `isActive` is also true during the GCD (out of combat every spell read `dur=1.500 active=true` right after any cast; in the boss fight Consecration read active for ~1.4 s after Judgement). An arrival pin therefore releases at the later of cooldown end and GCD end — the spell is not pressable before that either.

### Probe 12. Spell usability readability in combat

1. `/stl cdwatch 7384 5308 78` (Overpower, Execute, Heroic Strike) — the
   watch lines carry `usable=` and `noPower=`.
2. In combat: get dodged (Overpower lights up), take a mob under 20 %
   (Execute), sit at 0 rage. Each change logs one line.
3. `/stl cdwatch off`.

Gates: what the ready mark means — plain: off cooldown and usable, with the
unusable mark (blue resource-short, grey otherwise); secret: off cooldown
only.

Verdict: **Plain (resource case).** `usable`/`noPower` stay plain in combat and track rage/energy (Thunder Clap and Heroic Strike flip `usable=false noPower=true` → `true/false` as rage moves; Gouge on energy likewise; Judgement/Consecration plain in the boss). Reactive conditions (Overpower after a dodge, Execute under 20 %) **not tested** — level-6 warrior lacks both.

### Probe 5. Resource secrecy

1. `/stl power` once mid-fight (combat enter and leave log on their own).

Gates: the resource lane (out of v1 scope; recorded for later).

Verdict: **Secret, always.** `UnitPower` reads `<secret>` for rage, energy and mana at login, combat enter and combat leave — secret even out of combat. `UnitPowerType` stays plain. A resource lane could only be a sink.

### Probe 13. On-next-swing SUCCEEDED timing

1. `/stl note 13 HS`, press Heroic Strike early in a swing (queued), let it
   land. Repeat 5×. Once with Cleave if trained.
2. Compare times: the `CAST 78` line against the `QUEUE at-swing` and
   main-hand `SWING` line. Same instant = SUCCEEDED fires at the swing; well
   before it = at the press.

Gates: where the queued ability's happened mark sits — on the main-hand
swing it rode, or (conservative default) the cast lane.

Verdict: **At the swing.** Every Heroic Strike `CAST 78` carries the same timestamp as the main-hand `SWING` it rode (e.g. 18024.773, 18029.851, 18032.339; queued ~2.4 s after the previous swing). The happened mark sits on the main-hand lane at that swing.

### Probe 2. Cast events on avoided attacks

1. Fight a mob that dodges and parries (a frontal attacker, higher level
   helps). Spam Sunder Armor (7386) and Heroic Strike.
2. Look for `TGTCOMBAT DODGE|PARRY|MISS` lines and whether a `CAST` line
   sits at the same instant (SUCCEEDED fired on the avoided cast) or not.
   A `TGTCOMBAT <secret>` means the target's outcomes are unreadable —
   record that too.

Gates: cast-lane happened marks for avoided ability casts, and Sunder-count
inference. No bearing on white-swing outcomes.

Verdict: **SUCCEEDED fires on avoided attacks (Heroic Strike).** `TGTCOMBAT DODGE` (16999.725), `PARRY` (17126.484, 17350.498) and `MISS` (17031.875) share the instant of a `CAST 78`. Sunder Armor **not tested** (not trained at level 6). Side finding: `UNIT_COMBAT` on the target reports DODGE/PARRY/MISS **plain** — but unattributed (one MISS at 16753.516 matches no player swing), so it is not an outcome source for the player's own swings.

### Probe 7. Extra attacks

1. With a sword and Sword Specialization, Hand of Justice or Windfury
   (shaman group), fight long enough for several procs.
2. Look for a second main-hand `SWING` a few ms after the first, with no
   new library `START`/`UPDATE` between, or with one.

Gates: nothing in v1 (extra attacks are out of scope); records whether the
library ever reports them.

Verdict: **Not run** (no Sword Specialization, Hand of Justice or Windfury at level 6). No v1 impact — extra attacks stay out of scope.

### Probe 15a. Stance read

1. Switch Battle → Defensive → Berserker out of combat and once mid-fight
   (`FORM event` lines log on their own).

Expected: `formID` or `index` plain in combat. Gates: the wrong-stance grey
unusable mark (e.g. Overpower outside Battle Stance).

Verdict: **Plain.** `GetShapeshiftFormID` reads 17 (Battle Stance) in and out of combat; a Paladin aura reads `formID=nil` with a plain index (auras are shapeshift slots). Stance switching not exercised (one stance at level 6), but the read is plain in combat — the wrong-stance grey unusable mark can use it.

---

## Part C — Rogue

### Probe 10. Energy GCD duration

1. Out of combat, cast Sinister Strike (1752) five times. Each cast logs
   `CD gcd` (spell 61304) and `CD post-cast` (Sinister Strike has no
   cooldown of its own, so its read is the GCD). Read `dur=`: 1.0 or 1.5.
2. If `61304` logs `info=nil` or an error, the post-cast read alone decides.

Gates: the GCD lane's power-type default for energy users.

Verdict: **GCD spell 61304 does not exist on Forever** (`info=nil` on every cast). Step 1 not runnable (Sinister Strike needs a target). Indirect evidence: two Backstab → Slice and Dice pairs 1.363 s and 1.437 s apart in combat, both GCD spells, so the energy GCD is **shorter than 1.5 s**; 1.0 s is consistent but unmeasured. The warrior's post-cast read shows the GCD plainly out of combat (`dur=1.500`), so a no-target no-cooldown spell read would settle it.

### Delayed-start read (Stealth)

1. Out of combat: Stealth (1784). `CD post-cast` should read **not started**
   (`dur=0` or `active=false`) while stealthed.
2. Break Stealth, then `/stl cd 1784`: now cooling.

Gates: delayed-start detection during calibration (Stealth's lane shows
happened marks only).

Verdict: **Detectable.** Right after casting Stealth: `start=18330.533 dur=10.000 active=false enabled=false` — the cooldown is known but **disabled** while stealthed; after breaking it reads `start=18334.435 dur=10.000 active=true`. Calibration flags delayed-start on `isEnabled == false` right after the cast.

### Probe 4. Sink precision

1. Out of combat: `/stl sinkview 1776` (Gouge).
2. In combat: Gouge, then watch the icon against the 0–10 tick scale and
   the countdown text (engine truth via `SetText`). Count with a stopwatch
   or a video capture.
3. Repeat in a dungeon pull (Part F). `/stl sinkview off`.

Expected: the icon is on the countdown's second within about one tick.
Gates: nothing structural (the sink is already proven); records precision.

Verdict: **Ran without errors** (Gouge, `remaining` secret in combat and plain on the first frame out of it, no SetValue/SetText errors). Precision by eye **not recorded** in the notes.

### Probes 3 / 12 re-check (energy)

1. `/stl cdwatch 1776 1766` (Gouge, Kick) through a fight, including a
   moment at low energy (`noPower=`).

Verdict: **Plain.** Gouge `active` flips at its 10 s and `usable`/`noPower` follow energy in combat (see probes 3 and 12).

---

## Part D — Paladin, then any real caster

### Probe 11. Cast duration readability in combat

1. Out of combat: cast Holy Light (635) once. `CASTINFO start cast` shows
   `len=` (expect the tooltip cast time) and `left=`.
2. In combat: cast it again (on yourself while a mob hits you).
   `len=<secret>` or a number?
3. Pushback: let the mob hit you mid-cast — `CASTEDGE delayed` and a new
   `CASTINFO delayed` line (does `left=` grow?).
4. Interrupt yourself by moving mid-cast: `CASTEDGE stop` / `failed` /
   `CASTSTOP interrupted` order.
5. A channel (mage Arcane Missiles 5143, priest Mind Flay, or Evocation):
   `CASTINFO channel-start` length, then stop it early by moving —
   `channel-stop` timing vs expected end.

Gates: the cast lane's duration source — plain: live read, full-color
completion mark; secret: `SUCCEEDED − START` calibration, desaturated.

Verdict: **Plain.** In combat `UnitCastingInfo` gives Holy Light `len=2.500` and a plain `left=`. Pushback: `UNIT_SPELLCAST_DELAYED` fires and re-reads move the end (left 1.223 at 18708.466 → completed 18709.767, within 0.08 s). Moving cancels with `INTERRUPTED` (fired **four times**: 18740.084 once, 18740.284 three times) plus one `STOP` — dedupe needed. Channel (Cannibalize) `len=10.000` plain; stopped early at 4.8 s with `CHANNEL_STOP`; the channel's spell ID (20578) differs from the SUCCEEDED ID (20577). The completion mark is fed by the live read: full color.

---

## Part E — Druid (if one is available)

### Probe 15b. Shapeshift leaves the swing alone

1. Melee a dummy in caster form, shift to Cat Form (768) mid-swing, then to
   Bear Form (5487), then back. `/stl note 15 shift` before each.
2. Expected: no library `STOP`/`START`/`UPDATE` at the shift instant; the
   cadence continues. `FORM event` lines log the form read; mid-fight shifts
   tell whether it is plain in combat.

Gates: confirms SPEC's no-classification rule for shifts, and the
wrong-form grey unusable mark's source.

Verdict: **Not run** (no druid available). Shift-leaves-swing stays play-observed only; the druid wrong-form read is unverified (the warrior stance read is plain).

---

## Part F — Dungeon and a boss pull (any character, ideally a Part B–D one)

### Probe 1. Boss-pull cast IDs

1. Enter a dungeon; `/stl cdwatch <two of your cooldowns>`; optionally
   `/stl sinkview <one>`.
2. Pull trash, then the boss (`ENCOUNTER start` marks it).
3. Check the `CAST` lines during the encounter: plain spell IDs, or
   `<secret>`? Also `CD`, `CDWATCH`, `CASTINFO`, `POWER` during the boss.

Gates: the past side keys on spell IDs in restricted content; probes 3, 4,
11 and 12 re-checked where restrictions are strongest.

Verdict: **Plain in a boss pull.** Witherfang (encounter 3353, 98 s): every player `CAST` spell ID plain (no secret spell ID anywhere in the log), `isActive` and `IsSpellUsable` plain, cast-time reads plain; `UnitPower` secret as everywhere.

---

## Probe 6 — answered

`C_Spell.IsCurrentSpell` returns plain booleans in combat (4everSwingTimer's
queued-highlight poll). The main-hand queued mark-swap is unblocked.

## Part G — follow-up (Rogue 10, Paladin 20)

Closes what the first session left on assumptions. Out of combat
throughout unless a step says otherwise.

### G1. Exact energy GCD (probe 10) — Rogue

Out of combat, any spell with no cooldown of its own reads the GCD right
after a GCD-triggering cast. Sinister Strike needs a target to *cast*,
but not to be *read*.

1. `/stl cdwatch 1752` (Sinister Strike).
2. Out of combat, with no target needed, cast in turn: Sprint, Evasion,
   Stealth (then break it). Wait 3 s between casts.
3. After each cast, the `CDWATCH 1752` line shows `dur=` with
   `active=true` if that spell triggered the GCD. `dur=1.000` confirms the
   gate decision; `dur=1.500` overturns it. A spell that is off the GCD
   leaves the line unchanged. Record which spells trigger it.
4. Control: a Paladin cast out of combat must read `dur=1.500` the same way
   (`/stl cdwatch 20271`, then cast Blessing of Might on yourself).
5. `/stl cdwatch off`.

Verdict: **Not measured — all three candidates are off the GCD.** After Sprint, Evasion and Stealth the `CDWATCH 1752` line never changed (each logged only its own cooldown: Sprint and Evasion `dur=300.000`, Stealth `enabled=false`). The Paladin control read `dur=1.500` (Blessing of Might). The 1.0 s gate decision stands; G1b measures it in combat. Side finding: for instants, the cooldown `start` precedes the `SUCCEEDED` event by ~0.2 s (Sprint 20207.054 vs 20207.254, Evasion 0.217 s, Blessing of Might 0.216 s) — the event arrives a server round trip after the cooldown starts.

### G1b. Energy GCD in combat (probe 10) — Rogue

`isActive` is plain in combat and true while the GCD runs (probe 3), so
the GCD shows as an `active=true` → `active=false` pair on a watched
no-cooldown spell, timestamped to 0.2 s.

1. `/stl cdwatch 1752` (Sinister Strike — **do not cast it** during the
   test, so its line only reflects the GCD).
2. Fight a mob with Backstab (from behind), Gouge, Eviscerate or Slice and
   Dice only, at least 5 casts, a few seconds apart.
3. Each cast gives a `CDWATCH 1752 ... active=true` line and an
   `active=false` line; their gap is the GCD (≈1.0 or ≈1.5, ±0.2).
4. `/stl cdwatch off`.

Verdict: **1.0 s, measured (Rogue, in combat, build 70235).** Eight `CDWATCH 1752` active true→false pairs after Backstab, Gouge and Slice and Dice: 1.018, 1.002, 1.002, 1.005, 1.002, 1.001, 1.003, 1.007 s; two Backstabs 1.017 s apart merged into one 2.0 s window. `active` turns true 0.05–0.15 s before the SUCCEEDED event — the cast offset again. The energy-user GCD default is 1.0 s by measurement, no longer by assumption.

### G2. Mana resource-short read (probe 12) — Paladin

1. `/stl cdwatch 647 26573` (Holy Light, Consecration).
2. Spend mana down below a Holy Light cost (cast on yourself, or fight).
   The watch line should flip to `usable=false noPower=true`, then back as
   mana returns. Do it once in combat too.
3. `/stl cdwatch off`.

Expected: plain, like rage and energy. Gates: the blue resource-short
unusable mark for mana users.

Verdict: **Plain (mana).** Holy Light spammed out of mana: the watch flipped to `usable=false noPower=true` for Holy Light and Consecration (20071.473) and back as mana returned. Not repeated in combat, but in-combat usability already read plain for rage, energy and the Paladin's boss pull. Side finding: each press without mana fired `UNIT_SPELLCAST_FAILED` with no START (14 in 2.6 s).

### G3. Talent-reduced cooldown (optional) — Paladin

Only if Improved Judgement (Retribution, −1 s per rank) is talented, or
you can take it.

1. Judgement needs an enemy, so the read happens at combat end:
   `/stl cdwatch 20271`, kill a weak mob with Judgement as the last cast.
   The first `CDWATCH 20271` line after `COMBAT leave` is plain and shows
   the duration, as long as the 10 s base cooldown is still running.
2. `dur=10.000` with the talent means the read ignores talents (the
   calibration cache would be wrong for talented players); `dur=9` or `8`
   means the read includes them.
3. If you change talents, note whether a `TALENT PLAYER_TALENT_UPDATE`
   line appears.

Gates: whether a talent change only marks calibration stale (read includes
talents), or calibration needs manual overrides for talented spells.

Verdict: **Not run** (Improved Judgement not available). The "base cooldowns ignore talents" claim stays open; mitigations are unchanged — `PLAYER_TALENT_UPDATE` marks the cache stale (it fired on this client at 20152.472), the combat-end re-read corrects it, and manual overrides remain.

## Part H — Bar track follow-up (to run)

For ADR-0006. Any character; H3 needs a hunter or any class with a
ranged weapon equipped.

### H1. Blizzard's cast bar art

The mainline cast bar's atlases (`CastingBarFrameTemplates.xml`,
Forever branch); the rig checks exact names.

1. `/stl atlas ui-castingbar-frame ui-castingbar-background ui-castingbar-filling-standard ui-castingbar-filling-channel ui-castingbar-pip`
2. `/stl atlas show ui-castingbar-frame ui-castingbar-background`, then
   `/stl atlas show off`: does the frame read as a border around a bar,
   and does it stretch to a long, 26 px tall bar without distorting?

Gates: Bar track's border and body (Native); the fills are candidates for
its casts and channels. With none, the `WHITE8X8` border stays.

Verdict: **All five exist** ("5 checked, 0 missing", 2026-10-12). Shown at
their atlas size, `ui-castingbar-frame` reads as a bar frame (dark rails
top and bottom, a gold edge) and `ui-castingbar-background` as a grey
stone fill. Whether the frame stretches to a long 26 px bar without
distorting was not checked: a look to take when the bar is built.

### H2. A link glyph — no candidate

Blizzard's source names no link or chain atlas, so the linked-set mark is
the fallback: a small corner badge drawn with `WHITE8X8`. Nothing to run
unless a candidate turns up.

### H3. Auto Shot icon and the weapon's base speed

1. `/run print(C_Spell.GetSpellTexture(75))` - a file ID means the icon
   resolves.
2. With a ranged weapon equipped:
   `/run local d=C_TooltipInfo and C_TooltipInfo.GetInventoryItem("player",18) for _,l in ipairs(d and d.lines or {}) do local t=l.rightText if t and t:find("Speed") then print(t, issecretvalue and issecretvalue(t)) end end`
   Do it out of combat and once in combat.

Expected: the icon resolves; the speed line is plain out of combat. Gates:
whether the addon can compute the Auto Shot windup itself (base speed
plain) or must wait for the library to expose it.

Verdict: **Icon resolves, base speed plain** (2026-10-12).
`GetSpellTexture(75)` returned 132369 (twice: the icon and the original
icon). The ranged weapon's tooltip line read `Speed 2.30`, plain
(`issecretvalue` false); one read, out of combat. A tooltip shows the
weapon's base speed (not the hasted one), a fixed item stat: read it at
equip and cache it per item, as the swing library's own
`GetRangedBaseSpeed` does (the localized `SPEED` pattern on a hidden
tooltip). The addon can compute the windup itself: 0.52 s x the library's
ranged speed / the base speed.

## Gate decisions (2026-10-06)

Session run on build 70235 (Paladin, Warrior level 6, Rogue). For what it
could not cover, the user accepted:

- **Energy GCD 1.0 s** for energy users — since measured (G1b); at the gate the evidence was GCD casts 1.363 s
  apart, so under 1.5 s; the GCD override corrects it if wrong).
- **Druid form read plain** (same API as the verified warrior stance
  read) and **shifting leaves the swing alone** (play-observed) — verify
  on the first druid pass.
- **Reactive usability plain** (Overpower, Execute), following the
  verified resource case — verify on a higher-level warrior.
- **Extra attacks and Sunder skipped** — no v1 impact.
- **Sink precision** measured during the M5 encoding check instead.

The gate is cleared: build milestone M1 may start.

Follow-up session (Part G, same day) decisions:

- A `UNIT_SPELLCAST_FAILED` with no START (a refused press) leaves **no
  mark**; only a started cast can end red.
- Cooldown predictions subtract a **cast offset** learned in calibration
  (cooldown start minus SUCCEEDED time, ~0.2 s observed).
- The energy GCD is **1.0 s, measured** in combat (G1b).

## Conservative defaults (used only where a probe could not be run)

| Probe | Default |
|---|---|
| 3 `isActive` | secret — cooldown marks turn ready on arrival |
| 9 Edit Mode | failed — custom unlock overlay |
| 10 energy GCD | 1.5 s for every class |
| 11 cast time | secret — calibration-fed, desaturated completion mark |
| 12 usability | secret — ready means off cooldown only |
| 13 HS SUCCEEDED | at the press — cast-lane mark |
| 14 atlases | each missing atlas uses its Flat equivalent |
| 15 form read | secret — no wrong-form unusable mark |


## Part E — configuration surfaces (build 70338, M10)

Forever's own UI source (the `forever` branch of the wow-ui-source mirror,
1.60.1 build 70338) ships the Cooldown Manager and a Swing Timer, both
configured through Edit Mode, a content window and Options. The source says
each pattern below works for an addon; these probes confirm it on the client
before the code depends on it. Verdicts go to `Addon.PROBES`.

| Probe | Question | Steps | Verdict goes to |
|---|---|---|---|
| E1 Settings widgets | Do `CreateSettingsButtonInitializer`, `CreateSettingsListSectionHeaderInitializer` and `initializer:SetParentInitializer` work on the addon's category? | Open Options: the headers, the "Timeline spells" button, Custom GCD greyed unless GCD length is Custom | built in (nil-guarded) |
| E2 Selection art | Do the `editmode-actionbar-highlight` / `-selected` nine-slice kits draw on our frame? | Enter Edit Mode: blue frame and label on the timeline, yellow when clicked | built in (falls back to a band) |
| E3 Hand-off | Can our click clear Blizzard's own selection (`EditModeManagerFrame:ClearSelectedSystem()`) untainted? | **Fail** (build 70338, in game): CompactUnitFrame_UpdateHealPrediction errors, "execution tainted by 4everActionTimeline", on every raid-frame update. Never called; both selections can show. | built out |
| E4 Layouts | What do `GetActiveLayoutInfo().layoutType / layoutName` report for the preset layouts and a new one; does `EDIT_MODE_LAYOUTS_UPDATED` fire on a switch? | Switch layouts in Edit Mode: the timeline follows its own position | built in |
| E5 Keys | Is `SetPropagateKeyboardInput` callable by an addon (arrow-key nudge)? | **Fail** (build 70338, in game): ADDON_ACTION_BLOCKED, protected. No nudge; no keyboard capture. | built out |
| E6 Opening Edit Mode | Can our buttons step Edit Mode aside (`CheckHideAndLockEditMode`) untainted? | **Fail** (build 70338), called directly and through `securecallfunction` alike: raid frames' CompactUnitFrame update errors, "execution tainted by 4everActionTimeline". No Options button in the panel; `/actiontimeline options` in chat. | built out |
| E7 Stacking | Does the spell window (`FULLSCREEN_DIALOG`) take the mouse over open Edit Mode? | Pass (in game): it opens over Edit Mode. The Settings panel does not (E6). | built in |
