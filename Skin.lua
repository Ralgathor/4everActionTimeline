-- 4everActionTimeline — the skins (docs/VISUAL.md, Skins; docs/ASSETS.md).
-- Native (default): Blizzard's cast bar family - its background, fills,
-- spark and glow, the swing timer's border, the Cooldown Manager bar art for
-- the GCD - with the Encounter Timeline's divider and pip as the now line's
-- fallback. Flat: WHITE8X8 lines and boxes, no atlas dependency. Each Native
-- element checks its own atlases (Util.AtlasExists): a missing one falls
-- back to the Flat look for that element only, never an error.
-- Orientation-dependent art is turned through tex coords
-- (Layout:OrientTexCoord), the way Blizzard's
-- EncounterTimelineOrientedTextureMixin does.
--
-- The icon (marks and the sink icons) is plain in both skins, as Blizzard's
-- cast bar shows its icon: edge-cropped in a 1 px border. StyleIcon sizes
-- it, SetBorder colors its border.

local Addon = FourEverActionTimeline
local Util, Layout = Addon.Util, Addon.Layout

local ICON_CROP = Util.ICON_CROP
local max, sqrt, pi = math.max, math.sqrt, math.pi
local SQRT2 = sqrt(2)
local BLACK = { 0, 0, 0, 1 }
-- Flat: the now line is warm, with a small diamond at its lane-start end
local NOW_COLOR = { 0.91, 0.85, 0.66, 0.75 }
local FLAT_PIP_ROOM = 5 -- the Flat pip reaches 2.5 line widths past the line's end
-- The cooldown divider draws its line this far inside its end-facing edge
-- (atlas pixels, measured in game on build 70235).
local DIVIDER_LINE_INSET = 5
-- The pip's diamond sits this far toward the axis start of its texture's
-- center (measured in game on build 70235), so the pip is nudged back.
local PIP_NUDGE = 2.5

local Skin = {
	ATLAS = {
		-- The now line where the cast bar's spark is missing.
		divider = "combattimeline-cooldown-divider",
		pip = "combattimeline-pip",
		bar = "UI-HUD-CoolDownManager-Bar", -- the GCD's tint
		pausedIcon = "combattimeline-fx-pause-icon", -- a paused hand's diamond
		chevron = "uitools-icon-chevron-right", -- probe 14
		-- Blizzard's cast bar, one art family for the whole bar
		-- (CastingBarFrameTemplates.xml; probe H1 for the first five).
		-- The border: Blizzard's swing timer's, drawn to stretch over a bar of
		-- any size (4everSwingTimer stretches it over its bars).
		swingFrame = "ui-swingtimerbar-frame",
		castBackground = "ui-castingbar-background",
		castFill = "ui-castingbar-filling-standard",
		castChannel = "ui-castingbar-filling-channel",
		castPip = "ui-castingbar-pip",
		-- Blizzard's swing timer's own tick: a swing badge's stem across the bar.
		swingPip = "ui-swingtimerbar-pip",
		-- The glow trailing the cast bar's spark, and a channel's shadow there.
		castGlow = "cast_standard_pipglow",
		channelShadow = "cast_channel_pipshadow",
	},
}
Addon.Skin = Skin
local ATLAS = Skin.ATLAS

-- The bar's own frame art (Native): the cast bar's background under the
-- swing timer's border. The bar's inset and its art follow this one check.
function Skin.NativeBar()
	return Skin.Native("swingFrame", "castBackground")
end

-- Native's bar art is not even across: the swing timer border's dark band
-- is thicker on its lane-start side and the cast bar background shades
-- toward it, so its lit middle sits about a pixel off the geometric one (a
-- screenshot, build 70338). An icon smaller than the bar sits on the lit
-- middle; one filling the bar needs no nudge.
local NATIVE_MIDDLE_NUDGE = 1

-- The bar art's lit middle, across from its geometric one (`scale`: the bar
-- height's, SingleLane.Scale).
function Skin.BarMiddle(scale)
	if not Skin.NativeBar() then
		return 0
	end
	return Layout.orient.crossSign * NATIVE_MIDDLE_NUDGE * scale
end

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

-- How far the now line's pip reaches past its end across the axis (Native's,
-- or Flat's stepped diamond), so the clipped frame keeps it.
function Skin.CrossPad()
	if Skin.Native("pip") then
		local width, height = Util.AtlasSize(ATLAS.pip, 0, 0)
		return math.ceil(math.max(width, height) / 2)
	end
	return FLAT_PIP_ROOM
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

-- Sets a texture to an atlas turned to the axis, or to plain WHITE8X8.
function Skin.SetArt(texture, atlas)
	if atlas then
		texture:SetAtlas(atlas)
		Layout:OrientTexCoord(texture)
	else
		texture:SetTexture(Util.WHITE)
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

-- The now line across the bar: Native the cast bar's spark (or, where it is
-- missing, the cooldown divider with the pip at its lane-start end), Flat a
-- 2 px warm line. It is anchored at the frame's corner where the time axis
-- starts on the lane-start edge. The divider art draws its line near its
-- end-facing edge (Blizzard anchors it by "END"), so the divider anchors
-- that edge just past the now instant, the line itself on it, and centers
-- the pip on the line; the others are centered.
-- Flat: a stepped diamond on each end of the now line, five
-- bars 1-3-5-3-1 line widths wide and one line width deep (as wide as it is
-- tall). Odd multiples of the line width, every bar snaps to the screen
-- pixels exactly as the line does, so it sits square on the line at any
-- scale (a turned square is drawn centred on a pixel while an even-width
-- line is centred between two).
local PIP_STEPS = { 1, 3, 5, 3, 1 }

-- The steps kept as pip[key], centred on the now line's `point`.
local function StylePipSteps(pip, key, nowLine, point, thickness, shown)
	local steps = pip[key]
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
		pip[key] = steps
	end
	local middle = (#PIP_STEPS + 1) / 2
	for i, width in ipairs(PIP_STEPS) do
		local bar = steps[i]
		bar:SetVertexColor(NOW_COLOR[1], NOW_COLOR[2], NOW_COLOR[3], 1)
		bar:SetSize(Layout:Extents(width * thickness, thickness))
		bar:ClearAllPoints()
		bar:SetPoint("CENTER", nowLine, point, Layout:Offsets(0, (i - middle) * thickness))
		bar:Show()
	end
end

function Skin.StyleNowLine(nowLine, pip, frame)
	local orient = Layout.orient
	-- Native: the cast bar's spark, as Blizzard's cast bar draws the edge of a
	-- running cast - the art family the whole bar uses, no timeline pip.
	local spark = Skin.Native("castPip")
	local native = not spark and Skin.Native("divider")
	local point, inset, thickness = orient.crossStart, 0, Util.PixelSize(frame, 2)
	nowLine:SetBlendMode(spark and "ADD" or "BLEND")
	local atlas = spark and ATLAS.castPip or native and ATLAS.divider or nil
	Skin.SetArt(nowLine, atlas)
	if spark then
		thickness = Util.AtlasSize(ATLAS.castPip, 4, 0)
	elseif native then
		point, inset = orient.cornerFinish, DIVIDER_LINE_INSET
		thickness = Util.AtlasSize(ATLAS.divider, 2, 0)
	end
	if atlas then
		nowLine:SetVertexColor(1, 1, 1, 1)
	else
		nowLine:SetVertexColor(NOW_COLOR[1], NOW_COLOR[2], NOW_COLOR[3], NOW_COLOR[4])
	end
	nowLine:ClearAllPoints()
	-- Inward from the lane-start edge: across the bar and its reach past it
	-- (Layout.nowFrom / nowLength).
	nowLine:SetPoint(point, frame, orient.corner, Layout:Offsets(Layout.nowX + inset, Layout.nowFrom * orient.crossSign))
	nowLine:SetSize(Layout:Extents(thickness, math.max(Layout.nowLength, 1)))
	if native then
		pip:SetAtlas(ATLAS.pip, true)
		pip:SetRotation(0)
		pip:SetVertexColor(1, 1, 1, 1)
		pip:ClearAllPoints()
		pip:SetPoint("CENTER", nowLine, point, Layout:Offsets(PIP_NUDGE - inset, 0))
	end
	pip:SetShown(native)
	local flat = not native and not spark
	StylePipSteps(pip, "steps", nowLine, point, thickness, flat)
	StylePipSteps(pip, "lowSteps", nowLine, orient.crossEnd, thickness, flat)
end

-- ---------------------------------------------------------------------------
-- The icon
-- ---------------------------------------------------------------------------

-- The icon and diamond art scrolls with its mark: unsnapped (Util.MovingTexture).
local MovingTexture = Util.MovingTexture

-- An atlas's region, for drawing parts of it: its info when the client
-- reports the file and coordinates, else nil.
function Skin.Region(atlas)
	local info = Util.AtlasInfo(atlas)
	if info and (info.file or info.filename) and info.leftTexCoord then
		return info
	end
	return nil
end

-- Shows the part u0..u1 (fractions of its width, the full height) of a
-- region (Skin.Region) on a texture set to its file, turned for the
-- orientation: a cast's fill revealed up to now, as Blizzard's cast bar
-- reveals it.
function Skin.RegionCoords(texture, info, u0, u1)
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local x0, x1 = l + (r - l) * u0, l + (r - l) * u1
	local c = Layout.orient.texCoord
	texture:SetTexCoord(
		c[1] == 0 and x0 or x1, c[2] == 0 and t or b,
		c[3] == 0 and x0 or x1, c[4] == 0 and t or b,
		c[5] == 0 and x0 or x1, c[6] == 0 and t or b,
		c[7] == 0 and x0 or x1, c[8] == 0 and t or b)
end

-- Shows one cell of a region laid out as a grid (`columns` x `rows`, the
-- cell at 0-based `column`, `row`): a flipbook's frame.
function Skin.RegionCell(texture, info, column, row, columns, rows)
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local w, h = (r - l) / columns, (b - t) / rows
	texture:SetTexCoord(l + column * w, l + (column + 1) * w, t + row * h, t + (row + 1) * h)
end

-- RegionCell turned 45 degrees: the quad (sqrt 2 times the cell's size) samples
-- the cell rotated about its centre, so it reaches into the neighbouring cells;
-- a mask of the cell's turned shape cuts it back (Effects, TurnFlipbook).
function Skin.RegionCellTurned(texture, info, column, row, columns, rows)
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local w, h = (r - l) / columns, (b - t) / rows
	local cx, cy = l + (column + 0.5) * w, t + (row + 0.5) * h
	-- The quad's corners (+-0.5 sqrt 2 cells) turned back by 45 degrees land on
	-- the cell's edge midpoints, a whole cell out: top, left, right, bottom.
	texture:SetTexCoord(cx, cy - h, cx - w, cy, cx + w, cy, cx, cy + h)
end

-- The link mark: a linked set returning together is one icon,
-- badged in its corner - a dark square with a warm dot, in both skins (no
-- link atlas exists, ASSETS.md).
local LINK_BADGE, LINK_DOT = 8, 4
local LINK_COLOR = { 0.91, 0.85, 0.66 }

function Skin.CreateLinkBadge(mark)
	local badge = CreateFrame("Frame", nil, mark)
	badge:SetSize(LINK_BADGE, LINK_BADGE)
	badge:SetPoint("CENTER", mark.art.icon, "TOPRIGHT", -2, -2)
	local back = MovingTexture(badge, "OVERLAY", 6)
	back:SetTexture(Util.WHITE)
	back:SetAllPoints()
	back:SetVertexColor(0, 0, 0, 1)
	back:SetAlpha(0.85)
	local dot = MovingTexture(badge, "OVERLAY", 7)
	dot:SetTexture(Util.WHITE)
	dot:SetSize(LINK_DOT, LINK_DOT)
	dot:SetPoint("CENTER")
	dot:SetVertexColor(LINK_COLOR[1], LINK_COLOR[2], LINK_COLOR[3], 1)
	badge:Hide()
	return badge
end

-- The icon's size and crop: a plain icon is 2 px under its size and
-- edge-cropped; a framed one (SetIconFrame) fills its size and shows the whole
-- texture, the frame art and mask trimming its edge.
local FRAME_WIDTH, FRAME_HEIGHT, BUTTON = 46, 45, 45 -- the action button's frame art on its icon
Skin.FRAME_RATIO = FRAME_WIDTH / BUTTON
local function FitIcon(art)
	local icon, size = art.icon, art.size
	if not size then
		return
	end
	if art.framed then
		icon:SetSize(size, size)
		icon:SetTexCoord(0, 1, 0, 1)
		if art.turned then
			icon:SetRotation(math.pi / 4) -- replaces the coordinates just set
		end
		art.frame:SetSize(size * FRAME_WIDTH / BUTTON, size * FRAME_HEIGHT / BUTTON)
		-- Centered (not from the top left) so a turned frame turns on the icon.
		art.frame:ClearAllPoints()
		art.frame:SetPoint("CENTER", icon, "CENTER", size * (FRAME_WIDTH - BUTTON) / 2 / BUTTON, 0)
		art.frameMask:SetSize(size * art.maskWidth / BUTTON, size * art.maskHeight / BUTTON)
	else
		icon:SetSize(size - 2, size - 2)
		icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	end
end

function Skin.CreateIconArt(owner)
	local art = { owner = owner }
	art.border = MovingTexture(owner, "ARTWORK", -2)
	art.icon = MovingTexture(owner, "ARTWORK", 0)
	return art
end

-- Sizes the icon: 2 px smaller than `size`, edge-cropped, in a 1 px
-- border. The border color is re-applied by the next SetBorder.
function Skin.StyleIcon(art, size)
	if art.size == size then
		return
	end
	art.size = size
	local icon = art.icon
	FitIcon(art)
	art.border:ClearAllPoints()
	art.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
	art.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
	art.borderColor = false
end

-- The action bar button's art (Blizzard_ActionBar, ActionButtonTemplate.xml):
-- the icon cut by IconFrame-Mask (wrap modes CLAMPTOBLACKADDITIVE: nothing
-- outside the mask's own area), the slot art and the opaque background
-- behind it, and IconFrame over it, 46x45 on the 45x45 icon from its top
-- left. Returns whether it was drawn; without the atlases the caller keeps a
-- plain rim.
local ICON_FRAME, ICON_FRAME_MASK = "UI-HUD-ActionBar-IconFrame", "UI-HUD-ActionBar-IconFrame-Mask"
local ICON_FRAME_SLOT, ICON_FRAME_BACKGROUND = "UI-HUD-ActionBar-IconFrame-Slot", "UI-HUD-ActionBar-IconFrame-Background"

-- A mask from an atlas with the button's wrap modes (SetAtlas takes none).
local function SetMaskAtlas(mask, atlas)
	local info = Skin.Region(atlas)
	if info then
		mask:SetTexture(info.file or info.filename, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord)
	else
		mask:SetAtlas(atlas)
	end
end

-- Sets the button's pieces from their atlases, then turns them a diamond
-- (SetRotation replaces the texture coordinates, so the art is set first).
local function ApplyFrameArt(art)
	art.appliedTurn = art.turned
	SetMaskAtlas(art.frameMask, ICON_FRAME_MASK)
	if Util.AtlasInfo(ICON_FRAME_BACKGROUND) then
		art.back:SetAtlas(ICON_FRAME_BACKGROUND)
	else
		art.back:SetColorTexture(0, 0, 0, 1)
	end
	if Util.AtlasInfo(ICON_FRAME_SLOT) then
		art.slot:SetAtlas(ICON_FRAME_SLOT)
	end
	art.frame:SetAtlas(ICON_FRAME)
	if art.turned then
		local turn = math.pi / 4
		art.frameMask:SetRotation(turn)
		art.back:SetRotation(turn)
		art.slot:SetRotation(turn)
		art.frame:SetRotation(turn)
	end
end

-- `turned`: the whole badge turned 45 degrees, a diamond.
function Skin.SetIconFrame(art, on, turned)
	local framed = on and Util.AtlasInfo(ICON_FRAME) and Util.AtlasInfo(ICON_FRAME_MASK) and true or false
	turned = framed and turned and true or false
	if art.framed == framed and art.turned == turned then
		return framed
	end
	art.framed, art.turned = framed, turned
	local icon = art.icon
	if framed then
		if not art.frame then
			local owner = art.owner
			art.frameMask = owner:CreateMaskTexture()
			-- Centered on the icon at the atlas's own size, not stretched to
			-- the icon (the button sets no size): the shape may sit inside a
			-- larger atlas, and stretching it would shrink the visible area.
			art.frameMask:SetPoint("CENTER", icon, "CENTER")
			art.maskWidth, art.maskHeight = Util.AtlasSize(ICON_FRAME_MASK, BUTTON, BUTTON)
			-- Behind the icon: the opaque background, cut by the mask, and the slot
			-- art over it (ApplyFrameArt sets their art).
			art.back = MovingTexture(owner, "ARTWORK", -3)
			art.back:SetAllPoints(icon)
			art.back:AddMaskTexture(art.frameMask)
			art.slot = MovingTexture(owner, "ARTWORK", -1)
			art.slot:SetAllPoints(icon)
			art.frame = MovingTexture(owner, "OVERLAY", 2)
			ApplyFrameArt(art)
		elseif art.appliedTurn ~= turned then
			ApplyFrameArt(art)
		end
		icon:AddMaskTexture(art.frameMask)
		art.frame:Show()
		art.back:Show()
		art.slot:Show()
	elseif art.frame then
		icon:RemoveMaskTexture(art.frameMask)
		art.frame:Hide()
		art.back:Hide()
		art.slot:Hide()
	end
	art.border:SetShown(not framed) -- the frame art is the rim
	FitIcon(art)
	return framed
end

-- A badge's stem: the swing's exact time on the bar, across it from the badge,
-- under the badge. Native: the swing timer's own tick (ASSETS.md), desaturated
-- and tinted `color` ({r, g, b}: the pip's blue-grey would clash with the
-- frame's bronze), at its own proportions scaled to the bar's height and
-- centered on the bar - or on the bar's near half (`half`) when dual-wielding,
-- so the two hands' stems never cross - turned for a vertical timeline;
-- otherwise a 1 px line from the badge to the bar's far edge. `across`: the
-- mark's place across the bar. A nil `color` hides it.
local PIP_WIDTH = 0.65 -- the pip drawn this much narrower, in line with the badge's thin frame
local PIP_MAX_SCALE = 1.5 -- ... and scaled up to the bar's height, no more than this

function Skin.SetStem(mark, color, across, half)
	local tick = mark.tick
	if not color then
		if tick then
			tick:Hide()
			tick.native = nil -- re-applied when shown again
		end
		return
	end
	local native = Skin.Native("swingPip") and true or false
	local vertical = Layout.orient.vertical and true or false
	local extent = Layout.trackExtent
	if tick and tick.native == native and tick.vertical == vertical and tick.extent == extent
		and tick.across == across and tick.half == half and tick.color == color then
		return
	end
	if not tick then
		tick = MovingTexture(mark, "ARTWORK", -5)
		mark.tick = tick
	end
	-- SetRotation replaces the texture coordinates, so the art is set again
	-- before each change of art or turn, then turned.
	if tick.native ~= native or tick.vertical ~= vertical then
		if native then
			tick:SetAtlas(ATLAS.swingPip)
		else
			tick:SetTexture(Util.WHITE)
		end
		if vertical then
			tick:SetRotation(pi / 2)
		end
	end
	tick.native, tick.vertical, tick.extent, tick.across, tick.half, tick.color = native, vertical, extent, across, half, color
	local out = across < 0 and -1 or 1
	local thickness, length, middle -- the stem's centre across the bar, from the mark's centre
	if native then
		local width, height = Util.AtlasSize(ATLAS.swingPip, 4, 26)
		local full = math.min(extent / height, PIP_MAX_SCALE)
		local scale = half and math.min(extent / 2 / height, PIP_MAX_SCALE) or full
		-- The thickness keeps the full-bar pip's (it would halve with the length).
		thickness, length = width * full * PIP_WIDTH, height * scale
		middle = (half and out * extent / 4 or 0) - across
	else
		thickness = Util.PixelSize(mark, 1)
		length = math.abs(across) + extent / 2
		middle = -out * length / 2
	end
	tick:SetSize(thickness, length) -- unturned: thin and long
	tick:ClearAllPoints()
	tick:SetPoint("CENTER", mark, "CENTER", Layout:Offsets(0, middle))
	tick:SetDesaturated(native)
	tick:SetVertexColor(color[1], color[2], color[3], native and 1 or 0.9)
	tick:Show()
end

-- The border's color: nil for black, or {r, g, b} (VISUAL.md, Stopped
-- casts; Held).
function Skin.SetBorder(art, color)
	if art.borderColor == color then
		return
	end
	art.borderColor = color
	color = color or BLACK
	art.border:SetColorTexture(color[1], color[2], color[3], 1)
end

-- ---------------------------------------------------------------------------
-- The swing diamond
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
local function TintDiamond(art, r, g, b)
	if art.hollow then
		for _, stroke in ipairs(art.strokes) do
			stroke:SetVertexColor(r, g, b, 1)
		end
	else
		art.fill:SetVertexColor(r, g, b, 1)
	end
end

function Skin.SetDiamondColor(art, color)
	if art.color == color then
		return
	end
	art.color = color
	TintDiamond(art, color[1], color[2], color[3])
end

-- A passing color (a flash easing back): not kept, so the next
-- SetDiamondColor applies whatever it is given.
function Skin.TintDiamond(art, r, g, b)
	art.color = nil
	TintDiamond(art, r, g, b)
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
