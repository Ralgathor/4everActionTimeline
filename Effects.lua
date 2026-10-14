-- 4everActionTimeline — transient effects (docs/VISUAL.md, Hand-lane effects).
-- The reposition pop (cast_standard_pipglow, ADD, tinted), the correction
-- streak (bright at the new instant, transparent at the old one, so it
-- points the way the prediction moved), the across-lane shake, the urgency
-- flash (an icon's flipbook, a diamond's halo), a return's flash and linger,
-- and a used parked icon's finish. Effects are anchored to timeline instants
-- or follow their mark, and fade within ~0.8 s; none is ever a mark. The shake is an offset the renderer
-- adds across the lane, never along the time axis and never through
-- ScriptAnimationUtil.ShakeFrame (the anchor rule), and it honors the
-- ShakeStrengthUI CVar (0 disables it).

local Addon = FourEverActionTimeline
local Util, Layout = Addon.Util, Addon.Layout

local GetTime, GetCVar = GetTime, GetCVar
local abs, max, min, sin, pi, remove = math.abs, math.max, math.min, math.sin, math.pi, table.remove

local WHITE = Util.WHITE
local POP_ATLAS = "cast_standard_pipglow" -- shared with 4everSwingTimer
local POP_TIME = 0.3
local RING_TIME = 0.8
-- A return with no place in the ready stack: its icon stays on the now line
-- this long, fading, under the ring (ADR-0009).
local LINGER_TIME = 0.5
-- A parked ready icon used: Blizzard's finish (EncounterTimelineTrackEvent:
-- grows to 1.35x and fades over 0.2 s) where it stood in the stack.
local FINISH_TIME, FINISH_GROWTH = 0.2, 0.35
-- Returns arriving together: each ring this much after the last, so two
-- read as two.
local RING_STAGGER = 0.1
local RING_COLOR = { 1.0, 0.93, 0.75 } -- also the highlight's
-- An icon's flash (the urgency cue on an icon, and a return): the Cooldown
-- Manager's own cooldown-ending flash (CooldownViewer.xml CooldownFlash: a
-- 22-frame flipbook, 11 rows of 2, over 0.75 s, the icon's size).
local FLASH_ATLAS, FLASH_ROWS, FLASH_COLUMNS, FLASH_FRAMES, FLASH_TIME = "UI-HUD-ActionBar-GCD-Flipbook", 11, 2, 22, 0.75
-- Drawn bigger than the icon and additive: Blizzard's is for a 30-40 px
-- action button, ours for an 18-24 px icon on a busy bar, where at the
-- icon's size and blended it was hard to see (in game).
local FLASH_SCALE = 1.35
-- Without that art: the pip glow rising and falling once around the icon,
-- 1.5x its size - Blizzard's HighlightGlow timing (0 to 0.7 and back over
-- 0.4 s), a little stronger for the corner of the eye.
local HIGHLIGHT_TIME, HIGHLIGHT_PEAK, HIGHLIGHT_SIZE = 0.4, 0.9, 1.5
-- A diamond's flash: its fill (a hollow one's outline) turns white and eases
-- back to its color - the diamond itself lights, in its own shape and place -
-- under a halo of its shape, growing from DIAMOND_HALO times its size and
-- fading (alone the color change was too small to see, in game).
local DIAMOND_FLASH_TIME = 0.45
local DIAMOND_HALO, DIAMOND_HALO_GROWTH, DIAMOND_HALO_ALPHA = 1.6, 1.2, 0.9
local WHITE_COLOR = { 1, 1, 1 }
local POP_GROWTH = 0.4
local STREAK_TIME = 0.3
local STREAK_HEIGHT = 3
local SHAKE_TIME = 0.25
local SHAKE_AMPLITUDE = 3 -- pixels
local SHAKE_FREQUENCY = 16 -- Hz

local Effects = {
	-- 4everSwingTimer's effect colors (Bars.lua HASTE_TINT, DELAY_TINT, CLIP_TINT).
	TEAL = { 0.10, 0.95, 0.65 },
	AMBER = { 1.0, 0.60, 0.10 },
	RED = { 1.0, 0.25, 0.20 },
}
Addon.Effects = Effects

local SingleLane = Addon.SingleLane
local layer
local live = {}
local shakeStrength = 1
local freePops, freeStreaks, freeIcons, freeFlashes, freeHalos = {}, {}, {}, {}, {}
local lastRing = -math.huge
local EaseOut = Util.EaseOut
local floor, sqrt = math.floor, math.sqrt

-- How long a diamond's flash runs (the renderer eases its color back over it).
Effects.DIAMOND_FLASH_TIME = DIAMOND_FLASH_TIME

local function NewPop()
	local texture = layer:CreateTexture(nil, "OVERLAY")
	if Util.AtlasExists(POP_ATLAS) then
		texture:SetAtlas(POP_ATLAS)
	else
		texture:SetTexture(WHITE)
	end
	texture:SetBlendMode("ADD")
	return texture
end

-- A lingering icon: a mark's icon art (Skin), on a frame that fades whole.
local function NewIcon()
	local icon = CreateFrame("Frame", nil, layer)
	icon.art = Addon.Skin.CreateIconArt(icon)
	icon.art.icon:SetPoint("CENTER")
	return icon
end

-- The flash's art: the flipbook's file, a frame shown at a time (Place).
local function NewFlipbook()
	local texture = Util.MovingTexture(layer, "OVERLAY")
	texture:SetBlendMode("ADD")
	return texture
end

-- A diamond's halo: a white square turned 45 degrees, additive.
local function NewHalo()
	local texture = Util.MovingTexture(layer, "ARTWORK")
	texture:SetTexture(WHITE)
	texture:SetBlendMode("ADD")
	if texture.SetRotation then
		texture:SetRotation(pi / 4)
	end
	return texture
end

local function NewStreak()
	local texture = layer:CreateTexture(nil, "ARTWORK")
	texture:SetTexture(WHITE)
	texture:SetBlendMode("ADD")
	return texture
end

-- Tracks an effect on its pooled texture from `start` (now by default): shown,
-- transparent until Place draws it.
local function Track(effect, texture, pool, start)
	effect.texture, effect.pool, effect.start = texture, pool, start or GetTime()
	texture:SetAlpha(0)
	texture:Show()
	live[#live + 1] = effect
	return texture
end

-- A glow: a pooled pop texture, tinted (`oriented`: the wide glow turned
-- with the axis).
local function Flash(effect, color, oriented, start)
	local texture = remove(freePops) or NewPop()
	if oriented then
		Layout:OrientTexCoord(texture)
	else
		texture:SetTexCoord(0, 1, 0, 1)
	end
	texture:SetVertexColor(color[1], color[2], color[3], 1)
	return Track(effect, texture, freePops, start)
end

-- A lane's icon in a mark's art, `size` across, at a place on its lane
-- (a linger, a finish).
local function ShowIcon(kind, lane, size, along, across, start, duration)
	local icon = remove(freeIcons) or NewIcon()
	icon:SetSize(size, size)
	Addon.Skin.StyleIcon(icon.art, size)
	Addon.Skin.SetBorder(icon.art)
	icon.art.icon:SetTexture(lane.icon)
	icon:SetPoint("CENTER", lane.frame, Layout.orient.start, Layout:Offsets(along, across))
	Track({ kind = kind, lane = lane, size = size, duration = duration }, icon, freeIcons, start)
end

-- The flipbook flash, from the client's atlas; nil without it.
local function Flipbook(effect, start)
	local region = Addon.Skin.Region(FLASH_ATLAS)
	if not region then
		return nil
	end
	local texture = remove(freeFlashes) or NewFlipbook()
	texture:SetTexture(region.file or region.filename)
	effect.kind, effect.region, effect.duration, effect.frame = "flipbook", region, FLASH_TIME, nil
	return Track(effect, texture, freeFlashes, start)
end

-- Centres a texture `size` across on a lane's ring place.
local function PlaceAtRing(texture, lane, size)
	local along, across = SingleLane.RingPosition(lane)
	texture:SetSize(size, size)
	texture:SetPoint("CENTER", lane.frame, Layout.orient.start, Layout:Offsets(along, across))
end

function Effects:Pop(lane, t, color)
	if layer and t then
		Flash({ kind = "pop", lane = lane, t = t, duration = POP_TIME }, color, true)
	end
end

-- A diamond lights in `color` (white: it crossed into its last 1.5 s; a
-- correction's teal, amber or red: it just moved) under a halo of its shape
-- in that color; the renderer eases the diamond's own color back from
-- `flashColor` (PlaceDiamond).
local function FlashDiamond(widget, radius, color)
	color = color or WHITE_COLOR
	local start = GetTime()
	widget.flashColor, widget.flashStart = color, start
	local halo = remove(freeHalos) or NewHalo()
	halo:SetVertexColor(color[1], color[2], color[3], 1)
	halo:SetPoint("CENTER", widget, "CENTER")
	-- A square turned 45 degrees: its side is the half diagonal times sqrt 2.
	Track({ kind = "halo", side = radius * sqrt(2), duration = DIAMOND_FLASH_TIME }, halo, freeHalos, start)
end

-- A mark (`widget`, drawing `desc`) crossed into its last 1.5 s, or a
-- diamond a correction just moved (`color`): a diamond lights in its own
-- shape; an icon plays the cooldown-ending flash over it, following it.
function Effects:Highlight(widget, desc, color)
	if not layer then
		return
	end
	if desc.radius then
		FlashDiamond(widget, desc.radius, color)
		return
	end
	local size = desc.size or Layout.iconSize
	local texture = Flipbook({})
	if texture then
		size = size * FLASH_SCALE
	else
		texture = Flash({ kind = "highlight", duration = HIGHLIGHT_TIME }, RING_COLOR)
		size = size * HIGHLIGHT_SIZE
	end
	texture:SetSize(size, size)
	texture:SetPoint("CENTER", widget, "CENTER")
end

-- A cooldown came back: the flash on its place in the ready stack, or on the
-- now line (SingleLane.RingPosition); with no place in the stack, its icon
-- lingers on the now line under it. Returns arriving together flash
-- RING_STAGGER apart.
function Effects:Ring(lane)
	if not layer then
		return
	end
	local start = max(GetTime(), lastRing + RING_STAGGER)
	lastRing = start
	if lane.icon and lane.frame and not SingleLane.HasPlace(lane) then
		local along, across = SingleLane.RingPosition(lane)
		ShowIcon("linger", lane, Layout.iconSize, along, across, start, LINGER_TIME)
	end
	if not Flipbook({ lane = lane, ring = true }, start) then
		Flash({ kind = "ring", lane = lane, duration = RING_TIME }, RING_COLOR, false, start)
	end
end

-- A parked ready icon was used (its spell cast): the icon grows and fades
-- where it stood in the stack, as it leaves it.
function Effects:Finish(lane)
	if layer and lane.icon and lane.frame and lane.readyOrder and lane.parkIndex then
		local along, across = SingleLane.RingPosition(lane)
		ShowIcon("finish", lane, Layout.parkSize, along, across, nil, FINISH_TIME)
	end
end

-- A fading streak from the old instant to the new one.
function Effects:Streak(lane, from, to, color)
	if not (layer and from and to) or from == to then
		return
	end
	local texture = remove(freeStreaks) or NewStreak()
	-- Bright at the new instant: the end-facing side when it is the later one.
	Addon.Skin.Gradient(texture, color[1], color[2], color[3], to > from)
	Track({ kind = "streak", lane = lane, from = from, to = to, duration = STREAK_TIME }, texture, freeStreaks)
end

-- A corrected prediction: the streak from the old instant to the new one,
-- and the pop at the new one unless the pop budget is spent (pop == false).
-- With the pop, the lane's next diamond lights in the same color: the
-- renderer's next rebuild of the lane reads `lane.flashColor` and clears it.
function Effects:Correct(lane, from, to, color, pop)
	if pop ~= false then
		self:Pop(lane, to, color)
		lane.flashColor = color
	end
	self:Streak(lane, from, to, color)
end

-- Starts the across-lane shake and returns its start time, which shaking
-- marks carry as their `shake` field. The CVar is read once per shake.
function Effects:Shake(lane)
	lane.shakeStart = GetTime()
	shakeStrength = tonumber(GetCVar and GetCVar("ShakeStrengthUI")) or 1
	return lane.shakeStart
end

-- The shake's offset (pixels, across the lane) for a shake started at start.
function Effects.ShakeOffset(start, now)
	local progress = (now - start) / SHAKE_TIME
	if progress >= 1 or progress < 0 then
		return 0
	end
	return SHAKE_AMPLITUDE * shakeStrength * (1 - progress) * sin(2 * pi * SHAKE_FREQUENCY * (now - start))
end

local function Release(effect)
	local texture = effect.texture
	texture:Hide()
	texture:ClearAllPoints()
	local pool = effect.pool
	pool[#pool + 1] = texture
end

-- Each kind's per-frame placement (`progress` 0..1, `eased` its ease-out),
-- and whether it then fades out with 1 - eased (`fade`).
local KINDS = {
	-- One flipbook frame at a time, at full alpha, as Blizzard plays it; a
	-- return's on its ring place, the parked icon's size or a bar icon's.
	flipbook = { place = function(effect, texture, progress)
		local frame = min(floor(progress * FLASH_FRAMES), FLASH_FRAMES - 1)
		if effect.frame ~= frame then
			if not effect.frame then
				texture:SetAlpha(1)
			end
			effect.frame = frame
			Addon.Skin.RegionCell(texture, effect.region, frame % FLASH_COLUMNS, floor(frame / FLASH_COLUMNS), FLASH_COLUMNS, FLASH_ROWS)
		end
		if effect.ring then
			local lane = effect.lane
			PlaceAtRing(texture, lane, lane.parkIndex and lane.readyOrder and Layout.parkSize or Layout.iconSize)
		end
	end },
	halo = { place = function(effect, texture, _, eased)
		local side = effect.side * (DIAMOND_HALO + DIAMOND_HALO_GROWTH * eased)
		texture:SetSize(side, side)
		texture:SetAlpha(DIAMOND_HALO_ALPHA * (1 - eased))
	end },
	-- Without the flipbook: the glow rising and falling around the icon.
	highlight = { place = function(_, texture, progress)
		texture:SetAlpha(HIGHLIGHT_PEAK * (1 - abs(2 * progress - 1)))
	end },
	-- Without the flipbook: the glow growing on the return's place.
	ring = { fade = true, place = function(effect, texture, _, eased)
		PlaceAtRing(texture, effect.lane, Layout.iconSize * (0.9 + 1.2 * eased))
	end },
	-- Placed once (Effects:Ring); it only fades.
	linger = { fade = true, place = function() end },
	finish = { fade = true, place = function(effect, texture, _, eased)
		local size = effect.size * (1 + FINISH_GROWTH * eased)
		texture:SetSize(size, size)
		Addon.Skin.StyleIcon(texture.art, size)
	end },
	-- On the hand's edge of the bar, where its marks are.
	pop = { fade = true, place = function(effect, texture, _, eased, now, far)
		local size = Layout.iconSize * (1 + POP_GROWTH * eased)
		texture:SetSize(Layout:Extents(size * 1.6, size))
		texture:SetPoint("CENTER", effect.lane.frame, Layout.orient.start, Layout:Offsets(Layout:TimeToOffset(min(effect.t, far), now), SingleLane.Across(effect.lane)))
	end },
	streak = { fade = true, place = function(effect, texture, _, _, now, far)
		local a1 = Layout:TimeToOffset(min(min(effect.from, effect.to), far), now)
		local a2 = Layout:TimeToOffset(min(max(effect.from, effect.to), far), now)
		local start = Layout.orient.start
		texture:SetPoint(start, effect.lane.frame, start, Layout:Offsets(a1, SingleLane.Across(effect.lane)))
		texture:SetSize(Layout:Extents(max(a2 - a1, 1), STREAK_HEIGHT))
	end },
}

-- Called by the renderer every frame; costs nothing while no effect is live.
function Effects:Place(now)
	local far = Layout:FarEdge(now)
	for i = #live, 1, -1 do
		local effect = live[i]
		local progress = (now - effect.start) / effect.duration
		if progress >= 1 or (effect.lane and not effect.lane.frame) then
			Release(effect)
			remove(live, i)
		elseif progress >= 0 then -- (below 0: staggered, not started yet)
			local kind = KINDS[effect.kind]
			local eased = EaseOut(progress)
			kind.place(effect, effect.texture, progress, eased, now, far)
			if kind.fade then
				effect.texture:SetAlpha(1 - eased)
			end
		end
	end
end

-- The renderer's effects layer: above the marks.
function Effects:Init(parent)
	layer = parent
end
