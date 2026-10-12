-- 4everActionTimeline — spell lanes (docs/SPEC.md, Cooldown marks, Mark
-- encoding). One lane per enabled, known spell of the lane set, in lane
-- order. A cast leaves a happened mark at its SUCCEEDED and starts the
-- cooldown: a predicted mark at SUCCEEDED + offset + duration (desaturated:
-- calibration-sourced; full color when an out-of-combat plain read gave the
-- exact end), or the unknown-cooldown mark (desaturated, on the now line)
-- when no duration is known. A mark reaching the now line pins there
-- (overdue) until the engine reports the spell ready (isActive, plain in
-- combat - probe 3; it also covers the GCD), then becomes the ready mark.
-- Idle lanes show the ready mark, or the unusable mark tinted like the
-- action bar (blue when resource-short, grey otherwise or in the wrong
-- stance or form). Linked spells start together; resets make their spells
-- ready; delayed-start spells show happened marks only and the
-- unknown-cooldown mark once their cooldown is running.
--
-- A lane's state is one phase: nil (idle), "cooling" (readyAt - nil when
-- the end is unknown - with exact, flagged and castAt) or "delayed" (a
-- delayed-start cooldown waiting for its effect to end).

local Addon = FourEverActionTimeline
local Util, Layout, Store, Renderer, Spellbook, Calibration =
	Addon.Util, Addon.Layout, Addon.Store, Addon.Renderer, Addon.Spellbook, Addon.Calibration

local GetTime = GetTime
local IsSpellUsable = C_Spell and C_Spell.IsSpellUsable
local GetShapeshiftFormID = GetShapeshiftFormID
local InCombatLockdown = InCombatLockdown
local IsSecret = Util.IsSecret

-- A cast out of combat is read this long after its SUCCEEDED: the first
-- read is the GCD, the spell's own cooldown replaces it ~0.2 s later.
local SETTLE = 0.3
-- A cast this much before its predicted ready proves the value too long.
local EARLY_TOLERANCE = 0.3
-- Still active this long past its predicted ready (beyond a GCD) proves the
-- value too short.
local OVERDUE_TOLERANCE = 0.5
local WATCH_INTERVAL = 0.1
-- After combat ends: when the read pass runs (seconds after the event).
local COMBAT_END_READS = { 0.2, 0.5, 1.0 }
local RECENT_MAX = 5

local Spells = {}
Addon.Spells = Spells

local lanes = {} -- base ID -> lane
local byID, byName = {}, {} -- resolved ID / spell name -> lane
local resetsByName = {} -- reset spell name -> { base IDs it readies }
local seedLinks = {} -- base ID -> { base IDs sharing its cooldown (class data) }
local recent = {} -- the last few SUCCEEDEDs (spell ID, name, lane), for /actiontimeline debug
local EnsureWatch -- starts the watcher; defined with it below

-- ---------------------------------------------------------------------------
-- The lane
-- ---------------------------------------------------------------------------

local function Contains(list, value)
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end

-- The idle mark's tint: nil (ready), "resource" or "unusable".
local function IdleTint(lane)
	local forms = Addon:ClassInfo().forms[lane.base]
	if forms and Addon.PROBES.formPlain and GetShapeshiftFormID then
		local form = GetShapeshiftFormID()
		if not IsSecret(form) and not Contains(forms, form) then
			return "unusable"
		end
	end
	if not (Addon.PROBES.usablePlain and IsSpellUsable) then
		return nil
	end
	local usable, noPower = IsSpellUsable(lane.id)
	if IsSecret(usable) or IsSecret(noPower) or usable then
		return nil -- unreadable: ready means off cooldown only
	end
	return noPower and "resource" or "unusable"
end

-- Re-reads the idle tint; only a changed tint on a lane showing it rebuilds.
local function Retint(lane)
	local tint = IdleTint(lane)
	if tint ~= lane.tint then
		lane.tint = tint
		if lane.state.phase ~= "cooling" then
			Renderer:MarkDirty(lane)
		end
	end
end

local function Collect(lane, now, out)
	Layout.CollectHappened(lane, now, out)
	local state = lane.state
	if state.phase == "cooling" and state.readyAt then
		-- With its sink on, the engine-drawn icon is this spell's only future
		-- mark: no calibrated guess racing the truth.
		if not lane.sink then
			out[#out + 1] = { t = state.readyAt, icon = lane.icon, predicted = true, desaturated = not state.exact }
		end
	elseif state.phase == "cooling" then
		out[#out + 1] = { atNow = true, icon = lane.icon, desaturated = true } -- the unknown-cooldown mark
	else
		out[#out + 1] = { atNow = true, icon = lane.icon, tint = lane.tint }
	end
end

local function IsActive(lane)
	return lane.state.phase == "cooling"
end

-- Moves a lane to a phase. readyAt and exact belong to "cooling"; castAt
-- survives only while it stays cooling.
local function SetPhase(lane, phase, readyAt, exact)
	local state = lane.state
	local returned = state.phase == "cooling" and phase == nil
	if phase ~= "cooling" then
		state.castAt = nil
	end
	state.phase, state.readyAt, state.exact, state.flagged = phase, readyAt, exact, nil
	if phase ~= "cooling" then
		lane.tint = IdleTint(lane)
	end
	Renderer:MarkDirty(lane)
	if returned then
		Addon.Effects:Ring(lane)
	end
	if phase then
		EnsureWatch()
	end
end

local function Ready(lane)
	SetPhase(lane, nil)
end

local function IsDelayedStart(lane)
	local entry = Calibration:Entry(lane.id)
	return Addon:ClassInfo().delayedStart[lane.base] or (entry and entry.delayedStart) or false
end

-- The duration predicting this lane: the override, else its calibrated
-- value. nil when unknown.
local function Duration(lane)
	local entry = Calibration:Entry(lane.id)
	return Addon:GetLaneValue(lane.base, "override") or (entry and entry.duration)
end

-- A long cooldown (Single lane: no ready-row slot, a ring on the now line when
-- it returns): flagged in the lane window, tagged in the class data, or a
-- known cooldown of 30 s or more. A spell whose cooldown is not known yet
-- counts as a rotation ability.
local LONG_COOLDOWN = 30
Spells.LONG_COOLDOWN = LONG_COOLDOWN

function Spells.IsLong(lane)
	if Addon:GetLaneValue(lane.base, "long") or Addon:ClassInfo().long[lane.base] then
		return true
	end
	local duration = Duration(lane)
	return duration ~= nil and duration >= LONG_COOLDOWN
end

-- The cooldown starts at `at` (a cast, or a linked spell's cast; a linked
-- lane with no value of its own takes the shared one).
local function StartCooldown(lane, at, shared)
	if IsDelayedStart(lane) then
		SetPhase(lane, "delayed") -- happened marks only, watched until it runs
		return
	end
	local duration = Duration(lane) or shared
	SetPhase(lane, "cooling", duration and at + Calibration:Offset() + duration, false)
	lane.state.castAt = at
end

-- The lanes sharing a cooldown with this one: learned links, plus the class
-- data's seed groups.
local function Linked(lane)
	local out = {}
	for id in pairs(Calibration:Links(lane.id) or {}) do
		local other = byID[id]
		if other and other ~= lane then
			out[other] = true
		end
	end
	for _, base in ipairs(seedLinks[lane.base] or {}) do
		local other = lanes[base]
		if other and other ~= lane then
			out[other] = true
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

local function ResolvedIDs()
	local ids = {}
	for _, lane in pairs(lanes) do
		ids[#ids + 1] = lane.id
	end
	return ids
end

-- A plain read of a lane (after its cast out of combat - castAt - or in a
-- read pass): learn what it shows, and show it - the exact end, a delayed
-- start, or ready.
local function ApplyRead(lane, castAt)
	local info = Calibration:Read(lane.id)
	if not info then
		return
	end
	local learned = Calibration:Learn(lane.id, lane.base, info, castAt)
	if learned == "learned" then
		if castAt then
			Calibration:LearnLinks(lane.id, info, ResolvedIDs())
		end
		SetPhase(lane, "cooling", info.startTime + info.duration, true)
	elseif learned == "delayed" then
		SetPhase(lane, "delayed")
	elseif not info.isActive and lane.state.phase == "cooling" then
		Ready(lane)
	end
end

local function ReadPass()
	for _, lane in pairs(lanes) do
		ApplyRead(lane)
	end
end

-- Every player SUCCEEDED, from the cast lane (which owns the events).
function Spells:OnSucceeded(spellID, now)
	local name = Spellbook.Name(spellID)
	for _, base in ipairs(name and resetsByName[name] or {}) do
		if lanes[base] then
			Ready(lanes[base])
		end
	end
	local lane = byID[spellID] or (name and byName[name])
	table.insert(recent, 1, { spellID, name, lane })
	recent[RECENT_MAX + 1] = nil
	if not lane then
		return
	end
	Store:Ingest({ kind = "spell", lane = lane.key, time = now, icon = lane.icon })
	local state = lane.state
	if state.readyAt and now < state.readyAt - EARLY_TOLERANCE then
		Calibration:MarkStale(lane.id) -- cast before its predicted ready: the value is too long
	end
	local duration = Duration(lane)
	StartCooldown(lane, now)
	for other in pairs(Linked(lane)) do
		StartCooldown(other, now, duration)
	end
	if not (InCombatLockdown and InCombatLockdown()) then
		C_Timer.After(SETTLE, function()
			ApplyRead(lane, now)
		end)
	end
end

-- ---------------------------------------------------------------------------
-- The watcher: lanes waiting on the engine (an arrived prediction, an
-- unknown end, a delayed start). It runs only while one is waiting.
-- ---------------------------------------------------------------------------

-- The engine just reported the cooldown over: unless an exact read already
-- gave the end, the cast-to-isActive-false time is the cooldown, measured
-- to within half a watch interval - unless a GCD ended at the same moment
-- (the spell's own end may have hidden behind it). Event to event: the
-- SUCCEEDED and the isActive flip both arrive a server round trip after
-- the engine's instants, so the delays cancel (Consecration measured 8.2 s
-- with the offset applied, 8.0 s without, against a plain 8.0 s read).
local function Measure(lane, now)
	local state = lane.state
	if not state.castAt or state.exact or Addon.Gcd:EndedNear(now, WATCH_INTERVAL * 1.5) then
		return
	end
	Calibration:LearnMeasured(lane.id, lane.base, now - WATCH_INTERVAL / 2 - state.castAt)
end

local function WatchLane(lane, now)
	local state = lane.state
	local active, enabled = Calibration:Flags(lane.id)
	if state.phase == "delayed" then
		-- Running once the effect ended: enabled again and active. (While
		-- the effect lasts it is disabled, so another spell's GCD never
		-- reads as this one starting.)
		if active and enabled then
			SetPhase(lane, "cooling")
		end
	elseif state.readyAt and now < state.readyAt then
		return -- not arrived yet
	elseif active == false then
		Measure(lane, now)
		Ready(lane)
	elseif state.readyAt and not state.flagged and now > state.readyAt + Addon.Gcd:Length() + OVERDUE_TOLERANCE then
		state.flagged = true
		Calibration:MarkStale(lane.id) -- stuck overdue: the value is too short
	end
end

local watchTicker

local function Watch()
	local now, waiting = GetTime(), false
	local plain = Addon.PROBES.isActivePlain
	for _, lane in pairs(lanes) do
		local state = lane.state
		if state.phase then
			waiting = true
			if plain then
				WatchLane(lane, now)
			elseif state.readyAt and now >= state.readyAt then
				Ready(lane) -- unreadable: trust calibration on arrival
			end
		end
	end
	if not waiting and watchTicker then
		watchTicker:Cancel()
		watchTicker = nil
	end
end

function EnsureWatch()
	watchTicker = watchTicker or C_Timer.NewTicker(WATCH_INTERVAL, Watch)
end

-- ---------------------------------------------------------------------------
-- The lane set
-- ---------------------------------------------------------------------------

-- Rebuilds the lanes from the lane set: enabled, known spells in lane order,
-- each resolved to its known rank.
function Spells:Rebuild()
	local wanted, order = {}, Addon:LaneOrder()
	for index, base in ipairs(order) do
		if Addon:GetLaneValue(base, "enabled") then
			local id, name = Spellbook.Resolve(base)
			if id then
				wanted[base] = { order = index, id = id, name = name }
			end
		end
	end
	local changed = false
	for base, lane in pairs(lanes) do
		if not wanted[base] then
			lane.registered, changed = nil, true
			Layout:UnregisterLane(lane)
			lanes[base] = nil
		end
	end
	wipe(byID)
	wipe(byName)
	for base, want in pairs(wanted) do
		local lane = lanes[base]
		if not lane then
			lane = { key = "spell:" .. base, group = "spell", base = base, state = {}, Collect = Collect, IsActive = IsActive }
			lanes[base] = lane
		end
		lane.order, lane.id, lane.name, lane.icon = want.order, want.id, want.name, Spellbook.Icon(want.id)
		lane.tint = IdleTint(lane)
		byID[want.id], byName[want.name] = lane, lane
		if not lane.registered then
			lane.registered, changed = true, true
			Layout:RegisterLane(lane)
		end
	end
	Layout:SortLanes()
	local info = Addon:ClassInfo()
	wipe(resetsByName)
	for resetBase, readies in pairs(info.resets) do
		local name = Spellbook.Name(resetBase)
		if name then
			resetsByName[name] = readies
		end
	end
	wipe(seedLinks)
	for _, group in ipairs(info.linked) do
		for _, base in ipairs(group) do
			seedLinks[base] = group
		end
	end
	-- The engine-drawn sink lanes: opted-in spell lanes, in lane order, at
	-- most Sinks.MAX.
	local sinks = {}
	for _, base in ipairs(order) do
		local lane = lanes[base]
		if lane then
			local sink = (#sinks < Addon.Sinks.MAX and Addon:GetLaneValue(base, "sink")) and true or false
			if sink ~= (lane.sink or false) then
				lane.sink = sink
				Renderer:MarkDirty(lane)
			end
			if sink then
				sinks[#sinks + 1] = lane
			end
		end
	end
	Addon.Sinks:Sync(sinks)
	if changed then
		Renderer:UpdateVisibility()
	end
end

-- One line per lane for /actiontimeline calibration.
function Spells:Report()
	local lines = {}
	for _, base in ipairs(Addon:LaneOrder()) do
		local lane = lanes[base]
		if lane then
			local entry = Calibration:Entry(lane.id)
			local override = Addon:GetLaneValue(base, "override")
			local status
			if override then
				status = string.format("override %.1f s", override)
			elseif IsDelayedStart(lane) then
				status = "delayed start (happened marks only)"
			elseif entry and entry.duration then
				status = string.format("%.1f s%s%s", entry.duration, entry.measured and " (measured in combat)" or "",
					entry.stale and ", stale - re-read pending" or "")
			else
				status = "uncalibrated: cast it once out of combat"
			end
			lines[#lines + 1] = lane.name .. ": " .. status
		end
	end
	return lines
end

-- Live lane state and the last casts, for /actiontimeline debug.
function Spells:Debug()
	local lines, now = {}, GetTime()
	for _, base in ipairs(Addon:LaneOrder()) do
		local lane = lanes[base]
		if lane then
			local state = lane.state
			local what
			if state.phase == "cooling" and state.readyAt then
				what = string.format("predicting ready in %.1f s (%s)", state.readyAt - now, state.exact and "exact" or "calibrated")
			elseif state.phase == "cooling" then
				what = "cooling, end unknown"
			elseif state.phase == "delayed" then
				what = "delayed start pending"
			else
				what = "idle, tint " .. tostring(lane.tint or "none")
			end
			local usable, noPower
			if IsSpellUsable then
				usable, noPower = IsSpellUsable(lane.id)
			end
			lines[#lines + 1] = string.format("%s (id %d, registered %s, frame %s): %s; usable=%s noPower=%s active=%s",
				lane.name, lane.id, lane.registered and "yes" or "no", lane.frame and "yes" or "no", what,
				tostring(usable), tostring(noPower), tostring((Calibration:Flags(lane.id))))
		end
	end
	local casts = {}
	for i, cast in ipairs(recent) do
		casts[i] = string.format("%d %s -> %s", cast[1], cast[2] or "?", cast[3] and cast[3].name or "no lane")
	end
	lines[#lines + 1] = "last casts: " .. (#casts > 0 and table.concat(casts, "; ") or "none")
	return lines
end

Addon:OnLaneSetChanged(function()
	Spells:Rebuild()
end)

function Spells:Init()
	local events = CreateFrame("Frame")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("SPELL_UPDATE_USABLE")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	pcall(events.RegisterEvent, events, "PLAYER_TALENT_UPDATE")
	pcall(events.RegisterEvent, events, "CHARACTER_POINTS_CHANGED")
	events:SetScript("OnEvent", function(_, event)
		if event == "SPELLS_CHANGED" then
			Spells:Rebuild()
			Calibration:Prune()
		elseif event == "PLAYER_REGEN_ENABLED" then
			-- Cooldown values turn plain a moment after combat ends, not at
			-- the event: read a few times as they settle.
			for _, delay in ipairs(COMBAT_END_READS) do
				C_Timer.After(delay, ReadPass)
			end
		elseif event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED" then
			-- The event also fires with nothing changed (seen after a
			-- Hearthstone): only a real change of talent ranks goes stale.
			if Calibration:TalentsChanged() then
				Calibration:MarkAllStale()
			end
		else
			-- Usability or form changed: idle lanes re-read their tint.
			for _, lane in pairs(lanes) do
				Retint(lane)
			end
		end
	end)
	self:Rebuild()
	Calibration:TalentsChanged() -- records the ranks at login
	-- Session re-seed: out of combat the reads are plain; in combat a spell
	-- known to be cooling shows the unknown-cooldown mark until it is ready.
	if InCombatLockdown and InCombatLockdown() then
		for _, lane in pairs(lanes) do
			if Calibration:Flags(lane.id) then
				SetPhase(lane, "cooling")
			end
		end
	else
		ReadPass()
	end
end
