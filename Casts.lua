-- 4everActionTimeline — the cast lane (docs/SPEC.md, Cast lane).
-- Happened marks are cast completions, instants included: full color, the
-- spell's icon, meaning "cast completed", never "landed". The in-flight
-- cast or channel rides the now line at full color (the now-line icon) with
-- a predicted mark at its expected end: full color when the live
-- UnitCastingInfo / UnitChannelInfo end time is plain (probe 11), else
-- desaturated from the cast time learned out of combat. Pushback moves that
-- mark with an amber pop. A started cast that stops, fails or is
-- interrupted leaves a red-bordered mark at the stop instant (flash and
-- across-lane shake) while its predicted mark pops red and vanishes; a
-- refused press (FAILED with no START) leaves nothing. A channel stopping
-- more than 0.2 s before its known end is red; without a known end it is a
-- normal completion. Every player cast appears except auto-repeat spells
-- (the ranged lane shows them) and the hand lanes' own spells
-- (on-next-swing abilities ride the main hand; the Attack toggle).
--
-- This module owns the player's spellcast events: it feeds the GCD lane
-- (which works whether or not the cast lane is shown), every SUCCEEDED to
-- the spell lanes, and on-next-swing SUCCEEDEDs to the hand lanes.

local Addon = FourEverActionTimeline
local Util, Layout, Store, Renderer, Effects, Hands =
	Addon.Util, Addon.Layout, Addon.Store, Addon.Renderer, Addon.Effects, Addon.Hands

local GetTime = GetTime
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local IsAutoRepeatSpell = C_Spell and C_Spell.IsAutoRepeatSpell
local InCombatLockdown = InCombatLockdown
local IsSecret = Util.IsSecret

-- A channel ending more than this before its expected end was cut short.
local CHANNEL_EARLY = 0.2
-- A cast still "in flight" this long after its expected end (or, with no
-- known end, after its start) reported no end event: dropped silently -
-- the timeline does not guess how it ended.
local STALE_AFTER_END, STALE_NO_END, SWEEP_INTERVAL = 1.0, 60, 0.5
-- Never cast-lane marks: the auto-repeat shots (a fallback for clients
-- without C_Spell.IsAutoRepeatSpell) and the login visual.
local EXCLUDED = {
	[75] = true, -- Auto Shot
	[5019] = true, -- Shoot (wand)
	[836] = true, -- LOGINEFFECT
}

local Casts = {}
Addon.Casts = Casts

local lane = { key = "cast", group = "cast", order = 1, setting = "showCasts" }
local cast -- the in-flight cast or channel
local castTimes = {} -- learned out of combat: spellID -> seconds (SUCCEEDED - START)
local pendingInstant -- an instant's mark, held to the end of its frame

function lane:Collect(now, out)
	Layout.CollectHappened(self, now, out)
	if cast then
		if cast.finish and Layout.castBars then
			-- Single lane: the cast is a bar from its start to its completion.
			out[#out + 1] = { shape = "bar", tStart = cast.start, tEnd = cast.finish, channel = cast.channel }
		else
			out[#out + 1] = { atNow = true, icon = cast.icon }
		end
		if cast.finish then
			out[#out + 1] = { t = cast.finish, icon = cast.icon, predicted = true, desaturated = not cast.live }
		end
	end
end

function lane:IsActive()
	return cast ~= nil
end

local function Excluded(spellID)
	return EXCLUDED[spellID] or (IsAutoRepeatSpell and IsAutoRepeatSpell(spellID)) or Hands.OwnsSpell(spellID)
end

-- The live end time (seconds), or nil when unavailable or secret.
local function LiveEnd(channel)
	local read = channel and UnitChannelInfo or UnitCastingInfo
	if not (read and Addon.PROBES.castTimePlain) then
		return nil
	end
	local _, _, texture, _, endMS = read("player")
	if endMS == nil or IsSecret(endMS) then
		return nil, texture
	end
	return endMS / 1000, texture
end

local function Icon(spellID, texture)
	if texture and not IsSecret(texture) then
		return texture
	end
	return Addon.Spellbook.Icon(spellID)
end

-- Marks only while the lane is shown; the GCD lane is fed regardless.
local function Ingest(entry)
	if lane.registered then
		entry.lane = lane.key
		Store:Ingest(entry)
		Renderer:MarkDirty(lane)
	end
end

-- Same cast: by GUID when both are readable, else by spell.
local function Matches(guid, spellID)
	if not cast then
		return false
	end
	if guid and cast.guid and not IsSecret(guid) then
		return guid == cast.guid
	end
	return spellID == cast.spellID
end

local function Begin(guid, spellID, channel)
	local now = GetTime()
	local finish, texture = LiveEnd(channel)
	local live = finish ~= nil
	if not live and not channel and castTimes[spellID] then
		finish = now + castTimes[spellID]
	end
	cast = {
		guid = not IsSecret(guid) and guid or nil,
		spellID = spellID,
		icon = Icon(spellID, texture),
		start = now,
		finish = finish,
		live = live,
		channel = channel,
	}
	Renderer:MarkDirty(lane)
end

-- The in-flight cast completed (or the channel ran to its end).
local function Complete(now)
	Ingest({ kind = "cast", time = now, icon = cast.icon, castStart = cast.start, channel = cast.channel })
	cast = nil
	Renderer:MarkDirty(lane)
end

-- A started cast or channel that did not complete: red mark at the stop
-- instant (flash, shake); the predicted mark pops red and vanishes; the GCD
-- it began may be cleared.
local function Fail(now)
	Ingest({ kind = "cast-stop", time = now, icon = cast.icon, border = "red", shake = Effects:Shake(lane), castStart = cast.start, channel = cast.channel })
	Effects:Pop(lane, now, Effects.RED)
	if cast.finish then
		Effects:Pop(lane, cast.finish, Effects.RED)
	end
	Addon.Gcd:OnCastStopped(now)
	cast = nil
	Renderer:MarkDirty(lane)
end

-- Pushback (DELAYED) or channel shortening (CHANNEL_UPDATE): the live end
-- moved; a calibration-fed mark stays put and the completion corrects it.
local function Reposition()
	if not (cast and cast.live) then
		return
	end
	local finish = LiveEnd(cast.channel)
	if finish and finish ~= cast.finish then
		Effects:Correct(lane, cast.finish, finish, Effects.AMBER)
		cast.finish = finish
		Renderer:MarkDirty(lane)
	end
end

local handlers = {}

function handlers.UNIT_SPELLCAST_START(guid, spellID)
	if Excluded(spellID) then
		return
	end
	Begin(guid, spellID, false)
	-- A cast-time spell's GCD starts with the cast.
	Addon.Gcd:OnCast(cast.start)
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(guid, spellID)
	-- Spell lanes track every cast with a cooldown, on-next-swing ones too.
	Addon.Spells:OnSucceeded(spellID, GetTime())
	if Hands.IsOnNextSwing(spellID) then
		Hands:OnSpellSucceeded(spellID)
		return
	end
	if Excluded(spellID) then
		return
	end
	local now = GetTime()
	if cast and not cast.channel and Matches(guid, spellID) then
		if not (InCombatLockdown and InCombatLockdown()) then
			castTimes[spellID] = now - cast.start
		end
		Complete(now)
		return
	end
	-- An instant (an in-flight cast is left alone); its GCD, if it has one,
	-- starts now. Its mark waits for the end of the frame: a channel's own
	-- SUCCEEDED arrives in the same frame as its CHANNEL_START, and the
	-- channel's mark belongs at its end.
	local held = { kind = "cast", time = now, icon = Icon(spellID) }
	pendingInstant = held
	C_Timer.After(0, function()
		if pendingInstant == held then
			pendingInstant = nil
			Ingest(held)
		end
	end)
	Addon.Gcd:OnCast(now)
end

local function Stopped(guid, spellID)
	if cast and not cast.channel and Matches(guid, spellID) then
		Fail(GetTime())
	end
end

handlers.UNIT_SPELLCAST_STOP = Stopped
handlers.UNIT_SPELLCAST_FAILED = Stopped
handlers.UNIT_SPELLCAST_INTERRUPTED = Stopped

function handlers.UNIT_SPELLCAST_DELAYED(guid, spellID)
	if Matches(guid, spellID) then
		Reposition()
	end
end

function handlers.UNIT_SPELLCAST_CHANNEL_START(guid, spellID)
	if Excluded(spellID) then
		return
	end
	pendingInstant = nil -- the channel's own SUCCEEDED, this frame
	Begin(guid, spellID, true)
end

function handlers.UNIT_SPELLCAST_CHANNEL_UPDATE()
	if cast and cast.channel then
		Reposition()
	end
end

function handlers.UNIT_SPELLCAST_CHANNEL_STOP()
	if not (cast and cast.channel) then
		return
	end
	local now = GetTime()
	if cast.live and cast.finish and now < cast.finish - CHANNEL_EARLY then
		Fail(now)
	else
		Complete(now)
	end
end

local function Sweep()
	if not cast then
		return
	end
	local now = GetTime()
	if (cast.finish and now > cast.finish + STALE_AFTER_END) or (not cast.finish and now - cast.start > STALE_NO_END) then
		cast = nil
		Renderer:MarkDirty(lane)
	end
end

Layout:DeclareLane(lane)

function Casts:Init()
	local events = CreateFrame("Frame")
	for event in pairs(handlers) do
		events:RegisterUnitEvent(event, "player")
	end
	events:SetScript("OnEvent", function(_, event, _, guid, spellID)
		if IsSecret(spellID) then
			Util.CountDrop("cast")
			return
		end
		handlers[event](guid, spellID)
	end)
	C_Timer.NewTicker(SWEEP_INTERVAL, Sweep)
end
