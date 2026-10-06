-- 4everActionTimeline — curated class data: Rogue (verified in game).
-- Field meanings: Data\Warrior.lua.

local Addon = FourEverActionTimeline
Addon.ClassData = Addon.ClassData or {}

Addon.ClassData.ROGUE = {
	starter = {
		1776, -- Gouge
		1766, -- Kick
		408, -- Kidney Shot
		5277, -- Evasion
		2983, -- Sprint
	},
	gcdReference = { 1752 }, -- Sinister Strike
	delayedStart = {
		[1784] = true, -- Stealth: starts when Stealth breaks (probe session)
		[14177] = true, -- Cold Blood: starts when consumed
	},
	resets = {
		-- Preparation readies the other rogue cooldowns.
		[14185] = { 5277, 2983, 1856, 1766, 1776, 408, 2094, 14177, 14183, 1966 },
	},
}
