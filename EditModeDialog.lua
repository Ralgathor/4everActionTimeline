-- 4everActionTimeline — the Edit Mode settings panel (docs/SPEC.md, Settings
-- surface split; VISUAL.md, Edit Mode). Click the timeline in Edit Mode and
-- this panel opens beside it, like a Blizzard system's: the frame's own look
-- and size. It is not a registered Edit Mode system (see EditMode.lua), so
-- it is built from generic templates - the slider, dropdown and dialog
-- border Blizzard's panel uses, never the EditModeSetting* templates whose
-- mixins report to Edit Mode's manager. The settings are declared as data,
-- like Blizzard_EditMode's EditModeSettingDisplayInfo, and written through
-- Addon:GetSetting / SetSetting (the player layer, live). Its buttons lead
-- to the other places: Reset position and the spell window.

local Addon = FourEverActionTimeline

local NAME = "FourEverActionTimelineEditDialog"
local WIDTH, LABEL_WIDTH, ROW_HEIGHT = 380, 110, 32

local EditModeDialog = {}
Addon.EditModeDialog = EditModeDialog

local function Percent(value)
	return format("%d%%", value)
end

local function Seconds(value)
	return format("%.1f s", value)
end

local function Orientation()
	local value = Addon:GetSetting("orientation")
	return value == "vertical" or value == "verticalFlipped"
end

-- The two end labels of a slider: the first pair when the time axis is
-- vertical, else the second.
local function Ends(verticalLow, verticalHigh, low, high)
	if Orientation() then
		return verticalLow, verticalHigh
	end
	return low, high
end

-- One entry per setting: a slider (shown as `min`..`max` in steps of `step`,
-- stored through toStored / fromStored; `ends` names its two ends) or a
-- dropdown. Slider values are what the panel shows (percent for scale).
local SETTINGS = {
	{ key = "scale", type = "slider", name = "Scale", min = 50, max = 200, step = 5, format = Percent,
		fromStored = function(v) return v * 100 end, toStored = function(v) return v / 100 end },
	{ key = "opacity", type = "slider", name = "Opacity", min = 10, max = 100, step = 5, format = Percent,
		fromStored = function(v) return v * 100 end, toStored = function(v) return v / 100 end },
	{ key = "width", type = "slider", name = "Length", min = 200, max = 1200, step = 10,
		ends = function() return Ends(SHORT or "Short", TALL or "Tall", NARROW or "Narrow", WIDE or "Wide") end },
	{ key = "laneHeight", type = "slider", name = "Bar height", min = 16, max = 48, step = 1,
		ends = function() return Ends(NARROW or "Narrow", WIDE or "Wide", SHORT or "Short", TALL or "Tall") end },
	{ key = "pastWindow", type = "slider", name = "Past window", min = 0.5, max = 10, step = 0.5, format = Seconds },
	{ key = "futureWindow", type = "slider", name = "Future window", min = 2, max = 15, step = 0.5, format = Seconds },
	{ key = "laneSpacing", type = "slider", name = "Engine lane gap", min = 0, max = 16, step = 1 },
	{ key = "visibility", type = "dropdown", name = "Visible", options = {
		{ "combat", "In combat" }, { "always", "Always" }, { "active", "While active" } } },
	{ key = "orientation", type = "dropdown", name = "Orientation", relabels = true, options = {
		{ "horizontal", "Horizontal" }, { "horizontalFlipped", "Horizontal, flipped" },
		{ "vertical", "Vertical" }, { "verticalFlipped", "Vertical, flipped" } } },
	{ key = "readyRowSide", type = "dropdown", name = "Ready row", options = {
		{ "past", "Past side" }, { "future", "Future side" } } },
	{ key = "skin", type = "dropdown", name = "Skin", options = {
		{ "native", "Native" }, { "flat", "Flat" } } },
	{ key = "barGcd", type = "dropdown", name = "GCD", options = {
		{ "tint", "Tint the bar" }, { "strip", "Strip on the edge" } } },
	{ key = "barScale", type = "checkbox", name = "Seconds scale" },
}
EditModeDialog.SETTINGS = SETTINGS

local dialog
local rows = {}
local ROW_TYPES

local function Write(setting, value)
	Addon:SetSetting(setting.key, setting.toStored and setting.toStored(value) or value)
end

-- A slider row on Blizzard's minimal slider (nil without the template, like
-- the dropdown: the row is then a label only).
local function BuildSlider(row, setting)
	local ok, slider = pcall(CreateFrame, "Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	if not (ok and slider.Init and MinimalSliderWithSteppersMixin) then
		return
	end
	slider:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH, 0)
	slider:SetWidth(200)
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if not row.initializing then
			Write(setting, value)
		end
	end, row)
	return slider
end

local function BuildDropdown(row, setting)
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	if not (ok and dropdown.SetupMenu) then
		return
	end
	dropdown:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH, 0)
	dropdown:SetWidth(200)
	dropdown:SetupMenu(function(_, root)
		for _, option in ipairs(setting.options) do
			root:CreateRadio(option[2], function()
				return Addon:GetSetting(setting.key) == option[1]
			end, function()
				Addon:SetSetting(setting.key, option[1])
				if setting.relabels then
					EditModeDialog:Refresh()
				end
			end)
		end
	end)
	return dropdown
end

local function BuildCheckbox(row, setting)
	local ok, check = pcall(CreateFrame, "CheckButton", nil, row, "UICheckButtonTemplate")
	if not ok then
		return
	end
	check:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH - 4, 0)
	check:SetScript("OnClick", function(self)
		Write(setting, self:GetChecked() and true or false)
	end)
	return check
end

local function RefreshSlider(row, control)
	local setting = row.setting
	local value = Addon:GetSetting(setting.key)
	value = setting.fromStored and setting.fromStored(value) or value
	local minText, maxText
	if setting.ends then
		minText, maxText = setting.ends()
	end
	local formatters = {}
	if setting.format and CreateMinimalSliderFormatter then
		formatters[MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, setting.format)
	end
	row.initializing = true
	control:Init(value, setting.min, setting.max, (setting.max - setting.min) / setting.step, formatters)
	row.initializing = false
	if control.MinText and control.MaxText then
		control.MinText:SetText(minText or "")
		control.MaxText:SetText(maxText or "")
		control.MinText:SetShown(minText ~= nil)
		control.MaxText:SetShown(maxText ~= nil)
	end
end

-- How each row type is built and read back.
ROW_TYPES = {
	slider = { build = BuildSlider, refresh = RefreshSlider },
	dropdown = { build = BuildDropdown, refresh = function(_, control) control:GenerateMenu() end },
	checkbox = { build = BuildCheckbox, refresh = function(row, control) control:SetChecked(Addon:GetSetting(row.setting.key) and true or false) end },
}

local function BuildRow(setting, index)
	local row = CreateFrame("Frame", nil, dialog)
	row:SetSize(WIDTH - 40, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -(48 + (index - 1) * ROW_HEIGHT))
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.label:SetText(setting.name)
	row.setting = setting
	row.control = ROW_TYPES[setting.type].build(row, setting)
	return row
end

-- Reads every setting back into its control.
function EditModeDialog:Refresh()
	if not dialog then
		return
	end
	for _, row in ipairs(rows) do
		if row.control then
			ROW_TYPES[row.setting.type].refresh(row, row.control)
		end
	end
end

local function Button(text, onClick)
	local button = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	button:SetSize(WIDTH - 80, 24)
	button:SetNormalFontObject("GameFontNormal") -- gold, like Blizzard's panel buttons
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function Build()
	dialog = CreateFrame("Frame", NAME, UIParent)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(200)
	dialog:SetClampedToScreen(true)
	dialog:SetMovable(true)
	dialog:EnableMouse(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	local ok, border = pcall(CreateFrame, "Frame", nil, dialog, "DialogBorderTranslucentTemplate")
	if ok then
		border:SetAllPoints()
	else
		local back = dialog:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.8)
	end
	local title = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -15)
	title:SetText("Action Timeline")
	local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT")
	close:SetScript("OnClick", function()
		Addon.EditMode:Deselect()
	end)
	for index, setting in ipairs(SETTINGS) do
		rows[index] = BuildRow(setting, index)
	end
	local top = 48 + #SETTINGS * ROW_HEIGHT + 8
	local reset = Button("Reset position", function()
		Addon.EditMode:ResetPosition()
	end)
	reset:SetPoint("TOP", dialog, "TOP", 0, -top)
	local spells = Button("Advanced Combat Timeline Settings", function()
		Addon.LaneWindow:Open()
	end)
	spells:SetPoint("TOP", reset, "BOTTOM", 0, -4)
	-- No Options button: opening the Settings panel from here needs Edit Mode
	-- stepped aside, and every way our code can do that taints the raid frames
	-- (M10 probe E6).
	local note = dialog:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOP", spells, "BOTTOM", 0, -8)
	note:SetText("More settings: /actiontimeline options")
	dialog:SetSize(WIDTH, top + 2 * 28 + 34)
	dialog:Hide()
end

-- Opens beside the selected timeline (anchor): under it, or over it when
-- there is no room below.
function EditModeDialog:Show(anchor)
	if not dialog then
		Build()
	end
	self:Refresh()
	dialog:ClearAllPoints()
	local bottom = anchor:GetBottom()
	if bottom and bottom > dialog:GetHeight() + 40 then
		dialog:SetPoint("TOP", anchor, "BOTTOM", 0, -30)
	else
		dialog:SetPoint("BOTTOM", anchor, "TOP", 0, 30)
	end
	-- Pin it where it landed: the timeline resizes under the sliders and the
	-- panel must not follow it. It stays draggable.
	local left, top = dialog:GetLeft(), dialog:GetTop()
	if left and top then
		dialog:ClearAllPoints()
		dialog:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	dialog:Show()
end

function EditModeDialog:Hide()
	if dialog then
		dialog:Hide()
	end
end
