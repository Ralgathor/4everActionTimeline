-- 4everActionTimeline — shared helpers: the secret guard and its drop
-- counters, widget pools, and the atlas guard.

local Addon = FourEverActionTimeline
local Util = {}
Addon.Util = Util

local issecretvalue = issecretvalue
local GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
local format, next, pairs, pcall, setmetatable, sort, concat, remove =
	format, next, pairs, pcall, setmetatable, table.sort, table.concat, table.remove

-- ---------------------------------------------------------------------------
-- Secret guard
-- ---------------------------------------------------------------------------

-- Test mode cannot make a real secret, so it emits this sentinel; the guard
-- treats it exactly like one, which drives the real drop-and-report path.
Util.TEST_SECRET = setmetatable({}, { __tostring = function() return "<test secret>" end })
local TEST_SECRET = Util.TEST_SECRET

-- True for a secret value. issecretvalue runs first, so a real secret is
-- never compared with anything.
function Util.IsSecret(value)
	if issecretvalue and issecretvalue(value) then
		return true
	end
	return value == TEST_SECRET
end

local drops = {}

function Util.CountDrop(kind)
	drops[kind] = (drops[kind] or 0) + 1
end

-- Reported once, after combat (or when test mode ends), never mid-fight.
function Util.ReportDrops()
	if not next(drops) then
		return
	end
	local parts, total = {}, 0
	for kind, count in pairs(drops) do
		parts[#parts + 1] = kind .. " " .. count
		total = total + count
	end
	sort(parts)
	Addon:Print(format("skipped %d event(s) that carried an unreadable (secret) value: %s. Nothing broke; please report it together with /actiontimeline status.",
		total, concat(parts, ", ")))
	wipe(drops)
end

-- ---------------------------------------------------------------------------
-- Pools
-- ---------------------------------------------------------------------------

-- A pool reused in place for each rebuild: Take hands back the objects of
-- the previous pass in order (keeping their configured state, so unchanged
-- settings cost nothing), and Trim releases whatever the new pass did not
-- take. `used` is exactly what the last pass placed. (Blizzard's object
-- pools release on reuse, which would drop that configured state.)
local PoolMixin = {}

function PoolMixin:BeginReuse()
	self.cursor = 0
end

function PoolMixin:Take()
	local cursor = self.cursor + 1
	self.cursor = cursor
	local object = self.used[cursor]
	if not object then
		object = remove(self.free) or self.create()
		self.used[cursor] = object
	end
	return object
end

function PoolMixin:Trim()
	local used, free, reset = self.used, self.free, self.reset
	for i = #used, self.cursor + 1, -1 do
		local object = used[i]
		used[i] = nil
		reset(object)
		free[#free + 1] = object
	end
end

function Util.NewPool(create, reset)
	return setmetatable({ create = create, reset = reset, free = {}, used = {} }, { __index = PoolMixin })
end

-- ---------------------------------------------------------------------------
-- Atlas guard
-- ---------------------------------------------------------------------------

-- Every atlas is checked once before use; a missing one falls back to the
-- Flat equivalent at the call site, never an error.
local atlasKnown = {}

function Util.AtlasExists(name)
	local known = atlasKnown[name]
	if known == nil then
		known = false
		if GetAtlasInfo then
			local ok, info = pcall(GetAtlasInfo, name)
			known = ok and info ~= nil
		end
		atlasKnown[name] = known
	end
	return known
end

-- ---------------------------------------------------------------------------
-- Color
-- ---------------------------------------------------------------------------

-- The grey a color desaturates to (luma weights), for flat-color glyphs
-- that cannot use Texture:SetDesaturated.
function Util.Gray(r, g, b)
	local l = 0.299 * r + 0.587 * g + 0.114 * b
	return l, l, l
end
