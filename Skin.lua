-- 4everActionTimeline — the skins (docs/VISUAL.md, Skins; docs/ASSETS.md).
-- Native (default): the Encounter Timeline + Cooldown Manager family - the
-- combattimeline track art, the Cooldown Manager icon frame (mask and
-- overlay), the Cooldown Manager bar art, Blizzard's pause and queued
-- overlays, the icon trail. Flat: WHITE8X8 lines, edge-cropped icons, 1 px
-- borders, no atlas dependency. Each Native element checks its own atlases
-- (Util.AtlasExists): a missing one falls back to the Flat look for that
-- element only, never an error. Orientation-dependent art is turned through
-- tex coords (Layout:OrientTexCoord), the way Blizzard's
-- EncounterTimelineOrientedTextureMixin does.
--
-- The framed icon (marks and the sink icons) is a set of textures around one
-- icon texture the caller anchors: StyleIcon sizes it for the skin,
-- SetBorder colors its frame, SetStates shows the pause and queued overlays.

local Addon = FourEverActionTimeline
local Util, Layout = Addon.Util, Addon.Layout

local ICON_CROP = Util.ICON_CROP
local max, sqrt, pi = math.max, math.sqrt, math.pi
local SQRT2 = sqrt(2)
local BLACK = { 0, 0, 0, 1 }
local NOW_COLOR = { 1, 1, 1, 0.6 }
-- Single lane: the now line is warm and brighter, with a small diamond at its
-- lane-start end (Native has Blizzard's pip there; Flat draws one).
local NOW_COLOR_SINGLE = { 0.91, 0.85, 0.66, 0.75 }
local FLAT_PIP_ROOM = 5 -- the Flat pip reaches 2.5 line widths past the line's end
-- The cooldown divider draws its line this far inside its end-facing edge
-- (atlas pixels, measured in game on build 70235).
local DIVIDER_LINE_INSET = 5
-- The pip's diamond sits this far toward the axis start of its texture's
-- center (measured in game on build 70235), so the pip is nudged back.
local PIP_NUDGE = 2.5
-- Blizzard's event icon (EncounterTimelineEventIconTemplate): a 35 px icon,
-- the overlay overhanging it by -7/+6/+7/-7, a 16 px pause icon inset 4 px.
local BLIZZARD_ICON = 35
local OVERHANG_LEFT, OVERHANG_TOP, OVERHANG_RIGHT, OVERHANG_BOTTOM = 7, 6, 7, 7
local PAUSE_ICON, PAUSE_INSET = 16, 4

local Skin = {
	ATLAS = {
		lineStart = "combattimeline-line-left",
		lineEnd = "combattimeline-line-right",
		lineBreak = "combattimeline-line-break-mask",
		divider = "combattimeline-cooldown-divider",
		pip = "combattimeline-pip",
		trail = "combattimeline-line-icontrail",
		mask = "UI-HUD-CoolDownManager-Mask",
		overlay = "UI-HUD-CoolDownManager-IconOverlay",
		bar = "UI-HUD-CoolDownManager-Bar",
		barBG = "UI-HUD-CoolDownManager-Bar-BG",
		paused = "combattimeline-fx-pause",
		pausedIcon = "combattimeline-fx-pause-icon",
		queued = "combattimeline-fx-queued",
		chevron = "uitools-icon-chevron-right", -- probe 14
	},
}
Addon.Skin = Skin
local ATLAS = Skin.ATLAS

-- True when the Native skin is on and every named atlas exists.
function Skin.Native(...)
	if Layout.skin ~= "native" then
		return false
	end
	for i = 1, select("#", ...) do
		if not Util.AtlasExists(ATLAS[select(i, ...)]) then
			return false
		end
	end
	return true
end

-- How far Native art reaches past the lanes across the axis (the icon
-- overlay's overhang, the now line's pip), so the clipped frame keeps it.
function Skin.CrossPad(iconSize)
	local pad = 0
	if Skin.Native("mask", "overlay") then
		pad = math.ceil(OVERHANG_LEFT * iconSize / BLIZZARD_ICON) - 1
	end
	if Skin.Native("pip") then
		local width, height = Util.AtlasSize(ATLAS.pip, 0, 0)
		pad = math.max(pad, math.ceil(math.max(width, height) / 2))
	elseif Layout.single then
		pad = math.max(pad, FLAT_PIP_ROOM)
	end
	return math.max(pad, 0)
end

-- A left-to-right fade, turned to the axis: bright at the end-facing side
-- (the later instant) when brightAtFinish, else at the start-facing side.
-- `alpha` is the bright end's (default 1). `across`: the fade runs across the
-- axis instead, "finish" being the side positive across offsets go to.
function Skin.Gradient(texture, r, g, b, brightAtFinish, alpha, across)
	alpha = alpha or 1
	if not (texture.SetGradient and CreateColor) then
		texture:SetVertexColor(r, g, b, alpha)
		return
	end
	local faint, bright = CreateColor(r, g, b, 0), CreateColor(r, g, b, alpha)
	local orient = Layout.orient
	-- HORIZONTAL runs left to right and VERTICAL bottom to top: the finish
	-- side is the max side when the axis runs that way (sign 1). Across
	-- offsets run up, or right when vertical: the max side.
	local axis, sign = orient.axis, orient.sign
	if across then
		axis, sign = orient.vertical and "HORIZONTAL" or "VERTICAL", 1
	end
	local flip = brightAtFinish ~= (sign > 0)
	texture:SetGradient(axis, flip and bright or faint, flip and faint or bright)
end

-- The now line across every lane: Native the cooldown divider with the pip
-- at its lane-start end, Flat a 2 px white line. It is anchored at the
-- frame's corner where the time axis starts on the lane-start edge. The
-- divider art draws its line near its end-facing edge (Blizzard anchors it
-- by "END"), so Native anchors that edge just past the now instant, the
-- line itself on it, and centers the pip on the line; Flat is centered.
-- Flat Single lane: a stepped diamond on the now line's lane-start end, five
-- bars 1-3-5-3-1 line widths wide and one line width deep (as wide as it is
-- tall). Odd multiples of the line width, every bar snaps to the screen
-- pixels exactly as the line does, so it sits square on the line at any
-- scale (a turned square is drawn centred on a pixel while an even-width
-- line is centred between two).
local PIP_STEPS = { 1, 3, 5, 3, 1 }

local function StylePipSteps(pip, nowLine, point, thickness, shown)
	local steps = pip.steps
	if not shown then
		if steps then
			for _, bar in ipairs(steps) do
				bar:Hide()
			end
		end
		return
	end
	if not steps then
		steps = {}
		local parent = pip:GetParent()
		for i = 1, #PIP_STEPS do
			steps[i] = parent:CreateTexture(nil, "OVERLAY", nil, 1)
			steps[i]:SetTexture(Util.WHITE)
		end
		pip.steps = steps
	end
	local middle = (#PIP_STEPS + 1) / 2
	for i, width in ipairs(PIP_STEPS) do
		local bar = steps[i]
		bar:SetVertexColor(NOW_COLOR_SINGLE[1], NOW_COLOR_SINGLE[2], NOW_COLOR_SINGLE[3], 1)
		bar:SetSize(Layout:Extents(width * thickness, thickness))
		bar:ClearAllPoints()
		bar:SetPoint("CENTER", nowLine, point, Layout:Offsets(0, (i - middle) * thickness))
		bar:Show()
	end
end

function Skin.StyleNowLine(nowLine, pip, frame)
	local orient = Layout.orient
	local native = Skin.Native("divider")
	local point, inset, thickness = orient.crossStart, 0, Util.PixelSize(frame, 2)
	if native then
		point, inset = orient.cornerFinish, DIVIDER_LINE_INSET
		thickness = Util.AtlasSize(ATLAS.divider, 2, 0)
		nowLine:SetAtlas(ATLAS.divider)
		nowLine:SetVertexColor(1, 1, 1, 1)
		Layout:OrientTexCoord(nowLine)
	else
		nowLine:SetTexture(Util.WHITE)
		nowLine:SetTexCoord(0, 1, 0, 1)
		local color = Layout.single and NOW_COLOR_SINGLE or NOW_COLOR
		nowLine:SetVertexColor(color[1], color[2], color[3], color[4])
	end
	nowLine:ClearAllPoints()
	-- Inward from the lane-start edge by the cross pad.
	nowLine:SetPoint(point, frame, orient.corner, Layout:Offsets(Layout.nowX + inset, Layout.crossPad * orient.crossSign))
	nowLine:SetSize(Layout:Extents(thickness, math.max(Layout.lanesExtent, 1)))
	if native then
		pip:SetAtlas(ATLAS.pip, true)
		pip:SetRotation(0)
		pip:SetVertexColor(1, 1, 1, 1)
		pip:ClearAllPoints()
		pip:SetPoint("CENTER", nowLine, point, Layout:Offsets(PIP_NUDGE - inset, 0))
	end
	pip:SetShown(native)
	StylePipSteps(pip, nowLine, point, thickness, not native and Layout.single)
end

-- ---------------------------------------------------------------------------
-- The framed icon
-- ---------------------------------------------------------------------------

-- The icon and diamond art scrolls with its mark: unsnapped (Util.MovingTexture).
local MovingTexture = Util.MovingTexture

function Skin.CreateIconArt(owner)
	local art = { owner = owner }
	art.border = MovingTexture(owner, "ARTWORK", -2)
	art.icon = MovingTexture(owner, "ARTWORK", 0)
	return art
end

local function Overhang(texture, icon, k)
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", icon, "TOPLEFT", -OVERHANG_LEFT * k, OVERHANG_TOP * k)
	texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", OVERHANG_RIGHT * k, -OVERHANG_BOTTOM * k)
end

local function OverlayTexture(art, atlas, subLevel)
	local texture = MovingTexture(art.owner, "OVERLAY", subLevel)
	texture:SetAtlas(atlas)
	texture:Hide()
	return texture
end

-- Lazily creates the overlay art[key], overhangs it over the icon and
-- shows or hides it.
local function ShowOverlay(art, key, atlas, subLevel, shown, k)
	local texture = art[key]
	if shown and not texture then
		texture = OverlayTexture(art, atlas, subLevel)
		art[key] = texture
	end
	if texture then
		if shown then
			Overhang(texture, art.icon, k)
		end
		texture:SetShown(shown)
	end
end

-- Sizes the framed icon for the current skin. Native: the icon at full
-- size, masked, the overlay overhanging it. Flat: the icon 2 px smaller,
-- edge-cropped, in a 1 px border. The border color and the overlays are
-- re-applied by the next SetBorder / SetStates.
function Skin.StyleIcon(art, size)
	if art.style == Layout.style and art.size == size then
		return
	end
	local icon = art.icon
	local native = Skin.Native("mask", "overlay")
	art.native, art.size, art.style = native, size, Layout.style
	if native then
		icon:SetSize(size, size)
		icon:SetTexCoord(0, 1, 0, 1)
		if not art.mask then
			art.mask = art.owner:CreateMaskTexture()
			Util.NoSnap(art.mask)
			art.mask:SetAtlas(ATLAS.mask)
			art.mask:SetAllPoints(icon)
			art.overlay = OverlayTexture(art, ATLAS.overlay, 0)
		end
		if not art.masked then
			icon:AddMaskTexture(art.mask)
			art.masked = true
		end
		Overhang(art.overlay, icon, size / BLIZZARD_ICON)
		art.overlay:Show()
		art.border:Hide()
	else
		icon:SetSize(size - 2, size - 2)
		icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
		if art.masked then
			icon:RemoveMaskTexture(art.mask)
			art.masked = nil
		end
		if art.overlay then
			art.overlay:Hide()
		end
		art.border:ClearAllPoints()
		art.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
		art.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
		art.border:Show()
	end
	art.borderColor, art.paused, art.queued = false, nil, nil
end

-- The frame's color: nil for the skin's plain frame (Native: the overlay as
-- drawn; Flat: black), or {r, g, b} - Native tints the overlay, Flat the
-- 1 px border (VISUAL.md, Stopped casts; Held).
function Skin.SetBorder(art, color)
	if art.borderColor == color then
		return
	end
	art.borderColor = color
	if art.native then
		if color then
			art.overlay:SetVertexColor(color[1], color[2], color[3])
		else
			art.overlay:SetVertexColor(1, 1, 1)
		end
	else
		color = color or BLACK
		art.border:SetColorTexture(color[1], color[2], color[3], 1)
	end
end

-- Native only: Blizzard's pause overlay and icon on a paused hand's marks,
-- the queued overlay on the main-hand mark showing a queued ability. Flat
-- keeps the plain treatment (dim, icon swap).
function Skin.SetStates(art, paused, queued)
	paused = (paused and art.native and Skin.Native("paused", "pausedIcon")) or false
	queued = (queued and art.native and Skin.Native("queued")) or false
	if art.paused == paused and art.queued == queued then
		return
	end
	art.paused, art.queued = paused, queued
	local k = art.size / BLIZZARD_ICON
	ShowOverlay(art, "pausedOverlay", ATLAS.paused, 0, paused, k)
	if paused and not art.pausedIcon then
		art.pausedIcon = OverlayTexture(art, ATLAS.pausedIcon, 1)
	end
	if art.pausedIcon then
		if paused then
			art.pausedIcon:ClearAllPoints()
			art.pausedIcon:SetPoint("BOTTOMRIGHT", art.icon, "BOTTOMRIGHT", -PAUSE_INSET * k, PAUSE_INSET * k)
			art.pausedIcon:SetSize(PAUSE_ICON * k, PAUSE_ICON * k)
		end
		art.pausedIcon:SetShown(paused)
	end
	ShowOverlay(art, "queuedOverlay", ATLAS.queued, 0, queued, k)
end

-- ---------------------------------------------------------------------------
-- The swing diamond (the Single lane layout)
-- ---------------------------------------------------------------------------

-- A diamond is a frame the caller anchors and scales, the same in both skins:
-- a tinted square turned 45 degrees on a dark backing that outlines it, so it
-- reads against any scene (the pip's own art is no help at this size: its
-- color and shape are not ours and it has no outline). Hollow (ranged) is four
-- rotated strokes over a dark, translucent diamond, so its color stands out.
-- Orientation never changes it.
function Skin.CreateDiamond(owner)
	local art = { owner = owner }
	art.backing = MovingTexture(owner, "ARTWORK", -2)
	art.backing:SetTexture(Util.WHITE)
	art.backing:SetRotation(pi / 4)
	art.backing:SetPoint("CENTER", owner, "CENTER")
	art.fill = MovingTexture(owner, "ARTWORK", 0)
	art.fill:SetTexture(Util.WHITE)
	art.fill:SetRotation(pi / 4)
	art.fill:SetPoint("CENTER", owner, "CENTER")
	return art
end

-- Each stroke: the offset of its midpoint (in half radii) and its rotation.
local STROKES = {
	{ 1, 1, -pi / 4 }, { 1, -1, pi / 4 }, { -1, -1, -pi / 4 }, { -1, 1, pi / 4 },
}
-- How far the dark backing reaches past the diamond.
local OUTLINE = 1.5

-- Sizes the diamond to a half diagonal `radius`. The color is re-applied by
-- the next SetDiamondColor.
function Skin.StyleDiamond(art, radius, hollow)
	if art.radius == radius and art.hollow == hollow then
		return
	end
	art.radius, art.hollow, art.color = radius, hollow, nil
	local owner, fill = art.owner, art.fill
	owner:SetSize(radius * 2, radius * 2)
	local reach = (radius + OUTLINE) * SQRT2
	art.backing:SetSize(reach, reach)
	art.backing:SetVertexColor(0, 0, 0, hollow and 0.55 or 0.9)
	if hollow then
		fill:Hide()
		if not art.strokes then
			art.strokes = {}
			for i = 1, #STROKES do
				art.strokes[i] = MovingTexture(owner, "ARTWORK", 0)
				art.strokes[i]:SetTexture(Util.WHITE)
			end
		end
		local length, thickness = radius * SQRT2 + 1, max(radius * 0.3, 1.25)
		for i, stroke in ipairs(art.strokes) do
			local def = STROKES[i]
			stroke:SetSize(length, thickness)
			stroke:ClearAllPoints()
			stroke:SetPoint("CENTER", owner, "CENTER", def[1] * radius / 2, def[2] * radius / 2)
			stroke:SetRotation(def[3])
			stroke:Show()
		end
		return
	end
	if art.strokes then
		for _, stroke in ipairs(art.strokes) do
			stroke:Hide()
		end
	end
	fill:Show()
	fill:SetSize(radius * SQRT2, radius * SQRT2)
end

-- Tints the diamond `color` ({r, g, b}).
function Skin.SetDiamondColor(art, color)
	if art.color == color then
		return
	end
	art.color = color
	local r, g, b = color[1], color[2], color[3]
	if art.hollow then
		for _, stroke in ipairs(art.strokes) do
			stroke:SetVertexColor(r, g, b, 1)
		end
	else
		art.fill:SetVertexColor(r, g, b, 1)
	end
end

-- A paused hand's marks are frozen, which alone reads as a stuck diamond: its
-- next diamond wears a pause glyph on its past side - Native Blizzard's pause
-- icon, Flat two upright bars.
local PAUSE_GAP = 3
function Skin.SetDiamondPause(art, shown)
	local pause = art.pause
	if not shown then
		if pause and art.pauseKey then
			art.pauseKey = nil
			pause[1]:Hide()
			pause[2]:Hide()
		end
		return
	end
	local key = Layout.style .. ":" .. art.radius
	if art.pauseKey == key then
		return
	end
	art.pauseKey = key
	if not pause then
		pause = { MovingTexture(art.owner, "OVERLAY"), MovingTexture(art.owner, "OVERLAY") }
		art.pause = pause
	end
	local owner, radius, orient = art.owner, art.radius, Layout.orient
	if Skin.Native("pausedIcon") then
		local size = radius * 2 + 2
		pause[1]:SetAtlas(ATLAS.pausedIcon)
		pause[1]:SetSize(size, size)
		pause[1]:ClearAllPoints()
		pause[1]:SetPoint(orient.finish, owner, orient.start, Layout:Offsets(-PAUSE_GAP, 0))
		pause[1]:Show()
		pause[2]:Hide()
		return
	end
	local width, height = max(radius * 0.4, 1.5), radius * 1.6
	for i, bar in ipairs(pause) do
		bar:SetTexture(Util.WHITE)
		bar:SetTexCoord(0, 1, 0, 1)
		bar:SetVertexColor(0.91, 0.93, 0.96, 1)
		bar:SetSize(width, height)
		bar:ClearAllPoints()
		bar:SetPoint("CENTER", owner, "CENTER", Layout:Offsets(-(radius + PAUSE_GAP + width * (i == 1 and 0.5 or 2.5)), 0))
		bar:Show()
	end
end
