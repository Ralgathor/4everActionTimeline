-- 4everActionTimeline — the renderer (Flat skin, horizontal).
-- One OnUpdate pass over pooled widgets. A lane's mark set - every texture,
-- tint and border - is rebuilt only when that lane changed (it flagged
-- itself dirty, its store entries changed, the layout changed) plus a 1 s
-- safety pass; each lane owns its widget pools, reused in place, so one
-- lane's change never reconfigures another's widgets. Each frame only moves
-- readable marks along the time axis, and skips any widget that did not
-- move (docs/SPEC.md, Performance budget). A hidden frame receives no
-- OnUpdate, so showing it forces a full rebuild, and the expiry sweep runs
-- on its own low-frequency ticker whatever the visibility (hidden-frame
-- convergence). The frame never takes the mouse.

local Addon = FourEverActionTimeline
local Util, Layout, Store, Effects = Addon.Util, Addon.Layout, Addon.Store, Addon.Effects
local ShakeOffset = Effects.ShakeOffset

local GetTime = GetTime
local debugprofilestop = debugprofilestop
local ipairs, max, min, random, wipe = ipairs, math.max, math.min, math.random, wipe

local WHITE = [[Interface\Buttons\WHITE8X8]]
local QUESTION_MARK = 134400 -- INV_Misc_QuestionMark
local ICON_CROP = 0.08
local SAFETY_REBUILD = 1.0
local SWEEP_INTERVAL = 0.5
-- The store keeps entries this long past the past edge (research: past + 2 s).
local STORE_MARGIN = 2
local PERF_SAMPLES = 300
local DIM_ALPHA = 0.5
local BAR_HEIGHT_RATIO = 0.4
local CHEVRON_ATLAS = "uitools-icon-chevron-right" -- probe 14
local TRACK_COLOR = { 1, 1, 1, 0.18 }
local NOW_COLOR = { 1, 1, 1, 0.6 }
-- Red (cast failure, clip) and amber (the held ranged hand) are the effect
-- colors, so a border always matches its pop.
local BORDER_COLORS = {
	default = { 0, 0, 0, 1 },
	red = { Effects.RED[1], Effects.RED[2], Effects.RED[3], 1 },
	amber = { Effects.AMBER[1], Effects.AMBER[2], Effects.AMBER[3], 1 },
}
-- Blizzard's action-bar usability tints (VISUAL.md, State tints).
local TINTS = {
	resource = { 0.5, 0.5, 1.0 },
	unusable = { 0.4, 0.4, 0.4 },
}
local TICK_COLOR = BORDER_COLORS.red

local Renderer = {}
Addon.Renderer = Renderer

local frame, barLayer, markLayer, nowLine
local laneFrames = {}
local scratch = {}
local allDirty, layoutDirty = true, true
-- Frame-time rings (ms): plain frames, frames that also rebuilt a lane, and
-- layout frames (sizing lanes, creating widgets: the first frame shown).
local perfSteady, perfRebuild, perfLayout = {}, {}, {}

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------

local function SizeChevron(chevron, size)
	chevron:SetSize(size, size)
	if chevron.upper then
		local length = size * 0.7
		chevron.upper:SetSize(length, 2)
		chevron.lower:SetSize(length, 2)
		chevron.upper:SetPoint("CENTER", chevron, "CENTER", 0, size * 0.22)
		chevron.lower:SetPoint("CENTER", chevron, "CENTER", 0, -size * 0.22)
	end
end

-- The edge-clamp cue: the probed chevron atlas, or a ">" of two rotated
-- WHITE8X8 strokes where the atlas is missing (VISUAL.md, Edge clamp cue).
local function CreateChevron(parent)
	local chevron = CreateFrame("Frame", nil, parent)
	chevron:SetPoint("LEFT", parent, "RIGHT", 2, 0)
	local r, g, b = TRACK_COLOR[1], TRACK_COLOR[2], TRACK_COLOR[3]
	if Util.AtlasExists(CHEVRON_ATLAS) then
		local texture = chevron:CreateTexture(nil, "OVERLAY")
		texture:SetAllPoints()
		texture:SetAtlas(CHEVRON_ATLAS)
		texture:SetVertexColor(r, g, b, 0.9)
	else
		chevron.upper = chevron:CreateTexture(nil, "OVERLAY")
		chevron.upper:SetTexture(WHITE)
		chevron.upper:SetVertexColor(r, g, b, 0.9)
		chevron.upper:SetRotation(-math.pi / 4)
		chevron.lower = chevron:CreateTexture(nil, "OVERLAY")
		chevron.lower:SetTexture(WHITE)
		chevron.lower:SetVertexColor(r, g, b, 0.9)
		chevron.lower:SetRotation(math.pi / 4)
	end
	chevron:Hide()
	return chevron
end

local function CreateMark()
	local mark = CreateFrame("Frame", nil, markLayer)
	mark.border = mark:CreateTexture(nil, "BACKGROUND")
	mark.border:SetAllPoints()
	mark.icon = mark:CreateTexture(nil, "ARTWORK")
	mark.icon:SetPoint("TOPLEFT", mark, "TOPLEFT", 1, -1)
	mark.icon:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", -1, 1)
	mark.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	mark.chevron = CreateChevron(mark)
	return mark
end

local function ResetMark(mark)
	mark:Hide()
	mark:ClearAllPoints()
	mark.chevron:Hide()
	mark.desc, mark.laneFrame, mark.pinned, mark.visible, mark.x, mark.y = nil, nil, nil, nil, nil, nil
end

local function CreateTick()
	local tick = barLayer:CreateTexture(nil, "ARTWORK")
	tick:SetTexture(WHITE)
	return tick
end

local function ResetTick(tick)
	tick:Hide()
	tick:ClearAllPoints()
	tick.desc, tick.laneFrame, tick.visible, tick.x = nil, nil, nil, nil
end

-- A window bar: the elapsed span at full color, the unelapsed span
-- desaturated, split at the now line (SPEC, GCD lane).
local function CreateBar()
	local bar = {
		elapsed = barLayer:CreateTexture(nil, "ARTWORK"),
		unelapsed = barLayer:CreateTexture(nil, "ARTWORK"),
	}
	bar.elapsed:SetTexture(WHITE)
	bar.unelapsed:SetTexture(WHITE)
	return bar
end

local function ResetSpan(texture)
	texture:Hide()
	texture:ClearAllPoints()
	texture.visible, texture.x, texture.width = nil, nil, nil
end

local function ResetBar(bar)
	ResetSpan(bar.elapsed)
	ResetSpan(bar.unelapsed)
	bar.desc, bar.laneFrame = nil, nil
end

-- Each lane frame owns one pool per widget shape; a pool's `used` array is
-- exactly what the last rebuild placed.
local function CreateLaneFrame()
	local lane = CreateFrame("Frame", nil, frame)
	lane.band = lane:CreateTexture(nil, "BACKGROUND")
	lane.band:SetAllPoints()
	lane.track = lane:CreateTexture(nil, "BORDER")
	lane.track:SetColorTexture(TRACK_COLOR[1], TRACK_COLOR[2], TRACK_COLOR[3], TRACK_COLOR[4])
	lane.marks = Util.NewPool(CreateMark, ResetMark)
	lane.ticks = Util.NewPool(CreateTick, ResetTick)
	lane.bars = Util.NewPool(CreateBar, ResetBar)
	return lane
end

-- Releases every widget of a lane frame that no lane uses any more.
local function ClearLaneFrame(laneFrame)
	laneFrame.marks:BeginReuse()
	laneFrame.marks:Trim()
	laneFrame.ticks:BeginReuse()
	laneFrame.ticks:Trim()
	laneFrame.bars:BeginReuse()
	laneFrame.bars:Trim()
end

-- ---------------------------------------------------------------------------
-- Configure (on rebuild)
-- ---------------------------------------------------------------------------

-- Widgets are reused in place across rebuilds and remember what they were
-- last set to, so a rebuild only calls the API for what actually changed.
local function ConfigureMark(mark, desc)
	local size = Layout.iconSize
	if mark.size ~= size then
		mark.size = size
		mark:SetSize(size, size)
		SizeChevron(mark.chevron, Layout.chevronSize)
	end
	local icon = desc.icon or QUESTION_MARK
	if mark.iconTexture ~= icon then
		mark.iconTexture = icon
		mark.icon:SetTexture(icon)
	end
	local desaturated = desc.desaturated and true or false
	if mark.desaturated ~= desaturated then
		mark.desaturated = desaturated
		mark.icon:SetDesaturated(desaturated)
	end
	local tintKey = desc.tint or "none"
	if mark.tintKey ~= tintKey then
		mark.tintKey = tintKey
		local tint = TINTS[tintKey]
		if tint then
			mark.icon:SetVertexColor(tint[1], tint[2], tint[3])
		else
			mark.icon:SetVertexColor(1, 1, 1)
		end
	end
	local alpha = desc.dim and DIM_ALPHA or 1
	if mark.alphaValue ~= alpha then
		mark.alphaValue = alpha
		mark:SetAlpha(alpha)
	end
	local borderKey = desc.border or "default"
	if mark.borderKey ~= borderKey then
		mark.borderKey = borderKey
		local border = BORDER_COLORS[borderKey] or BORDER_COLORS.default
		mark.border:SetColorTexture(border[1], border[2], border[3], border[4])
	end
end

local function ConfigureTick(tick, desc)
	local color = desc.color or TICK_COLOR
	if tick.colorRef ~= color then
		tick.colorRef = color
		tick:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	end
	local height = max(Layout.laneHeight / 3, 4)
	if tick.height ~= height then
		tick.height = height
		tick:SetSize(2, height)
	end
end

local function ConfigureBar(bar, desc)
	local color = desc.color
	if bar.colorRef ~= color then
		bar.colorRef = color
		local r, g, b, a = color[1], color[2], color[3], color[4] or 1
		bar.elapsed:SetVertexColor(r, g, b, a)
		local gr, gg, gb = Util.Gray(r, g, b)
		bar.unelapsed:SetVertexColor(gr, gg, gb, a * 0.8)
	end
	local height = max(Layout.iconSize * BAR_HEIGHT_RATIO, 3)
	if bar.height ~= height then
		bar.height = height
		bar.elapsed:SetHeight(height)
		bar.unelapsed:SetHeight(height)
	end
end

-- ---------------------------------------------------------------------------
-- Place (every frame)
-- ---------------------------------------------------------------------------

local function SetVisible(widget, visible)
	if widget.visible ~= visible then
		widget.visible = visible
		widget:SetShown(visible)
	end
end

-- The anchor name never changes ("CENTER" on the lane's LEFT), so moving a
-- widget needs no ClearAllPoints (the anchor rule); an unmoved one is
-- skipped. y is the across-lane shake offset, never a time offset.
local function Anchor(widget, x, y)
	if widget.x ~= x or widget.y ~= y then
		widget.x, widget.y = x, y
		widget:SetPoint("CENTER", widget.laneFrame, "LEFT", x, y)
	end
end

-- The time a mark or tick is drawn at, and whether the edge clamp pinned it;
-- nil when it is out of the window. A predicted mark never scrolls into the
-- past: an overdue one pins at the now line, and a chain derived from it
-- follows. Past the far edge a predicted mark clamps (the edge clamp) and a
-- chain mark hides.
-- An atNow mark sits at a fixed offset from the now line (`after`, 0 by
-- default): the idle family on it, a paused hand's frozen marks ahead of it.
local function ResolveTime(desc, now)
	local t, far = desc.t, Layout:FarEdge(now)
	if desc.atNow or desc.predicted then
		if desc.atNow or t < now then
			t = now
		end
		t = t + (desc.after or 0)
		if t > far then
			if desc.chain then
				return nil
			end
			return far, true
		end
		return t, false
	end
	if t < Layout:CullEdge(now) or t > far then
		return nil
	end
	return t, false
end

local function PlaceMark(mark, now)
	local t, pinned = ResolveTime(mark.desc, now)
	if not t then
		SetVisible(mark, false)
		return
	end
	local shake = mark.desc.shake
	Anchor(mark, Layout:TimeToX(t, now), shake and ShakeOffset(shake, now) or 0)
	if mark.pinned ~= pinned then
		mark.pinned = pinned
		mark.chevron:SetShown(pinned)
	end
	SetVisible(mark, true)
end

local function PlaceTick(tick, now)
	local t = ResolveTime(tick.desc, now)
	if not t then
		SetVisible(tick, false)
		return
	end
	Anchor(tick, Layout:TimeToX(t, now), 0)
	SetVisible(tick, true)
end

local function PlaceSpan(texture, laneFrame, from, to, now)
	if to <= from then
		SetVisible(texture, false)
		return
	end
	local x = Layout:TimeToX(from, now)
	if texture.x ~= x then
		texture.x = x
		texture:SetPoint("LEFT", laneFrame, "LEFT", x, 0)
	end
	local width = max((to - from) * Layout.pxPerSec, 1)
	if texture.width ~= width then
		texture.width = width
		texture:SetWidth(width)
	end
	SetVisible(texture, true)
end

local function PlaceBar(bar, now)
	local desc = bar.desc
	local from = max(desc.tStart, Layout:CullEdge(now))
	local to = min(desc.tEnd, Layout:FarEdge(now))
	PlaceSpan(bar.elapsed, bar.laneFrame, from, min(to, now), now)
	PlaceSpan(bar.unelapsed, bar.laneFrame, max(from, now), to, now)
end

-- ---------------------------------------------------------------------------
-- Layout and rebuild
-- ---------------------------------------------------------------------------

local function ApplyLayout()
	Layout:Compute()
	local lanes = Layout:Lanes()
	frame:SetSize(Layout.width, max(Layout.height, 1))
	frame:SetScale(Addon:GetSetting("scale"))
	local bandAlpha = Addon:GetSetting("backgroundAlpha")
	local trackLength = Layout.future * Layout.pxPerSec + Layout.nowX - Layout.padStart
	for i, lane in ipairs(lanes) do
		local laneFrame = laneFrames[i]
		if not laneFrame then
			laneFrame = CreateLaneFrame()
			laneFrames[i] = laneFrame
		end
		laneFrame:ClearAllPoints()
		laneFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -Layout:LaneOffset(i))
		laneFrame:SetSize(Layout.width, Layout.laneHeight)
		laneFrame.band:SetColorTexture(1, 1, 1, bandAlpha)
		laneFrame.band:SetShown(bandAlpha > 0)
		laneFrame.track:ClearAllPoints()
		laneFrame.track:SetPoint("LEFT", laneFrame, "LEFT", Layout.padStart, 0)
		laneFrame.track:SetSize(trackLength, 1)
		laneFrame:Show()
		lane.frame = laneFrame
	end
	for i = #lanes + 1, #laneFrames do
		ClearLaneFrame(laneFrames[i])
		laneFrames[i]:Hide()
	end
	nowLine:ClearAllPoints()
	nowLine:SetPoint("TOP", frame, "TOPLEFT", Layout.nowX, 0)
	nowLine:SetSize(2, max(Layout.height, 1))
	layoutDirty = false
	allDirty = true
end

local function RebuildLane(lane, now)
	local laneFrame = lane.frame
	local marks, ticks, bars = laneFrame.marks, laneFrame.ticks, laneFrame.bars
	marks:BeginReuse()
	ticks:BeginReuse()
	bars:BeginReuse()
	wipe(scratch)
	lane:Collect(now, scratch)
	for i = 1, #scratch do
		local desc = scratch[i]
		local shape = desc.shape
		local widget
		if shape == "bar" then
			widget = bars:Take()
			ConfigureBar(widget, desc)
		elseif shape == "tick" then
			widget = ticks:Take()
			ConfigureTick(widget, desc)
		else
			widget = marks:Take()
			ConfigureMark(widget, desc)
		end
		widget.desc, widget.laneFrame = desc, laneFrame
	end
	marks:Trim()
	ticks:Trim()
	bars:Trim()
	lane.dirty = false
	lane.builtVersion = Store:LaneVersion(lane.key)
	-- Jittered, so the lanes' safety passes do not all land on one frame.
	lane.nextRebuild = now + SAFETY_REBUILD * (0.75 + 0.5 * random())
end

local function Record(samples, value)
	local index = (samples.index or 0) % PERF_SAMPLES + 1
	samples.index = index
	samples[index] = value
end

local function OnUpdate()
	local start = debugprofilestop and debugprofilestop()
	local now = GetTime()
	local rebuilt, laidOut = false, layoutDirty
	if layoutDirty then
		ApplyLayout()
	end
	local lanes = Layout:Lanes()
	for i = 1, #lanes do
		local lane = lanes[i]
		if allDirty or lane.dirty or lane.builtVersion ~= Store:LaneVersion(lane.key) or now >= (lane.nextRebuild or 0) then
			RebuildLane(lane, now)
			rebuilt = true
		end
	end
	allDirty = false
	for i = 1, #lanes do
		local laneFrame = lanes[i].frame
		local used = laneFrame.marks.used
		for j = 1, #used do
			PlaceMark(used[j], now)
		end
		used = laneFrame.ticks.used
		for j = 1, #used do
			PlaceTick(used[j], now)
		end
		used = laneFrame.bars.used
		for j = 1, #used do
			PlaceBar(used[j], now)
		end
	end
	Effects:Place(now)
	if start then
		Record(laidOut and perfLayout or rebuilt and perfRebuild or perfSteady, debugprofilestop() - start)
	end
end

-- ---------------------------------------------------------------------------
-- Visibility and the sweep
-- ---------------------------------------------------------------------------

-- "Active" visibility: a happened entry inside the past window (entries are
-- in time order, so the newest decides), or a lane reporting a live mark.
-- Evaluated by the sweep while hidden, so it reads the setting, not Layout.
function Renderer:IsActive(now)
	local latest = Store:Latest()
	if latest and latest.time >= now - Addon:GetSetting("pastWindow") then
		return true
	end
	for _, lane in ipairs(Layout:Lanes()) do
		if lane.IsActive and lane:IsActive(now) then
			return true
		end
	end
	return false
end

function Renderer:UpdateVisibility()
	if not frame then
		return
	end
	local show
	if Addon.testing then
		show = true
	else
		local mode = Addon:GetSetting("visibility")
		if mode == "always" then
			show = true
		elseif mode == "active" then
			show = self:IsActive(GetTime())
		else
			show = Addon.inCombat and true or false
		end
	end
	frame:SetShown(show and #Layout:Lanes() > 0)
end

local function Sweep()
	Store:Prune(GetTime() - Addon:GetSetting("pastWindow") - STORE_MARGIN)
	Renderer:UpdateVisibility()
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- With a lane, rebuilds that lane on the next frame; without, every lane.
function Renderer:MarkDirty(lane)
	if lane then
		lane.dirty = true
	else
		allDirty = true
	end
	-- "Active" visibility shows the frame the moment a lane changes (a cast or
	-- swing starting) instead of waiting for the sweep.
	if frame and not frame:IsShown() and Addon:GetSetting("visibility") == "active" then
		self:UpdateVisibility()
	end
end

-- The next frame re-lays the lanes out, which also rebuilds every lane.
function Renderer:MarkLayoutDirty()
	layoutDirty = true
end

local function Summarize(samples)
	local count, sum, worst = #samples, 0, 0
	for i = 1, count do
		local sample = samples[i]
		sum = sum + sample
		if sample > worst then
			worst = sample
		end
	end
	return { count = count, average = count > 0 and sum / count or 0, worst = worst }
end

-- Frame times (ms) over the recent samples, by frame kind, for the
-- performance budget (docs/SPEC.md).
function Renderer:Perf()
	local lanes, widgets = Layout:Lanes(), 0
	for i = 1, #lanes do
		local laneFrame = lanes[i].frame
		if laneFrame then
			widgets = widgets + #laneFrame.marks.used + #laneFrame.ticks.used + #laneFrame.bars.used
		end
	end
	return Summarize(perfSteady), Summarize(perfRebuild), Summarize(perfLayout), widgets, #lanes
end

-- The lane keys in order and whether the frame is shown, for /actiontimeline status.
function Renderer:Status()
	local keys = {}
	for i, lane in ipairs(Layout:Lanes()) do
		keys[i] = lane.key
	end
	return keys, frame ~= nil and frame:IsShown()
end

function Renderer:ResetPerf()
	wipe(perfSteady)
	wipe(perfRebuild)
	wipe(perfLayout)
end

function Renderer:Init()
	if frame then
		return
	end
	frame = CreateFrame("Frame", "FourEverActionTimelineFrame", UIParent)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	frame:SetFrameStrata("MEDIUM")
	frame:EnableMouse(false)
	if frame.SetClipsChildren then
		frame:SetClipsChildren(true)
	end
	frame:Hide()
	-- Draw order: lane bands and tracks, then bars and ticks, then the now
	-- line, then icon marks, then transient effects on top.
	local level = frame:GetFrameLevel()
	barLayer = CreateFrame("Frame", nil, frame)
	barLayer:SetAllPoints()
	barLayer:SetFrameLevel(level + 2)
	local nowLayer = CreateFrame("Frame", nil, frame)
	nowLayer:SetAllPoints()
	nowLayer:SetFrameLevel(level + 3)
	markLayer = CreateFrame("Frame", nil, frame)
	markLayer:SetAllPoints()
	markLayer:SetFrameLevel(level + 4)
	local effectsLayer = CreateFrame("Frame", nil, frame)
	effectsLayer:SetAllPoints()
	effectsLayer:SetFrameLevel(level + 5)
	Effects:Init(effectsLayer)
	nowLine = nowLayer:CreateTexture(nil, "OVERLAY")
	nowLine:SetColorTexture(NOW_COLOR[1], NOW_COLOR[2], NOW_COLOR[3], NOW_COLOR[4])

	frame:SetScript("OnShow", function()
		Renderer:MarkLayoutDirty()
	end)
	frame:SetScript("OnUpdate", OnUpdate)
	C_Timer.NewTicker(SWEEP_INTERVAL, Sweep)
	self:UpdateVisibility()
end
