# Inferred cooldown marks with an opt-in engine-drawn overlay

Status: accepted (2026-10-05). Founding research:
`docs/Forever Combat Timeline.md`.

On WoW: Forever, `C_Spell.GetSpellCooldown` returns secret values in combat,
and no API reports a base cooldown for a ready spell, so a timeline cannot
read true cooldown numbers where it needs them. Out of combat the values turn
plain, and a secret fed to `StatusBar:SetValue` draws correctly while staying
unreadable to Lua (proven on build 70205, 2026-10-05). We therefore infer
every cooldown mark from the cast event plus a calibration cache — a plain
value read out of combat on `PLAYER_REGEN_ENABLED` (spells just used are on
cooldown and plain), on demand via `/calibrate`, or manually overridden per
spell — and keep the engine-drawn StatusBar sink as an opt-in per-lane
overlay, never the foundation: the sink is display-only, linear-scale and
Lua-blind (no overlap avoidance, no hide-on-complete), while inferred marks
are fully renderable and configurable. Uncalibrated spells draw happened
marks only, honestly, rather than falling back to the sink in v1.

## Considered options

- Sink-only (all cooldown marks engine-drawn): rejected — the sink's
  display-only constraints would then shape the whole renderer, and Lua
  cannot even hide a finished icon.
- Inference-only (drop the sink): rejected — the sink is the only
  always-true source and the only future mark for spells the cache has
  missed; it is already proven in a dungeon.

## Consequences

Two renderer code paths: readable pooled marks, plus optional sink lanes.
Calibration can go stale if a base cooldown changes (the "base cooldowns
ignore talents" claim is itself probe-listed); mitigations: combat-end
re-read, per-spell manual override, sink overlay. A future Cooldown Manager
mirror can sharpen accuracy without changing this foundation.
