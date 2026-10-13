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
	-- Seconds on the past and future side of the now line (ADR-0006: the bar
	-- reads what is coming, so the past is short).
	pastWindow = 1.5,
	futureWindow = 10,
	-- The ready row's slots end at the now line ("past") or start at it ("future").
	readyRowSide = "past",
	width = 700, -- pixels along the time axis; the time scale follows from it
	laneHeight = 26, -- pixels: the bar's height
	laneSpacing = 4, -- between the bar and each engine-drawn lane's row
	scale = 1.0,
	opacity = 1.0, -- the whole frame (the boss timeline's Edit Mode Transparency)
	visibility = "combat", -- "combat" | "always" | "active"
	skin = "native", -- "native" | "flat" (VISUAL.md, Skins)
	-- "horizontal" (past left) | "horizontalFlipped" | "vertical" (past at
	-- the bottom) | "verticalFlipped"
	orientation = "horizontal",
	-- The GCD as a "tint" of the bar's body or a "strip" along its far edge;
	-- the seconds scale (cuts and ticks at 1, 3 and 5 s).
	barGcd = "tint",
	barScale = false,
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

-- The past and future window, in seconds.
function Addon:GetWindow()
	return self:GetSetting("pastWindow"), self:GetSetting("futureWindow")
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
	resets = EMPTY, forms = EMPTY, shortCooldown = EMPTY, long = EMPTY,
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

-- A per-spell lane value: enabled (boolean) or override (seconds, or nil),
-- as layer `from` sees it: "player" (the default) is what this character
-- gets, "class" what the class layer and the shipped defaults give.
function Addon:GetLaneValue(id, key, from)
	return Resolve(self, from or "player", id, key)
end

local laneSetListeners = {}

-- fn runs whenever the lane set changes.
function Addon:OnLaneSetChanged(fn)
	laneSetListeners[#laneSetListeners + 1] = fn
end

local function Notify()
	for _, fn in ipairs(laneSetListeners) do
		fn()
	end
end

-- True when the layer itself stores anything for the spell.
function Addon:LayerHasSpell(layerName, id)
	local layer = Layer(self, layerName)
	local spells = layer and layer.lanes and layer.lanes.spells
	return spells and spells[id] ~= nil
end

-- Stores a layer's lane order (a player order replaces the class order whole).
function Addon:SetLaneOrder(layerName, order)
	local layer = Layer(self, layerName)
	if not layer then
		return
	end
	layer.lanes = layer.lanes or {}
	layer.lanes.order = order
	Notify()
end

-- "Reset to class": deletes this character's lane settings and order.
function Addon:ResetPlayerLanes()
	if self.playerLayer then
		self.playerLayer.lanes = nil
		Notify()
	end
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
	Notify()
end

-- The lane set's base ID for a spell argument (an ID or a name, any rank): a
-- curated or tracked spell of the class matched by name, else the spell as
-- given. Returns the base ID and the spell's name, or nil.
function Addon:LaneBaseFor(text)
	local id, name = self.Spellbook.FromArgument(text)
	if not id then
		return nil
	end
	return self:LaneBasesByName()[name] or id, name
end

-- Spell name -> lane base ID for the class's curated and tracked spells
-- (the first match wins: starter set, then `order`, default the lane
-- order), so any rank of a curated spell keeps its curated base ID.
function Addon:LaneBasesByName(order)
	local bases = {}
	for _, list in ipairs({ self:ClassInfo().starter, order or self:LaneOrder() }) do
		for _, base in ipairs(list) do
			local name = self.Spellbook.Name(base)
			if name and not bases[name] then
				bases[name] = base
			end
		end
	end
	return bases
end

-- The lane order as seen from layer `from` ("player", the default, or
-- "class"): the player's order, else the class's, else the starter set's; a
-- spell stored at a walked layer but missing from it is appended. The second
-- return is the set of class-layer spells appended to the player's own
-- order - flagged "new" in the lane window.
function Addon:LaneOrder(from)
	local playerLanes = from ~= "class" and self.playerLayer and self.playerLayer.lanes or nil
	local classLanes = self.classLayer and self.classLayer.lanes
	local own = playerLanes and playerLanes.order
	local base = own or (classLanes and classLanes.order) or self:ClassInfo().starter
	local order, seen, new = {}, {}, {}
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
				new[id] = own and lanes == classLanes or nil
			end
		end
	end
	table.sort(extra)
	for _, id in ipairs(extra) do
		order[#order + 1] = id
	end
	return order, new
end
