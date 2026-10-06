-- 4everActionTimeline — curated class data: Druid (unverified in game).
-- Field meanings: Data\Warrior.lua.

local Addon = FourEverActionTimeline
Addon.ClassData = Addon.ClassData or {}

local CAT, BEAR, DIRE_BEAR = 1, 5, 8

Addon.ClassData.DRUID = {
	starter = {
		5211, -- Bash
		1850, -- Dash
		22812, -- Barkskin
		29166, -- Innervate
	},
	gcdReference = { 5176, 5185 }, -- Wrath, Healing Touch
	delayedStart = {
		[17116] = true, -- Nature's Swiftness: starts when consumed
	},
	forms = {
		[5211] = { BEAR, DIRE_BEAR }, -- Bash
		[5229] = { BEAR, DIRE_BEAR }, -- Enrage
		[16979] = { BEAR, DIRE_BEAR }, -- Feral Charge
		[1850] = { CAT }, -- Dash
		[5217] = { CAT }, -- Tiger's Fury
	},
	shortCooldown = {
		[5217] = true, -- Tiger's Fury (1 s)
	},
}
