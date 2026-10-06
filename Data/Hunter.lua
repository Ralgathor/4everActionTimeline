-- 4everActionTimeline — curated class data: Hunter (unverified in game).
-- Field meanings: Data\Warrior.lua.

local Addon = FourEverActionTimeline
Addon.ClassData = Addon.ClassData or {}

Addon.ClassData.HUNTER = {
	starter = {
		3044, -- Arcane Shot
		2643, -- Multi-Shot
		5116, -- Concussive Shot
		3045, -- Rapid Fire
	},
	gcdReference = { 1978, 13163 }, -- Serpent Sting, Aspect of the Monkey
	linked = {
		-- The traps share one cooldown.
		{ 1499, 13795, 13809, 13813 }, -- Freezing, Immolation, Frost, Explosive Trap
	},
}
