-- 4everActionTimeline — placement in Blizzard's Edit Mode (docs/SPEC.md,
-- Frame anchoring; probe 9). ForeverCDM's proven pattern on this client: the
-- timeline is not a registered Edit Mode system (no writes into Blizzard's
-- layout tables). It listens for EventRegistry EditMode.Enter / Exit; while
-- Edit Mode is open the timeline shows, a labelled handle over it takes the
-- mouse and drags it, a drop snaps to nearby Edit Mode frames when Edit
-- Mode's snap is on, and the position is stored UIParent-relative at the
-- player layer. Outside Edit Mode the frame stays click-through. Edit
-- Mode's own scale does not apply: scale is a Settings slider.

local Addon = FourEverActionTimeline

local SNAP_DISTANCE = 10
local HANDLE_MIN_HEIGHT = 30

local EditMode = {}
Addon.EditMode = EditMode

local timeline, handle

local function Restore()
	local position = Addon.playerLayer.position
	if position then
		timeline:ClearAllPoints()
		timeline:SetPoint("CENTER", UIParent, "BOTTOMLEFT", position.x, position.y)
	end
end

local function Plain(value)
	return type(value) == "number" and not Addon.Util.IsSecret(value)
end

-- A visible frame's edges in UIParent units, or nil when unreadable.
local function Rect(frame)
	local ok, visible = pcall(frame.IsVisible, frame)
	if not ok or Addon.Util.IsSecret(visible) or not visible then
		return nil
	end
	local okL, left, bottom, width, height = pcall(frame.GetRect, frame)
	if not (okL and Plain(left) and Plain(bottom) and Plain(width) and Plain(height)) then
		return nil
	end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale
end

-- The smallest shift (within SNAP_DISTANCE) lining one of ours up with one of
-- theirs: edges and centers.
local function Nearest(shift, ours, theirs)
	for _, a in ipairs(ours) do
		for _, b in ipairs(theirs) do
			local delta = b - a
			if math.abs(delta) <= SNAP_DISTANCE and (not shift or math.abs(delta) < math.abs(shift)) then
				shift = delta
			end
		end
	end
	return shift
end

-- With Edit Mode's snap on: the shift (UIParent units, either may be nil)
-- aligning the timeline to nearby Edit Mode frames.
local function Snap()
	local manager = EditModeManagerFrame
	if not (manager and manager.IsSnapEnabled and manager:IsSnapEnabled()) then
		return
	end
	local left, bottom, right, top = Rect(timeline)
	if not left then
		return
	end
	local dx, dy
	for _, other in ipairs(manager.registeredSystemFrames or {}) do
		local oLeft, oBottom, oRight, oTop = Rect(other)
		if oLeft then
			dx = Nearest(dx, { left, right, (left + right) / 2 }, { oLeft, oRight, (oLeft + oRight) / 2 })
			dy = Nearest(dy, { bottom, top, (bottom + top) / 2 }, { oBottom, oTop, (oBottom + oTop) / 2 })
		end
	end
	return dx, dy
end

-- On drop: snap, store the center at the player layer, re-anchor to
-- UIParent whatever StartMoving left.
local function Save()
	local x, y = timeline:GetCenter()
	if not x then
		return
	end
	local dx, dy = Snap()
	local scale = UIParent:GetEffectiveScale() / timeline:GetEffectiveScale()
	Addon.playerLayer.position = { x = x + (dx or 0) * scale, y = y + (dy or 0) * scale }
	Restore()
end

local function SetActive(active)
	Addon.editMode = active
	handle:SetShown(active)
	Addon.Renderer:MarkLayoutDirty()
	Addon.Renderer:UpdateVisibility()
end

local function BuildHandle()
	handle = CreateFrame("Frame", nil, UIParent)
	handle:SetPoint("TOPLEFT", timeline, "TOPLEFT")
	handle:SetPoint("TOPRIGHT", timeline, "TOPRIGHT")
	handle:SetFrameStrata("HIGH")
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	local band = handle:CreateTexture(nil, "BACKGROUND")
	band:SetAllPoints()
	band:SetColorTexture(0.82, 0.38, 0.12, 0.25)
	local label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("BOTTOM", handle, "TOP", 0, 2)
	label:SetText("4everActionTimeline - drag to move")
	handle:SetScript("OnDragStart", function()
		timeline:StartMoving()
	end)
	handle:SetScript("OnDragStop", function()
		timeline:StopMovingOrSizing()
		Save()
	end)
	-- Keep the handle over the whole timeline as its height changes.
	local function FitHeight()
		local height = timeline:GetHeight()
		handle:SetHeight(math.max(Plain(height) and height or 0, HANDLE_MIN_HEIGHT))
	end
	timeline:HookScript("OnSizeChanged", FitHeight)
	FitHeight()
	handle:Hide()
end

function EditMode:Init(frame)
	timeline = frame
	timeline:SetMovable(true)
	timeline:SetClampedToScreen(true)
	Restore()
	BuildHandle()
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			SetActive(true)
		end, EditMode)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			SetActive(false)
		end, EditMode)
	end
	local manager = EditModeManagerFrame
	if manager and manager.IsEditModeActive and manager:IsEditModeActive() then
		SetActive(true)
	end
end
