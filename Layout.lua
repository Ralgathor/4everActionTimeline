-- 4everActionTimeline — lane registry and the time axis.
-- Lane order is fixed by group (hands, then the GCD, then the cast lane,
-- then spell lanes, then sink lanes - docs/SPEC.md), then by each lane's
-- `order` within its group. Every position is an offset along the time axis
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
-- Happened marks come from the store through Layout.CollectHappened: an entry
-- with a `duration` becomes a window bar, any other an icon (or tick) mark.

local Addon = FourEverActionTimeline

local Layout = {}
Addon.Layout = Layout

local floor, max, sort, remove = math.floor, math.max, table.sort, table.remove

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
	local past, future = Addon:GetSetting("pastWindow"), Addon:GetSetting("futureWindow")
	local laneHeight = Addon:GetSetting("laneHeight")
	local iconSize = laneHeight - 2
	self.past, self.future = past, future
	self.orient = ORIENTATIONS[Addon:GetSetting("orientation")] or ORIENTATIONS.horizontal
	self.skin = Addon:GetSetting("skin")
	-- Widgets compare this to re-apply what the skin or orientation decides.
	self.style = self.skin .. ":" .. Addon:GetSetting("orientation")
	-- The length along the time axis (the "width" setting, whatever the
	-- orientation).
	self.width = Addon:GetSetting("width")
	self.laneHeight, self.spacing = laneHeight, Addon:GetSetting("laneSpacing")
	self.iconSize = iconSize
	self.chevronSize = max(floor(iconSize / 3 + 0.5), 6)
	-- Padding keeps an icon centred on either end of the axis inside the
	-- frame; the future end also leaves room for the edge-clamp chevron.
	self.padStart = iconSize / 2
	self.padEnd = iconSize / 2 + self.chevronSize + 2
	self.pxPerSec = (self.width - self.padStart - self.padEnd) / (past + future)
	self.nowX = self.padStart + past * self.pxPerSec
	-- The extent across the lanes, and the frame's: Native art that reaches
	-- past the outer lanes (the icon overlay, the pip) gets a pad each side.
	self.crossPad = Addon.Skin.CrossPad(iconSize)
	self.lanesExtent = #lanes * laneHeight + max(#lanes - 1, 0) * self.spacing
	self.height = self.lanesExtent + 2 * self.crossPad
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

-- A lane's offset across the axis from the frame's lane-start edge (top,
-- or left when vertical).
function Layout:LaneOffset(index)
	return self.crossPad + (index - 1) * (self.laneHeight + self.spacing)
end

-- The cadence chain after a next landing at t: equal intervals of speed,
-- desaturated, filling the future window (one interval of slack, so a mark
-- entering at the far edge never leaves a gap between rebuilds). Drawn from
-- the now line while the next landing is overdue (the renderer's max(t, now)).
function Layout.AppendChain(out, t, speed, icon, now)
	local horizon = now + Layout.future + speed
	local n = 1
	while t + n * speed <= horizon do
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
				out[#out + 1] = { shape = entry.shape, t = time, icon = entry.icon, border = entry.border, color = entry.color, shake = entry.shake }
			end
		end
	end
end
