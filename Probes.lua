-- 4everActionTimeline — probe verdicts.
-- The in-game probe session (docs/PROBE_SESSION.md, build 70235) decided
-- which reads stay plain in combat. Every probe-gated branch reads this
-- table, so a later build that turns a read secret changes a value here,
-- not the code.

local Addon = FourEverActionTimeline

Addon.PROBES = {
	-- C_Spell.GetSpellCooldown(...).isActive is plain in combat (probe 3).
	-- It also reads true while the GCD runs.
	isActivePlain = true,
	-- C_Spell.IsSpellUsable, both returns, plain in combat (probe 12).
	usablePlain = true,
	-- UnitCastingInfo / UnitChannelInfo end times plain in combat (probe 11).
	castTimePlain = true,
	-- GetShapeshiftFormID plain in combat (probe 15; druid forms accepted at
	-- the gate).
	formPlain = true,
	-- Heroic Strike / Cleave SUCCEEDED fires at the swing it rode (probe 13),
	-- also when that swing is avoided (probe 2).
	onNextSwingAtSwing = true,
	-- Frame placement: ForeverCDM's EventRegistry Edit Mode pattern (probe 9).
	editMode = "eventregistry",
	-- Calling Blizzard's Edit Mode manager from our handlers (ClearSelectedSystem,
	-- CheckHideAndLockEditMode, ShowUIPanel(EditModeManagerFrame)) taints the
	-- raid frames' updates (M10 probes E3, E6, in game, build 70338): none of
	-- it is called. Only post-hooks on it (hooksecurefunc) are used.
	-- GCD lengths in seconds, both measured (probe 10, follow-up G1b).
	gcd = 1.5,
	energyGCD = 1.0,
}
