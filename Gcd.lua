-- 4everActionTimeline — the GCD lane (docs/SPEC.md, GCD lane).
-- Window bars: a pale-blue span from the triggering cast to the GCD's end,
-- elapsed full color and unelapsed desaturated (the renderer's split), one
-- cast deep, nothing when idle. Whether a cast started a GCD is read from the
-- engine, never assumed: right after the cast, C_Spell.GetSpellCooldown on a
-- reference spell - one with no cooldown of its own that is bound to the GCD
-- - reports isActive (plain in combat, probe 3). Off-GCD casts (Sprint,
-- Evasion, Stealth, Judgement) leave it false and draw nothing. The window's
-- length is the power-type default (1.5 s; 1.0 s for energy users, both
-- measured, probe 10) or the user's override. When a cast is stopped or
-- interrupted the same read decides again: the engine clears an interrupted
-- cast's GCD ~0.3 s after the interrupt (the server's confirmation; capture
-- 2026-10-06), so the reference is watched while the window runs, and a
-- clear before its natural end cuts the window at the stop instant.

local Addon = FourEverActionTimeline
local Util, Layout, Store, Renderer, Spellbook, Calibration =
	Addon.Util, Addon.Layout, Addon.Store, Addon.Renderer, Addon.Spellbook, Addon.Calibration

local GetTime = GetTime
local max = math.max
local UnitPowerType = UnitPowerType

local POWER_ENERGY = 3 -- Enum.PowerType.Energy
-- The engine's GCD can register a moment after the cast event: re-read for
-- this long before calling a cast off-GCD.
local OPEN_GRACE = 0.1
-- After a stop: how often the reference is polled, and how close to the
-- window's natural end a clear counts as the GCD simply running out.
local STOP_POLL, NATURAL_END_SLACK = 0.05, 0.1
-- A cast this close before the running window's end is not "inside" it.
local INSIDE_SLACK = 0.05

local Gcd = {
	-- Pale, whitish blue: near the swing timer's GCD tint, clear of
	-- Blizzard's not-enough-mana blue (VISUAL.md, GCD window bar).
	COLOR = { 0.78, 0.88, 1.0, 0.9 },
}
Addon.Gcd = Gcd

local lane = { key = "gcd", group = "gcd", order = 1, setting = "showGcd", Collect = Layout.CollectHappened }
local reference
local window -- the latest window's store entry
local openWatch, cutWatch

local function WindowEnd()
	return window and window.time + window.duration or 0
end

function lane:IsActive(now)
	return now < WindowEnd()
end

-- True when the latest GCD window ended within `slack` of `now`: a spell's
-- isActive turning false then may be the GCD's end, not its own.
function Gcd:EndedNear(now, slack)
	local ending = WindowEnd()
	return ending > 0 and math.abs(now - ending) < slack
end

-- Calls step now and then every interval until it returns true or the
-- deadline passes; returns the ticker (nil when step settled at once).
local function Watch(previous, interval, deadline, step)
	if previous then
		previous:Cancel()
	end
	if step() then
		return nil
	end
	return C_Timer.NewTicker(interval, function(ticker)
		if GetTime() >= deadline or step() then
			ticker:Cancel()
		end
	end)
end

-- The GCD length for a cast now: the override, else by power type.
function Gcd:Length()
	local override = Addon:GetSetting("gcdOverride")
	if override == "1.5" then
		return 1.5
	elseif override == "1.0" then
		return 1.0
	elseif override == "custom" then
		return Addon:GetSetting("gcdCustom")
	end
	local powerType = UnitPowerType and UnitPowerType("player")
	if powerType == POWER_ENERGY then
		return Addon.PROBES.energyGCD
	end
	return Addon.PROBES.gcd
end

-- true / false, or nil when the read is unavailable or secret.
local function GcdRunning()
	local active, _, secret = Calibration:Flags(reference)
	if secret then
		Util.CountDrop("gcd")
	end
	return active
end

-- A cast that could start a GCD: cast-time spells at their START, instants
-- at their SUCCEEDED. at is the cast's instant.
function Gcd:OnCast(at)
	if not (reference and lane.registered) then
		return
	end
	openWatch = Watch(openWatch, OPEN_GRACE, at + OPEN_GRACE + 0.01, function()
		-- An off-GCD cast during a running GCD cannot start another one.
		if at < WindowEnd() - INSIDE_SLACK then
			return true
		end
		local running = GcdRunning()
		if running then
			window = { kind = "gcd", lane = lane.key, time = at, duration = Gcd:Length(), color = Gcd.COLOR }
			Store:Ingest(window)
		end
		return running ~= false
	end)
end

-- A started cast stopped, failed or was interrupted at `at`: the GCD it began
-- may be cleared with it, a moment later. Watch until it is (cut the window
-- at the stop instant) or the window runs out.
function Gcd:OnCastStopped(at)
	local stopped = window
	if not (reference and lane.registered and stopped and at < WindowEnd()) then
		return
	end
	cutWatch = Watch(cutWatch, STOP_POLL, WindowEnd(), function()
		if window ~= stopped or GetTime() >= WindowEnd() - NATURAL_END_SLACK then
			return true
		end
		local running = GcdRunning()
		if running == false then
			stopped.duration = max(at - stopped.time, 0)
			Renderer:MarkDirty(lane)
		end
		return running ~= true
	end)
end

-- The first known reference spell for the class (the class data's
-- gcdReference, in order of preference; re-resolved as the spellbook
-- changes).
local function ResolveReference()
	reference = nil
	for _, spellID in ipairs(Addon:ClassInfo().gcdReference) do
		if Spellbook.IsKnown(spellID) then
			reference = spellID
			return
		end
	end
end

-- The reference spell's name, for /actiontimeline status.
function Gcd:ReferenceName()
	return reference and (Spellbook.Name(reference) or tostring(reference)) or nil
end

Layout:DeclareLane(lane)

function Gcd:Init()
	local events = CreateFrame("Frame")
	events:RegisterEvent("SPELLS_CHANGED")
	events:SetScript("OnEvent", ResolveReference)
	ResolveReference()
end
