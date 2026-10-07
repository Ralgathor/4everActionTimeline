-- 4everActionTimeline — the renderer.
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
-- The skin (Skin.lua) and the orientation (Layout.orient) are applied on a
-- layout pass: a widget whose `style` differs from Layout.style re-applies
-- what they decide before its next configure.

local Addon = FourEverActionTimeline
local Util, Layout, Store, Effects, Skin = Addon.Util, Addon.Layout, Addon.Store, Addon.Effects, Addon.Skin
local ShakeOffset = Effects.ShakeOffset

local GetTime = GetTime
local debugprofilestop = debugprofilestop
local ipairs, max, min, random, wipe = ipairs, math.max, math.min, math.random, wipe
local cos, sin, pi = math.cos, math.sin, math.pi

local WHITE = Util.WHITE
local ATLAS = Skin.ATLAS
local QUESTION_MARK = 134400 -- INV_Misc_QuestionMark
local SAFETY_REBUILD = 1.0
local SWEEP_INTERVAL = 0.5
-- The store keeps entries this long past the past edge (research: past + 2 s).
local STORE_MARGIN = 2
local PERF_SAMPLES = 300
local DIM_ALPHA = 0.5
local BAR_HEIGHT_RATIO = 0.4
-- The next predicted mark trails during its last 1.5 s (one GCD: "lands
-- within your next GCD"; VISUAL.md, Motion trail). A constant, not a setting.
local TRAIL_ONSET = 1.5
-- Blizzard anchors the trail's end 10 px into the icon (UpdateTrailLayout).
local TRAIL_OVERLAP = 10
local FLAT_TRAIL_LENGTH, FLAT_TRAIL_THICKNESS = 64, 3
local TRACK_COLOR = { 1, 1, 1, 0.18 }
-- Red (cast failure, clip) and amber (the held ranged hand) are the effect
-- colors, so a border always matches its pop.
local BORDER_COLORS = {
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

local frame, barLayer, markLayer, nowLine, pip
local laneFrames = {}
local scratch = {}
local allDirty, layoutDirty = true, true
-- Frame-time rings (ms): plain frames, frames that also rebuilt a lane, and
-- layout frames (sizing lanes, creating widgets: the first frame shown).
local perfSteady, perfRebuild, perfLayout = {}, {}, {}

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------

-- The edge-clamp cue: the probed chevron atlas, turned to the axis through
-- tex coords, or a ">" of two rotated WHITE8X8 strokes where the atlas is
-- missing (VISUAL.md, Edge clamp cue). It sits just past the mark's
-- end-facing side.
local function CreateChevron(parent)
	local chevron = CreateFrame("Frame", nil, parent)
	local r, g, b = TRACK_COLOR[1], TRACK_COLOR[2], TRACK_COLOR[3]
	if Util.AtlasExists(ATLAS.chevron) then
		chevron.texture = chevron:CreateTexture(nil, "OVERLAY")
		chevron.texture:SetAllPoints()
		chevron.texture:SetAtlas(ATLAS.chevron)
		chevron.texture:SetVertexColor(r, g, b, 0.9)
	else
		chevron.upper = chevron:CreateTexture(nil, "OVERLAY")
		chevron.upper:SetTexture(WHITE)
		chevron.upper:SetVertexColor(r, g, b, 0.9)
		chevron.lower = chevron:CreateTexture(nil, "OVERLAY")
		chevron.lower:SetTexture(WHITE)
		chevron.lower:SetVertexColor(r, g, b, 0.9)
	end
	chevron:Hide()
	return chevron
end

local function StyleChevron(chevron, parent, size)
	local orient = Layout.orient
	chevron:SetSize(size, size)
	chevron:ClearAllPoints()
	chevron:SetPoint(orient.start, parent, orient.finish, Layout:Offsets(2, 0))
	if chevron.texture then
		Layout:OrientTexCoord(chevron.texture)
		return
	end
	-- The strokes' offsets and angles turn with the axis.
	local turn, length, offset = orient.turn, size * 0.7, size * 0.22
	local dx, dy = -offset * sin(turn), offset * cos(turn)
	chevron.upper:SetSize(length, 2)
	chevron.lower:SetSize(length, 2)
	chevron.upper:SetRotation(turn - pi / 4)
	chevron.lower:SetRotation(turn + pi / 4)
	chevron.upper:ClearAllPoints()
	chevron.upper:SetPoint("CENTER", chevron, "CENTER", dx, dy)
	chevron.lower:ClearAllPoints()
	chevron.lower:SetPoint("CENTER", chevron, "CENTER", -dx, -dy)
end

-- The motion trail: Native the icon-trail art (ADD) at its own size; Flat a
-- WHITE8X8 streak in the track color, fading toward the now line. It lies
-- on the mark's now-facing side, its end under the icon.
local function StyleTrail(mark)
	local trail, orient = mark.trail, Layout.orient
	if Skin.Native("trail") then
		trail:SetAtlas(ATLAS.trail)
		trail:SetVertexColor(1, 1, 1, 1)
		trail:SetSize(Layout:Extents(Util.AtlasSize(ATLAS.trail, FLAT_TRAIL_LENGTH, FLAT_TRAIL_THICKNESS)))
		Layout:OrientTexCoord(trail)
	else
		trail:SetTexture(WHITE)
		trail:SetTexCoord(0, 1, 0, 1)
		trail:SetSize(Layout:Extents(FLAT_TRAIL_LENGTH, FLAT_TRAIL_THICKNESS))
		Skin.Gradient(trail, TRACK_COLOR[1], TRACK_COLOR[2], TRACK_COLOR[3], true)
	end
	trail:ClearAllPoints()
	trail:SetPoint(orient.finish, mark, orient.start, Layout:Offsets(TRAIL_OVERLAP, 0))
end

local function CreateMark()
	local mark = CreateFrame("Frame", nil, markLayer)
	mark.art = Skin.CreateIconArt(mark)
	mark.art.icon:SetPoint("CENTER", mark, "CENTER")
	mark.icon = mark.art.icon
	mark.trail = mark:CreateTexture(nil, "BACKGROUND")
	mark.trail:SetBlendMode("ADD")
	mark.trail:Hide()
	mark.chevron = CreateChevron(mark)
	return mark
end

local function ResetMark(mark)
	mark:Hide()
	mark:ClearAllPoints()
	mark.chevron:Hide()
	mark.trail:Hide()
	mark.desc, mark.laneFrame, mark.pinned, mark.visible, mark.x, mark.y = nil, nil, nil, nil, nil, nil
	mark.trailing, mark.trailShown = nil, nil
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
-- desaturated, split at the now line (SPEC, GCD lane); Native adds the
-- Cooldown Manager bar backing under the whole bar.
local function CreateBar()
	return {
		bg = barLayer:CreateTexture(nil, "BORDER"),
		elapsed = barLayer:CreateTexture(nil, "ARTWORK"),
		unelapsed = barLayer:CreateTexture(nil, "ARTWORK"),
	}
end

local function ResetSpan(texture)
	texture:Hide()
	texture:ClearAllPoints()
	texture.visible, texture.x, texture.width = nil, nil, nil
end

local function ResetBar(bar)
	ResetSpan(bar.bg)
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
	-- Flat: one 1 px line. Native: Blizzard's two line segments, the start
	-- one over the past window and the end one over the future window.
	lane.track = lane:CreateTexture(nil, "BORDER")
	Util.NoSnap(lane.track)
	lane.trackStart = lane:CreateTexture(nil, "BORDER")
	lane.trackEnd = lane:CreateTexture(nil, "BORDER")
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
	if mark.style ~= Layout.style or mark.size ~= size then
		mark.style, mark.size = Layout.style, size
		mark:SetSize(size, size)
		Skin.StyleIcon(mark.art, size)
		-- The chevron and trail restyle when first needed (PlaceMark).
		mark.chevronStale, mark.trailStale = true, true
		mark.pinned, mark.trailShown, mark.x, mark.y = nil, nil, nil, nil
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
	Skin.SetBorder(mark.art, BORDER_COLORS[desc.border])
	Skin.SetStates(mark.art, desc.paused, desc.queued)
end

local function ConfigureTick(tick, desc)
	local color = desc.color or TICK_COLOR
	if tick.colorRef ~= color then
		tick.colorRef = color
		tick:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	end
	local height = max(Layout.laneHeight / 3, 4)
	if tick.height ~= height or tick.style ~= Layout.style then
		tick.height, tick.style = height, Layout.style
		tick:SetSize(Layout:Extents(2, height))
		tick.x, tick.y = nil, nil
	end
end

-- A span's texture for the skin: the Cooldown Manager bar art (turned to
-- the axis) or WHITE8X8.
local function StyleSpan(texture, atlas)
	texture:ClearAllPoints()
	texture.x, texture.width = nil, nil
	if atlas then
		texture:SetAtlas(atlas)
		Layout:OrientTexCoord(texture)
	else
		texture:SetTexture(WHITE)
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

local function ConfigureBar(bar, desc)
	local thickness = max(Layout.iconSize * BAR_HEIGHT_RATIO, 3)
	if bar.style ~= Layout.style or bar.thickness ~= thickness then
		bar.style, bar.thickness = Layout.style, thickness
		local native = Skin.Native("bar", "barBG")
		StyleSpan(bar.elapsed, native and ATLAS.bar)
		StyleSpan(bar.unelapsed, native and ATLAS.bar)
		StyleSpan(bar.bg, native and ATLAS.barBG)
		bar.native = native
		bar.colorRef = nil -- SetAtlas / SetTexture keep the tint, but re-apply it once
	end
	local color = desc.color
	if bar.colorRef ~= color then
		bar.colorRef = color
		local r, g, b, a = color[1], color[2], color[3], color[4] or 1
		bar.elapsed:SetVertexColor(r, g, b, a)
		local gr, gg, gb = Util.Gray(r, g, b)
		bar.unelapsed:SetVertexColor(gr, gg, gb, a * 0.8)
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

-- The anchor name never changes ("CENTER" on the lane's axis start), so
-- moving a widget needs no ClearAllPoints (the anchor rule); an unmoved one
-- is skipped. `along` is the time-axis offset, `across` the across-lane
-- shake offset - never a time offset.
local function Anchor(widget, along, across)
	if widget.x ~= along or widget.y ~= across then
		widget.x, widget.y = along, across
		widget:SetPoint("CENTER", widget.laneFrame, Layout.orient.start, Layout:Offsets(along, across))
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

-- The next predicted mark's trail, fading in over its last TRAIL_ONSET
-- seconds; none while pinned at either end.
local function PlaceTrail(mark, t, pinned, now)
	local lead = t - now
	local shown = not pinned and lead > 0 and lead <= TRAIL_ONSET
	if shown then
		if mark.trailStale then
			mark.trailStale = nil
			StyleTrail(mark)
		end
		mark.trail:SetAlpha(1 - lead / TRAIL_ONSET)
	end
	if mark.trailShown ~= shown then
		mark.trailShown = shown
		mark.trail:SetShown(shown)
	end
end

local function PlaceMark(mark, now)
	local t, pinned = ResolveTime(mark.desc, now)
	if not t then
		SetVisible(mark, false)
		return
	end
	local shake = mark.desc.shake
	Anchor(mark, Layout:TimeToOffset(t, now), shake and ShakeOffset(shake, now) or 0)
	if mark.pinned ~= pinned then
		mark.pinned = pinned
		if pinned and mark.chevronStale then
			mark.chevronStale = nil
			StyleChevron(mark.chevron, mark, Layout.chevronSize)
		end
		mark.chevron:SetShown(pinned)
	end
	if mark.trailing then
		PlaceTrail(mark, t, pinned, now)
	end
	SetVisible(mark, true)
end

local function PlaceTick(tick, now)
	local t = ResolveTime(tick.desc, now)
	if not t then
		SetVisible(tick, false)
		return
	end
	Anchor(tick, Layout:TimeToOffset(t, now), 0)
	SetVisible(tick, true)
end

-- A span from `from` to `to` along the lane's axis; its start edge (the
-- past end) is anchored, so the anchor name stays the orientation's start.
local function PlaceSpan(texture, laneFrame, from, to, now, thickness)
	if to <= from then
		SetVisible(texture, false)
		return
	end
	local along = Layout:TimeToOffset(from, now)
	local length = max((to - from) * Layout.pxPerSec, 1)
	if texture.x ~= along then
		texture.x = along
		local start = Layout.orient.start
		texture:SetPoint(start, laneFrame, start, Layout:Offsets(along, 0))
	end
	if texture.width ~= length then
		texture.width = length
		texture:SetSize(Layout:Extents(length, thickness))
	end
	SetVisible(texture, true)
end

local function PlaceBar(bar, now)
	local desc = bar.desc
	local from = max(desc.tStart, Layout:CullEdge(now))
	local to = min(desc.tEnd, Layout:FarEdge(now))
	local laneFrame, thickness = bar.laneFrame, bar.thickness
	if bar.native then
		PlaceSpan(bar.bg, laneFrame, from, to, now, thickness)
	end
	PlaceSpan(bar.elapsed, laneFrame, from, min(to, now), now, thickness)
	PlaceSpan(bar.unelapsed, laneFrame, max(from, now), to, now, thickness)
end

-- ---------------------------------------------------------------------------
-- Layout and rebuild
-- ---------------------------------------------------------------------------

-- A lane's track: Native the two line segments meeting at the now line,
-- Flat one 1 px line in the track color. The art is set when the skin or
-- orientation changed; the geometry on every layout pass.
local function LayoutTrack(laneFrame, native, thickness)
	local trackEnd = Layout.future * Layout.pxPerSec
	local trackStart = Layout.nowX - Layout.padStart
	if laneFrame.trackStyle ~= Layout.style then
		laneFrame.trackStyle = Layout.style
		if native then
			laneFrame.trackStart:SetAtlas(ATLAS.lineStart)
			laneFrame.trackEnd:SetAtlas(ATLAS.lineEnd)
			Layout:OrientTexCoord(laneFrame.trackStart)
			Layout:OrientTexCoord(laneFrame.trackEnd)
		else
			laneFrame.track:SetColorTexture(TRACK_COLOR[1], TRACK_COLOR[2], TRACK_COLOR[3], TRACK_COLOR[4])
		end
		laneFrame.track:SetShown(not native)
		laneFrame.trackStart:SetShown(native)
		laneFrame.trackEnd:SetShown(native)
	end
	if native then
		Layout:PlaceAlong(laneFrame.trackStart, laneFrame, Layout.padStart, trackStart, thickness)
		Layout:PlaceAlong(laneFrame.trackEnd, laneFrame, Layout.nowX, trackEnd, thickness)
	else
		Layout:PlaceAlong(laneFrame.track, laneFrame, Layout.padStart, trackStart + trackEnd, thickness)
	end
end

local function ApplyLayout()
	Layout:Compute()
	local lanes = Layout:Lanes()
	frame:SetSize(Layout:Extents(Layout.width, max(Layout.height, 1)))
	frame:SetScale(Addon:GetSetting("scale"))
	local bandAlpha = Addon:GetSetting("backgroundAlpha")
	-- The track's skin-wide choices, once for every lane.
	local nativeTrack = Skin.Native("lineStart", "lineEnd")
	local trackThickness
	if nativeTrack then
		trackThickness = select(2, Util.AtlasSize(ATLAS.lineStart, 0, 8))
	else
		trackThickness = Util.PixelSize(frame, 1)
	end
	for i, lane in ipairs(lanes) do
		local laneFrame = laneFrames[i]
		if not laneFrame then
			laneFrame = CreateLaneFrame()
			laneFrames[i] = laneFrame
		end
		laneFrame:ClearAllPoints()
		laneFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", Layout:CrossOffsets(Layout:LaneOffset(i)))
		laneFrame:SetSize(Layout:Extents(Layout.width, Layout.laneHeight))
		laneFrame.band:SetColorTexture(1, 1, 1, bandAlpha)
		laneFrame.band:SetShown(bandAlpha > 0)
		LayoutTrack(laneFrame, nativeTrack, trackThickness)
		laneFrame:Show()
		lane.frame = laneFrame
	end
	for i = #lanes + 1, #laneFrames do
		ClearLaneFrame(laneFrames[i])
		laneFrames[i]:Hide()
	end
	Skin.StyleNowLine(nowLine, pip, frame)
	layoutDirty = false
	allDirty = true
	Addon.Sinks:Layout()
end

local function RebuildLane(lane, now)
	local laneFrame = lane.frame
	local marks, ticks, bars = laneFrame.marks, laneFrame.ticks, laneFrame.bars
	marks:BeginReuse()
	ticks:BeginReuse()
	bars:BeginReuse()
	wipe(scratch)
	lane:Collect(now, scratch)
	-- The lane's next predicted mark (the earliest, not a chain mark, not on
	-- the now line) is the one that trails.
	local nextDesc
	for i = 1, #scratch do
		local desc = scratch[i]
		if desc.predicted and not desc.chain and not desc.atNow and (not nextDesc or desc.t < nextDesc.t) then
			nextDesc = desc
		end
	end
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
			local trailing = desc == nextDesc
			if widget.trailing and not trailing then
				widget.trail:Hide()
				widget.trailShown = nil
			end
			widget.trailing = trailing
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
	Addon.Sinks:Place()
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
	-- With no lanes there is nothing to show - except in Edit Mode, where the
	-- frame must be there to be placed.
	frame:SetShown(Addon.editMode or (show and #Layout:Lanes() > 0))
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

-- The lanes in order (a spell lane by its spell's name) and whether the
-- frame is shown, for /actiontimeline status.
function Renderer:Status()
	local keys = {}
	for i, lane in ipairs(Layout:Lanes()) do
		keys[i] = lane.name or lane.key
	end
	return keys, frame ~= nil and frame:IsShown()
end

-- Each lane frame and its track line as the client sees them, for
-- /actiontimeline debug layout (bug reports on the skins and orientations).
function Renderer:DebugLayout()
	local out = { string.format("skin %s, orientation %s, scale %.2f, pad %d", tostring(Layout.skin), tostring(Layout.orient.start), frame:GetEffectiveScale(), Layout.crossPad or 0) }
	for i, lane in ipairs(Layout:Lanes()) do
		local laneFrame = lane.frame
		if laneFrame then
			local track = Layout.skin == "native" and laneFrame.trackEnd:IsShown() and laneFrame.trackEnd or laneFrame.track
			local point, _, relPoint, x, y = track:GetPoint(1)
			local _, laneTop = laneFrame:GetCenter()
			out[#out + 1] = string.format("%d %s: lane %s lvl %d mid %.1f | line %s %dx%.2f %s>%s %.1f,%.1f a%.2f",
				i, lane.name or lane.key, laneFrame:IsShown() and "shown" or "HIDDEN", laneFrame:GetFrameLevel(), laneTop or -1,
				track:IsShown() and "shown" or "HIDDEN", track:GetWidth(), track:GetHeight(), tostring(point), tostring(relPoint), x or 0, y or 0, track:GetAlpha())
		end
	end
	return out
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
	-- line, then icon marks, then the engine-drawn sink icons, then
	-- transient effects on top.
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
	local sinkLayer = CreateFrame("Frame", nil, frame)
	sinkLayer:SetAllPoints()
	sinkLayer:SetFrameLevel(level + 5)
	Addon.Sinks:Init(sinkLayer)
	local effectsLayer = CreateFrame("Frame", nil, frame)
	effectsLayer:SetAllPoints()
	effectsLayer:SetFrameLevel(level + 6)
	Effects:Init(effectsLayer)
	nowLine = nowLayer:CreateTexture(nil, "OVERLAY", nil, 0)
	Util.NoSnap(nowLine)
	pip = nowLayer:CreateTexture(nil, "OVERLAY", nil, 1)

	frame:SetScript("OnShow", function()
		Renderer:MarkLayoutDirty()
	end)
	frame:SetScript("OnUpdate", OnUpdate)
	C_Timer.NewTicker(SWEEP_INTERVAL, Sweep)
	self:UpdateVisibility()
end
