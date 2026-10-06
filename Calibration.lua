-- 4everActionTimeline — calibration (docs/SPEC.md, Cooldown marks;
-- ADR-0001). Cooldown predictions come from values read plain out of
-- combat and cached per resolved spell ID in the player layer's own
-- `calibration` sub-table (wiping it never touches the lane set):
--   spells[id] = { duration, stale, delayedStart }
--   links[id]  = { [otherID] = true }  shared cooldowns, learned
--   offset     cooldown start minus SUCCEEDED time (a server round trip,
--              ~-0.2 s), a running average subtracted from predictions
-- Reads come after any out-of-combat cast (settled ~0.3 s later: the first
-- read is the GCD) and at combat end. In combat a cooldown is also measured
-- from the engine: the SUCCEEDED to the instant isActive - plain in combat
-- - turns false (M4 decision, 2026-10-06); a measurement fills a gap or
-- replaces a stale value, never a plain read. A read no longer than the GCD is
-- rejected unless the class data marks the spell short; a read with the
-- cooldown not yet enabled marks a delayed-start spell. Talent changes mark
-- the whole cache stale (still predicting, flagged for a re-read); combat
-- evidence marks single entries stale. The cast-to-cast gap is never cached.

local Addon = FourEverActionTimeline
local Util, Spellbook = Addon.Util, Addon.Spellbook

local GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
local abs, max, min = math.abs, math.max, math.min
local IsSecret = Util.IsSecret

-- How far above the GCD a read must be to count as the spell's own cooldown.
local GCD_MARGIN = 0.1
-- Two reads with starts this close began together (a shared cooldown).
local SAME_START = 0.01
-- The offset is a round trip: keep samples to a sane range.
local OFFSET_MIN, OFFSET_MAX, OFFSET_WEIGHT = -1.0, 0.5, 0.2

local Calibration = {}
Addon.Calibration = Calibration

local function Cache()
	local player = Addon.playerLayer
	player.calibration = player.calibration or { spells = {}, links = {} }
	return player.calibration
end

local function Entry(id, create)
	local spells = Cache().spells
	local entry = spells[id]
	if not entry and create then
		entry = {}
		spells[id] = entry
	end
	return entry
end

function Calibration:Entry(id)
	return Entry(id)
end

function Calibration:Offset()
	return Cache().offset or 0
end

-- A plain cooldown read, or nil when unavailable or any field is secret.
function Calibration:Read(id)
	local info = GetSpellCooldown and GetSpellCooldown(id)
	if not info then
		return nil
	end
	if IsSecret(info.startTime) or IsSecret(info.duration) or IsSecret(info.isActive) or IsSecret(info.isEnabled) then
		return nil
	end
	return info
end

-- The cooldown's isActive and isEnabled flags, from one read: plain in
-- combat (probe 3; isActive also reads true during the GCD), unlike its
-- start and duration. Each is nil when unavailable or secret; the third
-- return is true when isActive was secret (for the caller's drop count).
function Calibration:Flags(id)
	local info = GetSpellCooldown and GetSpellCooldown(id)
	if not info then
		return nil, nil, false
	end
	local active, enabled = info.isActive, info.isEnabled
	local secret = active ~= nil and IsSecret(active)
	if secret then
		active = nil
	end
	if enabled ~= nil and IsSecret(enabled) then
		enabled = nil
	end
	return active, enabled, secret
end

-- A read no longer than the GCD is the GCD, not the spell's own cooldown -
-- unless the class data marks the spell that short.
local function IsGcdOnly(base, duration)
	return duration <= Addon.Gcd:Length() + GCD_MARGIN and not Addon:ClassInfo().shortCooldown[base]
end

-- Learns from a plain read of spell id (base: its lane's base ID, for the
-- class data). castAt is the SUCCEEDED instant when the read follows a
-- cast. Returns "delayed", "learned", or nil (nothing learned).
function Calibration:Learn(id, base, info, castAt)
	if info.isEnabled == false then
		Entry(id, true).delayedStart = true
		return "delayed"
	end
	if not info.isActive then
		return nil
	end
	if IsGcdOnly(base, info.duration) then
		return nil
	end
	local entry = Entry(id, true)
	entry.duration, entry.stale, entry.delayedStart, entry.measured = info.duration, nil, nil, nil
	if castAt then
		local sample = min(max(info.startTime - castAt, OFFSET_MIN), OFFSET_MAX)
		local cache = Cache()
		cache.offset = cache.offset and cache.offset + (sample - cache.offset) * OFFSET_WEIGHT or sample
	end
	return "learned"
end

-- A cooldown measured in combat (cast to isActive false). Learned only when
-- longer than the GCD (a shorter end hides behind it) and when no plain
-- read already holds a current value. Returns true when learned.
function Calibration:LearnMeasured(id, base, duration)
	if IsGcdOnly(base, duration) then
		return false
	end
	local entry = Entry(id, true)
	if entry.duration and not entry.measured and not entry.stale then
		return false
	end
	entry.duration, entry.measured, entry.stale = duration, true, nil
	return true
end

-- After a learned read of id: every other id whose cooldown started at the
-- same instant with the same duration shares it.
function Calibration:LearnLinks(id, info, others)
	local links = Cache().links
	for _, other in ipairs(others) do
		if other ~= id then
			local read = self:Read(other)
			if read and read.isActive and abs(read.startTime - info.startTime) < SAME_START and abs(read.duration - info.duration) < SAME_START then
				links[id] = links[id] or {}
				links[other] = links[other] or {}
				links[id][other], links[other][id] = true, true
			end
		end
	end
end

function Calibration:Links(id)
	return Cache().links[id]
end

function Calibration:MarkStale(id)
	local entry = Entry(id)
	if entry and entry.duration then
		entry.stale = true
	end
end

-- The player's talent ranks as one string, or nil when unreadable.
local function TalentSignature()
	local GetNumTalentTabs, GetNumTalents, GetTalentInfo = GetNumTalentTabs, GetNumTalents, GetTalentInfo
	if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then
		return nil
	end
	local ranks = {}
	for tab = 1, GetNumTalentTabs() or 0 do
		for index = 1, GetNumTalents(tab) or 0 do
			local rank = select(5, GetTalentInfo(tab, index))
			if rank == nil or IsSecret(rank) then
				return nil
			end
			ranks[#ranks + 1] = rank
		end
	end
	return table.concat(ranks, ",")
end

-- True when the talent ranks differ from the last ones seen (unreadable
-- talents count as changed). The first reading only records them. Kept in
-- the player layer beside the cache, so a calibration wipe keeps it.
function Calibration:TalentsChanged()
	local signature = TalentSignature()
	local player = Addon.playerLayer
	local previous = player.talents
	player.talents = signature
	if signature == nil then
		return true
	end
	return previous ~= nil and previous ~= signature
end

function Calibration:MarkAllStale()
	for _, entry in pairs(Cache().spells) do
		if entry.duration then
			entry.stale = true
		end
	end
end

-- Drops entries for spell IDs no longer known (a retired rank).
function Calibration:Prune()
	local cache = Cache()
	for id in pairs(cache.spells) do
		if not Spellbook.IsKnown(id) then
			cache.spells[id] = nil
		end
	end
	for id in pairs(cache.links) do
		if not Spellbook.IsKnown(id) then
			cache.links[id] = nil
		end
	end
end

function Calibration:Wipe()
	Addon.playerLayer.calibration = nil
end
