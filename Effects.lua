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
function Effects:Pop(lane, t, color)
	if not (layer and t) then
		return
	end
	local texture = remove(freePops) or NewPop()
	texture:SetVertexColor(color[1], color[2], color[3], 1)
	texture:Show()
	live[#live + 1] = { kind = "pop", lane = lane, t = t, texture = texture, start = GetTime(), duration = POP_TIME }
end

-- A fading streak from the old instant to the new one.
function Effects:Streak(lane, from, to, color)
	if not (layer and from and to) or from == to then
		return
	end
	local texture = remove(freeStreaks) or NewStreak()
	local r, g, b = color[1], color[2], color[3]
	if texture.SetGradient and CreateColor then
		-- Horizontal gradients run left to right; the bright end is the new
		-- instant (orientation-dependent once M7 adds the other orientations).
		local faint, bright = CreateColor(r, g, b, 0), CreateColor(r, g, b, 1)
		if to > from then
			texture:SetGradient("HORIZONTAL", faint, bright)
		else
			texture:SetGradient("HORIZONTAL", bright, faint)
		end
	else
		texture:SetVertexColor(r, g, b, 1)
	end
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
	local pool = effect.kind == "pop" and freePops or freeStreaks
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
			if effect.kind == "pop" then
				local size = Layout.iconSize * (1 + POP_GROWTH * progress)
				texture:SetSize(size * 1.6, size)
				texture:SetPoint("CENTER", laneFrame, "LEFT", Layout:TimeToX(min(effect.t, far), now), 0)
			else
				local x1 = Layout:TimeToX(min(min(effect.from, effect.to), far), now)
				local x2 = Layout:TimeToX(min(max(effect.from, effect.to), far), now)
				texture:SetSize(max(x2 - x1, 1), STREAK_HEIGHT)
				texture:SetPoint("LEFT", laneFrame, "LEFT", x1, 0)
			end
			texture:SetAlpha(1 - progress)
		end
	end
end

-- The renderer's effects layer: above the marks.
function Effects:Init(parent)
	layer = parent
end
