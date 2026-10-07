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
local BLACK = { 0, 0, 0, 1 }
local NOW_COLOR = { 1, 1, 1, 0.6 }
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
	end
	return math.max(pad, 0)
end

-- A left-to-right fade, turned to the axis: bright at the end-facing side
-- (the later instant) when brightAtFinish, else at the start-facing side.
function Skin.Gradient(texture, r, g, b, brightAtFinish)
	if not (texture.SetGradient and CreateColor) then
		texture:SetVertexColor(r, g, b, 1)
		return
	end
	local faint, bright = CreateColor(r, g, b, 0), CreateColor(r, g, b, 1)
	local orient = Layout.orient
	-- HORIZONTAL runs left to right and VERTICAL bottom to top: the finish
	-- side is the max side when the axis runs that way (sign 1).
	local flip = brightAtFinish ~= (orient.sign > 0)
	texture:SetGradient(orient.axis, flip and bright or faint, flip and faint or bright)
end

-- The now line across every lane: Native the cooldown divider with the pip
-- at its lane-start end, Flat a 2 px white line. It is anchored at the
-- frame's corner where the time axis starts on the lane-start edge. The
-- divider art draws its line near its end-facing edge (Blizzard anchors it
-- by "END"), so Native anchors that edge just past the now instant, the
-- line itself on it, and centers the pip on the line; Flat is centered.
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
		nowLine:SetVertexColor(NOW_COLOR[1], NOW_COLOR[2], NOW_COLOR[3], NOW_COLOR[4])
	end
	nowLine:ClearAllPoints()
	-- Inward from the lane-start edge by the cross pad.
	nowLine:SetPoint(point, frame, orient.corner, Layout:Offsets(Layout.nowX + inset, Layout.crossPad * orient.crossSign))
	nowLine:SetSize(Layout:Extents(thickness, math.max(Layout.lanesExtent, 1)))
	if native then
		pip:SetAtlas(ATLAS.pip, true)
		pip:ClearAllPoints()
		pip:SetPoint("CENTER", nowLine, point, Layout:Offsets(PIP_NUDGE - inset, 0))
	end
	pip:SetShown(native)
end

-- ---------------------------------------------------------------------------
-- The framed icon
-- ---------------------------------------------------------------------------

function Skin.CreateIconArt(owner)
	local art = { owner = owner }
	art.border = owner:CreateTexture(nil, "ARTWORK", nil, -2)
	art.icon = owner:CreateTexture(nil, "ARTWORK", nil, 0)
	return art
end

local function Overhang(texture, icon, k)
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", icon, "TOPLEFT", -OVERHANG_LEFT * k, OVERHANG_TOP * k)
	texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", OVERHANG_RIGHT * k, -OVERHANG_BOTTOM * k)
end

local function OverlayTexture(art, atlas, subLevel)
	local texture = art.owner:CreateTexture(nil, "OVERLAY", nil, subLevel)
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
