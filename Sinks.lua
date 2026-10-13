-- 4everActionTimeline — engine-drawn sink lanes (docs/SPEC.md, Engine-drawn
-- lane constraints; ADR-0001). An opt-in overlay per spell, never the
-- foundation: a transparent StatusBar spans the future window, min/max set
-- to the window in seconds, fed every frame the cooldown's secret remaining
-- time (C_Spell.GetSpellCooldownDuration, ignoreGCD so the GCD keeps its
-- own lane). StatusBar:SetValue accepts the secret and the layout engine
-- places the spell's icon, anchored to the fill's leading edge (build 70205
-- smoke tests): pinned at the far edge while the cooldown exceeds the
-- window, at rest on the now line at zero (where a ready mark parks - no
-- hide-on-complete needed). Display-only: Lua never reads its geometry, the
-- icon is a leaf, linear scale only, no chevron. Full color: engine truth.
-- Sink lanes group at the bottom, in lane order; the optional countdown is
-- the engine's own Cooldown numbers, fed the same secret. Every orientation:
-- the bar fills from the now line toward the far edge (SetOrientation,
-- SetReverseFill), the icon on the fill's end-facing edge.

local Addon = FourEverActionTimeline
-- Loaded before the renderer: Addon.Renderer is looked up when needed.
local Util, Layout, Skin, SingleLane = Addon.Util, Addon.Layout, Addon.Skin, Addon.SingleLane

local GetCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration

local Sinks = {
	-- At most this many: the per-frame GetSpellCooldownDuration read is the
	-- one cost that cannot be trimmed (SPEC, Performance budget). The spell
	-- lanes count against it when they pick the sinks.
	MAX = 6,
}
Addon.Sinks = Sinks

local layer
local lanes = {} -- base ID -> sink lane (widgets kept for reuse)
local shown = {} -- the registered sink lanes, fed every frame

local function Collect() end -- no readable marks: the engine draws the icon

-- The bar, its icon (a leaf on the fill's edge, framed like a mark) and
-- the countdown.
local function Build(lane)
	local bar = CreateFrame("StatusBar", nil, layer)
	bar:SetStatusBarTexture(Util.WHITE)
	bar:GetStatusBarTexture():SetAlpha(0) -- transparent: only the icon shows
	bar:SetValue(0)
	lane.art = Skin.CreateIconArt(bar)
	lane.iconTexture = lane.art.icon
	lane.countdown = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
	lane.countdown:SetAllPoints(lane.iconTexture)
	if lane.countdown.SetDrawSwipe then
		lane.countdown:SetDrawSwipe(false)
		lane.countdown:SetDrawEdge(false)
		lane.countdown:SetHideCountdownNumbers(false)
	end
	lane.bar = bar
end

-- The engine's countdown, fed the DurationObject while the setting is on.
-- (Not gated on IsShown: a Cooldown frame hides itself when its cooldown
-- ends, and feeding it is what shows it again.)
local function FeedCountdown(lane)
	if not Addon:GetSetting("sinkCountdown") then
		return
	end
	local duration = GetCooldownDuration and GetCooldownDuration(lane.id, true)
	if duration and lane.countdown.SetCooldownFromDurationObject then
		lane.countdown:SetCooldownFromDurationObject(duration)
	end
end

-- Syncs the sink lanes with the spell lanes that opted in (already capped
-- at MAX, in lane order; read for base, id, name, icon and order).
function Sinks:Sync(spellLanes)
	local changed = false
	wipe(shown)
	for _, spell in ipairs(spellLanes) do
		local lane = lanes[spell.base]
		if not lane then
			lane = { key = "sink:" .. spell.base, group = "sink", base = spell.base, Collect = Collect }
			lanes[spell.base] = lane
			Build(lane)
		end
		lane.order, lane.id, lane.name, lane.live = spell.order, spell.id, spell.name .. " (engine)", true
		lane.iconTexture:SetTexture(spell.icon)
		shown[#shown + 1] = lane
	end
	for _, lane in pairs(lanes) do
		if lane.live and not lane.registered then
			lane.registered, changed = true, true
			Layout:RegisterLane(lane)
		elseif not lane.live and lane.registered then
			lane.registered, changed = nil, true
			lane.bar:Hide()
			Layout:UnregisterLane(lane)
		end
		lane.live = nil
	end
	Layout:SortLanes()
	if changed then
		Addon.Renderer:UpdateVisibility()
	end
end

-- After the renderer laid the lanes out: each bar spans its lane's future
-- window, from the now line to the far edge (linear, as TimeToOffset).
function Sinks:Layout()
	local countdown, orient = Addon:GetSetting("sinkCountdown"), Layout.orient
	-- A thin row each under the bar.
	local rowHeight, size = SingleLane.SinkRow(), SingleLane.SinkIcon()
	for _, lane in ipairs(shown) do
		local bar = lane.bar
		bar:ClearAllPoints()
		if lane.frame then
			Layout:PlaceAlong(bar, lane.frame, Layout.nowX, Layout.future * Layout.pxPerSec, rowHeight)
			bar:SetOrientation(orient.axis)
			bar:SetReverseFill(orient.sign < 0)
			bar:SetMinMaxValues(0, Layout.future)
			lane.iconTexture:ClearAllPoints()
			lane.iconTexture:SetPoint("CENTER", bar:GetStatusBarTexture(), orient.finish)
			Skin.StyleIcon(lane.art, size)
			Skin.SetBorder(lane.art, nil)
			lane.countdown:SetShown(countdown)
			FeedCountdown(lane)
			bar:Show()
		else
			bar:Hide()
		end
	end
end

-- Every frame: the secret remaining time, straight into each bar.
function Sinks:Place()
	if not GetCooldownDuration then
		return
	end
	for i = 1, #shown do
		local lane = shown[i]
		local duration = GetCooldownDuration(lane.id, true)
		lane.bar:SetValue(duration and duration:GetRemainingDuration() or 0)
	end
end

-- The renderer's sink layer (above the marks, below the effects).
function Sinks:Init(parent)
	layer = parent
	local events = CreateFrame("Frame")
	events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	events:SetScript("OnEvent", function()
		for _, lane in ipairs(shown) do
			FeedCountdown(lane)
		end
	end)
end
