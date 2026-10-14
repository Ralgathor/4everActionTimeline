-- 4everActionTimeline — placement in Blizzard's Edit Mode (docs/SPEC.md,
-- Frame anchoring; probe 9). ForeverCDM's proven pattern on this client: the
-- timeline is not a registered Edit Mode system (no writes into Blizzard's
-- layout tables). It listens for EventRegistry EditMode.Enter / Exit; while
-- Edit Mode is open the timeline shows inside Blizzard's own selection art
-- (blue while idle, yellow once clicked, a label), drags and snaps to
-- nearby Edit Mode frames and the grid when Edit Mode's snap is on, drawing
-- Blizzard's red snap preview lines while it drags. (No arrow-key nudge:
-- capturing the keyboard needs SetPropagateKeyboardInput, protected on this
-- client.) Clicking it opens its settings panel (EditModeDialog.lua). The
-- position is stored UIParent-relative at the player layer, one per Edit
-- Mode layout, with the "default" one for a layout that has none. Outside
-- Edit Mode the frame stays click-through. Edit Mode's own scale does not
-- apply: scale is a setting in the panel.

local Addon = FourEverActionTimeline

local SNAP_DISTANCE = 10
local HANDLE_MIN_HEIGHT = 30
-- Blizzard's snap preview line (MagnetismPreviewLineTemplate): red, 1.5
-- screen pixels.
local PREVIEW_COLOR, PREVIEW_WIDTH = { 1, 0, 0 }, 1.5

-- Blizzard's selection frame (EditModeSystemTemplates.lua), applied with
-- NineSliceUtil to our own frame - never inherited, whose mouse handler
-- selects a system in Edit Mode's own manager.
local KITS = { highlight = "editmode-actionbar-highlight", selected = "editmode-actionbar-selected" }
local SELECTION = {
	TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
	BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
	LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
	RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
	Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

local EditMode = {}
Addon.EditMode = EditMode

local timeline, handle, preview
local selected = false

-- ---------------------------------------------------------------------------
-- The position: one per Edit Mode layout
-- ---------------------------------------------------------------------------

-- The active Edit Mode layout's key, or "default" without one.
local function LayoutKey()
	local manager = EditModeManagerFrame
	local info = manager and manager.GetActiveLayoutInfo and manager:GetActiveLayoutInfo()
	if not info then
		return "default"
	end
	local name = info.layoutName
	if name == nil or name == "" then
		name = manager.layoutInfo and manager.layoutInfo.activeLayout or "?"
	end
	return (info.layoutType or 0) .. ":" .. name
end

local function Positions()
	local player = Addon.playerLayer
	player.positions = player.positions or {}
	return player.positions
end

-- Positions are kept in UIParent units, so the frame's own scale never moves
-- them: an anchor offset is in the frame's scale, a stored position is not.
local function ScaleToParent()
	return timeline:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function Place(position)
	local scale = ScaleToParent()
	timeline:ClearAllPoints()
	timeline:SetPoint("CENTER", UIParent, "BOTTOMLEFT", position.x / scale, position.y / scale)
end

-- Below the screen's center, where the frame starts.
local function DefaultPosition()
	return { x = (UIParent:GetWidth() or 0) / 2, y = (UIParent:GetHeight() or 0) / 2 - 180 }
end

local function Restore()
	local positions = Positions()
	Place(positions[LayoutKey()] or positions.default or DefaultPosition())
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
-- theirs (edges and centers), and the line it lines up on.
local function Nearest(shift, at, ours, theirs)
	for _, a in ipairs(ours) do
		for _, b in ipairs(theirs) do
			local delta = b - a
			if math.abs(delta) <= SNAP_DISTANCE and (not shift or math.abs(delta) < math.abs(shift)) then
				shift, at = delta, b
			end
		end
	end
	return shift, at
end

-- The same, putting one of ours on a line of a grid `spacing` apart through
-- `center`.
local function NearestLine(shift, at, ours, center, spacing)
	local lines = {}
	for i, a in ipairs(ours) do
		lines[i] = center + math.floor((a - center) / spacing + 0.5) * spacing
	end
	return Nearest(shift, at, ours, lines)
end

-- With Edit Mode's snap on: the shift (UIParent units, either may be nil)
-- aligning the timeline to nearby Edit Mode frames and, while it shows, to
-- Edit Mode's grid (lines `gridSpacing` apart through its center, as
-- EditModeGridMixin:UpdateGrid draws them), then the x and y of the lines it
-- lines up on. Only reads Blizzard's frames.
local function Snap()
	local manager = EditModeManagerFrame
	if not (manager and manager.IsSnapEnabled and manager:IsSnapEnabled()) then
		return
	end
	local left, bottom, right, top = Rect(timeline)
	if not left then
		return
	end
	local dx, dy, atX, atY
	local xs, ys = { left, right, (left + right) / 2 }, { bottom, top, (bottom + top) / 2 }
	for _, other in ipairs(manager.registeredSystemFrames or {}) do
		local oLeft, oBottom, oRight, oTop = Rect(other)
		if oLeft then
			dx, atX = Nearest(dx, atX, xs, { oLeft, oRight, (oLeft + oRight) / 2 })
			dy, atY = Nearest(dy, atY, ys, { oBottom, oTop, (oBottom + oTop) / 2 })
		end
	end
	local grid = manager.Grid
	local spacing = grid and grid.gridSpacing
	local gLeft, gBottom, gRight, gTop
	if Plain(spacing) and spacing > 0 then
		gLeft, gBottom, gRight, gTop = Rect(grid)
	end
	if gLeft then
		spacing = spacing * grid:GetEffectiveScale() / UIParent:GetEffectiveScale()
		dx, atX = NearestLine(dx, atX, xs, (gLeft + gRight) / 2, spacing)
		dy, atY = NearestLine(dy, atY, ys, (gBottom + gTop) / 2, spacing)
	end
	return dx, dy, atX, atY
end

-- ---------------------------------------------------------------------------
-- The snap preview: Blizzard's red lines, drawn by us
-- ---------------------------------------------------------------------------

-- While the timeline drags, a line across the screen where each axis would
-- snap, as Edit Mode draws for its own frames (MagnetismPreviewLineMixin).
-- Our own lines: asking Edit Mode's manager to draw them would taint.
local function NewPreviewLine()
	local line = preview:CreateLine(nil, "OVERLAY")
	line:SetColorTexture(PREVIEW_COLOR[1], PREVIEW_COLOR[2], PREVIEW_COLOR[3], 1)
	line:Hide()
	return line
end

local function ShowPreviewLine(line, at, vertical)
	if not at then
		line:Hide()
		return
	end
	line:SetThickness(Addon.Util.PixelSize(preview, PREVIEW_WIDTH))
	if vertical then
		line:SetStartPoint("BOTTOMLEFT", UIParent, at, 0)
		line:SetEndPoint("TOPLEFT", UIParent, at, 0)
	else
		line:SetStartPoint("BOTTOMLEFT", UIParent, 0, at)
		line:SetEndPoint("BOTTOMRIGHT", UIParent, 0, at)
	end
	line:Show()
end

local function UpdatePreview()
	local _, _, atX, atY = Snap()
	ShowPreviewLine(preview.vertical, atX, true)
	ShowPreviewLine(preview.horizontal, atY, false)
end

local function StartPreview()
	if not preview then
		preview = CreateFrame("Frame", nil, UIParent)
		preview:SetAllPoints(UIParent)
		preview:SetFrameStrata("HIGH")
		if not preview.CreateLine then
			return
		end
		preview.vertical, preview.horizontal = NewPreviewLine(), NewPreviewLine()
	end
	if preview.vertical then
		preview:SetScript("OnUpdate", UpdatePreview)
		preview:Show()
	end
end

local function StopPreview()
	if preview then
		preview:SetScript("OnUpdate", nil)
		preview:Hide()
	end
end

-- Stores the center (shifted by dx, dy UIParent units) at the active layout
-- and re-anchors to UIParent whatever StartMoving left.
local function Store(dx, dy)
	local x, y = timeline:GetCenter()
	if not x then
		return
	end
	local scale = ScaleToParent()
	Positions()[LayoutKey()] = { x = x * scale + (dx or 0), y = y * scale + (dy or 0) }
	Restore()
end

-- On drop: snap, then store.
local function Save()
	Store(Snap())
end

-- Back to the default spot: forgets this layout's position.
function EditMode:ResetPosition()
	Positions()[LayoutKey()] = nil
	Restore()
end

-- ---------------------------------------------------------------------------
-- The selection
-- ---------------------------------------------------------------------------

-- Blizzard's art when the client has it, else a plain band.
local function ShowKit(kit)
	if handle.kit == kit then
		return
	end
	handle.kit = kit
	local ready = NineSliceUtil and NineSliceUtil.ApplyLayout and Addon.Util.AtlasExists(kit .. "-NineSlice-Corner")
	if ready then
		NineSliceUtil.ApplyLayout(handle, SELECTION, kit)
		handle.band:Hide()
	else
		local selectedKit = kit == KITS.selected
		handle.band:SetColorTexture(selectedKit and 1 or 0.82, selectedKit and 0.82 or 0.38, selectedKit and 0 or 0.12, selectedKit and 0.4 or 0.25)
		handle.band:Show()
	end
end

local function UpdateLabel()
	handle.label:SetShown(selected or handle.hover)
end

local function Select(on)
	if selected == on then
		return
	end
	selected = on
	ShowKit(on and KITS.selected or KITS.highlight)
	UpdateLabel()
	if on then
		Addon.EditModeDialog:Show(handle)
	else
		Addon.EditModeDialog:Hide()
	end
end

-- Our panel closes: its close button, or another window of ours opens over
-- Edit Mode. Nothing of Blizzard's is touched from here (calling its Edit
-- Mode manager from our handlers taints the raid frames' updates, M10 probes
-- E3 and E6).
function EditMode:Deselect()
	Select(false)
end

local function SetActive(active)
	Addon.editMode = active
	if not active then
		Select(false)
		StopPreview()
	end
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
	handle.band = handle:CreateTexture(nil, "BACKGROUND")
	handle.band:SetAllPoints()
	handle.band:Hide()
	handle.label = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	handle.label:SetPoint("CENTER")
	handle.label:SetText("Action Timeline")
	handle.label:Hide()
	handle:SetScript("OnMouseDown", function()
		Select(true)
	end)
	handle:SetScript("OnEnter", function(self)
		self.hover = true
		UpdateLabel()
	end)
	handle:SetScript("OnLeave", function(self)
		self.hover = false
		UpdateLabel()
	end)
	handle:SetScript("OnDragStart", function()
		Select(true)
		timeline:StartMoving()
		StartPreview()
	end)
	handle:SetScript("OnDragStop", function()
		timeline:StopMovingOrSizing()
		StopPreview()
		Save()
	end)
	-- Keep the handle over the whole timeline as its height changes.
	local function FitHeight()
		local height = timeline:GetHeight()
		handle:SetHeight(math.max(Plain(height) and height or 0, HANDLE_MIN_HEIGHT))
	end
	timeline:HookScript("OnSizeChanged", FitHeight)
	FitHeight()
	ShowKit(KITS.highlight)
	handle:Hide()
end

function EditMode:Init(frame)
	timeline = frame
	timeline:SetMovable(true)
	timeline:SetClampedToScreen(true)
	Restore()
	-- A new scale re-anchors the stored position (the offset is in the frame's
	-- scale), so scaling never moves the timeline.
	if hooksecurefunc then
		local scale
		hooksecurefunc(timeline, "SetScale", function(_, new)
			if new ~= scale then
				scale = new
				Restore()
			end
		end)
	end
	BuildHandle()
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			Restore()
			SetActive(true)
		end, EditMode)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			SetActive(false)
		end, EditMode)
	end
	-- A switch of the active Edit Mode layout moves the timeline to that
	-- layout's own position.
	if EventRegistry and EventRegistry.RegisterFrameEventAndCallback then
		EventRegistry:RegisterFrameEventAndCallback("EDIT_MODE_LAYOUTS_UPDATED", Restore, EditMode)
	end
	-- Blizzard selecting a system (or clearing its selection) deselects ours.
	local manager = EditModeManagerFrame
	if manager and hooksecurefunc then
		for _, method in ipairs({ "SelectSystem", "ClearSelectedSystem" }) do
			if manager[method] then
				hooksecurefunc(manager, method, function()
					Select(false)
				end)
			end
		end
	end
	if manager and manager.IsEditModeActive and manager:IsEditModeActive() then
		SetActive(true)
	end
end
