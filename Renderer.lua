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
-- Two layouts: Detailed (a lane frame per lane) and Single lane (the lanes
-- but the sink lanes share one track; SingleLane.Adapt rewrites each
-- descriptor - glyph, offset across the track, size, fade - before the
-- widgets are configured).

local Addon = FourEverActionTimeline
local Util, Layout, Store, Effects, Skin, SingleLane = Addon.Util, Addon.Layout, Addon.Store, Addon.Effects, Addon.Skin, Addon.SingleLane
local ShakeOffset = Effects.ShakeOffset
-- Everything that scrolls is unsnapped (VISUAL.md, Pixel grid).
local MovingTexture = Util.MovingTexture

local GetTime = GetTime
local debugprofilestop = debugprofilestop
local ipairs, abs, max, min, random, wipe = ipairs, math.abs, math.max, math.min, math.random, wipe
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
-- A prediction this close to the now line when it went was used up (it
-- landed), not withdrawn; a new one within this of an old one is the same.
-- A withdrawn one fades out over Blizzard's CancelAnimation time.
local WITHDRAW_LEAD, WITHDRAW_MATCH, WITHDRAW_TIME = 0.1, 0.05, 0.2
-- A prediction that appears fades in over Blizzard's intro time.
local ENTER_TIME = 0.2
-- Single lane's highlight glow (Effects:Highlight): around an icon at
-- Blizzard's overhang, around a diamond wider. (Blizzard's own highlight art
-- draws a blank square here, build 70235.)
local HIGHLIGHT_ICON, HIGHLIGHT_DIAMOND = 1.5, 2.6
local TRACK_COLOR = { 1, 1, 1, 0.18 }
-- The track breaks at these seconds from the now line (past negative, in
-- order along the axis), Blizzard's line breaks (1 s, then every 2 s; at most
-- three masks per line segment): the timeline's seconds scale. Flat leaves a
-- gap this wide.
local LINE_BREAKS = { -5, -3, -1, 1, 3, 5 }
local LINE_BREAK_GAP = 3
-- Single lane has one track, its spine: the Flat line is 2 px and brighter,
-- so it still reads when a thin unsnapped line straddles two screen pixels.
local SINGLE_TRACK_ALPHA = 0.28
-- Single lane: the dark ground behind everything (the mock-up's).
local BACKDROP_COLOR = { 0.05, 0.06, 0.05 }
-- Single lane: a cooling spell's empty ready-row slot.
local SLOT_OUTLINE_COLOR, SLOT_OUTLINE_ALPHA = { 0.9, 0.91, 0.93 }, 0.3
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

local frame, backdrop, barLayer, markLayer, nowLine, pip
local shadow -- Single lane: the line shadow's two halves (LayoutShadow)
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
		chevron.texture = MovingTexture(chevron, "OVERLAY")
		chevron.texture:SetAllPoints()
		chevron.texture:SetAtlas(ATLAS.chevron)
		chevron.texture:SetVertexColor(r, g, b, 0.9)
	else
		chevron.upper = MovingTexture(chevron, "OVERLAY")
		chevron.upper:SetTexture(WHITE)
		chevron.upper:SetVertexColor(r, g, b, 0.9)
		chevron.lower = MovingTexture(chevron, "OVERLAY")
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
	mark.trail = MovingTexture(mark, "BACKGROUND")
	mark.trail:SetBlendMode("ADD")
	mark.trail:Hide()
	mark.chevron = CreateChevron(mark)
	return mark
end

-- A growing widget's scale: nil is 1 (the next mark grows as it nears the now line).
local function SetWidgetScale(widget, scale)
	if (widget.scale or 1) ~= scale then
		widget.scale = scale ~= 1 and scale or nil
		widget:SetScale(scale)
	end
end

local function ResetMark(mark)
	mark:Hide()
	mark:ClearAllPoints()
	mark.chevron:Hide()
	mark.trail:Hide()
	mark.desc, mark.laneFrame, mark.pinned, mark.visible, mark.x, mark.y = nil, nil, nil, nil, nil, nil
	mark.trailing, mark.trailShown = nil, nil
	SetWidgetScale(mark, 1)
end

-- The Single lane swing diamond: a frame (it scales as it nears the now line).
local function CreateDiamond()
	local diamond = CreateFrame("Frame", nil, markLayer)
	diamond.art = Skin.CreateDiamond(diamond)
	return diamond
end

local function ResetDiamond(diamond)
	diamond:Hide()
	diamond:ClearAllPoints()
	diamond.desc, diamond.laneFrame, diamond.visible, diamond.x, diamond.y = nil, nil, nil, nil, nil
	SetWidgetScale(diamond, 1)
end

-- A cooling spell's ready-row slot: a faint square outline, the same in both
-- skins. Its edges stretch between two corners each (two anchor names on
-- purpose).
local function CreateOutline()
	local outline = CreateFrame("Frame", nil, markLayer)
	local edges = {}
	for i = 1, 4 do
		edges[i] = outline:CreateTexture(nil, "ARTWORK")
		edges[i]:SetTexture(WHITE)
		edges[i]:SetVertexColor(SLOT_OUTLINE_COLOR[1], SLOT_OUTLINE_COLOR[2], SLOT_OUTLINE_COLOR[3], 1)
	end
	edges[1]:SetPoint("TOPLEFT")
	edges[1]:SetPoint("TOPRIGHT")
	edges[2]:SetPoint("BOTTOMLEFT")
	edges[2]:SetPoint("BOTTOMRIGHT")
	edges[3]:SetPoint("TOPLEFT")
	edges[3]:SetPoint("BOTTOMLEFT")
	edges[4]:SetPoint("TOPRIGHT")
	edges[4]:SetPoint("BOTTOMRIGHT")
	outline.edges = edges
	outline:SetAlpha(SLOT_OUTLINE_ALPHA)
	return outline
end

local function ResetOutline(outline)
	outline:Hide()
	outline:ClearAllPoints()
	outline.desc, outline.laneFrame, outline.visible, outline.x, outline.y = nil, nil, nil, nil, nil
end

local function CreateTick()
	local tick = MovingTexture(barLayer, "ARTWORK")
	tick:SetTexture(WHITE)
	return tick
end

local function ResetTick(tick)
	tick:Hide()
	tick:ClearAllPoints()
	tick.desc, tick.laneFrame, tick.visible, tick.x, tick.y = nil, nil, nil, nil, nil
end

-- A window bar: the elapsed span at full color, the unelapsed span
-- desaturated, split at the now line (SPEC, GCD lane); Native adds the
-- Cooldown Manager bar backing under the whole bar.
local function CreateBar()
	return {
		bg = MovingTexture(barLayer, "BORDER"),
		elapsed = MovingTexture(barLayer, "ARTWORK"),
		unelapsed = MovingTexture(barLayer, "ARTWORK"),
	}
end

local function ResetSpan(texture)
	texture:Hide()
	texture:ClearAllPoints()
	texture.visible, texture.x, texture.across, texture.width = nil, nil, nil, nil
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
	lane.segments = { lane.track }
	lane.trackStart = lane:CreateTexture(nil, "BORDER")
	lane.trackEnd = lane:CreateTexture(nil, "BORDER")
	lane.marks = Util.NewPool(CreateMark, ResetMark)
	lane.diamonds = Util.NewPool(CreateDiamond, ResetDiamond)
	lane.outlines = Util.NewPool(CreateOutline, ResetOutline)
	lane.ticks = Util.NewPool(CreateTick, ResetTick)
	lane.bars = Util.NewPool(CreateBar, ResetBar)
	return lane
end

-- Releases every widget of a lane frame that no lane uses any more.
local function ClearLaneFrame(laneFrame)
	laneFrame.marks:BeginReuse()
	laneFrame.marks:Trim()
	laneFrame.diamonds:BeginReuse()
	laneFrame.diamonds:Trim()
	laneFrame.outlines:BeginReuse()
	laneFrame.outlines:Trim()
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
	local size = desc.size or Layout.iconSize
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
	-- The base alpha, rewritten on every rebuild: a fading mark writes its alpha
	-- every frame, and what a fade left must not outlive the mark's use.
	mark.alphaValue, mark.fadeAlpha = desc.alpha or (desc.dim and DIM_ALPHA or 1), nil
	mark:SetAlpha(mark.alphaValue)
	Skin.SetBorder(mark.art, BORDER_COLORS[desc.border])
	Skin.SetStates(mark.art, desc.paused, desc.queued)
end

local function ConfigureTick(tick, desc)
	local color = desc.color or TICK_COLOR
	if tick.colorRef ~= color then
		tick.colorRef = color
		tick:SetVertexColor(color[1], color[2], color[3], 1)
	end
	-- A texture's alpha is one value (SetAlpha replaces SetVertexColor's): the
	-- color goes in opaque, the alpha (rewritten on every rebuild) after it.
	tick.alphaValue, tick.fadeAlpha = color[4] or 1, nil
	tick:SetAlpha(tick.alphaValue)
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

local function ConfigureDiamond(diamond, desc)
	Skin.StyleDiamond(diamond.art, desc.radius, desc.hollow)
	Skin.SetDiamondPause(diamond.art, desc.glyph == "pause")
	-- A held ranged diamond's outline turns amber.
	Skin.SetDiamondColor(diamond.art, desc.hollow and BORDER_COLORS[desc.border] or desc.color)
	diamond.alphaValue, diamond.fadeAlpha = desc.alpha or 1, nil
	diamond:SetAlpha(diamond.alphaValue)
end

-- The outline's edges are a whole screen pixel thick (a thinner one can
-- vanish under the pixel grid).
local function ConfigureOutline(outline, desc)
	local size, line = desc.size, Util.PixelSize(frame, 1)
	if outline.size ~= size or outline.line ~= line then
		outline.size, outline.line = size, line
		outline:SetSize(size, size)
		local edges = outline.edges
		edges[1]:SetHeight(line)
		edges[2]:SetHeight(line)
		edges[3]:SetWidth(line)
		edges[4]:SetWidth(line)
	end
end

local function ConfigureBar(bar, desc)
	local thickness = desc.thickness or max(Layout.iconSize * BAR_HEIGHT_RATIO, 3)
	if bar.style ~= Layout.style or bar.thickness ~= thickness then
		bar.style, bar.thickness = Layout.style, thickness
		local native = Skin.Native("bar", "barBG")
		StyleSpan(bar.elapsed, native and ATLAS.bar)
		StyleSpan(bar.unelapsed, native and ATLAS.bar)
		StyleSpan(bar.bg, native and ATLAS.barBG)
		bar.native = native
		bar.colorRef = nil -- SetAtlas / SetTexture keep the tint, but re-apply it once
	end
	-- The unelapsed span is the elapsed color's grey unless the descriptor
	-- gives its own.
	local color, rest = desc.color, desc.unelapsedColor
	if bar.colorRef ~= color or bar.restRef ~= rest then
		bar.colorRef, bar.restRef = color, rest
		-- A texture's alpha is one value (SetAlpha replaces SetVertexColor's):
		-- the colors go in opaque, the alpha (base times fade) after them.
		local r, g, b, a = color[1], color[2], color[3], color[4] or 1
		bar.elapsed:SetVertexColor(r, g, b, 1)
		bar.elapsedAlpha = a
		if rest then
			bar.unelapsed:SetVertexColor(rest[1], rest[2], rest[3], 1)
			bar.restAlpha = rest[4] or 1
		else
			local gr, gg, gb = Util.Gray(r, g, b)
			bar.unelapsed:SetVertexColor(gr, gg, gb, 1)
			bar.restAlpha = a * 0.8
		end
	end
	bar.fadeAlpha = nil
	bar.bg:SetAlpha(1)
	bar.elapsed:SetAlpha(bar.elapsedAlpha)
	bar.unelapsed:SetAlpha(bar.restAlpha)
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
-- A scaled widget (the next mark grows) takes its offsets in its own scale.
local function Anchor(widget, along, across, scale)
	if scale then
		along, across = along / scale, across / scale
	end
	-- The same offsets land elsewhere in another orientation: a widget that
	-- does not move (a ready-row slot) must still re-anchor when it turns.
	local orient = Layout.orient
	if widget.x ~= along or widget.y ~= across or widget.orient ~= orient then
		widget.x, widget.y, widget.orient = along, across, orient
		widget:SetPoint("CENTER", widget.laneFrame, orient.start, Layout:Offsets(along, across))
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

-- How far a growing mark has grown toward `ratio`: it starts in its last
-- TRAIL_ONSET seconds before the now line and is full size there.
-- How far a mark is into its last TRAIL_ONSET seconds: 0 before, 1 on the now line.
local function Approach(lead)
	return min(max(1 - lead / TRAIL_ONSET, 0), 1)
end

local function Growth(ratio, lead)
	return 1 + (ratio - 1) * Approach(lead)
end

-- Single lane: a happened mark fades over the past window (1 at its instant,
-- 0 a past window later).
local function FadeFactor(t, now)
	return min(max(1 - (now - t) * Layout.invPast, 0), 1)
end

-- Sets a widget's alpha; an unchanged alpha costs nothing.
local function SetFade(widget, a)
	if widget.fadeAlpha ~= a then
		widget.fadeAlpha = a
		widget:SetAlpha(a)
	end
end

-- Scales the widget's base alpha by its fade.
local function ApplyFade(widget, t, now)
	SetFade(widget, FadeFactor(t, now) * widget.alphaValue)
end

local function ApplyBarFade(bar, tEnd, now)
	local a = FadeFactor(tEnd, now)
	if bar.fadeAlpha ~= a then
		bar.fadeAlpha = a
		bar.bg:SetAlpha(a)
		bar.elapsed:SetAlpha(a * bar.elapsedAlpha)
		bar.unelapsed:SetAlpha(a * bar.restAlpha)
	end
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

-- Marks and diamonds: sit `across` the track (plus a shake), fade, and say
-- when they are within TRAIL_ONSET of the now line: `grow` grows them toward
-- it, `highlight` flashes once as they cross it (SingleLane.Adapt decides).
-- A fixed place (a ready-row slot: `t` nil) neither grows nor fades.
local function PlaceScaled(widget, desc, along, t, now)
	local lead = t and t - now
	local scale = (desc.grow and t) and Growth(desc.grow, lead) or 1
	if desc.highlight and t then
		-- One flash on crossing; a mark built already inside never flashes,
		-- so a rebuild does not flash it again.
		local inside = lead <= TRAIL_ONSET
		if desc.highlighted == nil then
			desc.highlighted = inside
		elseif inside and not desc.highlighted then
			desc.highlighted = true
			Effects:Highlight(widget, desc.radius and desc.radius * 2 * HIGHLIGHT_DIAMOND or (desc.size or Layout.iconSize) * HIGHLIGHT_ICON)
		end
	end
	SetWidgetScale(widget, scale)
	local shake = desc.shake
	Anchor(widget, along, (desc.across or 0) + (shake and ShakeOffset(shake, now) or 0), scale ~= 1 and scale or nil)
	local a
	if desc.fade and t then
		a = FadeFactor(t, now) * widget.alphaValue
	elseif desc.farAlpha and t then
		-- Dimmer while far: brightening as it grows, or at once on the flash.
		if desc.highlight then
			a = lead > TRAIL_ONSET and desc.farAlpha or 1
		else
			a = desc.farAlpha + (1 - desc.farAlpha) * Approach(lead)
		end
	end
	-- A withdrawn prediction fades out, a new one fades in (RebuildLane).
	if desc.leaving then
		a = (a or widget.alphaValue) * max(desc.leaving - now, 0) / WITHDRAW_TIME
	elseif desc.entering then
		local entered = (now - desc.entering) / ENTER_TIME
		if entered >= 1 then
			desc.entering = nil
		end
		a = (a or widget.alphaValue) * min(entered, 1)
	end
	if a then
		SetFade(widget, a)
	end
end

local function PlaceMark(mark, now)
	local desc = mark.desc
	-- A ready-row slot (`along`) is a fixed place, not an instant: never
	-- pinned, so the chevron of a track icon this widget was is hidden.
	local t, pinned = nil, false
	if not desc.along then
		t, pinned = ResolveTime(desc, now)
		if not t then
			SetVisible(mark, false)
			return
		end
	end
	PlaceScaled(mark, desc, desc.along or Layout:TimeToOffset(t, now), t, now)
	if mark.pinned ~= pinned then
		mark.pinned = pinned
		if pinned and mark.chevronStale then
			mark.chevronStale = nil
			StyleChevron(mark.chevron, mark, Layout.chevronSize)
		end
		mark.chevron:SetShown(pinned)
	end
	if mark.trailing and t then
		PlaceTrail(mark, t, pinned, now)
	end
	SetVisible(mark, true)
end

-- A Single lane swing diamond: like a mark without the icon art.
local function PlaceDiamond(diamond, now)
	local desc = diamond.desc
	local t = ResolveTime(desc, now)
	if not t then
		SetVisible(diamond, false)
		return
	end
	PlaceScaled(diamond, desc, Layout:TimeToOffset(t, now), t, now)
	SetVisible(diamond, true)
end

-- A ready-row slot's outline: a fixed place.
local function PlaceOutline(outline)
	local desc = outline.desc
	Anchor(outline, desc.along, desc.across or 0)
	SetVisible(outline, true)
end

local function PlaceTick(tick, now)
	local t = ResolveTime(tick.desc, now)
	if not t then
		SetVisible(tick, false)
		return
	end
	Anchor(tick, Layout:TimeToOffset(t, now), tick.desc.across or 0)
	if tick.desc.fade then
		ApplyFade(tick, t, now)
	end
	SetVisible(tick, true)
end

-- A span from `from` to `to` along the lane's axis, `across` off its middle
-- line; its start edge (the past end) is anchored, so the anchor name stays
-- the orientation's start.
local function PlaceSpan(texture, laneFrame, from, to, now, thickness, across)
	if to <= from then
		SetVisible(texture, false)
		return
	end
	local along = Layout:TimeToOffset(from, now)
	local length = max((to - from) * Layout.pxPerSec, 1)
	across = across or 0
	if texture.x ~= along or texture.across ~= across then
		texture.x, texture.across = along, across
		local start = Layout.orient.start
		texture:SetPoint(start, laneFrame, start, Layout:Offsets(along, across))
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
	local laneFrame, thickness, across = bar.laneFrame, bar.thickness, desc.across
	if desc.fade then
		ApplyBarFade(bar, desc.tEnd, now)
	end
	-- The Single lane GCD band has no backing.
	if bar.native and not desc.band then
		PlaceSpan(bar.bg, laneFrame, from, to, now, thickness, across)
	else
		SetVisible(bar.bg, false)
	end
	PlaceSpan(bar.elapsed, laneFrame, from, min(to, now), now, thickness, across)
	PlaceSpan(bar.unelapsed, laneFrame, max(from, now), to, now, thickness, across)
end

-- ---------------------------------------------------------------------------
-- Layout and rebuild
-- ---------------------------------------------------------------------------

-- Flat: the track's segments between its line breaks; the first is the
-- lane's track texture, the rest are made on demand.
local function TrackSegment(laneFrame, index)
	local segments = laneFrame.segments
	local segment = segments[index]
	if not segment then
		segment = laneFrame:CreateTexture(nil, "BORDER")
		Util.NoSnap(segment)
		segments[index] = segment
	end
	return segment
end

local function HideSegments(laneFrame, from)
	local segments = laneFrame.segments
	for i = from, #segments do
		segments[i]:Hide()
	end
end

-- Native: the line-break masks, three per line segment (a texture takes at
-- most three), past ones on the start segment and future ones on the end
-- segment.
local function BreakMasks(laneFrame)
	local masks = laneFrame.breakMasks
	if not masks then
		masks = {}
		for i, seconds in ipairs(LINE_BREAKS) do
			local mask = laneFrame:CreateMaskTexture()
			mask:SetAtlas(ATLAS.lineBreak, true)
			local segment = seconds < 0 and laneFrame.trackStart or laneFrame.trackEnd
			segment:AddMaskTexture(mask)
			masks[i] = mask
		end
		laneFrame.breakMasks = masks
	end
	return masks
end

-- A line break's place along the axis, or nil when it is out of the window.
local function BreakOffset(seconds)
	if seconds < -Layout.past or seconds > Layout.future then
		return nil
	end
	return Layout:TimeToOffset(seconds, 0)
end

-- Flat: places the count-th track segment from `from` to `to` (none when
-- empty) and returns the segment count.
local function PlaceSegment(laneFrame, count, from, to, alpha, thickness)
	if to <= from then
		return count
	end
	count = count + 1
	local segment = TrackSegment(laneFrame, count)
	segment:SetColorTexture(TRACK_COLOR[1], TRACK_COLOR[2], TRACK_COLOR[3], alpha)
	Layout:PlaceAlong(segment, laneFrame, from, to - from, thickness)
	segment:Show()
	return count
end

-- A lane's track: Native the two line segments meeting at the now line,
-- Flat a 1 px line in the track color, both broken at fixed seconds from the
-- now line (Blizzard's line breaks: the timeline's seconds scale). The art
-- is set when the skin or orientation changed; the geometry on every layout
-- pass.
local function LayoutTrack(laneFrame, native, thickness, alpha, drawn)
	-- Single lane: only one lane frame draws the shared track.
	if not drawn then
		if laneFrame.trackStyle ~= false then
			laneFrame.trackStyle = false
			HideSegments(laneFrame, 1)
			laneFrame.trackStart:Hide()
			laneFrame.trackEnd:Hide()
		end
		return
	end
	local trackEnd = Layout.future * Layout.pxPerSec
	local trackStart = Layout.nowX - Layout.padStart
	if laneFrame.trackStyle ~= Layout.style then
		laneFrame.trackStyle = Layout.style
		if native then
			laneFrame.trackStart:SetAtlas(ATLAS.lineStart)
			laneFrame.trackEnd:SetAtlas(ATLAS.lineEnd)
			Layout:OrientTexCoord(laneFrame.trackStart)
			Layout:OrientTexCoord(laneFrame.trackEnd)
			HideSegments(laneFrame, 1)
		end
		laneFrame.trackStart:SetShown(native)
		laneFrame.trackEnd:SetShown(native)
	end
	if native then
		Layout:PlaceAlong(laneFrame.trackStart, laneFrame, Layout.padStart, trackStart, thickness)
		Layout:PlaceAlong(laneFrame.trackEnd, laneFrame, Layout.nowX, trackEnd, thickness)
		if Skin.Native("lineBreak") then
			local start = Layout.orient.start
			for i, mask in ipairs(BreakMasks(laneFrame)) do
				-- A break out of the window parks off the line, where it masks nothing.
				local along = BreakOffset(LINE_BREAKS[i]) or -1000
				mask:SetPoint("CENTER", laneFrame, start, Layout:Offsets(along, 0))
				mask:SetRotation(Layout.orient.vertical and pi / 2 or 0)
			end
		end
	else
		-- The segments run from the past end to the future end, skipping a
		-- short gap at each break.
		local gap = Util.PixelSize(frame, LINE_BREAK_GAP)
		local from, count = Layout.padStart, 0
		for _, seconds in ipairs(LINE_BREAKS) do
			local along = BreakOffset(seconds)
			if along then
				count = PlaceSegment(laneFrame, count, from, along - gap / 2, alpha, thickness)
				from = along + gap / 2
			end
		end
		count = PlaceSegment(laneFrame, count, from, Layout.nowX + trackEnd, alpha, thickness)
		HideSegments(laneFrame, count + 1)
	end
end

-- Single lane: the line shadow under the one track over its whole length,
-- two dark bands fading out from the line across the axis, in both skins
-- (VISUAL.md, Frame chrome). (Blizzard's shadow art stretches into a dark
-- block at this size.) Hidden at alpha 0 or without a track.
local function LayoutShadow(trackFrame, extent, alpha)
	local shown = trackFrame ~= nil and alpha > 0
	for i, half in ipairs(shadow) do
		half:SetShown(shown)
		if shown then
			local sign = i == 1 and 1 or -1
			-- Dark at the line: the min side of the upper (or right) half.
			Skin.Gradient(half, 0, 0, 0, sign < 0, alpha, true)
			Layout:PlaceAlong(half, trackFrame, Layout.padStart, Layout.nowX + Layout.future * Layout.pxPerSec - Layout.padStart, extent / 2, sign * extent / 4)
		end
	end
end

local function ApplyLayout()
	Layout:Compute()
	local lanes = Layout:Lanes()
	frame:SetSize(Layout:Extents(Layout.frameWidth, max(Layout.height, 1)))
	frame:SetScale(Addon:GetSetting("scale"))
	frame:SetAlpha(Addon:GetSetting("opacity"))
	-- Single lane: one dark panel behind everything instead of a band per lane.
	local backdropAlpha = Layout.single and Addon:GetSetting("singleBackgroundAlpha") or 0
	backdrop:SetColorTexture(BACKDROP_COLOR[1], BACKDROP_COLOR[2], BACKDROP_COLOR[3], backdropAlpha)
	backdrop:SetShown(backdropAlpha > 0)
	local bandAlpha = Layout.single and 0 or Addon:GetSetting("backgroundAlpha")
	-- The track's skin-wide choices, once for every lane.
	local nativeTrack = Skin.Native("lineStart", "lineEnd")
	local trackThickness
	if nativeTrack then
		trackThickness = select(2, Util.AtlasSize(ATLAS.lineStart, 0, 8))
	else
		trackThickness = Util.PixelSize(frame, Layout.single and 2 or 1)
	end
	local trackAlpha = Layout.single and SINGLE_TRACK_ALPHA or TRACK_COLOR[4]
	local trackLane, trackIndex -- Single lane: the first track lane, which draws the track
	for i, lane in ipairs(lanes) do
		local laneFrame = laneFrames[i]
		if not laneFrame then
			laneFrame = CreateLaneFrame()
			laneFrames[i] = laneFrame
		end
		laneFrame:ClearAllPoints()
		laneFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", Layout:CrossOffsets(Layout:LaneOffset(i)))
		laneFrame:SetSize(Layout:Extents(Layout.frameWidth, Layout.laneExtents[i]))
		local drawn = true
		if Layout.single and lane.group ~= "sink" then
			drawn = trackLane == nil
			if drawn then
				trackLane, trackIndex = lane, i
			end
		end
		laneFrame.band:SetColorTexture(1, 1, 1, bandAlpha)
		laneFrame.band:SetShown(drawn and bandAlpha > 0)
		LayoutTrack(laneFrame, nativeTrack, trackThickness, trackAlpha, drawn)
		laneFrame:Show()
		lane.frame = laneFrame
	end
	for i = #lanes + 1, #laneFrames do
		ClearLaneFrame(laneFrames[i])
		laneFrames[i]:Hide()
	end
	LayoutShadow(trackLane and trackLane.frame, trackIndex and Layout.laneExtents[trackIndex], Addon:GetSetting("singleShadowAlpha"))
	Skin.StyleNowLine(nowLine, pip, frame)
	layoutDirty = false
	allDirty = true
	Addon.Sinks:Layout()
end

-- Takes the widget for a descriptor from the lane frame's pool for its
-- shape and configures it. Only the lane's next predicted mark trails.
local function Build(laneFrame, desc, nextDesc)
	local shape = desc.shape
	local widget
	if shape == "bar" then
		widget = laneFrame.bars:Take()
		ConfigureBar(widget, desc)
	elseif shape == "tick" then
		widget = laneFrame.ticks:Take()
		ConfigureTick(widget, desc)
	elseif shape == "diamond" then
		widget = laneFrame.diamonds:Take()
		ConfigureDiamond(widget, desc)
	elseif shape == "outline" then
		widget = laneFrame.outlines:Take()
		ConfigureOutline(widget, desc)
	else
		widget = laneFrame.marks:Take()
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

-- Withdrawn and new predictions (VISUAL.md, Mark motion), per pool (marks,
-- diamonds): a predicted widget on screen before a rebuild is paired with a
-- new one at its instant. Of the ones left unpaired, an old one and a new one
-- are one prediction that moved (it jumps); the old ones left over were
-- withdrawn - each descriptor is kept for WITHDRAW_TIME as `leaving`, so the
-- mark itself fades out - and the new ones left over appeared and fade in.
-- One within WITHDRAW_LEAD of the now line was used up, not withdrawn.
local function Withdrawable(desc)
	return desc.predicted and not desc.atNow and not desc.along
end

-- Before the rebuild: the pool's predictions and their drawn instants (a
-- leaving one carries on until its time is up).
local function Note(pool, now)
	local notes, times, count = pool.notes or {}, pool.noteTimes or {}, 0
	pool.notes, pool.noteTimes = notes, times
	local used = pool.used
	for i = 1, #used do
		local widget = used[i]
		local desc = widget.desc
		local t = not desc.leaving and widget.visible and Withdrawable(desc) and ResolveTime(desc, now)
		if (desc.leaving and desc.leaving > now) or (t and t - now > WITHDRAW_LEAD) then
			count = count + 1
			notes[count], times[count] = desc, t
		end
	end
	pool.noteCount = count
end

-- After the rebuild: pairs the pool's new predictions with its notes, then
-- fades the leftovers in and out.
local function Reconcile(lane, pool, now)
	local notes, times, count = pool.notes, pool.noteTimes, pool.noteCount or 0
	local fresh, freshCount = pool.fresh or {}, 0
	pool.fresh = fresh
	local used = pool.used
	for i = 1, pool.cursor do
		local desc = used[i].desc
		if Withdrawable(desc) then
			local t = ResolveTime(desc, now)
			local paired = false
			for j = 1, t and count or 0 do
				local old = notes[j]
				if old and not old.leaving and abs(times[j] - t) < WITHDRAW_MATCH then
					notes[j], paired = false, true
					desc.entering = old.entering -- still fading in
					break
				end
			end
			if not paired then
				freshCount = freshCount + 1
				fresh[freshCount] = desc
			end
		end
	end
	local moved = 0
	for j = 1, count do
		local old = notes[j]
		if old and not old.leaving and moved < freshCount then
			moved = moved + 1
		elseif old then
			old.leaving = old.leaving or now + WITHDRAW_TIME
			Build(lane.frame, old)
			lane.nextRebuild = min(lane.nextRebuild, old.leaving)
		end
	end
	for i = moved + 1, freshCount do
		fresh[i].entering = now
	end
end

-- `withdraw`: fade out the predictions this rebuild removed and fade in the
-- ones it added (not on a layout pass, which rebuilds everything anew).
local function RebuildLane(lane, now, withdraw)
	local laneFrame = lane.frame
	local marks, diamonds, outlines, ticks, bars = laneFrame.marks, laneFrame.diamonds, laneFrame.outlines, laneFrame.ticks, laneFrame.bars
	if withdraw then
		Note(marks, now)
		Note(diamonds, now)
	end
	marks:BeginReuse()
	diamonds:BeginReuse()
	outlines:BeginReuse()
	ticks:BeginReuse()
	bars:BeginReuse()
	wipe(scratch)
	lane:Collect(now, scratch)
	local single = Layout.single
	if single then
		SingleLane.Prepare(lane, scratch)
	end
	-- The lane's next predicted mark (the earliest, not a chain mark, not on
	-- the now line) is the one that trails. Single lane: it grows instead.
	local nextDesc
	for i = 1, #scratch do
		local desc = scratch[i]
		if not single and desc.predicted and not desc.chain and not desc.atNow and (not nextDesc or desc.t < nextDesc.t) then
			nextDesc = desc
		end
	end
	for i = 1, #scratch do
		local desc = scratch[i]
		if not single or SingleLane.Adapt(lane, desc) then
			Build(laneFrame, desc, nextDesc)
		end
	end
	-- Jittered, so the lanes' safety passes do not all land on one frame.
	lane.nextRebuild = now + SAFETY_REBUILD * (0.75 + 0.5 * random())
	if withdraw then
		Reconcile(lane, marks, now)
		Reconcile(lane, diamonds, now)
	end
	marks:Trim()
	diamonds:Trim()
	outlines:Trim()
	ticks:Trim()
	bars:Trim()
	lane.dirty = false
	lane.builtVersion = Store:LaneVersion(lane.key)
end

-- Single lane: the cooldown icons that would overlap step off the track. One
-- pass over every spell lane's returns (and the in-flight cast's icon, which
-- holds the track), run whenever a lane was rebuilt.
local steps = {}
local function ByPosition(a, b)
	return a.x < b.x
end

local function StepMarks(now)
	local count = 0
	local lanes = Layout:Lanes()
	for i = 1, #lanes do
		local lane = lanes[i]
		if lane.group == "spell" or lane.group == "cast" then
			local used = lane.frame.marks.used
			for j = 1, #used do
				local desc = used[j].desc
				if desc.stepper or desc.occupant then
					local t = ResolveTime(desc, now)
					if t then
						count = count + 1
						local item = steps[count]
						if not item then
							item = {}
							steps[count] = item
						end
						item.desc, item.x, item.fixed = desc, Layout:TimeToOffset(t, now), desc.occupant
					end
				end
			end
		end
	end
	for i = #steps, count + 1, -1 do
		steps[i] = nil
	end
	if count > 0 then
		table.sort(steps, ByPosition)
		SingleLane.Step(steps, count)
	end
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
			RebuildLane(lane, now, not laidOut)
			rebuilt = true
		end
	end
	allDirty = false
	if rebuilt and Layout.single then
		StepMarks(now)
	end
	for i = 1, #lanes do
		local laneFrame = lanes[i].frame
		local used = laneFrame.marks.used
		for j = 1, #used do
			PlaceMark(used[j], now)
		end
		used = laneFrame.diamonds.used
		for j = 1, #used do
			PlaceDiamond(used[j], now)
		end
		used = laneFrame.outlines.used
		for j = 1, #used do
			PlaceOutline(used[j])
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
	if latest and latest.time >= now - (Addon:GetWindow()) then
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
	Store:Prune(GetTime() - (Addon:GetWindow()) - STORE_MARGIN)
	-- Single lane: a cooldown that turned out long (or a lane that came or
	-- went) renumbers the ready row's slots.
	if Layout.single and SingleLane.SlotsChanged(Layout:Lanes()) then
		layoutDirty = true
	end
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
			widgets = widgets + #laneFrame.marks.used + #laneFrame.diamonds.used + #laneFrame.outlines.used + #laneFrame.ticks.used + #laneFrame.bars.used
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
	local out = { string.format("%s layout, skin %s, orientation %s, scale %.2f, pad %d", Layout.single and "single lane" or "detailed", tostring(Layout.skin), tostring(Layout.orient.start), frame:GetEffectiveScale(), Layout.crossPad or 0) }
	if Layout.single then
		out[#out + 1] = string.format("track %.0f px, %d ready slots (%s side), frame %.0f wide", Layout.trackExtent, Layout.slotCount, tostring(Layout.readyRowSide), Layout.frameWidth)
	end
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
	backdrop = frame:CreateTexture(nil, "BACKGROUND")
	shadow = { frame:CreateTexture(nil, "BACKGROUND", nil, 1), frame:CreateTexture(nil, "BACKGROUND", nil, 1) }
	shadow[1]:SetTexture(WHITE)
	shadow[2]:SetTexture(WHITE)
	backdrop:SetAllPoints()
	backdrop:Hide()
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
