# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project overview

4everActionTimeline is a standalone addon for **WoW: Forever only**
(interface 16000+, currently `## Interface: 16001`) that draws a live timeline
of the player's actions around a now line: swing lanes (main-hand, off-hand,
ranged), the GCD, the player's casts, and one lane per tracked spell's
cooldown. Happened marks sit on the past side of the now line, predicted
marks on the future side (which side is which follows the orientation).

Status: **M10, configuration in Blizzard's patterns** (after M9, the Bar track
layout and Auto Shot as a cast) — the event
store, the renderer (one layout, Bar track: every lane on one framed bar,
ADR-0007; Native and Flat skins, four orientations, the card stack), test
mode, live hand, GCD, cast, spell and engine-drawn sink lanes, the Settings
category, the lane window and Edit Mode placement.
Next: the by-eye encoding check (`docs/SPEC.md`, Testing Decisions).
The probe session is done (`docs/PROBE_SESSION.md`, build 70235); its
verdicts live in `Probes.lua`.

All swing state comes from **LibClassicSwingTimerAPI** (embedded via
`.pkgmeta` externals, pinned to tag `v2.2.0`, LibStub MINOR 37 — bump
`REQUIRED_LIB_MINOR` in `Core.lua` when the pin moves). The addon holds **no
swing math**: it consumes the library's `UNIT_SWING_TIMER_*` events and
`UnitSwingTimerInfo`. Do not read `UnitAttackSpeed` or `UnitRangedDamage` —
on Forever they return secret values in combat, and the library owns that
problem. 4everSwingTimer is the other consumer of the same library; the two
addons are independent (ADR-0003).

## Read before changing behavior

- `docs/SPEC.md` — behavior: lanes, marks, predictors, calibration, storage,
  settings, testing seams, out of scope, probe gating.
- `docs/VISUAL.md` — look: skins (Native / Flat), orientation, marks, tints,
  hand-lane effects, animation rules.
- `docs/ASSETS.md` — every atlas and path the timeline references.
- `GLOSSARY.md` — the ubiquitous language. Use its terms (lane, mark, now
  line, ready mark, calibration, sink, …) in code and docs. Shared swing and
  secrecy terms are canonical in 4everSwingTimer's glossary.
- `docs/adr/` — decisions that must not be silently reversed.

## Repository layout

- `4everActionTimeline.toc` — manifest. The addon name starts with a digit;
  the saved-variable global is `FourEverActionTimelineDB` and the cross-file
  namespace is the global `FourEverActionTimeline` (valid Lua identifiers).
- `Core.lua` — bootstrap, saved variables, library gate, combat state, slash
  commands.
- `Probes.lua` — the probe verdicts (`Addon.PROBES`); a probe-gated branch
  reads its value here.
- `Util.lua` — the secret guard and drop report, pools, the atlas guard.
- `Settings.lua` — shipped defaults → player layer for the globals.
- `Store.lua` — the event store; `Store:Ingest` is testing seam 1.
- `Layout.lua` — lane registry, lane order, the time axis and the
  orientation (`Layout.orient`: offsets along and across, tex-coord
  turns), each lane's row (`ComputeRows`: the bar shared by every lane
  but the sink lanes, a thin row each for those), and the mark descriptor
  contract every lane's `Collect` follows.
- `Skin.lua` — Native and Flat: atlas names, the per-element atlas
  fallback, the plain icon and its border, the now line, the cast fill's
  atlas regions, the link badge, the axis-turned gradient, the swing
  diamond and its pause glyph.
- `SingleLane.lua` — where each lane's mark descriptors go on the bar
  (Single lane's rules, ADR-0005, on Bar track's geometry, ADR-0006; the
  name is kept from when Single lane was a layout): `Adapt` rewrites one
  in place (glyph, offset across the bar, size, fade, art), the ready
  row's slots and which spells have one, the card stack of overlapping
  icons, the return ring's place.
- `BarTrack.lua` — the bar itself: its body, its
  border cut at the now line and the seconds scale, the ready row's box, the
  scale's ticks and seconds, the now line's second diamond.
- `Effects.lua` — transient effects: reposition pop, correction streak,
  across-lane shake.
- `Sinks.lua` — the engine-drawn sink lanes: a StatusBar fed the secret
  remaining cooldown every frame, the icon a leaf on the fill's edge.
  Never read its geometry back.
- `Renderer.lua` — the timeline frame, pooled widgets (marks, diamonds,
  ticks, bars), the OnUpdate pass, now line, chevron, the cast glow, the
  card stack pass, visibility and the expiry sweep.
- `Classify.lua` — swing-event classification copied from 4everSwingTimer
  (marked for removal once the library reports a reason).
- `Hands.lua` — the hand lanes: library callbacks, landings, predictions,
  presence, icons, the queued swap, effects.
- `Data\<Class>.lua` — curated class data (starter set, GCD reference,
  linked, delayed-start, resets, forms, short cooldowns); field meanings
  in `Data\Warrior.lua`. Warrior, Rogue, Paladin verified in game.
- `Spellbook.lua` — resolves a lane's base spell to the known rank.
- `Calibration.lua` — the calibration cache: learned durations, the cast
  offset, links, delayed-start and stale flags.
- `Gcd.lua` — the GCD lane: window bars, opened only when the engine
  reports a GCD running (a per-class reference spell's `isActive`).
- `Spells.lua` — the spell lanes: predictions, the now-line idle family,
  overdue, linked cooldowns, resets, the calibration report.
- `Casts.lua` — the cast lane: completions, the in-flight now-line icon and
  completion mark, pushback, stopped casts, channels.
- `Options.lua` — the Settings category: proxies over `GetSetting` /
  `SetSetting` (checkbox, slider, dropdown; dropdown options are a
  function), section headers, buttons to the other places and a dependent
  control (ADR-0008).
- `LaneWindow.lua` — `/actiontimeline config`, the spell window in the
  Cooldown Manager's pattern: four sections of icons (Timeline, Long
  cooldowns, Engine lanes, Not displayed), drag between them, a right-click
  menu, search, a layer dropdown, Revert. `SectionOf` and `Drop` hold the
  rules without frames.
- `EditMode.lua` — placement in Edit Mode (EventRegistry callbacks, our own
  copy of Blizzard's selection art, drag, snap, one
  position per Edit Mode layout at the player layer).
- `EditModeDialog.lua` — the settings panel that opens when the timeline is
  clicked in Edit Mode: scale, opacity, length, bar height, past and future window,
  engine lane gap, visibility, orientation, ready row side, skin, GCD style,
  seconds scale, and buttons to the other places.
- `TestMode.lua` — `/actiontimeline test`: fake events and test lanes;
  `test effects`: the swing-event replay (seam 1b).
- `.pkgmeta` — BigWigs packager externals (LibStub, CallbackHandler-1.0, the
  library) and package ignores.
- `docs/`, `GLOSSARY.md` — design; not shipped in the package.

Do not commit `Libs/` or `.release/` — generated and gitignored.

## Conventions

- Tabs for indentation; CRLF line endings.
- Declare every variable `local` — the WoW environment is shared.
- WoW API calls in hot paths (the renderer's OnUpdate) are localized into
  upvalues at the top of the file.
- **Anchor rule:** always `ClearAllPoints()` before `SetPoint` unless the new
  anchor reuses the same anchor *name*. Anchors with different names coexist
  on a region and stretch or collapse it. Never move a scrolling mark with
  `ScriptAnimationUtil.ShakeFrame` — it restores a stale anchor; shake is a
  renderer offset (`docs/VISUAL.md`).
- **Secrets:** check payload values with `issecretvalue` at the event-store
  seam; a secret where plain was expected drops the event and counts it,
  never errors. Never compare or do math on a secret. Secrets may only be
  passed to sinks (`StatusBar:SetValue`, `FontString:SetText`).
- **Honesty rule:** the timeline never invents data. Desaturation means a
  prediction; full color means an engine-verified fact. No combat-log data,
  no proc buffs, no "press this next" output.
- This client (mainline 12.x-era) has **removed many old global functions** —
  `GetSpellCooldown`, `GetItemInfo`, `InterfaceOptions_AddCategory` among
  them. Use the `C_*` namespaces with a nil-guarded fallback, and verify a
  function exists before caching it into an upvalue.
- Guard every atlas with an exists check (`C_Texture.GetAtlasInfo`); a
  missing Native atlas falls back to its Flat equivalent, never an error.

## Settings API constraints (12.x)

- Use `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnCategory`
  with proxy settings. Beyond checkbox, slider and dropdown, build 70338
  has section headers (`CreateSettingsListSectionHeaderInitializer`),
  button rows (`CreateSettingsButtonInitializer`) and dependent controls
  (`initializer:SetParentInitializer`), added through the layout (the
  category call's second return) — no lists, no color pickers.
- The frame's own settings live in the Edit Mode panel, the lane list in the
  spell window, the rest in the Settings category (ADR-0008). Nothing
  dynamic registers in the Settings category.

## Verification

No test suite; verification is in-game on the Forever beta client. Before an
in-game pass: syntax check with `luajit -e "assert(loadfile('file.lua'))"`
(or `luac -p`). Testing seams and the by-eye encoding check: `docs/SPEC.md`,
Testing Decisions.

## Versioning and release

- `## Version` in the `.toc` bumps at release preparation only. Changelog
  entries are written with the change, under `[Unreleased]` in
  `CHANGELOG.md`.
- No release pipeline, remote or platform IDs exist yet. Before the first
  release: add the packaging workflow, the `X-Wago-ID` /
  `X-Curse-Project-ID` TOC lines, and check that the name and the slash
  alias are free.
- Agents must not push, tag or release without explicit instruction.
