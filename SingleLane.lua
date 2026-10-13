-- 4everActionTimeline — where each mark goes on the bar (docs/VISUAL.md,
-- Layouts; docs/SPEC.md, Layouts; ADR-0005's one-track rules, on the Bar
-- track's geometry, ADR-0006). Every lane kind except the sink lanes shares
-- one track, the bar, around the now line. The lanes and their Collect
-- functions are unchanged: this module only decides where each mark
-- descriptor goes. Adapt rewrites a descriptor in place - its glyph, its
-- offset across the bar, its size, whether it fades with age - and the
-- renderer draws the result; the card stack (Stack) sorts out icons that
-- would overlap. BarTrack.lua draws the bar itself.
--
-- Every size here is the value at the default bar height (26) and scales
-- with the bar height setting.

local Addon = FourEverActionTimeline
local Util, Layout = Addon.Util, Addon.Layout

local SingleLane = {}
Addon.SingleLane = SingleLane

local BASE_HEIGHT = 26
-- Sizes.
local DIAMOND, CHAIN_DIAMOND = 5, 4 -- a swing diamond's half diagonal
local DELAY_LINE = 2
-- An engine-drawn lane's thin row, and its icon.
local SINK_ROW, SINK_ICON = 18, 16
-- A far mark is dimmer and brightens on its flash: the next landing from 75 %,
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
-- Auto Shot as a cast (ADR-0006): teal, clear of the channel's green and the
-- GCD's blue; the shot after the next one dim.
local AUTO_ELAPSED = { 0.47, 0.78, 0.82, 0.95 }
local AUTO_REMAINING = { 0.55, 0.70, 0.72, 0.6 }
local AUTO_CHAIN = { 0.47, 0.78, 0.82, 0.2 }

-- The bar (ADR-0006; VISUAL.md, Layouts): a framed bar the setting's height.
-- Icons fill it inside its border (plain, in both skins, as Blizzard's cast
-- bar shows its icon - Skin.StyleIcon), casts fill it, and the ready row
-- sits under it in a strip ROW_ROOM tall, as Blizzard's cast bar shows
-- the spell's name in the box under its bar. Inside its border: Flat's is
-- 1 px; Native's, Blizzard's swing timer border, keeps what 4everSwingTimer
-- keeps clear inside it across - 4 px.
local FLAT_INSET, NATIVE_INSET = 1, 4
-- The ready row under the bar: ROW_GAP from the now line, 12 px slots 4 px
-- apart, padded inside their strip (2 px above and below a 12 px icon, and
-- at least ROW_PAD from the box's end).
local ROW_GAP = 12
local ROW_ICON, ROW_SPACE, ROW_ROOM, ROW_PAD = 12, 4, 16, 5
local BAR_NOW_REACH, BAR_PIP_ROOM = 6, 5 -- the now line past the bar, and its diamonds
local BAR_SCALE_ROOM = 16 -- under the bar: the seconds scale's ticks and numbers
local BAR_STRIP = 4 -- the GCD strip along the bar's far edge
-- The GCD strip is a mark-strength line, not a tint.
local STRIP_REMAINING = { 0.67, 0.78, 1.0, 0.75 }
local GCD_ELAPSED = { 0.67, 0.78, 1.0, 0.3 } -- the strip's and the tint's
-- The GCD over the bar's grey body, drawn with the Cooldown Manager bar
-- art (Native) tinted pale blue: a faint band would vanish there.
local TINT_REMAINING = { 0.67, 0.78, 1.0, 0.6 }

local function Scale()
	return Layout.laneHeight / BASE_HEIGHT
end

-- Every size here is a value at bar height 26 times this.
SingleLane.Scale = Scale

-- How far inside the bar, across it, its contents stay (at bar height 26).
local function BarInset()
	return Addon.Skin.NativeBar() and NATIVE_INSET or FLAT_INSET
end

-- What fills the bar inside its border: an icon, a cast, the GCD tint.
-- Layout keeps it as Layout.iconSize, every mark's and bar's default size.
function SingleLane.BarInner()
	return (BASE_HEIGHT - 2 * BarInset()) * Scale()
end

-- The pad across the frame (the now line's reach past the bar and its
-- diamonds), and the now line's reach.
function SingleLane.BarPad()
	return (BAR_NOW_REACH + BAR_PIP_ROOM) * Scale()
end

function SingleLane.NowReach()
	return BAR_NOW_REACH * Scale()
end

-- The strip under the bar holding the ready row, when any spell has a slot;
-- and all that hangs under the bar (the strip, the seconds scale).
function SingleLane.RowRoom()
	return Layout.slotCount > 0 and ROW_ROOM * Scale() or 0
end

function SingleLane.UnderBar()
	return SingleLane.RowRoom() + (Addon:GetSetting("barScale") and BAR_SCALE_ROOM * Scale() or 0)
end

-- A bar's art (Native: Blizzard's cast bar fills, one family with the bar's
-- frame; Renderer BarArt). The cast and channel fills carry their own
-- color, so they go in untinted; the grey uninterruptible fill takes Auto
-- Shot's teal. The fill fills the bar's height, its art laid across the
-- whole cast and revealed up to now (Renderer PlaceBar), as Blizzard's cast
-- bar fills.
local ART_ELAPSED, ART_REMAINING = { 1, 1, 1, 0.95 }, { 1, 1, 1, 0.4 }
local function CastArt(desc, key, elapsed, remaining)
	desc.art = key
	local native = Addon.Skin.Native(key)
	-- A cast fill is revealed up to now, as Blizzard's cast bar reveals it.
	desc.reveal = native or nil
	if native and key ~= "castNeutral" then
		elapsed, remaining = ART_ELAPSED, ART_REMAINING
	end
	desc.color, desc.unelapsedColor = elapsed, remaining
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
-- and returns how many slots there are. Run on every layout pass.
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

-- An engine-drawn lane's thin row and its icon.
function SingleLane.SinkRow()
	return SINK_ROW * Scale()
end

function SingleLane.SinkIcon()
	return SINK_ICON * Scale()
end

-- How far the ready row reaches from the now line: its near gap, its slots
-- and the padding to the box's end.
function SingleLane.RowSpan(count)
	if count == 0 then
		return 0
	end
	return (ROW_GAP + count * ROW_ICON + (count - 1) * ROW_SPACE + ROW_PAD) * Scale()
end

-- A slot's centre: the offset along the axis, and across from the bar's
-- middle line (in the strip under the bar).
function SingleLane.SlotOffsets(slot)
	local k = Scale()
	local pitch = (ROW_ICON + ROW_SPACE) * k
	local along
	if Layout.readyRowSide == "future" then
		along = Layout.nowX + (ROW_GAP + ROW_ICON / 2) * k + (slot - 1) * pitch
	else
		along = Layout.nowX - (ROW_GAP + ROW_ICON / 2) * k - (Layout.slotCount - slot) * pitch
	end
	return along, Layout.orient.crossSign * (Layout.trackExtent / 2 + ROW_ROOM * k / 2)
end

-- Where a returning cooldown's ring flashes: on its slot, or on the now
-- line for a long cooldown.
function SingleLane.RingPosition(lane)
	if lane.slot then
		return SingleLane.SlotOffsets(lane.slot)
	end
	return Layout.nowX, 0
end

-- Adds what a lane's own descriptors lack: a queued ability (or the landing
-- it rode) keeps its swing diamond on the bar's edge, the icon riding the
-- bar; a cooling spell has no ready mark, so its slot shows an empty outline.
function SingleLane.Prepare(lane, out)
	if lane.group == "hand" then
		for i = #out, 1, -1 do
			local desc = out[i]
			if desc.queued or (desc.onSwing and not desc.predicted) then
				local diamond = {}
				for key, value in pairs(desc) do
					diamond[key] = value
				end
				diamond.queued, diamond.onSwing = nil, nil
				out[#out + 1] = diamond
				desc.onBar = true
			end
		end
		return
	end
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
-- The card stack
-- ---------------------------------------------------------------------------

-- The card stack (VISUAL.md, Layouts, Bar track). The list holds every icon
-- ahead of the now line (x, t, desc, fixed - a fact: the cast's end, a
-- queued ability, the next Auto Shot - and far, pinned at the far edge),
-- sorted by x then time. It sets on each descriptor, for the renderer:
-- `peek` (px along the axis), `stacked` (hidden), `front`, `more` (how many
-- the front hides), `linkMark`, `noChevron`.
local STACK_PEEK = 5 -- px a stacked icon peeks out (and a parked one tucks)
local LINK_MATCH = 0.05 -- seconds: a linked set returning together

local function ClearStack(desc)
	desc.peek, desc.stacked, desc.front, desc.more, desc.linkMark, desc.noChevron = nil, nil, nil, nil, nil, nil
end

function SingleLane.Stack(list, count)
	local k = Scale()
	local width, peek = Layout.iconSize, STACK_PEEK * k
	for i = 1, count do
		ClearStack(list[i].desc)
	end
	-- A linked set returning together: one icon, with the link mark.
	for i = 1, count do
		local a = list[i]
		if a.desc.linkKey and not a.desc.stacked then
			for j = i + 1, count do
				local b = list[j]
				if b.desc.linkKey == a.desc.linkKey and not b.desc.stacked and math.abs(b.t - a.t) < LINK_MATCH then
					b.desc.stacked, a.desc.linkMark = true, true
				end
			end
		end
	end
	-- Parked past the window: each further one tucked left as tight as a
	-- stack's peek, one chevron.
	local parked = 0
	for i = 1, count do
		local item = list[i]
		if item.far and not item.desc.stacked then
			item.desc.peek = parked > 0 and -peek * parked or nil
			item.desc.noChevron = parked > 0 or nil
			parked = parked + 1
		end
	end
	-- Groups of icons closer than an icon's width: the front is the first
	-- fact, else the soonest, at its own place; the others keep theirs when
	-- that already shows them, else peek out further each; three show.
	local i = 1
	while i <= count do
		local head = list[i]
		if head.far or head.desc.stacked then
			i = i + 1
		else
			local j = i + 1
			while j <= count and (list[j].far or list[j].desc.stacked or list[j].x - head.x < width) do
				j = j + 1
			end
			local front
			for m = i, j - 1 do
				local item = list[m]
				if item.fixed and not item.far and not item.desc.stacked then
					front = item
					break
				end
			end
			front = front or head
			front.desc.front = true
			local shown, extra = 0, 0
			for m = i, j - 1 do
				local item = list[m]
				if item ~= front and not item.far and not item.desc.stacked then
					shown = shown + 1
					if shown > 2 then
						item.desc.stacked, extra = true, extra + 1
					elseif math.abs(item.x - front.x) < peek * shown then
						item.desc.peek = front.x + peek * shown - item.x
					end
				end
			end
			front.desc.more = extra > 0 and extra or nil
			i = j
		end
	end
end

-- A linked set's ready slots wear the link mark. `ready` is every ready
-- slot's descriptor.
function SingleLane.StackSlots(ready, readyCount)
	for i = 1, readyCount do
		ClearStack(ready[i])
	end
	for i = 1, readyCount do
		local a = ready[i]
		if a.linkKey then
			for j = 1, readyCount do
				if j ~= i and ready[j].linkKey == a.linkKey then
					a.linkMark = true
					break
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Adapt
-- ---------------------------------------------------------------------------

-- A mark that happened (not a prediction, not riding the now line): it fades.
local function Happened(desc)
	return not desc.predicted and not desc.atNow
end

-- A hand lane's diamonds sit on the bar's edges: the main hand and ranged on
-- the lane-start edge (top, or left when vertical), the off hand on the other.
local function Side(lane)
	local hand = lane.hand
	if not hand then
		return 0
	end
	local side = hand == "offhand" and -1 or 1
	return -Layout.orient.crossSign * side * Layout.trackExtent / 2
end

-- Where a lane's marks and effects sit across the bar: a ranged hand
-- drawing its shots as casts has them inside it (its delay span and clip
-- tick keep the ranged side).
function SingleLane.Across(lane)
	return lane.castShots and 0 or Side(lane)
end

-- A ranged shot drawn as a cast: its windup bar and the Auto Shot icon in
-- the bar, like the cast lane's bar and icon; a landed shot fades, the next
-- one is a fact for the card stack.
local function AdaptShot(desc)
	desc.across = 0
	if desc.shape == "bar" then
		if desc.chain then
			CastArt(desc, "castNeutral", AUTO_CHAIN, AUTO_CHAIN)
		else
			CastArt(desc, "castNeutral", AUTO_ELAPSED, AUTO_REMAINING)
		end
		desc.fade = true
		return true
	end
	desc.icon = Addon.Hands.AutoShotIcon()
	desc.fade = Happened(desc) or nil
	if desc.chain then
		desc.alpha = CHAIN_ALPHA
	elseif desc.predicted then
		desc.occupant, desc.highlight = true, true
	end
	return true
end

local function AdaptHand(lane, desc)
	if desc.autoShot then
		return AdaptShot(desc)
	end
	local k = Scale()
	desc.across = Side(lane)
	local shape = desc.shape
	if shape == "tick" then -- the clip mark
		desc.fade = true
		return true
	elseif shape == "bar" then -- the ranged delay span: a thin line on the bar's far edge, clear of the casts inside it
		desc.thickness, desc.fade, desc.art = DELAY_LINE * k, true, false
		desc.across = Layout.orient.crossSign * Layout.trackExtent / 2
		return true
	end
	local happened = Happened(desc)
	if desc.queued or (happened and desc.onSwing) then
		-- The queued ability, and the landing it rode, ride the bar; Prepare
		-- kept the diamond on its edge.
		desc.fade, desc.across = happened or nil, 0
		desc.highlight = desc.predicted or nil
		return true
	end
	local gray = desc.desaturated or (desc.atNow and desc.dim and not desc.paused)
	desc.shape = "diamond"
	desc.hollow = lane.hand == "ranged"
	desc.color = (gray and HAND_GRAY or HAND_COLORS)[lane.hand] or HAND_COLORS.mainhand
	desc.radius = (desc.chain and CHAIN_DIAMOND or DIAMOND) * k
	desc.alpha = desc.dim and 0.5 or (desc.chain and CHAIN_ALPHA or 1)
	if desc.predicted and not desc.chain and not desc.atNow then
		desc.farAlpha, desc.highlight = DIAMOND_FAR_ALPHA, true
	end
	desc.fade = happened or nil
	desc.glyph = (desc.paused and not desc.chain) and "pause" or nil
	return true
end

-- The GCD: a tint over the bar's body inside its border (the Cooldown
-- Manager bar art, Native), or a strip along its far edge; behind every
-- mark, dimmer where it has elapsed, and fading with age.
local function AdaptGcd(desc)
	if desc.shape ~= "bar" then
		return true
	end
	desc.fade = true
	if Addon:GetSetting("barGcd") == "strip" then
		local k = Scale()
		desc.art = false -- the strip: a plain line
		desc.color, desc.unelapsedColor = GCD_ELAPSED, STRIP_REMAINING
		desc.thickness = BAR_STRIP * k
		desc.across = Layout.orient.crossSign * (BASE_HEIGHT / 2 - BarInset() - BAR_STRIP / 2) * k
	else
		desc.art = "bar" -- the Cooldown Manager bar, as Blizzard's GCD wears it
		desc.color, desc.unelapsedColor = GCD_ELAPSED, TINT_REMAINING
	end
	return true
end

local function AdaptCast(desc)
	if desc.shape == "bar" then
		if desc.channel then
			CastArt(desc, "castChannel", CHANNEL_ELAPSED, CHANNEL_REMAINING)
		else
			CastArt(desc, "castFill", CAST_ELAPSED, CAST_REMAINING)
		end
		desc.fade = true
	else
		desc.fade = Happened(desc) or nil
		-- The in-flight cast's icon is a fact: the front of its card stack.
		desc.occupant = desc.predicted or nil
	end
	return true
end

-- Spell lanes: the predicted return rides the bar and flashes as it nears
-- the now line (the card stack sorts out overlaps); the ready, unusable and
-- unknown-cooldown marks and a cooling spell's ghost fill the spell's slot of
-- the ready row, a long cooldown having none. What a cast leaves behind is
-- the cast lane's.
local function AdaptSpell(lane, desc)
	if desc.shape == "bar" or desc.shape == "tick" then
		return false
	end
	if desc.atNow or desc.slot then
		if not lane.slot then
			return false
		end
		desc.slot = lane.slot
		desc.along, desc.across = SingleLane.SlotOffsets(lane.slot)
		desc.size = ROW_ICON * Scale()
		return true
	end
	if not desc.predicted then
		return false
	end
	desc.farAlpha, desc.highlight = COOLDOWN_FAR_ALPHA, true
	return true
end

-- Rewrites a lane's descriptor for the bar in place; false drops it.
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
