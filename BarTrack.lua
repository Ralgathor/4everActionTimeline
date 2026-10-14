-- 4everActionTimeline — the bar itself (docs/VISUAL.md, Layouts, Bar
-- track; ADR-0006): SingleLane places the marks, this file draws the bar
-- around them - a dark body, a light border over a dark outline, cut
-- where the now line crosses it (and at 1, 3 and 5 s with the seconds
-- scale), the scale's ticks and seconds. Still art, laid out on every
-- layout pass (nothing in it moves between them).

local Addon = FourEverActionTimeline
local Util, Layout, Skin = Addon.Util, Addon.Layout, Addon.Skin

local BarTrack = {}
Addon.BarTrack = BarTrack

local WHITE = { 1, 1, 1, 1 } -- art as drawn
local BODY_COLOR = { 0.05, 0.06, 0.07, 0.88 }
local OUTLINE_COLOR = { 0, 0, 0, 0.7 }
local BORDER_COLOR = { 0.9, 0.91, 0.93, 0.38 }
-- At bar height 26 (they scale with it).
local NOW_GAP, SCALE_GAP = 8, 4 -- the border's cuts
local TICK_OFFSET, TICK_LENGTH, TICK_ALPHA = 3, 5, 0.6
local NUMBER_OFFSET = 13 -- the seconds' centre under the bar's edge
local SCALE_MARKS = { -5, -3, -1, 1, 3, 5 }

local owner
local parts = {} -- created on first use

function BarTrack.Init(frame)
	owner = frame
end

-- Unsnapped, as the thin still lines are (VISUAL.md, Pixel grid).
local function Texture(layer, subLevel)
	local texture = Util.MovingTexture(owner, layer, subLevel)
	texture:SetTexture(Util.WHITE)
	return texture
end

local function Part(key, layer, subLevel)
	local texture = parts[key]
	if not texture then
		texture = Texture(layer, subLevel)
		parts[key] = texture
	end
	return texture
end

local function Color(texture, color, alpha)
	texture:SetVertexColor(color[1], color[2], color[3], 1)
	texture:SetAlpha(alpha or color[4])
end


-- The seconds scale's marks inside the window, as offsets along the axis.
local function ScaleOffsets(out)
	for _, seconds in ipairs(SCALE_MARKS) do
		if seconds >= -Layout.past and seconds <= Layout.future then
			out[#out + 1] = { along = Layout:TimeToOffset(seconds, 0), seconds = seconds }
		end
	end
	return out
end

-- The border's segments and the scale's ticks and seconds, taken afresh on
-- each layout pass (Util.NewPool: what a pass does not take is hidden).
local function NewLine()
	return Texture("ARTWORK")
end

local function NewNumber()
	return owner:CreateFontString(nil, "ARTWORK", "SystemFont_Shadow_Small")
end

local function HideRegion(region)
	region:Hide()
end

local segments, ticks, numbers = Util.NewPool(NewLine, HideRegion), Util.NewPool(NewLine, HideRegion), Util.NewPool(NewNumber, HideRegion)
local pools = { segments, ticks, numbers }

-- A border segment.
local function Segment(trackFrame, from, length, thickness, across)
	local segment = segments:Take()
	Color(segment, BORDER_COLOR)
	Layout:PlaceAlong(segment, trackFrame, from, length, thickness, across)
	segment:Show()
end

-- One edge's border, from the bar's start to its end, skipping each cut
-- (`cuts` ends with the bar's end, a cut of no width).
local function Edge(trackFrame, cuts, line, across)
	local from = 0
	for _, cut in ipairs(cuts) do
		local to = cut.along - cut.gap / 2
		if to > from then
			Segment(trackFrame, from, to - from, line, across)
		end
		from = cut.along + cut.gap / 2
	end
end

-- Lays the bar out around the lane frame the bar's lanes share; hidden
-- without one (only sink lanes, or none).
function BarTrack:Layout(trackFrame)
	for _, pool in ipairs(pools) do
		pool:BeginReuse()
	end
	if owner and trackFrame then
		self:LayoutBar(trackFrame)
	else
		for _, texture in pairs(parts) do
			texture:Hide()
		end
	end
	for _, pool in ipairs(pools) do
		pool:Trim()
	end
end

function BarTrack:LayoutBar(trackFrame)
	local k = Addon.SingleLane.Scale()
	local extent, length = Layout.trackExtent, Layout.width
	local line = Util.PixelSize(owner, 1)
	local cross = Layout.orient.crossSign
	local scale = Addon:GetSetting("barScale")
	local marks = scale and ScaleOffsets({}) or {}
	-- Native: the cast bar's background as the body (the art the casts
	-- filling the bar and the spark, the now line, share) under Blizzard's
	-- swing timer border, stretched over the bar whole as 4everSwingTimer
	-- stretches it over its bars: drawn for a bar of any size, where the cast
	-- bar's frame is drawn for one. The border art cannot be cut, so the now
	-- line crosses it. Flat: a dark body over a dark outline, a light border
	-- cut where the now line and the scale's marks cross it.
	local native = Skin.NativeBar()
	local body = Part("body", "BACKGROUND", 0)
	local outline = Part("outline", "BACKGROUND", -1)
	local border = Part("border", "ARTWORK", 1)
	if native then
		Skin.SetArt(body, Skin.ATLAS.castBackground)
		Color(body, WHITE)
		Layout:PlaceAlong(body, trackFrame, 0, length, extent)
		Skin.SetArt(border, Skin.ATLAS.swingFrame)
		Color(border, WHITE)
		Layout:PlaceAlong(border, trackFrame, 0, length, extent)
		border:Show()
		outline:Hide()
	else
		border:Hide()
		Skin.SetArt(body)
		Color(body, BODY_COLOR)
		Color(outline, OUTLINE_COLOR)
		Layout:PlaceAlong(outline, trackFrame, -line, length + 2 * line, extent + 2 * line)
		outline:Show()
		local cuts = { { along = Layout.nowX, gap = NOW_GAP * k } }
		for _, mark in ipairs(marks) do
			cuts[#cuts + 1] = { along = mark.along, gap = SCALE_GAP * k }
		end
		table.sort(cuts, function(a, b) return a.along < b.along end)
		cuts[#cuts + 1] = { along = length, gap = 0 }
		local edge = extent / 2 - line / 2
		Edge(trackFrame, cuts, line, -cross * edge)
		Edge(trackFrame, cuts, line, cross * edge)
		Segment(trackFrame, 0, line, extent)
		Segment(trackFrame, length - line, line, extent)
		Layout:PlaceAlong(body, trackFrame, 0, length, extent)
	end
	body:Show()
	-- The seconds scale: a tick under the bar at each mark, the seconds under
	-- the ticks ahead of the now line.
	local under = extent / 2
	for _, mark in ipairs(marks) do
		local tick = ticks:Take()
		Color(tick, BORDER_COLOR, TICK_ALPHA)
		Layout:PlaceAlong(tick, trackFrame, mark.along - line / 2, line, TICK_LENGTH * k, cross * (under + (TICK_OFFSET + TICK_LENGTH / 2) * k))
		tick:Show()
		if mark.seconds > 0 then
			local number = numbers:Take()
			number:SetText(mark.seconds)
			number:SetTextColor(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], 0.8)
			number:ClearAllPoints()
			number:SetPoint("CENTER", trackFrame, Layout.orient.start, Layout:Offsets(mark.along, cross * (under + NUMBER_OFFSET * k)))
			number:Show()
		end
	end
end
