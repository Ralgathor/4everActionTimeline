-- 4everActionTimeline — the renderer.
-- One OnUpdate pass over pooled widgets. A lane's mark set - every texture,
-- tint and border - is rebuilt only when that lane changed (it flagged
-- itself dirty, its store entries changed, the layout changed) plus a 1 s
-- safety pass; each lane owns its widget pools (POOLS, one per widget kind),
-- reused in place, so one lane's change never reconfigures another's
-- widgets. Each frame only moves
-- readable marks along the time axis, and skips any widget that did not
-- move (docs/SPEC.md, Performance budget). A hidden frame receives no
-- OnUpdate, so showing it forces a full rebuild, and the expiry sweep runs
-- on its own low-frequency ticker whatever the visibility (hidden-frame
-- convergence). The frame never takes the mouse.
-- The skin (Skin.lua) and the orientation (Layout.orient) are applied on a
-- layout pass: a widget whose `style` differs from Layout.style re-applies
-- what they decide before its next configure.
-- One layout, the bar (ADR-0006): every lane but the sink lanes anchors its
-- widgets to one frame, the bar's (sink lanes: a row frame each);
-- SingleLane.Adapt rewrites
-- each descriptor - glyph, offset across the bar, size, fade - before the
-- widgets are configured, and BarTrack draws the bar.

local Addon = FourEverActionTimeline
local Util, Layout, Store, Effects, Skin, SingleLane = Addon.Util, Addon.Layout, Addon.Store, Addon.Effects, Addon.Skin, Addon.SingleLane
local ShakeOffset = Effects.ShakeOffset
-- Everything that scrolls is unsnapped (VISUAL.md, Pixel grid).
local MovingTexture = Util.MovingTexture

local GetTime = GetTime
local debugprofilestop = debugprofilestop
local ipairs, abs, max, min, random, wipe = ipairs, math.abs, math.max, math.min, math.random, wipe
local cos, sin, pi = math.cos, math.sin, math.pi
local remove = table.remove

local WHITE = Util.WHITE
local ATLAS = Skin.ATLAS
local QUESTION_MARK = 134400 -- INV_Misc_QuestionMark
local SAFETY_REBUILD = 1.0
local SWEEP_INTERVAL = 0.5
-- The store keeps entries this long past the past edge (research: past + 2 s).
local STORE_MARGIN = 2
local PERF_SAMPLES = 300
-- A mark flashes as it comes within 1.5 s of the now line (one GCD: "lands
-- within your next GCD"; Blizzard's highlight time). A constant, not a setting.
local URGENT_LEAD = 1.5
-- A prediction this close to the now line when it went was used up (it
-- landed), not withdrawn; a new one within this of an old one is the same.
-- A withdrawn one fades out over Blizzard's CancelAnimation time.
local WITHDRAW_LEAD, WITHDRAW_MATCH, WITHDRAW_TIME = 0.1, 0.05, 0.2
-- A prediction that appears fades in over Blizzard's intro time.
local ENTER_TIME = 0.2
-- The highlight glow (Effects:Highlight): around an icon at Blizzard's
-- overhang, around a diamond wider. (Blizzard's own highlight art draws a
-- blank square here, build 70235.)
local HIGHLIGHT_ICON, HIGHLIGHT_DIAMOND = 1.5, 2.6
local CHEVRON_COLOR = { 1, 1, 1 }
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
-- Native: the cast bar's glow at the now line, the bar's lane frame it sits
-- on, and what it shows now ("cast", "channel" or nil).
local castGlow, glowMask, glowFrame, glowShown, glowMasked
-- The frame the bar's lanes anchor to, each sink lane's row frame, and each
-- lane's widget pools.
local barFrame
local rowFrames, lanePools = {}, {}
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
	local r, g, b = CHEVRON_COLOR[1], CHEVRON_COLOR[2], CHEVRON_COLOR[3]
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

local function CreateMark()
	local mark = CreateFrame("Frame", nil, markLayer)
	mark.art = Skin.CreateIconArt(mark)
	mark.art.icon:SetPoint("CENTER", mark, "CENTER")
	mark.icon = mark.art.icon
	mark.chevron = CreateChevron(mark)
	return mark
end

-- Back to the free list: hidden, unanchored, owned by no lane.
local function ResetWidget(widget)
	widget:Hide()
	widget:ClearAllPoints()
	widget.desc, widget.lane, widget.laneFrame, widget.visible, widget.x, widget.y = nil, nil, nil, nil, nil, nil
end

-- A mark's frame level in its stack (nil: the marks' own level, `base`).
local function Raise(mark, level, base)
	if mark.stackLevel ~= level then
		mark.stackLevel = level
		mark:SetFrameLevel(level or base)
	end
end

local function ResetMark(mark)
	ResetWidget(mark)
	mark.chevron:Hide()
	mark.pinned = nil
	-- The card stack (StackMarks): the level, the "+n" and the link mark.
	Raise(mark, nil, markLayer:GetFrameLevel() + 1)
	if mark.moreText then
		mark.moreText:Hide()
		mark.moreShown = nil
	end
	if mark.linkBadge then
		mark.linkBadge:Hide()
		mark.linkShown = nil
	end
end

-- A swing diamond: a frame on the bar's edge.
local function CreateDiamond()
	local diamond = CreateFrame("Frame", nil, markLayer)
	diamond.art = Skin.CreateDiamond(diamond)
	return diamond
end

local function CreateTick()
	local tick = MovingTexture(barLayer, "ARTWORK")
	tick:SetTexture(WHITE)
	return tick
end

-- A window bar: the elapsed span and the unelapsed span, split at the now
-- line (SPEC, GCD lane).
local function CreateBar()
	return {
		elapsed = MovingTexture(barLayer, "ARTWORK"),
		unelapsed = MovingTexture(barLayer, "ARTWORK"),
	}
end

local function ResetSpan(texture)
	texture:Hide()
	texture:ClearAllPoints()
	texture.visible, texture.x, texture.across, texture.width, texture.u0, texture.u1 = nil, nil, nil, nil, nil, nil
end

local function ResetBar(bar)
	ResetSpan(bar.elapsed)
	ResetSpan(bar.unelapsed)
	bar.desc, bar.lane, bar.laneFrame = nil, nil, nil
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
		-- The chevron restyles when first needed (PlaceMark).
		mark.chevronStale = true
		mark.pinned, mark.x, mark.y = nil, nil, nil
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
	mark.alphaValue, mark.fadeAlpha = desc.alpha or 1, nil
	mark:SetAlpha(mark.alphaValue)
	Skin.SetBorder(mark.art, BORDER_COLORS[desc.border])
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

-- A span's texture: an atlas (turned to the axis) or WHITE8X8.
local function StyleSpan(texture, atlas)
	texture:ClearAllPoints()
	texture.x, texture.width, texture.u0, texture.u1 = nil, nil, nil, nil
	Skin.SetArt(texture, atlas)
end

local function ConfigureDiamond(diamond, desc)
	Skin.StyleDiamond(diamond.art, desc.radius, desc.hollow)
	Skin.SetDiamondPause(diamond.art, desc.glyph == "pause")
	-- A held ranged diamond's outline turns amber.
	Skin.SetDiamondColor(diamond.art, desc.hollow and BORDER_COLORS[desc.border] or desc.color)
	diamond.alphaValue, diamond.fadeAlpha = desc.alpha or 1, nil
	diamond:SetAlpha(diamond.alphaValue)
end

-- A bar's art: the ATLAS key its descriptor names (`art`: the cast bar
-- family, the GCD's Cooldown Manager bar), or plain without one or when the
-- atlas is missing on the client.
local function BarArt(desc)
	local key = desc.art
	return key and Skin.Native(key) and ATLAS[key] or nil
end

local function ConfigureBar(bar, desc)
	local thickness = desc.thickness or Layout.iconSize
	if bar.style ~= Layout.style or bar.thickness ~= thickness or bar.art ~= desc.art or bar.reveal ~= desc.reveal then
		bar.style, bar.thickness, bar.art, bar.reveal = Layout.style, thickness, desc.art, desc.reveal
		local atlas = BarArt(desc)
		-- The cast bar fills are laid across the whole cast and
		-- revealed up to now (PlaceBar), as Blizzard's cast bar reveals its
		-- fill: drawn from the atlas's file, so a part of it can show.
		local region = desc.reveal and atlas and Skin.Region(atlas)
		bar.region = region
		if region then
			local file = region.file or region.filename
			StyleSpan(bar.elapsed)
			StyleSpan(bar.unelapsed)
			bar.elapsed:SetTexture(file)
			bar.unelapsed:SetTexture(file)
		else
			StyleSpan(bar.elapsed, atlas)
			StyleSpan(bar.unelapsed, atlas)
		end
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
local function Anchor(widget, along, across)
	-- The same offsets land elsewhere in another orientation: a widget that
	-- does not move (a parked ready mark) must still re-anchor when it turns.
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

-- A happened mark fades over the past the bar shows (1 at its instant, 0 at
-- the bar's start).
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
		bar.elapsed:SetAlpha(a * bar.elapsedAlpha)
		bar.unelapsed:SetAlpha(a * bar.restAlpha)
	end
end

-- Marks and diamonds: sit `across` the bar (plus a shake), fade, and flash
-- once (`highlight`) as they come within URGENT_LEAD of the now line
-- (SingleLane.Adapt decides). A fixed place (a parked ready mark: `t` nil)
-- neither flashes nor fades.
local function PlaceWidget(widget, desc, along, t, now)
	local lead = t and t - now
	if desc.highlight and t then
		-- One flash on crossing; a mark built already inside never flashes,
		-- so a rebuild does not flash it again.
		local inside = lead <= URGENT_LEAD
		if desc.highlighted == nil then
			desc.highlighted = inside
		elseif inside and not desc.highlighted then
			desc.highlighted = true
			Effects:Highlight(widget, desc.radius and desc.radius * 2 * HIGHLIGHT_DIAMOND or (desc.size or Layout.iconSize) * HIGHLIGHT_ICON)
		end
	end
	local shake = desc.shake
	Anchor(widget, along, (desc.across or 0) + (shake and ShakeOffset(shake, now) or 0))
	local a
	if desc.fade and t then
		a = FadeFactor(t, now) * widget.alphaValue
	elseif desc.farAlpha and t then
		-- Dimmer while far, full from the flash.
		a = lead > URGENT_LEAD and desc.farAlpha or 1
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

-- The card stack: "+n" beside the front icon, the link mark in its
-- corner (made on first use; both in the shadowed system font or plain art).
local function StackExtras(mark, desc)
	local more = desc.more
	if mark.moreShown ~= more then
		mark.moreShown = more
		if more and not mark.moreText then
			mark.moreText = mark:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
			mark.moreText:SetPoint("LEFT", mark, "RIGHT", 2, 0)
		end
		if mark.moreText then
			mark.moreText:SetText(more and "+" .. more or "")
			mark.moreText:SetShown(more ~= nil)
		end
	end
	local link = desc.linkMark or nil
	if mark.linkShown ~= link then
		mark.linkShown = link
		if link and not mark.linkBadge then
			mark.linkBadge = Skin.CreateLinkBadge(mark)
		end
		if mark.linkBadge then
			mark.linkBadge:SetShown(link ~= nil)
		end
	end
end

local function PlaceMark(mark, now)
	local desc = mark.desc
	if desc.stacked then -- hidden behind its card stack's front
		SetVisible(mark, false)
		return
	end
	-- A parked ready mark (`along`) is a fixed place, not an instant: never
	-- pinned, so the chevron of a track icon this widget was is hidden.
	local t, pinned = nil, false
	if not desc.along then
		t, pinned = ResolveTime(desc, now)
		if not t then
			SetVisible(mark, false)
			return
		end
	end
	-- An icon ending a bar sits past its end, its near edge on it (not when
	-- pinned at the far edge: it would leave the frame).
	local along = desc.along or Layout:TimeToOffset(t, now)
	if desc.endsBar and not pinned then
		along = along + mark.size / 2
	end
	PlaceWidget(mark, desc, along + (desc.peek or 0), t, now)
	pinned = pinned and not desc.noChevron
	StackExtras(mark, desc)
	if mark.pinned ~= pinned then
		mark.pinned = pinned
		if pinned and mark.chevronStale then
			mark.chevronStale = nil
			StyleChevron(mark.chevron, mark, Layout.chevronSize)
		end
		mark.chevron:SetShown(pinned)
	end
	SetVisible(mark, true)
end

-- A swing diamond: like a mark without the icon art.
local function PlaceDiamond(diamond, now)
	local desc = diamond.desc
	local t = ResolveTime(desc, now)
	if not t then
		SetVisible(diamond, false)
		return
	end
	PlaceWidget(diamond, desc, Layout:TimeToOffset(t, now), t, now)
	SetVisible(diamond, true)
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

-- Native: while a cast runs through the now line, the glow
-- Blizzard's cast bar trails behind its spark (StandardGlow: 37 x 12 on an
-- 11 px bar, its end 2 px past the spark, additive), or for a channel its
-- shadow (11 x 11), its height scaled to the bar. Masked to the running cast's
-- elapsed fill, as Blizzard masks it to its bar: never seen outside the art.
local GLOWS = {
	cast = { key = "castGlow", width = 37, height = 12, past = 2, blend = "ADD" },
	channel = { key = "channelShadow", width = 11, height = 11, past = 1, blend = "BLEND" },
}
local CAST_BAR_HEIGHT = 11 -- Blizzard's cast bar, which the glow is drawn for
local glowWanted, glowBar

local function ShowCastGlow(kind, bar)
	-- The mask follows the running cast's elapsed span (anchored to it).
	if bar and bar ~= glowMasked then
		glowMasked = bar
		glowMask:ClearAllPoints()
		glowMask:SetAllPoints(bar.elapsed)
	end
	if kind == glowShown then
		return
	end
	glowShown = kind
	local glow = kind and GLOWS[kind]
	if not (glow and glowFrame and Skin.Native(glow.key)) then
		castGlow:Hide()
		return
	end
	Skin.SetArt(castGlow, ATLAS[glow.key])
	castGlow:SetBlendMode(glow.blend)
	-- Its height follows the bar; its width stays Blizzard's (this bar's casts
	-- are shorter than the cast bar's 208 px, so a widened glow swamps them).
	local k = Layout.iconSize / CAST_BAR_HEIGHT
	Layout:PlaceAlong(castGlow, glowFrame, Layout.nowX + glow.past - glow.width, glow.width, glow.height * k)
	castGlow:Show()
end

-- Shows the part u0..u1 of a cast fill's art on a span; skipped while the
-- span is hidden or its part unchanged (an ended cast's never changes).
local function RevealSpan(texture, region, u0, u1)
	if texture.visible and (texture.u0 ~= u0 or texture.u1 ~= u1) then
		texture.u0, texture.u1 = u0, u1
		Skin.RegionCoords(texture, region, u0, u1)
	end
end

local BAR_END_INSET = 4 -- px: the bar border's rounded ends

local function PlaceBar(bar, now)
	local desc = bar.desc
	if bar.region and desc.tStart <= now and now < desc.tEnd then
		glowWanted, glowBar = desc.channel and "channel" or "cast", bar
	end
	-- A span stops inside the border's rounded ends, not over them.
	local endInset = BAR_END_INSET / Layout.pxPerSec
	local from = max(desc.tStart, now - Layout.past + endInset)
	local to = min(desc.tEnd, Layout:FarEdge(now) - endInset)
	local laneFrame, thickness, across = bar.laneFrame, bar.thickness, desc.across
	if desc.fade then
		ApplyBarFade(bar, desc.tEnd, now)
	end
	PlaceSpan(bar.elapsed, laneFrame, from, min(to, now), now, thickness, across)
	PlaceSpan(bar.unelapsed, laneFrame, max(from, now), to, now, thickness, across)
	local region = bar.region
	if region and region.width and region.height and region.height > 0 then
		-- The fill's art keeps its own proportions at the bar's height and
		-- starts at the cast's start: a short cast shows its first part
		-- (cropped, as a status bar's fill is), a cast longer than the art
		-- stretches it across; each span shows its own part.
		local artLength = region.width * thickness / region.height
		local perSecond = Layout.pxPerSec / max((desc.tEnd - desc.tStart) * Layout.pxPerSec, artLength)
		local start, mid = desc.tStart, min(max(now, from), to)
		RevealSpan(bar.elapsed, region, (from - start) * perSecond, (mid - start) * perSecond)
		RevealSpan(bar.unelapsed, region, (mid - start) * perSecond, (to - start) * perSecond)
	end
end

-- ---------------------------------------------------------------------------
-- Layout and rebuild
-- ---------------------------------------------------------------------------

-- The widget kinds, each with its pool's create and reset, how a widget is
-- configured on a rebuild and placed every frame; `SHAPES` picks a
-- descriptor's kind by its shape (an icon mark by default).
local MARKS = { key = "marks", create = CreateMark, reset = ResetMark, configure = ConfigureMark, place = PlaceMark }
local POOLS = {
	MARKS,
	{ key = "diamonds", shape = "diamond", create = CreateDiamond, reset = ResetWidget, configure = ConfigureDiamond, place = PlaceDiamond },
	{ key = "ticks", shape = "tick", create = CreateTick, reset = ResetWidget, configure = ConfigureTick, place = PlaceTick },
	{ key = "bars", shape = "bar", create = CreateBar, reset = ResetBar, configure = ConfigureBar, place = PlaceBar },
}
local SHAPES = {}
for _, kind in ipairs(POOLS) do
	if kind.shape then
		SHAPES[kind.shape] = kind
	end
end

-- A lane's widget pools, made on first use; a pool's `used` array is
-- exactly what the lane's last rebuild placed.
local function Pools(lane)
	local pools = lanePools[lane]
	if not pools then
		pools = {}
		for _, kind in ipairs(POOLS) do
			pools[kind.key] = Util.NewPool(kind.create, kind.reset)
		end
		lanePools[lane] = pools
	end
	return pools
end

local function ReleasePools(pools)
	for _, kind in ipairs(POOLS) do
		local pool = pools[kind.key]
		pool:BeginReuse()
		pool:Trim()
	end
end

-- Anchors and sizes a frame on its row across the axis.
local function PlaceRow(laneFrame, offset, extent)
	laneFrame:ClearAllPoints()
	laneFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", Layout:CrossOffsets(offset))
	laneFrame:SetSize(Layout:Extents(Layout.width, extent))
	laneFrame:Show()
end

local function ApplyLayout()
	Layout:Compute()
	local lanes = Layout:Lanes()
	frame:SetSize(Layout:Extents(Layout.width, max(Layout.height, 1)))
	frame:SetScale(Addon:GetSetting("scale"))
	frame:SetAlpha(Addon:GetSetting("opacity"))
	-- On the frame's scale, now it is set: whole screen pixels in from the bar's edges.
	Layout.parkSize = SingleLane.ParkSize(frame)
	-- The bar's lanes share its frame; each sink lane has a row frame.
	local onBar, present = false, {}
	for i, lane in ipairs(lanes) do
		local laneFrame = barFrame
		if lane.group == "sink" then
			laneFrame = rowFrames[lane] or CreateFrame("Frame", nil, frame)
			rowFrames[lane] = laneFrame
			PlaceRow(laneFrame, Layout.laneOffsets[i], Layout.laneExtents[i])
		elseif not onBar then
			onBar = true
			PlaceRow(barFrame, Layout.barOffset, Layout.trackExtent)
		end
		lane.frame, lane.pools, present[lane] = laneFrame, Pools(lane), true
	end
	barFrame:SetShown(onBar)
	-- A lane that went releases its widgets (and a sink lane its row).
	for lane, pools in pairs(lanePools) do
		if not present[lane] then
			ReleasePools(pools)
			lanePools[lane], lane.pools = nil, nil
		end
	end
	for lane, rowFrame in pairs(rowFrames) do
		if not present[lane] then
			rowFrame:Hide()
		end
	end
	local shownBar = onBar and barFrame or nil
	Addon.BarTrack:Layout(shownBar)
	glowFrame, glowShown = shownBar, false -- re-placed on the next frame
	Skin.StyleNowLine(nowLine, pip, frame)
	layoutDirty = false
	allDirty = true
	Addon.Sinks:Layout()
end

-- Takes the widget for a descriptor from the lane's pool for its shape and
-- configures it.
local function Build(lane, desc)
	local kind = SHAPES[desc.shape] or MARKS
	local widget = lane.pools[kind.key]:Take()
	kind.configure(widget, desc)
	widget.desc, widget.lane, widget.laneFrame = desc, lane, lane.frame
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
			Build(lane, old)
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
	local pools = lane.pools
	local marks, diamonds = pools.marks, pools.diamonds
	if withdraw then
		Note(marks, now)
		Note(diamonds, now)
	end
	for _, kind in ipairs(POOLS) do
		pools[kind.key]:BeginReuse()
	end
	wipe(scratch)
	lane:Collect(now, scratch)
	SingleLane.Prepare(lane, scratch)
	for i = 1, #scratch do
		local desc = scratch[i]
		if SingleLane.Adapt(lane, desc) then
			Build(lane, desc)
		end
	end
	-- Jittered, so the lanes' safety passes do not all land on one frame.
	lane.nextRebuild = now + SAFETY_REBUILD * (0.75 + 0.5 * random())
	if withdraw then
		Reconcile(lane, marks, now)
		Reconcile(lane, diamonds, now)
	end
	for _, kind in ipairs(POOLS) do
		pools[kind.key]:Trim()
	end
	lane.dirty = false
	lane.builtVersion = Store:LaneVersion(lane.key)
end

-- Every icon ahead of the now line goes through the card stack, and the
-- parked ready marks through the ready stack; the front of a stack draws on
-- top of the icons it covers, the ready stack over the card stack. Run
-- whenever a lane was rebuilt.
local stackItems, spareItems, parkedDescs, parkedMarks = {}, {}, {}, {}
local function ByStack(a, b)
	if a.x ~= b.x then
		return a.x < b.x
	end
	return a.t < b.t
end

local function StackMarks(now)
	local count, readyCount = 0, 0
	local lanes = Layout:Lanes()
	for i = 1, #lanes do
		local used = lanes[i].pools.marks.used
		for j = 1, #used do
			local mark = used[j]
			local desc = mark.desc
			if desc.parked then
				readyCount = readyCount + 1
				parkedDescs[readyCount], parkedMarks[readyCount] = desc, mark
			elseif desc.predicted and not desc.atNow and not desc.leaving then
				local t, far = ResolveTime(desc, now)
				if t then
					count = count + 1
					local item = stackItems[count] or remove(spareItems) or {}
					stackItems[count] = item
					item.desc, item.mark, item.t, item.far = desc, mark, desc.t + (desc.after or 0), far
					item.x = Layout:TimeToOffset(t, now) + (desc.endsBar and Layout.iconSize / 2 or 0)
					item.fixed = desc.occupant or desc.onBar
				end
			end
		end
	end
	-- The items past this pass's count wait in a spare list (not garbage).
	for i = #stackItems, count + 1, -1 do
		spareItems[#spareItems + 1] = stackItems[i]
		stackItems[i] = nil
	end
	table.sort(stackItems, ByStack)
	SingleLane.Stack(stackItems, count)
	SingleLane.StackReady(parkedDescs, readyCount)
	local base = markLayer:GetFrameLevel() + 1
	for i = 1, count do
		local item = stackItems[i]
		Raise(item.mark, item.desc.front and base + 1 or nil, base)
	end
	-- The ready stack's front on top, each fold behind it.
	for i = 1, readyCount do
		local index = parkedMarks[i].desc.parkIndex
		Raise(parkedMarks[i], index and base + 2 + readyCount - index or nil, base)
	end
	for i = readyCount + 1, #parkedMarks do
		parkedMarks[i] = nil
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
	if rebuilt then
		StackMarks(now)
	end
	for i = 1, #lanes do
		local pools = lanes[i].pools
		for k = 1, #POOLS do
			local kind = POOLS[k]
			local used, place = pools[kind.key].used, kind.place
			for j = 1, #used do
				place(used[j], now)
			end
		end
	end
	ShowCastGlow(glowWanted, glowBar)
	glowWanted, glowBar = nil, nil
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
	-- A cooldown that turned out long (or a lane that came or went)
	-- renumbers the ready stack's lane order.
	if SingleLane.NumberReady(Layout:Lanes()) then
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
		local pools = lanes[i].pools
		for k = 1, pools and #POOLS or 0 do
			widgets = widgets + #pools[POOLS[k].key].used
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

-- The bar's frame, each sink row and each lane's widgets as the client sees
-- them, for /actiontimeline debug layout (bug reports on the skins and
-- orientations).
function Renderer:DebugLayout()
	local out = {
		string.format("skin %s, orientation %s, scale %.2f, pad %d", tostring(Layout.skin), tostring(Layout.orient.start), frame:GetEffectiveScale(), Layout.crossPad or 0),
		string.format("bar %.0f px, ready spells %s, frame %.0f wide", Layout.trackExtent, tostring(Layout.readySpells), Layout.width),
	}
	local function Describe(name, laneFrame)
		local _, middle = laneFrame:GetCenter()
		out[#out + 1] = string.format("%s: %s lvl %d mid %.1f %dx%d", name, laneFrame:IsShown() and "shown" or "HIDDEN",
			laneFrame:GetFrameLevel(), middle or -1, laneFrame:GetWidth(), laneFrame:GetHeight())
	end
	Describe("bar frame", barFrame)
	for i, lane in ipairs(Layout:Lanes()) do
		if lane.group == "sink" and lane.frame then
			Describe(i .. " " .. (lane.name or lane.key) .. " row", lane.frame)
		end
		local pools = lane.pools
		if pools then
			out[#out + 1] = string.format("%d %s: %d marks, %d diamonds, %d bars", i, lane.name or lane.key, #pools.marks.used, #pools.diamonds.used, #pools.bars.used)
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
	-- Draw order: the bar (BarTrack, on the frame), then bars and ticks, then
	-- the now line, then icon marks, then the engine-drawn sink icons, then
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
	Addon.BarTrack.Init(frame)
	barFrame = CreateFrame("Frame", nil, frame)
	nowLine = nowLayer:CreateTexture(nil, "OVERLAY", nil, 0)
	castGlow = barLayer:CreateTexture(nil, "OVERLAY", nil, 3)
	glowMask = barLayer:CreateMaskTexture()
	glowMask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	castGlow:AddMaskTexture(glowMask)
	castGlow:Hide()
	Util.NoSnap(nowLine)
	pip = nowLayer:CreateTexture(nil, "OVERLAY", nil, 1)

	frame:SetScript("OnShow", function()
		Renderer:MarkLayoutDirty()
	end)
	frame:SetScript("OnUpdate", OnUpdate)
	C_Timer.NewTicker(SWEEP_INTERVAL, Sweep)
	self:UpdateVisibility()
end
