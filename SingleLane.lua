-- 4everActionTimeline — the Single lane layout (docs/VISUAL.md, Layouts;
-- docs/SPEC.md, Layouts; ADR-0005). Every lane kind except the sink lanes
-- shares one track around the now line, for reading at a glance. The lanes
-- and their Collect functions are unchanged: this module only decides where
-- each mark descriptor goes. Adapt rewrites a descriptor in place for the
-- layout - its glyph, its offset across the track, its size, whether it
-- fades with age - and the renderer draws the result.
--
-- Every size here is the value at the default lane height (26) and scales
-- with the lane height setting.

local Addon = FourEverActionTimeline
local Util, Layout = Addon.Util, Addon.Layout

local SingleLane = {}
Addon.SingleLane = SingleLane

local BASE_HEIGHT = 26
-- Across the track, from its middle line.
local HAND_OFFSET = 16 -- a hand's marks sit this far to their side of the track
local RANGED_STEP = 4 -- ranged sits this much further out while melee is live
local HALF_EXTENT = 28 -- half the track's height: the outermost mark fits
-- Sizes.
local DIAMOND, CHAIN_DIAMOND = 5, 4 -- a swing diamond's half diagonal
local QUEUED_ICON, CAST_ICON, COOLDOWN_ICON = 14, 16, 16
local CAST_BAR, DELAY_LINE = 6, 2
-- How far the next mark grows over its last 1.5 s: diamond 5 to 8, queued
-- icon 14 to 18, cooldown icon 16 to 24.
local DIAMOND_GROWTH, QUEUED_GROWTH, COOLDOWN_GROWTH = 1.6, 1.3, 1.5
-- A cooldown icon stepping off the track to clear its neighbour.
local ICON_STEP = 8
-- The ready row: fixed slots under the track, SLOT px with SLOT_GAP between,
-- the nearest one ROW_GAP from the now line.
local SLOT, SLOT_GAP, ROW_GAP, SINK_ICON = 18, 2, 12, 16
-- A far mark is dimmer and brightens as it grows: the next landing from 75 %,
-- a returning cooldown from 60 % (the mock-up's hierarchy: what is about to
-- happen stands out).
local DIAMOND_FAR_ALPHA, COOLDOWN_FAR_ALPHA = 0.75, 0.6
-- The cadence chain and a parked hand: a darker grey, well behind the next landing.
local CHAIN_ALPHA, GRAY_DIM = 0.55, 0.8

-- Filled for melee, hollow for ranged, so shape tells them apart first.
local HAND_COLORS = {
	mainhand = { 0.91, 0.93, 0.96 },
	offhand = { 0.79, 0.69, 0.54 },
	ranged = { 0.62, 0.86, 0.66 },
}
local HAND_GRAY = {}
for hand, color in pairs(HAND_COLORS) do
	local l = Util.Gray(color[1], color[2], color[3]) * GRAY_DIM
	HAND_GRAY[hand] = { l, l, l }
end
-- The cast bar: warm gold, kept clear of the GCD's blue. Solid where
-- elapsed, lighter where still to run.
local CAST_ELAPSED = { 0.88, 0.67, 0.35, 0.95 }
local CAST_REMAINING = { 0.67, 0.63, 0.57, 0.6 } -- a muted sand: still to run
-- A channel is green, as on Blizzard's cast bar: a yellow green, clear of the
-- ranged diamond's pale green and the teal pop.
local CHANNEL_ELAPSED = { 0.55, 0.82, 0.30, 0.95 }
local CHANNEL_REMAINING = { 0.58, 0.66, 0.50, 0.6 }
-- The GCD band: a clear blue, full where the GCD still runs, half where elapsed.
local BAND_REMAINING = { 0.67, 0.78, 1.0, 0.2 }
local BAND_ELAPSED = { 0.67, 0.78, 1.0, 0.1 }

local function Scale()
	return Layout.laneHeight / BASE_HEIGHT
end

-- The track's height across the axis.
function SingleLane.Extent()
	return 2 * HALF_EXTENT * Scale()
end

-- ---------------------------------------------------------------------------
-- The ready row
-- ---------------------------------------------------------------------------

-- A spell lane has a slot unless its cooldown is long (a test lane brings its
-- own IsLong).
local function Slotted(lane)
	return lane.group == "spell" and not (lane.IsLong or Addon.Spells.IsLong)(lane)
end

-- Numbers the spell lanes that get a slot, in lane order (the lane set's),
-- and returns how many. Run on every layout pass.
function SingleLane.AssignSlots(lanes)
	local count = 0
	for i = 1, #lanes do
		local lane = lanes[i]
		if Slotted(lane) then
			count = count + 1
			lane.slot = count
		else
			lane.slot = nil
		end
	end
	return count
end

-- True when the slots would be numbered differently now (a cooldown became
-- known to be long): the renderer re-lays out. A lane coming or going lays
-- out anyway.
function SingleLane.SlotsChanged(lanes)
	local count = 0
	for i = 1, #lanes do
		local lane = lanes[i]
		local want
		if Slotted(lane) then
			count = count + 1
			want = count
		end
		if lane.slot ~= want then
			return true
		end
	end
	return false
end

function SingleLane.SlotSize()
	return SLOT * Scale()
end

-- The icon of an engine-drawn lane's thin row (the row is a slot tall).
function SingleLane.SinkIcon()
	return SINK_ICON * Scale()
end

-- How far the ready row reaches from the now line (its near gap and slots).
function SingleLane.RowSpan(count)
	if count == 0 then
		return 0
	end
	return (ROW_GAP + count * SLOT + (count - 1) * SLOT_GAP) * Scale()
end

-- A slot's centre: the offset along the axis, and across from the track's
-- middle line (the row sits on the side away from the lane-start edge).
function SingleLane.SlotOffsets(slot)
	local k = Scale()
	local count = Layout.slotCount
	local pitch = (SLOT + SLOT_GAP) * k
	local along
	if Layout.readyRowSide == "future" then
		along = Layout.nowX + ROW_GAP * k + SLOT * k / 2 + (slot - 1) * pitch
	else
		along = Layout.nowX - ROW_GAP * k - SLOT * k / 2 - (count - slot) * pitch
	end
	local across = Layout.orient.crossSign * (Layout.trackExtent / 2 + Layout.spacing + SLOT * k / 2)
	return along, across
end

-- Where a returning cooldown's ring flashes: on its slot, or on the now
-- line for a long cooldown.
function SingleLane.RingPosition(lane)
	if lane.slot then
		return SingleLane.SlotOffsets(lane.slot)
	end
	return Layout.nowX, 0
end

-- Adds what a spell lane's own descriptors lack: a cooling spell has no
-- ready mark, so its slot shows an empty outline.
function SingleLane.Prepare(lane, out)
	if lane.group ~= "spell" or not lane.slot then
		return
	end
	for i = 1, #out do
		if out[i].atNow then
			return
		end
	end
	out[#out + 1] = { slot = lane.slot, shape = "outline" }
end

-- ---------------------------------------------------------------------------
-- Stepping
-- ---------------------------------------------------------------------------

-- Gives each icon of the sorted list (x, desc, fixed) the offset across the
-- track that clears its neighbours: on the track, then a step to the
-- lane-start side, then a step to the other. A fixed item (the in-flight
-- cast's icon) stays on the track. Sized for the icons' grown size, so a
-- step never changes as an icon grows; past three levels they overlap
-- slightly (the least-recent level).
function SingleLane.Step(list, count)
	local k = Scale()
	local gap = COOLDOWN_ICON * (Layout.highlight and 1 or COOLDOWN_GROWTH) * k + 1
	local last = { -math.huge, -math.huge, -math.huge }
	local offsets = { 0, -Layout.orient.crossSign * ICON_STEP * k, Layout.orient.crossSign * ICON_STEP * k }
	for i = 1, count do
		local item = list[i]
		local level = 1
		if not item.fixed then
			level = nil
			for l = 1, 3 do
				if item.x - last[l] >= gap then
					level = l
					break
				end
			end
			if not level then
				level = 1
				for l = 2, 3 do
					if last[l] < last[level] then
						level = l
					end
				end
			end
			item.desc.across = offsets[level]
		end
		last[level] = item.x
	end
end

-- A hand lane's marks sit to its side of the track: the main hand and ranged
-- on the lane-start side (top, or left when vertical), the off hand on the
-- other. Ranged steps out while the main hand is swinging.
function SingleLane.Across(lane)
	local hand = lane.hand
	if not hand then
		return 0
	end
	local distance = HAND_OFFSET
	if hand == "ranged" then
		local melee = Addon.Hands and Addon.Hands:State("mainhand")
		if melee and melee.active then
			distance = distance + RANGED_STEP
		end
	end
	local side = hand == "offhand" and -1 or 1
	return -Layout.orient.crossSign * side * distance * Scale()
end

-- How a mark says it is within the next GCD (Settings: Urgency cue): it
-- grows by `growth` over its last 1.5 s, or flashes once as it crosses into
-- them (Layout.highlight).
local function Urgent(desc, growth)
	if Layout.highlight then
		desc.highlight = true
	else
		desc.grow = growth
	end
end

local function AdaptHand(lane, desc)
	local k = Scale()
	desc.across = SingleLane.Across(lane)
	local shape = desc.shape
	if shape == "tick" then -- the clip mark
		desc.fade = true
		return true
	elseif shape == "bar" then -- the ranged delay span: a thin line on the hand's side
		desc.thickness, desc.fade = DELAY_LINE * k, true
		return true
	end
	local happened = not desc.predicted and not desc.atNow
	if desc.queued or (happened and desc.onSwing) then
		-- The queued ability replaces the diamond, and the landing it rode keeps it.
		desc.size, desc.fade = QUEUED_ICON * k, happened or nil
		if desc.predicted then
			Urgent(desc, QUEUED_GROWTH)
		end
		desc.queued, desc.paused = nil, nil -- no overlays on a small icon
		return true
	end
	local gray = desc.desaturated or (desc.atNow and desc.dim and not desc.paused)
	desc.shape = "diamond"
	desc.hollow = lane.hand == "ranged"
	desc.color = (gray and HAND_GRAY or HAND_COLORS)[lane.hand] or HAND_COLORS.mainhand
	desc.radius = (desc.chain and CHAIN_DIAMOND or DIAMOND) * k
	desc.alpha = desc.dim and 0.5 or (desc.chain and CHAIN_ALPHA or 1)
	if desc.predicted and not desc.chain and not desc.atNow then
		desc.farAlpha = DIAMOND_FAR_ALPHA
		Urgent(desc, DIAMOND_GROWTH)
	end
	desc.fade = happened or nil
	desc.glyph = (desc.paused and not desc.chain) and "pause" or nil
	return true
end

-- The GCD: a faint band across the track's full height, behind every mark;
-- dimmer where it has elapsed, and fading with age.
local function AdaptGcd(desc)
	if desc.shape == "bar" then
		desc.color, desc.unelapsedColor = BAND_ELAPSED, BAND_REMAINING
		desc.thickness, desc.band, desc.fade = SingleLane.Extent(), true, true
	end
	return true
end

local function AdaptCast(desc)
	local k = Scale()
	if desc.shape == "bar" then
		if desc.channel then
			desc.color, desc.unelapsedColor = CHANNEL_ELAPSED, CHANNEL_REMAINING
		else
			desc.color, desc.unelapsedColor = CAST_ELAPSED, CAST_REMAINING
		end
		desc.thickness, desc.fade = CAST_BAR * k, true
	else
		desc.size = CAST_ICON * k
		desc.fade = (not desc.predicted and not desc.atNow) or nil
		-- The in-flight cast's icon holds the track: cooldown icons step off it.
		desc.occupant = desc.predicted or nil
	end
	return true
end

-- Spell lanes: the predicted return rides the track and grows as it nears
-- the now line (the stepping pass offsets it); the ready, unusable and
-- unknown-cooldown marks and a cooling spell's ghost fill the spell's slot of
-- the ready row, a long cooldown having none. What a cast leaves behind is
-- the cast lane's.
local function AdaptSpell(lane, desc)
	local k = Scale()
	if desc.shape == "bar" or desc.shape == "tick" then
		return false
	end
	if desc.atNow or desc.slot then
		if not lane.slot then
			return false
		end
		desc.slot = lane.slot
		desc.along, desc.across = SingleLane.SlotOffsets(lane.slot)
		desc.size = SLOT * k
		return true
	end
	if not desc.predicted then
		return false
	end
	desc.size, desc.farAlpha, desc.stepper = COOLDOWN_ICON * k, COOLDOWN_FAR_ALPHA, true
	Urgent(desc, COOLDOWN_GROWTH)
	return true
end

-- Rewrites a lane's descriptor for the layout in place; false drops it.
function SingleLane.Adapt(lane, desc)
	local group = lane.group
	if group == "hand" then
		return AdaptHand(lane, desc)
	elseif group == "gcd" then
		return AdaptGcd(desc)
	elseif group == "cast" then
		return AdaptCast(desc)
	elseif group == "spell" then
		return AdaptSpell(lane, desc)
	end
	return true
end
