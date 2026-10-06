# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project overview

4everActionTimeline is a standalone addon for **WoW: Forever only**
(interface 16000+, currently `## Interface: 16001`) that draws a live timeline
of the player's actions around a now line: swing lanes (main-hand, off-hand,
ranged), the GCD, the player's casts, and one lane per tracked spell's
cooldown. Happened marks sit on the past side of the now line, predicted
marks on the future side (which side is which follows the orientation).

Status: **M2, hand lanes** — the event store, the renderer (Flat skin,
horizontal), test mode, and live main-hand, off-hand and ranged lanes with
their effects. Cast and GCD lanes arrive in M3.
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
- `Layout.lua` — lane registry, lane order, the time axis, and the mark
  descriptor contract every lane's `Collect` follows.
- `Effects.lua` — transient effects: reposition pop, correction streak,
  across-lane shake.
- `Renderer.lua` — the timeline frame, pooled widgets, the OnUpdate pass,
  visibility and the expiry sweep.
- `Classify.lua` — swing-event classification copied from 4everSwingTimer
  (marked for removal once the library reports a reason).
- `Hands.lua` — the hand lanes: library callbacks, landings, predictions,
  presence, icons, the queued swap, effects.
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
  with proxy settings. The vertical layout supports checkbox, slider and
  dropdown only — no buttons, no lists, no color pickers.
- Globals live in the Settings category; the lane list (per-spell enable,
  sink opt-in, manual override, drag order) lives in the addon's own
  settings window. Nothing dynamic registers in the Settings category.

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
