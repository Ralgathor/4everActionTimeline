-- 4everActionTimeline — curated class data: Warrior (verified in game).
-- The shape every Data\<Class>.lua shares (docs/SPEC.md, Cooldown resets
-- and Lane set discovery); all IDs are base (rank 1) spell IDs, resolved to
-- the known rank each session:
--   starter       the 3-5 spells the shipped defaults enable, in lane order
--   gcdReference  GCD-bound spells with no cooldown of their own, in order
--                 of preference (the GCD lane reads the first one known)
--   linked        groups of spells sharing one cooldown (a seed; links
--                 learned in calibration take over)
--   delayedStart  [spell] = true: cooldowns that start when the effect breaks
--                 or is consumed
--   resets        [spell] = { the spells its cast makes ready }
--   forms         [spell] = { the GetShapeshiftFormID values it needs }
--   shortCooldown [spell] = true: real cooldowns no longer than the GCD
--                 (exempt from calibration's GCD-length rejection)
--   long          [spell] = true: a long cooldown whatever its length (it
--                 gets no slot in the ready row; cooldowns of
--                 30 s or more are long anyway)
-- A file may leave out any field it does not use (Addon:ClassInfo
-- supplies an empty one).

local Addon = FourEverActionTimeline
Addon.ClassData = Addon.ClassData or {}

local BATTLE, DEFENSIVE, BERSERKER = 17, 18, 19

Addon.ClassData.WARRIOR = {
	starter = {
		7384, -- Overpower
		6343, -- Thunder Clap
		100, -- Charge
		2687, -- Bloodrage
	},
	gcdReference = { 6673, 772 }, -- Battle Shout, Rend
	linked = {},
	delayedStart = {},
	resets = {},
	forms = {
		[7384] = { BATTLE }, -- Overpower
		[6343] = { BATTLE }, -- Thunder Clap
		[100] = { BATTLE }, -- Charge
		[6572] = { DEFENSIVE }, -- Revenge
		[2565] = { DEFENSIVE }, -- Shield Block
		[1680] = { BERSERKER }, -- Whirlwind
		[20252] = { BERSERKER }, -- Intercept
		[6552] = { BERSERKER }, -- Pummel
		[72] = { BATTLE, DEFENSIVE }, -- Shield Bash
	},
	shortCooldown = {},
}
