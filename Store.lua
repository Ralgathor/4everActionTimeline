-- 4everActionTimeline — the event store.
-- A capped queue of happened entries {time, kind, lane, spellID, icon, ...},
-- fed only through Store:Ingest: seam 1 of the testing seams
-- (docs/SPEC.md, Testing Decisions). Every value is checked for secrecy here;
-- a secret drops the whole entry and counts it, never an error. Entries
-- expire past the past window plus a margin, and the cap backstops bursts.
-- An entry also keeps an unrendered `outcome` slot for a future outcome API.

local Addon = FourEverActionTimeline
local Util = Addon.Util

local IsSecret, CountDrop = Util.IsSecret, Util.CountDrop
local pairs, type = pairs, type

local CAP = 512

local Store = {}
Addon.Store = Store

local entries, first, last = {}, 1, 0
-- Per-lane change counters: the renderer rebuilds a lane only when its own
-- entries changed.
local laneVersions = {}

function Store:LaneVersion(key)
	return laneVersions[key] or 0
end

-- Returns true when the entry was kept. `kind` and `lane` are the addon's
-- own strings, never payload values, so they are safe to count by.
function Store:Ingest(entry)
	for _, value in pairs(entry) do
		if IsSecret(value) then
			CountDrop(entry.kind or "?")
			return false
		end
	end
	if type(entry.time) ~= "number" or not entry.lane then
		CountDrop("malformed")
		return false
	end
	last = last + 1
	entries[last] = entry
	if last - first + 1 > CAP then
		entries[first] = nil
		first = first + 1
	end
	laneVersions[entry.lane] = (laneVersions[entry.lane] or 0) + 1
	return true
end

-- Drops entries older than tMin. Entries arrive in time order, so the
-- oldest sit at the front. Each lane that lost an entry rebuilds once.
function Store:Prune(tMin)
	while first <= last and entries[first].time < tMin do
		local lane = entries[first].lane
		laneVersions[lane] = laneVersions[lane] + 1
		entries[first] = nil
		first = first + 1
	end
end

-- The live entries, oldest first: loop `for i = first, last do entries[i]`.
-- No iterator closure, so collectors can run on every rebuild for free.
function Store:Range()
	return entries, first, last
end

-- The newest entry, or nil.
function Store:Latest()
	return entries[last]
end

function Store:RemoveWhere(predicate)
	local kept = {}
	for i = first, last do
		local entry = entries[i]
		if not predicate(entry) then
			kept[#kept + 1] = entry
		end
	end
	entries, first, last = kept, 1, #kept
	for key, version in pairs(laneVersions) do
		laneVersions[key] = version + 1
	end
end

