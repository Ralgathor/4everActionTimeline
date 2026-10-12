-- 4everActionTimeline — lane registry and the time axis.
-- Lane order is fixed by group (hands, then the GCD, then the cast lane,
-- then spell lanes, then sink lanes - docs/SPEC.md), then by each lane's
-- `order` within its group. The Detailed layout stacks one lane per kind;
-- the Single lane layout (SingleLane.lua) puts every lane but the sink lanes
-- on one track. Every position is an offset along the time axis
-- from the axis start (the past end, Layout:TimeToOffset) and an offset
-- across the lane; Layout.orient turns the pair into a point for the
-- orientation (VISUAL.md, Orientation): horizontal (past left), horizontal
-- flipped (past right), vertical (past at the bottom), vertical flipped
-- (past at the top). Lanes stack along the cross axis - top to bottom, or
-- left to right when vertical - and a flip never changes the lane order.
--
-- A lane is a table {key, group, order, Collect(self, now, out)}, plus an
-- optional IsActive(self, now) for "Active" visibility (a live mark while
-- the frame is hidden). A declared lane (DeclareLane) also carries an
-- optional `setting` and Available(self), and Layout manages its presence. Collect appends mark descriptors to `out`:
--   shape      "icon" (default) | "tick" | "bar"
--   t          event time (icon, tick); bars use tStart / tEnd
--   icon       texture for icon marks
--   predicted  a forecast: never scrolls into the past (an overdue mark pins
--              at the now line) and clamps at the far edge with a chevron;
--              its drawn time is max(t, now) + (after or 0)
--   after      offset for cadence-chain marks (derived from now while overdue)
--   chain      a deeper cadence-chain mark: hidden past the far edge, not clamped
--   atNow      rides the now line (ready, unusable, unknown-cooldown, parked,
--              the in-flight cast's now-line icon); with `after`, a fixed
--              offset ahead of it (a paused hand's frozen marks)
--   shake      the start time of the lane's across-lane shake (Effects:Shake)
--   desaturated, dim, tint ("resource" | "unusable"), border ("red" | "amber")
--   paused     a paused hand's frozen mark (Native: Blizzard's pause overlay)
--   queued     the main-hand mark showing a queued ability (Native: the
--              queued overlay)
--   color      {r, g, b, a} for bars and ticks
--   onSwing    a landing that an on-next-swing ability rode (happened marks)
--   castStart  (store entries) a cast that began earlier: the Single lane
--              layout also draws its bar
--   channel    a cast bar (or the store entry it comes from) is a channel's
-- The Single lane layout (SingleLane.Adapt, run by the renderer after Collect)
-- rewrites a descriptor in place with the fields below, which only it writes
-- and only the renderer reads - a Collect never sets them, and a descriptor
-- lives for one rebuild:
--   shape      adds "diamond" (radius, hollow, color, alpha, glyph "pause")
--   size       an icon's size in pixels (default the lane's icon size)
--   across     the offset across the track, plus the shake
--   along      a fixed place along the axis (a ready-row slot), not an instant
--   alpha      the widget's base alpha (default 1, or the dim alpha)
--   fade       a happened mark: fades over the past window
--   grow       the ratio an icon or diamond grows to over its last 1.5 s
--   thickness, unelapsedColor, band    a bar's thickness, its own unelapsed
--              color, and `band` for the GCD band (no backing)
--   farAlpha   a growing mark's alpha while far; it brightens to 1 as it grows
--   slot       a ready-row slot's number; shape "outline" is a cooling
--              spell's empty slot
--   stepper, occupant    a cooldown icon the stepping pass may offset; the
--              in-flight cast's icon, which holds the track
-- Happened marks come from the store through Layout.CollectHappened: an entry
-- with a `duration` becomes a window bar, any other an icon (or tick) mark.

local Addon = FourEverActionTimeline

local Layout = {}
Addon.Layout = Layout

local floor, max, sort, remove, wipe = math.floor, math.max, table.sort, table.remove, wipe

local GROUP_ORDER = { hand = 1, gcd = 2, cast = 3, spell = 4, sink = 5 }
-- Happened marks stay drawn this long past the past edge, so they scroll
-- fully out of the clipped frame instead of vanishing at the edge.
Layout.HAPPENED_MARGIN = 1

local lanes = {}
local declared = {}

-- Per orientation: the axis start point (the past end) and end point, the
-- sign of a time offset along its screen axis, the tex coords that turn
-- left-to-right art to run start-to-end (Blizzard's
-- EncounterTimelineTrackOrientationSetup translators applied to the full
-- texture; corners UL, LL, UR, LR) and the rotation (radians) that turns
-- right-pointing art to face the axis end.
local ORIENTATIONS = {
	horizontal = { start = "LEFT", finish = "RIGHT", sign = 1, vertical = false, turn = 0, texCoord = { 0, 0, 0, 1, 1, 0, 1, 1 } },
	horizontalFlipped = { start = "RIGHT", finish = "LEFT", sign = -1, vertical = false, turn = math.pi, texCoord = { 1, 0, 1, 1, 0, 0, 0, 1 } },
	vertical = { start = "BOTTOM", finish = "TOP", sign = 1, vertical = true, turn = math.pi / 2, texCoord = { 1, 0, 0, 0, 1, 1, 0, 1 } },
	verticalFlipped = { start = "TOP", finish = "BOTTOM", sign = -1, vertical = true, turn = -math.pi / 2, texCoord = { 0, 0, 1, 0, 0, 1, 1, 1 } },
}
-- Derived: the StatusBar / gradient axis name, the lane-start edge across
-- the axis ("TOP", or "LEFT" when vertical), the frame corners where the
-- axis starts and ends on that edge, and the sign of the inward direction
-- from that edge.
for _, o in pairs(ORIENTATIONS) do
	o.axis = o.vertical and "VERTICAL" or "HORIZONTAL"
	o.crossStart = o.vertical and "LEFT" or "TOP"
	o.corner = o.vertical and o.start .. "LEFT" or "TOP" .. o.start
	o.cornerFinish = o.vertical and o.finish .. "LEFT" or "TOP" .. o.finish
	o.crossSign = o.vertical and 1 or -1
end
Layout.orient = ORIENTATIONS.horizontal

local function LaneOrder(a, b)
	local ga, gb = GROUP_ORDER[a.group], GROUP_ORDER[b.group]
	if ga ~= gb then
		return ga < gb
	end
	return (a.order or 0) < (b.order or 0)
end

function Layout:RegisterLane(lane)
	assert(GROUP_ORDER[lane.group], "unknown lane group " .. tostring(lane.group))
	lanes[#lanes + 1] = lane
	sort(lanes, LaneOrder)
	Addon.Renderer:MarkLayoutDirty()
end

function Layout:UnregisterLane(lane)
	for i = #lanes, 1, -1 do
		if lanes[i] == lane then
			remove(lanes, i)
		end
	end
	lane.frame = nil
	Addon.Renderer:MarkLayoutDirty()
end

function Layout:Lanes()
	return lanes
end

-- Re-sorts after lanes changed their `order` (the lane set's order).
function Layout:SortLanes()
	sort(lanes, LaneOrder)
	Addon.Renderer:MarkLayoutDirty()
end

-- A lane whose presence Layout manages: registered while its setting (if
-- it has one) is on and its Available() (if it has one) says so.
function Layout:DeclareLane(lane)
	declared[#declared + 1] = lane
end

-- Registers or drops each declared lane to match its setting and
-- availability; visibility re-evaluates only when a lane came or went.
function Layout:RefreshPresence()
	local changed = false
	for _, lane in ipairs(declared) do
		local present = (lane.setting == nil or Addon:GetSetting(lane.setting)) and (lane.Available == nil or lane:Available())
		if present and not lane.registered then
			lane.registered, changed = true, true
			self:RegisterLane(lane)
		elseif not present and lane.registered then
			lane.registered, changed = nil, true
			self:UnregisterLane(lane)
		end
	end
	if changed then
		Addon.Renderer:UpdateVisibility()
	end
	return changed
end

-- Geometry, recomputed on every layout pass.
function Layout:Compute()
	local past, future = Addon:GetWindow()
	local laneHeight = Addon:GetSetting("laneHeight")
	local iconSize = laneHeight - 2
	self.past, self.future = past, future
	self.single = Addon:GetSetting("layout") == "single"
	-- How many marks deep the cadence chain goes (nil: fills the window).
	self.chainDepth = self.single and 1 or math.huge
	-- Single lane draws a cast as a bar (Casts, CollectHappened).
	self.castBars = self.single
	-- Single lane's urgency cue: one highlight flash instead of growth.
	self.highlight = self.single and Addon:GetSetting("urgency") == "highlight"
	self.invPast = 1 / max(past, 0.1)
	self.orient = ORIENTATIONS[Addon:GetSetting("orientation")] or ORIENTATIONS.horizontal
	self.skin = Addon:GetSetting("skin")
	-- Widgets compare this to re-apply what the skin or orientation decides.
	self.style = self.skin .. ":" .. Addon:GetSetting("orientation")
	-- The length along the time axis (the "width" setting, whatever the
	-- orientation).
	self.width = Addon:GetSetting(Addon:LayoutKey("width"))
	self.laneHeight, self.spacing = laneHeight, Addon:GetSetting("laneSpacing")
	self.iconSize = iconSize
	self.chevronSize = max(floor(iconSize / 3 + 0.5), 6)
	-- Padding keeps an icon centred on either end of the axis inside the
	-- frame; the future end also leaves room for the edge-clamp chevron.
	self.padStart = iconSize / 2
	self.padEnd = iconSize / 2 + self.chevronSize + 2
	self.pxPerSec = (self.width - self.padStart - self.padEnd) / (past + future)
	self.nowX = self.padStart + past * self.pxPerSec
	self.frameWidth = self.width
	self.slotCount = 0
	if self.single then
		-- The ready row's slots; on the past side the frame widens to fit them.
		self.readyRowSide = Addon:GetSetting("readyRowSide")
		local SingleLane = Addon.SingleLane
		self.slotCount = SingleLane.AssignSlots(lanes)
		local extra = 0
		if self.readyRowSide == "past" then
			extra = max(SingleLane.RowSpan(self.slotCount) - self.nowX, 0)
		end
		self.padStart, self.nowX, self.frameWidth = self.padStart + extra, self.nowX + extra, self.width + extra
	end
	-- The extent across the lanes, and the frame's: Native art that reaches
	-- past the outer lanes (the icon overlay, the pip) gets a pad each side.
	self.crossPad = Addon.Skin.CrossPad(iconSize)
	self:ComputeRows()
	self.height = self.lanesExtent + 2 * self.crossPad
end

-- Each lane's offset across the axis from the frame's lane-start edge (top,
-- or left when vertical) and its extent, and the lanes' combined extent.
-- Detailed: one row per lane. Single lane: one track shared by every lane
-- but the sink lanes, which keep a row each below it.
function Layout:ComputeRows()
	local lanes, spacing, laneHeight = lanes, self.spacing, self.laneHeight
	local offsets, extents = wipe(self.laneOffsets or {}), wipe(self.laneExtents or {})
	self.laneOffsets, self.laneExtents = offsets, extents
	local used = 0
	if self.single then
		self.trackExtent = Addon.SingleLane.Extent()
		for i, lane in ipairs(lanes) do
			if lane.group ~= "sink" then
				offsets[i], extents[i] = self.crossPad, self.trackExtent
				used = self.trackExtent
			end
		end
		if self.slotCount > 0 then
			used = used + (used > 0 and spacing or 0) + Addon.SingleLane.SlotSize()
		end
		local sinkRow = Addon.SingleLane.SlotSize()
		for i, lane in ipairs(lanes) do
			if lane.group == "sink" then
				used = used + (used > 0 and spacing or 0)
				offsets[i], extents[i] = self.crossPad + used, sinkRow
				used = used + sinkRow
			end
		end
	else
		for i = 1, #lanes do
			offsets[i], extents[i] = self.crossPad + (i - 1) * (laneHeight + spacing), laneHeight
		end
		used = #lanes * laneHeight + max(#lanes - 1, 0) * spacing
	end
	self.lanesExtent = used
end

-- Offset along the time axis from the axis start (the past end).
function Layout:TimeToOffset(t, now)
	return self.nowX + (t - now) * self.pxPerSec
end

-- The point offsets for an offset along the axis and one across the lane.
function Layout:Offsets(along, across)
	local orient = self.orient
	if orient.vertical then
		return across, along * orient.sign
	end
	return along * orient.sign, across
end

-- The point offsets for a lane's offset across the axis (lanes stack top to
-- bottom, or left to right when vertical).
function Layout:CrossOffsets(offset)
	if self.orient.vertical then
		return offset, 0
	end
	return 0, -offset
end

-- A size given along and across the axis, as width and height.
function Layout:Extents(along, across)
	if self.orient.vertical then
		return across, along
	end
	return along, across
end

-- Anchors a region's start edge (its past end) `along` from the start of
-- `parent`, `across` off its middle line, and sizes it.
function Layout:PlaceAlong(region, parent, along, length, thickness, across)
	local start = self.orient.start
	region:ClearAllPoints()
	region:SetPoint(start, parent, start, self:Offsets(along, across or 0))
	region:SetSize(self:Extents(length, thickness))
end

-- Turns left-to-right art to run along the axis (start to end).
function Layout:OrientTexCoord(texture)
	local c = self.orient.texCoord
	texture:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
end

-- The visible window: anything ending before the cull edge has scrolled
-- out (the past window plus the scroll-out margin); the far edge is the end
-- of the future window.
function Layout:CullEdge(now)
	return now - self.past - self.HAPPENED_MARGIN
end

function Layout:FarEdge(now)
	return now + self.future
end

-- The offset of the index-th lane (Compute ran).
function Layout:LaneOffset(index)
	return self.laneOffsets[index]
end

-- The cadence chain after a next landing at t: equal intervals of speed,
-- desaturated, filling the future window (one interval of slack, so a mark
-- entering at the far edge never leaves a gap between rebuilds). Drawn from
-- the now line while the next landing is overdue (the renderer's max(t, now)).
function Layout.AppendChain(out, t, speed, icon, now)
	local horizon = now + Layout.future + speed
	local n, depth = 1, Layout.chainDepth
	while n <= depth and t + n * speed <= horizon do
		out[#out + 1] = { t = t, after = n * speed, icon = icon, predicted = true, desaturated = true, chain = true }
		n = n + 1
	end
end

-- The default happened-mark collector: every store entry of this lane still
-- inside the window. Lanes with nothing to predict use it as their Collect.
function Layout.CollectHappened(lane, now, out)
	local key, cull = lane.key, Layout:CullEdge(now)
	local entries, first, last = Addon.Store:Range()
	for i = first, last do
		local entry = entries[i]
		if entry.lane == key then
			local time, duration = entry.time, entry.duration
			if duration then
				if time + duration >= cull then
					out[#out + 1] = { shape = "bar", tStart = time, tEnd = time + duration, color = entry.color }
				end
			elseif time >= cull then
				out[#out + 1] = { shape = entry.shape, t = time, icon = entry.icon, border = entry.border, color = entry.color, shake = entry.shake, onSwing = entry.onSwing }
				if entry.castStart and Layout.castBars then
					out[#out + 1] = { shape = "bar", tStart = entry.castStart, tEnd = time, channel = entry.channel }
				end
			end
		end
	end
end
