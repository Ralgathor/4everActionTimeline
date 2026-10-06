-- 4everActionTimeline — settings resolution.
-- The Settings-category globals resolve shipped defaults -> player layer
-- (docs/SPEC.md, Storage model). The lane set resolves through three layers
-- (ADR-0002): shipped defaults (the class data's starter set) -> class layer
-- (shared by every character of the class) -> player layer (this
-- character's overrides). Every layer stores only what differs from the
-- layers below it, so a release that improves a default reaches everyone
-- who never changed it.

local Addon = FourEverActionTimeline

local DEFAULTS = {
	pastWindow = 5, -- seconds left of the now line
	futureWindow = 5, -- seconds right of the now line
	width = 420, -- pixels; the time scale follows from it
	laneHeight = 26, -- pixels; icons are laneHeight - 2
	laneSpacing = 4,
	scale = 1.0,
	visibility = "combat", -- "combat" | "always" | "active"
	backgroundAlpha = 0, -- a faint band behind each lane
	-- Per-hand lane toggles; a lane also needs the weapon equipped.
	showMainhand = true,
	showOffhand = true,
	showRanged = true,
	showCasts = true,
	showGcd = true,
	-- GCD length: "auto" (by power type: 1.0 s for energy users, else 1.5 s,
	-- both measured), "1.5", "1.0" or "custom" (gcdCustom, 0.5-2.0 s).
	gcdOverride = "auto",
	gcdCustom = 1.5,
	-- The sink icon shows the engine's own countdown (the true remaining time).
	sinkCountdown = false,
}
Addon.DEFAULTS = DEFAULTS

function Addon:GetSetting(key)
	local layer = self.playerLayer and self.playerLayer.settings
	local value = layer and layer[key]
	if value == nil then
		value = DEFAULTS[key]
	end
	return value
end

function Addon:SetSetting(key, value)
	assert(DEFAULTS[key] ~= nil, "unknown setting " .. tostring(key))
	local player = self.playerLayer
	if not player then
		return
	end
	player.settings = player.settings or {}
	if value == DEFAULTS[key] then
		value = nil
	end
	player.settings[key] = value
	if self.Renderer then
		self.Layout:RefreshPresence()
		self.Renderer:MarkLayoutDirty()
		self.Renderer:UpdateVisibility()
	end
end

-- ---------------------------------------------------------------------------
-- The lane set: <layer>.lanes = { spells = { [baseID] = { enabled, override } }, order = { baseIDs } }
-- ---------------------------------------------------------------------------

local EMPTY = {}
-- Every class data field, empty when a class file leaves it out.
local CLASS_DEFAULTS = {
	starter = EMPTY, gcdReference = EMPTY, linked = EMPTY, delayedStart = EMPTY,
	resets = EMPTY, forms = EMPTY, shortCooldown = EMPTY,
}
local DEFAULTED = { __index = CLASS_DEFAULTS }
local NO_CLASS = setmetatable({}, DEFAULTED)

-- The class's curated data (Data\<Class>.lua), every field present.
function Addon:ClassInfo()
	local info = self.ClassData and self.ClassData[self.classToken]
	if not info then
		return NO_CLASS
	end
	if not getmetatable(info) then
		setmetatable(info, DEFAULTED)
	end
	return info
end

local starterSets = {} -- classToken -> { [baseID] = true }

local function StarterSet(self)
	local set = starterSets[self.classToken]
	if not set then
		set = {}
		for _, id in ipairs(self:ClassInfo().starter) do
			set[id] = true
		end
		starterSets[self.classToken] = set
	end
	return set
end

local function Layer(self, name)
	return name == "class" and self.classLayer or self.playerLayer
end

local function SpellValue(layer, id, key)
	local lanes = layer and layer.lanes
	local spell = lanes and lanes.spells and lanes.spells[id]
	if spell then
		return spell[key]
	end
end

-- The value resolved from layer `from` down: "player" walks player, class,
-- shipped; "class" walks class, shipped; nil walks shipped only.
local function Resolve(self, from, id, key)
	local walking = false
	for _, name in ipairs({ "player", "class" }) do
		walking = walking or name == from
		if walking then
			local value = SpellValue(Layer(self, name), id, key)
			if value ~= nil then
				return value
			end
		end
	end
	if key == "enabled" then
		return StarterSet(self)[id] or false
	end
	return nil
end

-- A per-spell lane value: enabled (boolean) or override (seconds, or nil).
function Addon:GetLaneValue(id, key)
	return Resolve(self, "player", id, key)
end

local laneSetListeners = {}

-- fn runs whenever the lane set changes.
function Addon:OnLaneSetChanged(fn)
	laneSetListeners[#laneSetListeners + 1] = fn
end

-- Sets a per-spell value at the "class" or "player" layer; a value equal to
-- what the layers below already give is deleted instead of stored.
function Addon:SetLaneValue(layerName, id, key, value)
	local layer = Layer(self, layerName)
	if not layer then
		return
	end
	-- Off and unset are the same for a flag (sink has no shipped value).
	local below = Resolve(self, layerName == "player" and "class" or nil, id, key)
	if value == below or not (value or below) then
		value = nil
	end
	layer.lanes = layer.lanes or {}
	layer.lanes.spells = layer.lanes.spells or {}
	local spells = layer.lanes.spells
	local spell = spells[id] or {}
	spell[key] = value
	spells[id] = next(spell) and spell or nil
	for _, fn in ipairs(laneSetListeners) do
		fn()
	end
end

-- The lane set's base ID for a spell argument (an ID or a name, any rank): a
-- curated or tracked spell of the class matched by name, else the spell as
-- given. Returns the base ID and the spell's name, or nil.
function Addon:LaneBaseFor(text)
	local id, name = self.Spellbook.FromArgument(text)
	if not id then
		return nil
	end
	for _, list in ipairs({ self:ClassInfo().starter, self:LaneOrder() }) do
		for _, base in ipairs(list) do
			if base == id or self.Spellbook.Name(base) == name then
				return base, name
			end
		end
	end
	return id, name
end

-- The lane order: the player's order, else the class's, else the starter
-- set's; a spell enabled at any layer but missing from it is appended (a
-- class-layer addition reaches a character with its own order).
function Addon:LaneOrder()
	local playerLanes, classLanes = self.playerLayer and self.playerLayer.lanes, self.classLayer and self.classLayer.lanes
	local base = (playerLanes and playerLanes.order) or (classLanes and classLanes.order) or self:ClassInfo().starter
	local order, seen = {}, {}
	for _, id in ipairs(base) do
		if not seen[id] then
			order[#order + 1], seen[id] = id, true
		end
	end
	local extra = {}
	for _, lanes in ipairs({ classLanes or EMPTY, playerLanes or EMPTY }) do
		for id in pairs(lanes.spells or EMPTY) do
			if not seen[id] then
				extra[#extra + 1], seen[id] = id, true
			end
		end
	end
	table.sort(extra)
	for _, id in ipairs(extra) do
		order[#order + 1] = id
	end
	return order
end
