-- 4everActionTimeline — test mode (/actiontimeline test).
-- Seeds fake events on a running clock straight into Store:Ingest (seam 1,
-- above every predictor and the renderer) and drives temporary test lanes
-- that emit the mark family the encoding check covers: happened, predicted
-- (next landing full color, cadence chain desaturated, cooldowns
-- desaturated), overdue, edge clamp with chevron, ready, unusable (blue and
-- grey), unknown-cooldown, parked, paused, a queued ability on the main
-- hand (every other swing), the in-flight now-line icon, a stopped cast's
-- red border, a clip tick, GCD window bars and the next predicted mark's
-- motion trail. Every 10 s it ingests
-- an entry carrying the test secret, which the store drops and counts; the
-- count is reported when test mode ends. It doubles as the user demo.

local Addon = FourEverActionTimeline
local Util, Layout, Store, Renderer, Effects = Addon.Util, Addon.Layout, Addon.Store, Addon.Renderer, Addon.Effects

local GetTime = GetTime
local floor, max = math.floor, math.max
local GetInventoryItemTexture = GetInventoryItemTexture

local TICK = 0.05
local SWING = 2.6 -- main-hand speed
local OVERDUE_EVERY, OVERDUE_DELAY = 6, 1.0 -- landing k (k % 6 == 5) lands 1 s late
local CLIP_EVERY = 6 -- a clip tick before landing k (k % 6 == 2)
local QUEUED_ICON_SPELL = 78 -- Heroic Strike, queued on every other swing
local PAUSED_ICON_SPELL = 75 -- Auto Shot, the paused ranged hand's icon
local PAUSED_SPEED = 2.8 -- the test ranged hand's swing
local GCD_PERIOD, GCD = 3.2, Addon.PROBES.gcd
local CAST_PERIOD, CAST_TIME, CAST_STOP_AT = 6.0, 2.0, 1.2
local SECRET_EVERY = 10

local TestMode = { cycleRanged = true }
Addon.TestMode = TestMode

local t0, ticker, weaponIcon
local lanes = {}

local function SpellIcon(spellID)
	-- nil falls back to the renderer's question-mark icon.
	return Addon.Spellbook.Icon(spellID)
end

local function Ingest(entry)
	entry.test = true
	return Store:Ingest(entry)
end

local Happened = Layout.CollectHappened

-- Lanes whose look changes with time (a cast starting, a cooldown ending)
-- without a store entry ask the renderer for a rebuild when it flips.
local function SyncPhase(lane, now)
	local phase = lane:Phase(now)
	if phase ~= lane.phase then
		if lane.phase == "cooling" and phase == "idle" then
			Effects:Ring(lane) -- a cooldown came back
		end
		lane.phase = phase
		Renderer:MarkDirty(lane)
	end
end

-- ---------------------------------------------------------------------------
-- Main hand: landings, the next landing (full color), the cadence chain
-- (desaturated), an overdue landing every sixth swing and a clip tick.
-- ---------------------------------------------------------------------------

local mainHand = { key = "test-mainhand", group = "hand", order = 1, hand = "mainhand" }

local function Expected(k)
	return t0 + k * SWING
end

local function Landing(k)
	return Expected(k) + (k % OVERDUE_EVERY == OVERDUE_EVERY - 1 and OVERDUE_DELAY or 0)
end

function mainHand:Reset()
	self.nextLanding = 1
	self.clipped = 0
end

function mainHand:Advance(now)
	local k = self.nextLanding
	if k % CLIP_EVERY == 2 and self.clipped < k and Expected(k) - 1.2 <= now then
		self.clipped = k
		Ingest({ kind = "clip", lane = self.key, shape = "tick", time = Expected(k) - 1.2 })
	end
	if Landing(k) <= now then
		-- Every other swing carries the queued ability, as it is predicted to.
		local queued = k % 2 == 0
		Ingest({ kind = "swing", lane = self.key, time = Landing(k), icon = queued and SpellIcon(QUEUED_ICON_SPELL) or weaponIcon, onSwing = queued or nil })
		self.nextLanding = k + 1
		Effects:Land(self, Landing(k)) -- the badge flashes
	end
end

function mainHand:Collect(now, out)
	Happened(self, now, out)
	local expected = Expected(self.nextLanding)
	local queued = self.nextLanding % 2 == 0
	out[#out + 1] = { t = expected, icon = queued and SpellIcon(QUEUED_ICON_SPELL) or weaponIcon, queued = queued, predicted = true }
	Layout.AppendChain(out, expected, SWING, weaponIcon, now)
end

-- ---------------------------------------------------------------------------
-- Off hand: parked (dim weapon icon at the now line).
-- ---------------------------------------------------------------------------

local offHand = { key = "test-offhand", group = "hand", order = 2, hand = "offhand" }

function offHand:Reset() end

function offHand:Advance() end

function offHand:Collect(_, out)
	out[#out + 1] = { atNow = true, icon = weaponIcon, dim = true }
end

-- ---------------------------------------------------------------------------
-- Ranged: swinging, then paused (frozen, dimmed marks ahead of the now line),
-- in a repeating cycle - so the paused look is checked without a hand that
-- never moves. TestMode.cycleRanged = false holds it paused (the harness).
-- ---------------------------------------------------------------------------

local ranged = { key = "test-ranged", group = "hand", order = 3, hand = "ranged" }
local RANGED_CYCLE, RANGED_SWINGING = 10, 6 -- seconds; the swings land 2.8 s apart
-- What is left of the third swing when the cycle pauses the hand.
local PAUSED_LEFT = 3 * PAUSED_SPEED - RANGED_SWINGING

-- The cycle's start and our place in it; the held-paused mode sits at the
-- first paused instant.
local function RangedPhase(now)
	if not TestMode.cycleRanged then
		return t0, RANGED_SWINGING
	end
	local elapsed = now - t0
	local cycle = floor(elapsed / RANGED_CYCLE)
	return t0 + cycle * RANGED_CYCLE, elapsed - cycle * RANGED_CYCLE, cycle
end

function ranged:Reset()
	self.lastLanded = 0 -- the newest swing ingested (cycle * RANGED_CYCLE + k)
end

function ranged:Phase(now)
	local _, place = RangedPhase(now)
	return place < RANGED_SWINGING and "swinging" or "paused"
end

-- The test ranged hand's Auto Shot windup, from a fixed base speed.
local TEST_WINDUP = Addon.Hands.Windup(PAUSED_SPEED, Addon.Hands.TEST_BASE_SPEED)

function ranged:Advance(now)
	local start, place, cycle = RangedPhase(now)
	if place < RANGED_SWINGING then
		for k = 1, 2 do
			local at, key = start + k * PAUSED_SPEED, cycle * RANGED_CYCLE + k
			if at <= now and key > self.lastLanded then
				self.lastLanded = key
				-- A shot keeps its windup, drawn as a cast behind it.
				Ingest({ kind = "swing", lane = self.key, time = at, icon = SpellIcon(PAUSED_ICON_SPELL), castStart = at - TEST_WINDUP, autoShot = true })
			end
		end
	end
	SyncPhase(self, now)
end

function ranged:Collect(now, out)
	Happened(self, now, out)
	local start, place = RangedPhase(now)
	local icon = SpellIcon(PAUSED_ICON_SPELL)
	self.castShots = nil
	if place < RANGED_SWINGING then
		local expected = start + (floor(place / PAUSED_SPEED) + 1) * PAUSED_SPEED
		-- Auto Shot as a cast (ADR-0006), as the ranged hand draws it.
		self.castShots = true
		Addon.Hands.AppendShots(out, expected, PAUSED_SPEED, TEST_WINDUP, now)
		return
	end
	-- Paused: what was left of the swing when it froze, kept ahead of the now line.
	Layout.AppendPaused(out, PAUSED_LEFT, PAUSED_SPEED, icon)
end

-- ---------------------------------------------------------------------------
-- GCD: window bars from each triggering cast.
-- ---------------------------------------------------------------------------

local gcd = { key = "test-gcd", group = "gcd", order = 1 }

function gcd:Reset()
	self.nextCast = 0
end

function gcd:Advance(now)
	local t = t0 + 0.4 + self.nextCast * GCD_PERIOD
	if t <= now then
		-- A happened entry with a duration renders as a window bar.
		Ingest({ kind = "gcd", lane = self.key, time = t, duration = GCD, color = Addon.Gcd.COLOR })
		self.nextCast = self.nextCast + 1
	end
end

gcd.Collect = Layout.CollectHappened

-- ---------------------------------------------------------------------------
-- Cast lane: a 2 s cast every 6 s; every third one stops early (red), and
-- the one before it is a channel.
-- ---------------------------------------------------------------------------

local cast = { key = "test-cast", group = "cast", order = 1 }

local function CastStart(k)
	return t0 + 0.5 + k * CAST_PERIOD
end

local function CastStops(k)
	return k % 3 == 2
end

local function CastChannels(k)
	return k % 3 == 1 or nil
end

function cast:Reset()
	self.next = 0
	self.icon = SpellIcon(635) -- Holy Light
end

function cast:Phase(now)
	return CastStart(self.next) <= now and "casting" or "idle"
end

function cast:Advance(now)
	local k = self.next
	local start = CastStart(k)
	local stops = CastStops(k)
	local finish = start + (stops and CAST_STOP_AT or CAST_TIME)
	if finish <= now then
		Ingest({ kind = "cast", lane = self.key, time = finish, icon = self.icon, border = stops and "red" or nil, castStart = start, channel = CastChannels(k) })
		self.next = k + 1
	end
	SyncPhase(self, now)
end

function cast:Collect(now, out)
	Happened(self, now, out)
	local start = CastStart(self.next)
	if start <= now then
		-- The in-flight cast: a bar from its start, and its completion is full
		-- color (the live cast-time read is plain, probe 11).
		out[#out + 1] = { shape = "bar", tStart = start, tEnd = start + CAST_TIME, channel = CastChannels(self.next) }
		out[#out + 1] = { t = start + CAST_TIME, icon = self.icon, predicted = true }
	end
end

function cast:IsActive(now)
	return self:Phase(now) == "casting"
end

-- ---------------------------------------------------------------------------
-- Spell lanes: cooldown predictions, ready / unusable / unknown-cooldown.
-- ---------------------------------------------------------------------------

-- idleLook(k) returns the now-line mark style while the spell is idle after
-- cast k; unknown = true shows the unknown-cooldown mark instead of a
-- predicted mark while cooling.
local function SpellLane(key, order, spellID, period, offset, cooldown, idleLook, unknown)
	local lane = { key = key, group = "spell", order = order }

	-- A cooldown of 30 s or more is long, as for a real spell.
	function lane:IsLong()
		return cooldown >= Addon.Spells.LONG_COOLDOWN
	end

	local function CastTime(k)
		return t0 + offset + k * period
	end

	function lane:Reset()
		self.next = 0
		self.icon = SpellIcon(spellID)
	end

	function lane:Phase(now)
		local k = self.next - 1
		if k < 0 or CastTime(k) + cooldown <= now then
			return "idle"
		end
		return "cooling"
	end

	function lane:Advance(now)
		local t = CastTime(self.next)
		if t <= now then
			Ingest({ kind = "spell", lane = self.key, time = t, icon = self.icon, spellID = spellID })
			self.next = self.next + 1
		end
		SyncPhase(self, now)
	end

	function lane:Collect(now, out)
		Happened(self, now, out)
		local k = self.next - 1
		if self:Phase(now) == "cooling" then
			if unknown then
				out[#out + 1] = { atNow = true, icon = self.icon, desaturated = true }
			else
				out[#out + 1] = { t = CastTime(k) + cooldown, icon = self.icon, predicted = true, desaturated = true }
			end
		else
			out[#out + 1] = { atNow = true, icon = self.icon, tint = idleLook and idleLook(k) }
		end
	end

	return lane
end

-- Thunder Clap: 6 s cooldown, every 9 s; idle look cycles ready, blue
-- (resource-short), grey (unusable).
local IDLE_LOOKS = { [1] = "resource", [2] = "unusable" }
local thunderClap = SpellLane("test-spell-a", 1, 6343, 9, 1, 6, function(k)
	return IDLE_LOOKS[max(k, 0) % 3]
end)
-- Charge: 30 s cooldown, every 40 s - pinned at the far edge with the
-- chevron until it scrolls in.
local charge = SpellLane("test-spell-b", 2, 100, 40, 2, 30)
-- Hammer of Justice: cooling with an unknown end (uncalibrated), then ready.
local hammer = SpellLane("test-spell-c", 3, 853, 14, 3, 8, nil, true)

lanes = { mainHand, offHand, ranged, gcd, cast, thunderClap, charge, hammer }

-- ---------------------------------------------------------------------------
-- Clock
-- ---------------------------------------------------------------------------

local function Tick()
	local now = GetTime()
	for _, lane in ipairs(lanes) do
		lane:Advance(now)
	end
	local secrets = floor((now - t0) / SECRET_EVERY)
	if secrets > TestMode.secrets then
		TestMode.secrets = secrets
		-- Seam 1's secret case: dropped and counted by the store's guard.
		Ingest({ kind = "test-secret", lane = cast.key, time = now, spellID = Util.TEST_SECRET })
	end
end

function TestMode:IsRunning()
	return ticker ~= nil
end

function TestMode:Start()
	if ticker then
		return
	end
	t0 = GetTime()
	weaponIcon = GetInventoryItemTexture and GetInventoryItemTexture("player", 16) or SpellIcon(6603)
	self.secrets = 0
	for _, lane in ipairs(lanes) do
		lane.phase = nil
		lane:Reset()
		Layout:RegisterLane(lane)
	end
	ticker = C_Timer.NewTicker(TICK, Tick)
	TestMode:UpdateTesting()
	Renderer:ResetPerf()
	Renderer:UpdateVisibility()
	Addon:Print("test mode on: fake swings, casts and cooldowns on a running clock. |cffdddddd/actiontimeline test off|r to stop.")
end

function TestMode:Stop()
	if not ticker then
		return
	end
	ticker:Cancel()
	ticker = nil
	for _, lane in ipairs(lanes) do
		Layout:UnregisterLane(lane)
	end
	Store:RemoveWhere(function(entry)
		return entry.test
	end)
	TestMode:UpdateTesting()
	Addon:Print("test mode off.")
	Util.ReportDrops()
end

-- ---------------------------------------------------------------------------
-- Test effects (/actiontimeline test effects): seam 1b. Replays the library's
-- real swing-event signatures on a fake swing, through the same handlers the
-- library callbacks reach (Hands:OnStart / OnStop), so the copied classifier
-- and every hand-lane effect are verified outside combat - 4everSwingTimer's
-- effect previews, on the timeline. Each step prints its name as it fires.
-- ---------------------------------------------------------------------------

local Hands = Addon.Hands
local SPEED, RANGED_SPEED, SWAP_SPEED = 2.0, 2.8, 2.6
local START_GAP = 0.03 -- the START that follows a STOP inside the grace
local effectsGeneration = 0
local effectsRunning = false

local function MainHand()
	return Hands:State("mainhand")
end

local function Ranged()
	return Hands:State("ranged")
end

local function UntilLanding(state)
	return (state.expiration or GetTime()) - GetTime()
end

-- Runs fn after delay unless test effects stopped meanwhile.
local function Later(delay, fn)
	local generation = effectsGeneration
	C_Timer.After(max(delay, 0), function()
		if generation == effectsGeneration then
			fn()
		end
	end)
end

-- The signatures, as the library fires them.
local function Start(hand, speed)
	Hands:OnStart(hand, speed, GetTime() + speed, false)
end

-- A natural landing: the STOP and START pair at the expiry.
local function Land(hand, speed)
	Hands:OnStop(hand)
	Start(hand, speed)
end

-- An in-flight STOP, then a START inside the grace (early landing or swap).
local function StopThenStart(hand, speed)
	Hands:OnStop(hand)
	Later(START_GAP, function()
		Start(hand, speed)
	end)
end

-- A mid-swing UPDATE moving the landing by delta seconds.
local function Shift(hand, delta)
	local state = Hands:State(hand)
	Hands:OnStart(hand, state.speed, state.expiration + delta, true)
end

-- The movement-cancelled Auto Shot re-attempted ~0.5 s ahead.
local function Retry()
	Hands:OnStart("ranged", RANGED_SPEED, GetTime() + 0.5, true)
end

-- Each step: its name, its wait (seconds, or a function computing it from
-- the swing state when the previous step ran), and its signature.
local EFFECT_STEPS = {
	{ "main hand swinging", 0, function() Start("mainhand", SPEED) end },
	{ "parry haste: teal pop and streak, the landing jumps earlier", 0.8, function() Shift("mainhand", -0.6) end },
	{ "landing", function() return UntilLanding(MainHand()) end, function() Land("mainhand", SPEED) end },
	{ "early landing: the happened mark lands early, teal", 1.0, function() StopThenStart("mainhand", SPEED) end },
	{ "cast reset: red pop, shake, streak, clip tick", 1.0, function() Start("mainhand", SPEED) end },
	{ "weapon swap: red, clip tick at the swap", 1.0, function() StopThenStart("mainhand", SWAP_SPEED) end },
	{ "overdue: the next landing pins on the now line", START_GAP + SWAP_SPEED + 0.05, function() end },
	{ "late landing (no pop: nothing was corrected)", 0.6, function() Land("mainhand", SPEED) end },
	{ "cut short: the hand just parks", 1.0, function() Hands:OnStop("mainhand") end },
	{ "ranged swinging", 0.8, function() Start("ranged", RANGED_SPEED) end },
	{ "ranged dynamic haste: teal, the shot jumps earlier", 1.0, function() Shift("ranged", -0.8) end },
	{ "shot fired", function() return UntilLanding(Ranged()) end, function() Land("ranged", RANGED_SPEED) end },
	{ "movement retry: amber pop once, amber border while held", function() return UntilLanding(Ranged()) - 0.1 end, Retry },
	{ "retry again: streak only", 0.45, Retry },
	{ "retry again: streak only", 0.45, Retry },
	{ "shot fired: amber delay span records the time lost", function() return UntilLanding(Ranged()) end, function() Land("ranged", RANGED_SPEED) end },
}
local EFFECTS_TAIL = 3.0 -- seconds left to watch the last step scroll

local function RunStep(index)
	local step = EFFECT_STEPS[index]
	if not step then
		Later(EFFECTS_TAIL, function()
			TestMode:StopEffects()
		end)
		return
	end
	local wait = step[2]
	Later(type(wait) == "function" and wait() or wait, function()
		Addon:Print("effects: " .. step[1])
		step[3]()
		RunStep(index + 1)
	end)
end

function TestMode:UpdateTesting()
	Addon.testing = ticker ~= nil or effectsRunning
	Renderer:UpdateVisibility()
end

function TestMode:StartEffects()
	if effectsRunning then
		return
	end
	effectsRunning = true
	effectsGeneration = effectsGeneration + 1
	Hands:SetTesting(true)
	self:UpdateTesting()
	Addon:Print("test effects: replaying swing-event signatures on the main-hand and ranged lanes (out of combat).")
	RunStep(1)
end

function TestMode:StopEffects()
	if not effectsRunning then
		return
	end
	effectsRunning = false
	effectsGeneration = effectsGeneration + 1
	Hands:SetTesting(false)
	self:UpdateTesting()
	Addon:Print("test effects done.")
end
