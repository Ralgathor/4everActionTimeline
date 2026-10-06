-- 4everActionTimeline — curated class data: Mage (unverified in game).
-- Field meanings: Data\Warrior.lua.

local Addon = FourEverActionTimeline
Addon.ClassData = Addon.ClassData or {}

Addon.ClassData.MAGE = {
	starter = {
		2136, -- Fire Blast
		122, -- Frost Nova
		120, -- Cone of Cold
		1953, -- Blink
	},
	gcdReference = { 133, 168 }, -- Fireball, Frost Armor
	delayedStart = {
		[12043] = true, -- Presence of Mind: starts when consumed
	},
	resets = {
		-- Cold Snap readies the frost spells.
		[12472] = { 122, 120, 11958, 11426, 6143 }, -- Frost Nova, Cone of Cold, Ice Block, Ice Barrier, Frost Ward
	},
}
