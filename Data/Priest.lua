-- 4everActionTimeline — curated class data: Priest (unverified in game).
-- Field meanings: Data\Warrior.lua.

local Addon = FourEverActionTimeline
Addon.ClassData = Addon.ClassData or {}

Addon.ClassData.PRIEST = {
	starter = {
		8092, -- Mind Blast
		8122, -- Psychic Scream
		586, -- Fade
	},
	gcdReference = { 585, 2050 }, -- Smite, Lesser Heal
	delayedStart = {
		[14751] = true, -- Inner Focus: starts when consumed
	},
}
