-- 4everActionTimeline — curated class data: Shaman (unverified in game).
-- Field meanings: Data\Warrior.lua.

local Addon = FourEverActionTimeline
Addon.ClassData = Addon.ClassData or {}

Addon.ClassData.SHAMAN = {
	starter = {
		8042, -- Earth Shock
		8050, -- Flame Shock
		8056, -- Frost Shock
		8177, -- Grounding Totem
	},
	gcdReference = { 403, 331 }, -- Lightning Bolt, Healing Wave
	linked = {
		-- The shocks share one cooldown.
		{ 8042, 8050, 8056 },
	},
	delayedStart = {
		[16188] = true, -- Nature's Swiftness: starts when consumed
		[16166] = true, -- Elemental Mastery: starts when consumed
	},
}
