-- 4everActionTimeline — hand lanes: main hand, off hand, ranged.
-- All swing state comes from LibClassicSwingTimerAPI's UNIT_SWING_TIMER_*
-- callbacks and UnitSwingTimerInfo; the timeline does no swing math and never
-- reads UnitAttackSpeed (docs/SPEC.md, Hand lanes). Each library START is a
-- swing landing at its anchor (expiration - speed), unless the classifier
-- calls it a reset or a weapon swap.
--
-- Marks: happened landings (full color, the icon the swing landed with), the
-- next landing (full color: the library's expiry is fact-grade), the cadence
-- chain after it (desaturated), the parked mark (dim) when idle, frozen and
-- dimmed while paused. Every mark shows the equipped weapon's icon, the
-- druid form's icon while shifted, and the queued next-melee ability on the
-- main hand. Lane presence is equipment-driven, with per-hand settings.

local Addon = FourEverActionTimeline
local Util, Layout, Store, Renderer, Effects, Classify =
	Addon.Util, Addon.Layout, Addon.Store, Addon.Renderer, Addon.Effects, Addon.Classify

local GetTime = GetTime
local GetInventoryItemID, GetInventoryItemTexture = GetInventoryItemID, GetInventoryItemTexture
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local IsCurrentSpell = C_Spell and C_Spell.IsCurrentSpell
local FindBaseSpellByID = FindBaseSpellByID
local IsSecret = Util.IsSecret

local HANDS = { "mainhand", "offhand", "ranged" }
local SLOT = { mainhand = 16, offhand = 17, ranged = 18 }
local SETTING = { mainhand = "showMainhand", offhand = "showOffhand", ranged = "showRanged" }
local WEAPON_CLASS_ID = 2 -- Enum.ItemClass.Weapon
-- Queued next-melee abilities (base IDs; ranks resolve through the base):
-- Heroic Strike, Cleave, Raptor Strike, Maul.
local QUEUED_SPELLS = { 78, 845, 2973, 6807 }
local QUEUE_POLL = 0.2
-- SUCCEEDED for an on-next-swing ability fires at the swing it rode, in the
-- same frame as that swing's START (probe 13); either may come first.
local ON_NEXT_SWING_WINDOW = 0.15
local RESET_DEDUPE = 0.1
local SWEEP_INTERVAL = Classify.STALE_LANDING_GRACE / 2
local ATTACK_ICON = 135274 -- fallback when a slot reports no texture
local ATTACK_SPELL = 6603 -- the auto-attack toggle
-- Auto Shot is a cast (ADR-0006): a windup of WINDUP_BASE scaled by ranged
-- haste - the swing library's own value, 0.52 s x ranged speed / the
-- weapon's base speed - that needs the hunter standing still, then the
-- reload. The base speed is the ranged weapon's tooltip line (plain, probe
-- H3), read as the library reads it.
local AUTO_SHOT_SPELL = 75
local WINDUP_BASE = 0.52
local BASE_SPEED_RETRY = 2 -- seconds before re-reading a tooltip that had no speed line
local GetTooltipItem = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
local SPEED_PATTERN = (SPEED or "Speed") .. " (%d+[%.,]%d+)"

local Hands = {}
Addon.Hands = Hands
Hands.TEST_BASE_SPEED = 3.0 -- the test lanes' ranged weapon

local ON_NEXT_SWING = {}
for _, id in ipairs(QUEUED_SPELLS) do
	ON_NEXT_SWING[id] = true
end

local isDruid = false -- set at Init: class data is not reliable at file load
local lanes = {}

-- ---------------------------------------------------------------------------
-- Icons and presence
-- ---------------------------------------------------------------------------

-- The icon a hand's swing marks show now: the druid form's while shifted
-- (the lane shows what is attacking), else the equipped weapon's.
local function CurrentIcon(hand)
	if isDruid and hand ~= "ranged" then
		local index = GetShapeshiftForm and GetShapeshiftForm() or 0
		if index > 0 and GetShapeshiftFormInfo then
			local icon = GetShapeshiftFormInfo(index)
			if icon then
				return icon
			end
		end
	end
	return GetInventoryItemTexture("player", SLOT[hand]) or ATTACK_ICON
end

-- Shields, held items and relics sit in the off-hand and ranged slots but
-- never swing; only a weapon there gets a lane. Missing item data keeps the
-- lane (never hide a lane on unknown data).
local function HasWeapon(hand)
	local itemID = GetInventoryItemID("player", SLOT[hand])
	if not itemID then
		return false
	end
	if hand == "mainhand" or not GetItemInfoInstant then
		return true
	end
	local classID = select(6, GetItemInfoInstant(itemID))
	return classID == nil or classID == WEAPON_CLASS_ID
end

-- ---------------------------------------------------------------------------
-- Auto Shot as a cast
-- ---------------------------------------------------------------------------

-- The ranged weapon's base speed, by item ID: read once per weapon (a fixed
-- item stat); a tooltip without the line (item data not loaded yet) is read
-- again later.
local baseSpeeds, baseRetryAt = {}, {}

local function BaseSpeed()
	if Hands.testBaseSpeed then
		return Hands.testBaseSpeed
	end
	local itemID = GetInventoryItemID("player", SLOT.ranged)
	if not itemID or not GetTooltipItem then
		return nil
	end
	local speed = baseSpeeds[itemID]
	if speed or GetTime() < (baseRetryAt[itemID] or 0) then
		return speed
	end
	local data = GetTooltipItem("player", SLOT.ranged)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.rightText
		local match = type(text) == "string" and not IsSecret(text) and text:match(SPEED_PATTERN)
		if match then
			speed = tonumber((match:gsub(",", ".")))
			break
		end
	end
	if speed and speed > 0 then
		baseSpeeds[itemID] = speed
		return speed
	end
	baseRetryAt[itemID] = GetTime() + BASE_SPEED_RETRY
	return nil
end

-- The Auto Shot windup for a ranged speed, or nil without the weapon's base
-- speed (the ranged lane then keeps its hollow diamond). Test lanes pass
-- their own base speed.
function Hands.Windup(speed, base)
	base = speed and (base or BaseSpeed())
	return base and WINDUP_BASE * speed / base or nil
end

local autoShotIcon -- read once: a spell's texture never changes
function Hands.AutoShotIcon()
	autoShotIcon = autoShotIcon or (GetSpellTexture and GetSpellTexture(AUTO_SHOT_SPELL))
	return autoShotIcon or ATTACK_ICON
end

-- The next shot as a cast: its windup bar ending at the Auto Shot icon
-- (full color: the library's expiry is fact-grade; amber-bordered while
-- moving holds it back), then the cadence chain (Layout.AppendChain),
-- dimmed and desaturated, each shot with its dim windup bar.
function Hands.AppendShots(out, expiration, speed, windup, now, held, shake)
	local icon = Hands.AutoShotIcon()
	out[#out + 1] = { shape = "bar", tStart = expiration - windup, tEnd = expiration, autoShot = true }
	out[#out + 1] = { t = expiration, icon = icon, predicted = true, autoShot = true, border = held and "amber" or nil, shake = shake }
	local first = #out + 1
	Layout.AppendChain(out, expiration, speed, icon, now)
	for i = first, #out do
		local shot = out[i]
		shot.autoShot = true
		local at = expiration + shot.after
		out[#out + 1] = { shape = "bar", tStart = at - windup, tEnd = at, autoShot = true, chain = true }
	end
end

-- Entries made while test effects drive the hands are tagged for removal.
local function Ingest(entry)
	entry.test = Hands.testing
	return Store:Ingest(entry)
end

-- ---------------------------------------------------------------------------
-- The lane
-- ---------------------------------------------------------------------------

local function Collect(lane, now, out)
	Layout.CollectHappened(lane, now, out)
	local state, icon = lane.state, lane.icon
	lane.castShots = nil
	if not state.active then
		out[#out + 1] = { atNow = true, icon = icon, dim = true } -- the parked mark
		return
	end
	local speed, expiration = state.speed, state.expiration
	if state.paused then
		-- A paused hand freezes: its marks keep their offset from the now
		-- line, dimmed, until the swing resumes.
		Layout.AppendPaused(out, expiration - state.pausedAt, speed, icon)
		return
	end
	-- Ranged: Auto Shot as a cast (the hollow diamond without the weapon's
	-- base speed).
	local windup = lane.hand == "ranged" and Hands.Windup(speed)
	if windup then
		lane.castShots = true
		Hands.AppendShots(out, expiration, speed, windup, now, state.heldSince, lane.shakeStart)
		return
	end
	local queued = lane.hand == "mainhand" and state.queuedIcon
	out[#out + 1] = {
		t = expiration,
		icon = queued or icon,
		queued = queued and true or nil,
		predicted = true,
		border = state.heldSince and "amber" or nil,
		shake = lane.shakeStart,
	}
	Layout.AppendChain(out, expiration, speed, icon, now)
end

local function IsActive(lane)
	return lane.state.active
end

-- A hand's lane needs its weapon (test effects show main hand and ranged
-- without one).
local function Available(lane)
	return HasWeapon(lane.hand) or (Hands.testing and lane.hand ~= "offhand") or false
end

for i, hand in ipairs(HANDS) do
	lanes[hand] = {
		key = hand, group = "hand", order = i, hand = hand, state = {}, setting = SETTING[hand],
		Collect = Collect, IsActive = IsActive, Available = Available,
	}
	Layout:DeclareLane(lanes[hand])
end

-- Re-checks the hand lanes' presence and refreshes their icons; a lane only
-- rebuilds when its icon changed (UNIT_INVENTORY_CHANGED fires on every bag
-- change).
function Hands:UpdatePresence()
	Layout:RefreshPresence()
	for _, hand in ipairs(HANDS) do
		local lane = lanes[hand]
		local icon = CurrentIcon(hand)
		if icon ~= lane.icon then
			lane.icon = icon
			Renderer:MarkDirty(lane)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Library events -> state, happened entries and effects
-- ---------------------------------------------------------------------------

-- The landing's icon: the on-next-swing ability it carried (its SUCCEEDED
-- arrived just before), else the hand's current icon. The second value is
-- true when an ability rode the swing.
local function LandingIcon(lane, now)
	local state = lane.state
	if state.pendingIcon and now - state.pendingAt <= ON_NEXT_SWING_WINDOW then
		local icon = state.pendingIcon
		state.pendingIcon = nil
		return icon, true
	end
	return lane.icon
end

-- The red treatment: clip tick at the reset instant, red pop on the new
-- prediction, across-lane shake, streak - once per reset (a CLIPPED and the
-- mid-flight START report the same reset).
local function ResetFeedback(lane, at, from, to)
	local state = lane.state
	if at - (state.resetAt or -1) < RESET_DEDUPE then
		return
	end
	state.resetAt = at
	Ingest({ kind = "clip", lane = lane.key, shape = "tick", time = at })
	Effects:Correct(lane, from, to or from, Effects.RED)
	Effects:Shake(lane)
	Renderer:MarkDirty(lane)
end

function Hands:OnStart(hand, speed, expiration, isUpdate)
	local lane = lanes[hand]
	if IsSecret(speed) or IsSecret(expiration) then
		Util.CountDrop("swing")
		return
	end
	if not lane.registered then
		-- A swing proves the weapon: pick up a lane the inventory read missed.
		self:UpdatePresence()
	end
	local state, now = lane.state, GetTime()
	local previous = state.expiration
	if isUpdate then
		local reason = Classify.Update(hand, state, expiration, now)
		if reason == "retry" then
			-- The honest sawtooth: every retry jumps the mark out; the chain
			-- wears the amber border and gets one amber pop.
			Effects:Correct(lane, previous, expiration, Effects.AMBER, not state.heldSince)
			state.heldSince = state.heldSince or now
		elseif reason then -- parry or rescale: the landing moved earlier
			Effects:Correct(lane, previous, expiration, Effects.TEAL)
		end
	else
		local reason = Classify.Start(state, speed, now)
		if reason == "reset" then
			ResetFeedback(lane, now, previous, expiration)
		elseif reason == "swap" then
			ResetFeedback(lane, state.stoppedAt, previous, expiration)
		else
			-- A landing: at the anchor, with the icon it landed with.
			local landing = expiration - speed
			local icon, onSwing = LandingIcon(lane, now)
			local entry = { kind = "swing", lane = lane.key, time = landing, icon = icon, onSwing = onSwing }
			-- A shot's entry keeps the weapon's icon; the bar draws its windup
			-- and the Auto Shot icon in its place.
			local windup = hand == "ranged" and Hands.Windup(speed)
			if windup then
				entry.castStart, entry.autoShot = landing - windup, true
			end
			Ingest(entry)
			state.lastLanding, state.lastLandingAt = entry, now
			if reason == "early" then
				Effects:Correct(lane, previous, landing, Effects.TEAL)
			end
			if state.heldSince then
				-- The delay span: from the first retry to the shot that fired.
				Ingest({ kind = "delay", lane = lane.key, time = state.heldSince, duration = landing - state.heldSince, color = Effects.AMBER })
				state.heldSince = nil
			end
		end
	end
	state.speed, state.expiration, state.active, state.paused = speed, expiration, true, nil
	Renderer:MarkDirty(lane)
end

-- A stop with nothing following within the grace was cut short: it just
-- parks (no red - nothing went wrong). A START in the grace classifies it.
-- The expiration is kept: `active` guards every read, and the next START's
-- correction streak starts from it.
function Hands:OnStop(hand)
	local lane = lanes[hand]
	Classify.Stop(lane.state, GetTime())
	lane.state.active, lane.state.paused = false, nil
	Renderer:MarkDirty(lane)
end

function Hands:OnClipped(hand)
	local state = lanes[hand].state
	if state.active then
		ResetFeedback(lanes[hand], GetTime(), state.expiration, nil)
	end
end

function Hands:OnPaused(hand)
	local state = lanes[hand].state
	if state.active then
		state.paused, state.pausedAt = true, GetTime()
		Renderer:MarkDirty(lanes[hand])
	end
end

-- Seeds in-flight swings from the library (login, reload, its own init).
function Hands:Seed()
	local now = GetTime()
	for _, hand in ipairs(HANDS) do
		local speed, expiration = Addon.lib:UnitSwingTimerInfo("player", hand)
		local state = lanes[hand].state
		if speed and expiration and not IsSecret(speed) and not IsSecret(expiration) and expiration > now then
			state.speed, state.expiration, state.active = speed, expiration, true
			Renderer:MarkDirty(lanes[hand])
		end
	end
end

-- Whatever the visibility: a swing past its expiry with no STOP has landed
-- and parks (4everSwingTimer's stale-landing convergence), and a held retry
-- chain whose STOP was followed by no START is over.
local function Sweep()
	local now = GetTime()
	for _, hand in ipairs(HANDS) do
		local state = lanes[hand].state
		if state.active and state.expiration + Classify.STALE_LANDING_GRACE < now then
			Hands:OnStop(hand)
		elseif not state.active and state.heldSince and now - (state.stoppedAt or now) > Classify.STOP_WINDOW then
			state.heldSince = nil
		end
	end
end

-- The queued next-melee ability swaps the main hand's next-landing icon.
-- No event reports queue changes; IsCurrentSpell is a cheap plain read.
local function PollQueued()
	local lane = lanes.mainhand
	local icon
	for i = 1, #QUEUED_SPELLS do
		if IsCurrentSpell(QUEUED_SPELLS[i]) then
			icon = GetSpellTexture and GetSpellTexture(QUEUED_SPELLS[i])
			break
		end
	end
	if icon ~= lane.state.queuedIcon then
		lane.state.queuedIcon = icon
		Renderer:MarkDirty(lane)
	end
end

-- True for an on-next-swing ability (any rank): its happened mark belongs
-- to the main-hand swing it rode, never to the cast lane.
function Hands.IsOnNextSwing(spellID)
	local base = FindBaseSpellByID and FindBaseSpellByID(spellID) or spellID
	return ON_NEXT_SWING[base] or ON_NEXT_SWING[spellID] or false
end

-- True for a spell the hand lanes own, never a cast-lane mark: the
-- on-next-swing abilities and the auto-attack toggle.
function Hands.OwnsSpell(spellID)
	return spellID == ATTACK_SPELL or Hands.IsOnNextSwing(spellID)
end

-- An on-next-swing ability's SUCCEEDED (routed here by the cast lane, which
-- owns the spellcast events): tag the landing it rode. If the swing's START
-- came first this frame, retag that landing; else hold the icon for the
-- START.
function Hands:OnSpellSucceeded(spellID)
	local lane, now = lanes.mainhand, GetTime()
	local state, icon = lane.state, GetSpellTexture and GetSpellTexture(spellID)
	if state.lastLanding and state.lastLandingAt == now then
		state.lastLanding.icon, state.lastLanding.onSwing = icon, true
		Renderer:MarkDirty(lane)
	else
		state.pendingIcon, state.pendingAt = icon, now
	end
end

-- ---------------------------------------------------------------------------
-- Test effects support
-- ---------------------------------------------------------------------------

-- Test effects drive OnStart/OnStop/OnClipped directly (seam 1b) on the main
-- hand and ranged lanes, shown even without the weapons; their entries are
-- tagged for removal.
function Hands:SetTesting(testing)
	self.testing = testing or nil
	-- The replayed ranged hand has no weapon to read a base speed from.
	self.testBaseSpeed = testing and Hands.TEST_BASE_SPEED or nil
	if not testing then
		for _, hand in ipairs(HANDS) do
			wipe(lanes[hand].state)
		end
		Store:RemoveWhere(function(entry)
			return entry.test and lanes[entry.lane] ~= nil
		end)
		self:Seed()
	end
	self:UpdatePresence()
end

function Hands:State(hand)
	return lanes[hand].state
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

local LIB_EVENTS = {
	"UNIT_SWING_TIMER_START",
	"UNIT_SWING_TIMER_UPDATE",
	"UNIT_SWING_TIMER_STOP",
	"UNIT_SWING_TIMER_CLIPPED",
	"UNIT_SWING_TIMER_PAUSED",
	"UNIT_SWING_TIMER_INFO_INITIALIZED",
}

function Hands:Init(lib)
	isDruid = select(2, UnitClass("player")) == "DRUID"
	local function Handle(event, unitId, a, b, c)
		if unitId ~= "player" then
			return
		end
		if event == "UNIT_SWING_TIMER_INFO_INITIALIZED" then
			Hands:Seed()
			return
		end
		local isSwing = event == "UNIT_SWING_TIMER_START" or event == "UNIT_SWING_TIMER_UPDATE"
		local hand = isSwing and c or a -- START/UPDATE: speed, expiration, hand
		if not lanes[hand] then
			return
		end
		if isSwing then
			Hands:OnStart(hand, a, b, event == "UNIT_SWING_TIMER_UPDATE")
		elseif event == "UNIT_SWING_TIMER_STOP" then
			Hands:OnStop(hand)
		elseif event == "UNIT_SWING_TIMER_CLIPPED" then
			Hands:OnClipped(hand)
		elseif event == "UNIT_SWING_TIMER_PAUSED" then
			Hands:OnPaused(hand)
		end
	end
	for _, event in ipairs(LIB_EVENTS) do
		lib.RegisterCallback(Hands, event, Handle)
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	-- The inventory can read empty at login: re-check when the world loads and
	-- once more a second later (4everSwingTimer's pattern), and on any
	-- inventory change; a swing on a lane-less hand also re-checks (OnStart).
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	events:SetScript("OnEvent", function(_, event)
		Hands:UpdatePresence()
		if event == "PLAYER_ENTERING_WORLD" then
			C_Timer.After(1.0, function()
				Hands:UpdatePresence()
			end)
		end
	end)

	if IsCurrentSpell then
		C_Timer.NewTicker(QUEUE_POLL, PollQueued)
	end
	C_Timer.NewTicker(SWEEP_INTERVAL, Sweep)
	self:UpdatePresence()
	self:Seed()
end
