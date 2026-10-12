-- 4everActionTimeline — transient effects (docs/VISUAL.md, Hand-lane effects).
-- The reposition pop (cast_standard_pipglow, ADD, tinted), the correction
-- streak (bright at the new instant, transparent at the old one, so it
-- points the way the prediction moved) and the across-lane shake. Effects
-- are anchored to timeline instants, so they scroll with the marks, and fade
-- within ~0.3 s; none is ever a mark. The shake is an offset the renderer
-- adds across the lane, never along the time axis and never through
-- ScriptAnimationUtil.ShakeFrame (the anchor rule), and it honors the
-- ShakeStrengthUI CVar (0 disables it).

local Addon = FourEverActionTimeline
local Util, Layout = Addon.Util, Addon.Layout

local GetTime, GetCVar = GetTime, GetCVar
local max, min, sin, pi, remove = math.max, math.min, math.sin, math.pi, table.remove

local WHITE = Util.WHITE
local POP_ATLAS = "cast_standard_pipglow" -- shared with 4everSwingTimer
local POP_TIME = 0.3
local RING_TIME = 0.8
local RING_COLOR = { 1.0, 0.93, 0.75 }
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
local freePops, freeStreaks = {}, {}

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

local function NewStreak()
	local texture = layer:CreateTexture(nil, "ARTWORK")
	texture:SetTexture(WHITE)
	texture:SetBlendMode("ADD")
	return texture
end

-- A flash at instant t on the lane, tinted color, growing as it fades.
-- Starts a glow effect: a pooled pop texture, tinted, shown and tracked.
local function Flash(effect, color, oriented)
	local texture = remove(freePops) or NewPop()
	if oriented then
		Layout:OrientTexCoord(texture) -- the glow is wider than tall: turn it with the axis
	else
		texture:SetTexCoord(0, 1, 0, 1)
	end
	texture:SetVertexColor(color[1], color[2], color[3], 1)
	texture:Show()
	effect.texture, effect.start = texture, GetTime()
	live[#live + 1] = effect
end

function Effects:Pop(lane, t, color)
	if layer and t then
		Flash({ kind = "pop", lane = lane, t = t, duration = POP_TIME }, color, true)
	end
end

-- Single lane: a cooldown came back - a ring on its ready-row slot, or on the
-- now line for a long cooldown (SingleLane.RingPosition).
function Effects:Ring(lane)
	if layer and Layout.single then
		Flash({ kind = "ring", lane = lane, duration = RING_TIME }, RING_COLOR)
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
	texture:Show()
	live[#live + 1] = { kind = "streak", lane = lane, from = from, to = to, texture = texture, start = GetTime(), duration = STREAK_TIME }
end

-- A corrected prediction: the streak from the old instant to the new one,
-- and the pop at the new one unless the pop budget is spent (pop == false).
function Effects:Correct(lane, from, to, color, pop)
	if pop ~= false then
		self:Pop(lane, to, color)
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
	local pool = effect.kind == "streak" and freeStreaks or freePops
	pool[#pool + 1] = texture
end

-- Called by the renderer every frame; costs nothing while no effect is live.
function Effects:Place(now)
	local far = Layout:FarEdge(now)
	for i = #live, 1, -1 do
		local effect = live[i]
		local progress = (now - effect.start) / effect.duration
		local laneFrame = effect.lane.frame
		if progress >= 1 or not laneFrame then
			Release(effect)
			remove(live, i)
		else
			local texture = effect.texture
			if effect.kind == "ring" then
				local along, ringAcross = SingleLane.RingPosition(effect.lane)
				local size = Layout.iconSize * (0.9 + 1.2 * progress)
				texture:SetSize(size, size)
				texture:SetPoint("CENTER", laneFrame, Layout.orient.start, Layout:Offsets(along, ringAcross))
			else
				-- Single lane: on the hand's side of the track, where its marks are.
				local across = Layout.single and SingleLane.Across(effect.lane) or 0
				if effect.kind == "pop" then
					local size = Layout.iconSize * (1 + POP_GROWTH * progress)
					texture:SetSize(Layout:Extents(size * 1.6, size))
					texture:SetPoint("CENTER", laneFrame, Layout.orient.start, Layout:Offsets(Layout:TimeToOffset(min(effect.t, far), now), across))
				else
					local a1 = Layout:TimeToOffset(min(min(effect.from, effect.to), far), now)
					local a2 = Layout:TimeToOffset(min(max(effect.from, effect.to), far), now)
					local start = Layout.orient.start
					texture:SetPoint(start, laneFrame, start, Layout:Offsets(a1, across))
					texture:SetSize(Layout:Extents(max(a2 - a1, 1), STREAK_HEIGHT))
				end
			end
			texture:SetAlpha(1 - progress)
		end
	end
end

-- The renderer's effects layer: above the marks.
function Effects:Init(parent)
	layer = parent
end
