-- 4everActionTimeline — the spell window (/actiontimeline config; docs/SPEC.md,
-- Settings surface split; VISUAL.md, Settings window). It follows the
-- Cooldown Manager's settings window: every known class spell is an icon in
-- one of four sections - Timeline, Long cooldowns, Engine lanes, Not
-- displayed - dragged within a section to reorder and between sections to
-- change what it does; a right-click menu sets a manual cooldown; a search
-- box filters by name; Revert goes back to how the layer was when the window
-- opened. The sections are derived from the flags (enabled, sink, long) as
-- the edited layer sees them, never stored (ADR-0002: the class layer, shared
-- by every character of the class, or this character's own).
-- Built from generic Blizzard templates and plain frames, never by inheriting
-- CooldownViewerSettings*: their mixins are wired to the Cooldown Manager's
-- own data. The spellbook is scanned when the window opens (and on
-- SPELLS_CHANGED while open); a lane-set change re-merges the list.

local Addon = FourEverActionTimeline
local Spellbook = Addon.Spellbook

local GetCursorPosition = GetCursorPosition

local NAME = "FourEverActionTimelineLanes"
local ICON, PAD, STRIDE, LEFT = 38, 8, 7, 13 -- the Cooldown Manager's grid
local HEADER, GAP = 22, 12
local WIDTH, HEIGHT = 420, 560
local ICON_CROP = Addon.Util.ICON_CROP

local SECTIONS = {
	{ key = "timeline", title = "Timeline", hint = "Spells that ride the bar toward the now line." },
	{ key = "long", title = "Long cooldowns", hint = "No slot in the ready row; a ring flashes on the now line when one returns." },
	{ key = "engine", title = "Engine lanes", hint = "The game draws the spell's icon in a thin row under the bar, exact even in combat." },
	{ key = "hidden", title = "Not displayed", hint = "Not on the timeline." },
}
local LaneWindow = {}
Addon.LaneWindow = LaneWindow

local frame, scroll, child, ghost, searchBox, revertButton, layerDropdown, layerButtons
local sectionFrames, icons = {}, {}
local entries, classSpells, newForPlayer = {}, {}, {}
local layerName = "class"
local snapshots = {} -- layer -> a copy of its lanes when the window opened (false: none)
local collapsed = {}
local filter = ""
local dragging
local scanned = false

-- ---------------------------------------------------------------------------
-- The list: the lane order's known spells first, then the other class
-- spells by name; a curated spell keeps its curated base ID. Each carries its
-- section as the layer sees it.
-- ---------------------------------------------------------------------------

local function Scan()
	classSpells = Spellbook.ClassSpells()
	for _, spell in ipairs(classSpells) do
		spell.icon = Spellbook.Icon(spell.id)
	end
	scanned = true
end

-- The section a spell is in at `layer`: Not displayed when off, Engine lanes
-- with the engine opt-in (such a spell keeps its marks and ready slot on the
-- bar; only its future mark moves to the engine row), Long cooldowns when
-- flagged or long by itself, else Timeline.
function LaneWindow.SectionOf(base, layer, id)
	if not Addon:GetLaneValue(base, "enabled", layer) then
		return "hidden"
	end
	if Addon:GetLaneValue(base, "sink", layer) then
		return "engine"
	end
	if Addon.Spells.IsLongBase(base, id, layer) then
		return "long"
	end
	return "timeline"
end

local function BuildEntries(layer)
	wipe(entries)
	local order
	order, newForPlayer = Addon:LaneOrder(layer)
	if layer == "class" then
		newForPlayer = select(2, Addon:LaneOrder())
	end
	local function Add(base, id, name, icon)
		entries[#entries + 1] = { base = base, id = id, name = name, icon = icon, section = LaneWindow.SectionOf(base, layer, id),
			auto = Addon.Spells.AutoLongBase(base, id, layer) }
	end
	local listed = {}
	for _, base in ipairs(order) do
		local id, name = Spellbook.Resolve(base)
		if id and not listed[name] then
			listed[name] = true
			Add(base, id, name, Spellbook.Icon(id))
		end
	end
	local bases = Addon:LaneBasesByName(order)
	for _, spell in ipairs(classSpells) do
		if not listed[spell.name] then
			local base = bases[spell.name] or spell.id
			Add(base, spell.id, spell.name, spell.icon)
		end
	end
	return entries
end

local function Count(list, section, except)
	local count = 0
	for _, entry in ipairs(list) do
		if entry.section == section and entry.base ~= except then
			count = count + 1
		end
	end
	return count
end

-- Moves a spell into a section at a slot, written at `layer`; slot is the
-- 1-based place in that section's list without the spell itself (nil: the
-- section's end). Returns true, or false and why ("full": the engine section
-- holds Sinks.MAX; "auto": the spell is long by itself, so Timeline is not
-- its place; "unknown").
function LaneWindow.Drop(base, section, slot, layer)
	if not scanned then
		Scan()
	end
	local list = BuildEntries(layer)
	local entry, at
	for index, item in ipairs(list) do
		if item.base == base then
			entry, at = item, index
		end
	end
	if not entry then
		return false, "unknown"
	end
	if section == "engine" and entry.section ~= "engine" and Count(list, "engine", base) >= Addon.Sinks.MAX then
		return false, "full"
	end
	if section == "timeline" and entry.auto then
		return false, "auto"
	end
	local order, peers = {}, {}
	for _, item in ipairs(list) do
		if item.base ~= base then
			order[#order + 1] = item.base
			if item.section == section then
				peers[#peers + 1] = item.base
			end
		end
	end
	local function PlaceOf(target)
		for index, id in ipairs(order) do
			if id == target then
				return index
			end
		end
	end
	local insertAt
	if slot and peers[slot] then
		insertAt = PlaceOf(peers[slot])
	elseif #peers > 0 then
		insertAt = PlaceOf(peers[#peers]) + 1
	else
		insertAt = math.min(at, #order + 1) -- an empty section: keep its place
	end
	table.insert(order, insertAt, base)
	Addon:BatchLaneSet(function()
		if section == "hidden" then
			Addon:SetLaneValue(layer, base, "enabled", false)
		else
			Addon:SetLaneValue(layer, base, "enabled", true)
			Addon:SetLaneValue(layer, base, "sink", section == "engine")
			if section ~= "engine" then
				Addon:SetLaneValue(layer, base, "long", section == "long")
			end
		end
		Addon:SetLaneOrder(layer, order)
	end)
	return true
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local Render -- below

local function DeepEqual(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in pairs(a) do
		if not DeepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function Snapshot()
	for _, name in ipairs({ "class", "player" }) do
		local lanes = Addon:LayerLanes(name)
		snapshots[name] = lanes and CopyTable(lanes) or false
	end
end

local function Differs()
	local lanes, saved = Addon:LayerLanes(layerName), snapshots[layerName] or nil
	return not DeepEqual(lanes, saved)
end

local function Overridden(base)
	return Addon:LayerHasSpell("player", base)
end

local function Tooltip(button)
	local entry = button.entry
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if entry.id and GameTooltip.SetSpellByID then
		GameTooltip:SetSpellByID(entry.id)
	else
		GameTooltip:SetText(entry.name)
	end
	local override = Addon:GetLaneValue(entry.base, "override", layerName)
	if override then
		GameTooltip:AddLine("Manual cooldown: " .. override .. " s", 1, 0.82, 0)
	end
	if layerName == "class" and Overridden(entry.base) then
		GameTooltip:AddLine("This character overrides it.", 1, 0.82, 0)
	end
	if newForPlayer[entry.base] then
		GameTooltip:AddLine("New: the class added it after this character's own order.", 0.4, 0.8, 1)
	end
	if layerName == "player" and Overridden(entry.base) then
		GameTooltip:AddLine("Overridden for this character.", 1, 0.82, 0)
	end
	if entry.section == "long" and entry.auto then
		GameTooltip:AddLine("Long by itself (30 s or more, or tagged), so it stays here.", 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine("Drag to reorder or move; right-click for more.", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function Refuse(why, entry)
	if why == "full" then
		Addon:Print(format("Engine lanes are full (%d).", Addon.Sinks.MAX))
	elseif why == "auto" then
		Addon:Print(format("%s is a long cooldown by itself, so it stays in Long cooldowns.", entry.name))
	end
end

local function MoveTo(entry, key, slot)
	local ok, why = LaneWindow.Drop(entry.base, key, slot, layerName)
	if not ok then
		Refuse(why, entry)
	end
end

StaticPopupDialogs["FOUREVERACTIONTIMELINE_COOLDOWN"] = {
	text = "Cooldown of %s in seconds (empty clears it):",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	OnShow = function(self)
		local editBox = self.GetEditBox and self:GetEditBox() or self.editBox
		local override = Addon:GetLaneValue(self.data.base, "override", layerName)
		editBox:SetText(override and tostring(override) or "")
		editBox:HighlightText()
	end,
	OnAccept = function(self)
		local editBox = self.GetEditBox and self:GetEditBox() or self.editBox
		local seconds = tonumber(editBox:GetText())
		Addon:SetLaneValue(layerName, self.data.base, "override", seconds and seconds > 0 and seconds or nil)
	end,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		local seconds = tonumber(editBox:GetText())
		Addon:SetLaneValue(layerName, dialog.data.base, "override", seconds and seconds > 0 and seconds or nil)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
}

local function ShowMenu(button)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		return
	end
	local entry = button.entry
	MenuUtil.CreateContextMenu(button, function(_, root)
		root:CreateTitle(entry.name)
		root:CreateButton("Set cooldown...", function()
			StaticPopup_Show("FOUREVERACTIONTIMELINE_COOLDOWN", entry.name, nil, { base = entry.base })
		end)
		if Addon:GetLaneValue(entry.base, "override", layerName) then
			root:CreateButton("Clear cooldown", function()
				Addon:SetLaneValue(layerName, entry.base, "override", nil)
			end)
		end
		if entry.section == "engine" then
			root:CreateCheckbox("Long cooldown", function()
				return Addon:GetLaneValue(entry.base, "long", layerName) and true or false
			end, function()
				Addon:SetLaneValue(layerName, entry.base, "long", not Addon:GetLaneValue(entry.base, "long", layerName))
			end)
		end
		for _, section in ipairs(SECTIONS) do
			if section.key ~= entry.section then
				root:CreateButton("Move to " .. section.title, function()
					MoveTo(entry, section.key)
				end)
			end
		end
	end)
end

-- Where the cursor would drop: the section and the slot among its icons
-- (without the dragged one), or nil outside every section.
local function DropTarget()
	local x, y = GetCursorPosition()
	local scale = child:GetEffectiveScale()
	local left, top = child:GetLeft(), child:GetTop()
	if not (left and top) then
		return
	end
	x, y = x / scale - left, top - y / scale
	for _, section in ipairs(SECTIONS) do
		local view = sectionFrames[section.key]
		if y >= view.top and y < view.bottom and x >= 0 and x <= child:GetWidth() then
			local items = view.items
			local column = math.max(0, math.min(STRIDE - 1, math.floor((x - LEFT) / (ICON + PAD))))
			local row = math.max(0, math.floor((y - view.gridTop) / (ICON + PAD)))
			local slot = math.min(#items + 1, row * STRIDE + column + 1)
			for index, item in ipairs(items) do
				if item == dragging and section.key == dragging.section and index < slot then
					slot = slot - 1
					break
				end
			end
			return section.key, slot
		end
	end
end

local function StopDrag()
	if ghost then
		ghost:Hide()
	end
	local entry = dragging
	dragging = nil
	return entry
end

local function CreateIcon()
	local button = CreateFrame("Button", nil, child)
	button:SetSize(ICON, ICON)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	highlight:SetBlendMode("ADD")
	button.seconds = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.seconds:SetPoint("BOTTOMRIGHT", -2, 2)
	button.mark = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.mark:SetPoint("TOPLEFT", 2, -2)
	button:SetScript("OnEnter", Tooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			ShowMenu(self)
		end
	end)
	button:SetScript("OnDragStart", function(self)
		if filter ~= "" then
			return
		end
		GameTooltip:Hide()
		dragging = self.entry
		ghost.icon:SetTexture(self.entry.icon)
		ghost:Show()
		self:SetAlpha(0.4)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetAlpha(1)
		local entry = StopDrag()
		local key, slot = DropTarget()
		if entry and key then
			MoveTo(entry, key, slot)
		end
	end)
	return button
end

local function CreateSection(section)
	local view = { items = {} }
	local ok, header = pcall(CreateFrame, "Button", nil, child, "ListHeaderThreeSliceTemplate")
	if not ok then
		header = CreateFrame("Button", nil, child)
		header.band = header:CreateTexture(nil, "BACKGROUND")
		header.band:SetAllPoints()
		header.band:SetColorTexture(1, 1, 1, 0.08)
	end
	header:SetHeight(HEADER)
	header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.label:SetPoint("LEFT", 12, 0)
	header.toggle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.toggle:SetPoint("RIGHT", -12, 0)
	header:SetScript("OnClick", function()
		collapsed[section.key] = not collapsed[section.key]
		Render()
	end)
	header:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(section.title)
		GameTooltip:AddLine(section.hint, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", GameTooltip_Hide)
	view.header = header
	view.empty = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	view.empty:SetText("Drag a spell here")
	return view
end

local function Matches(entry)
	return filter == "" or entry.name:lower():find(filter, 1, true) ~= nil
end

-- Draws the sections and their icons from the current entries.
function Render()
	if not frame then
		return
	end
	local used, y = 0, 0
	for _, section in ipairs(SECTIONS) do
		local view = sectionFrames[section.key]
		if not view then
			view = CreateSection(section)
			sectionFrames[section.key] = view
		end
		wipe(view.items)
		for _, entry in ipairs(entries) do
			if entry.section == section.key and Matches(entry) then
				view.items[#view.items + 1] = entry
			end
		end
		local header = view.header
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		header:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
		local count = Count(entries, section.key)
		if section.key == "engine" then
			header.label:SetText(format("%s (%d/%d)", section.title, count, Addon.Sinks.MAX))
			local full = count >= Addon.Sinks.MAX
			header.label:SetTextColor(1, full and 0.4 or 0.82, full and 0.4 or 0)
		else
			header.label:SetText(format("%s (%d)", section.title, count))
			header.label:SetTextColor(1, 0.82, 0)
		end
		header.toggle:SetText(collapsed[section.key] and "+" or "-")
		view.top = y
		y = y + HEADER
		view.gridTop = y + PAD
		view.empty:Hide()
		if collapsed[section.key] then
			y = y + PAD
		else
			for index, entry in ipairs(view.items) do
				used = used + 1
				local button = icons[used]
				if not button then
					button = CreateIcon()
					icons[used] = button
				end
				button.entry = entry
				button.icon:SetTexture(entry.icon)
				button.icon:SetDesaturated(entry.section == "hidden")
				local override = Addon:GetLaneValue(entry.base, "override", layerName)
				button.seconds:SetText(override and tostring(override) or "")
				local mark = ""
				if newForPlayer[entry.base] then
					mark = "|cff66ccffnew|r"
				elseif entry.section == "engine" and Addon:GetLaneValue(entry.base, "long", layerName) then
					mark = "|cffffd100L|r"
				elseif entry.section == "long" and entry.auto then
					mark = "|cffaaaaaa=|r"
				end
				button.mark:SetText(mark)
				button:ClearAllPoints()
				local column, row = (index - 1) % STRIDE, math.floor((index - 1) / STRIDE)
				button:SetPoint("TOPLEFT", child, "TOPLEFT", LEFT + column * (ICON + PAD), -(view.gridTop + row * (ICON + PAD)))
				button:Show()
			end
			if #view.items == 0 then
				view.empty:ClearAllPoints()
				view.empty:SetPoint("TOPLEFT", child, "TOPLEFT", LEFT, -(view.gridTop + 10))
				view.empty:Show()
			end
			y = y + PAD + math.max(1, math.ceil(#view.items / STRIDE)) * (ICON + PAD)
		end
		view.bottom = y
		y = y + GAP
	end
	for index = used + 1, #icons do
		icons[index].entry = nil
		icons[index]:Hide()
	end
	child:SetHeight(math.max(y, 1))
	if layerDropdown and layerDropdown.GenerateMenu then
		layerDropdown:GenerateMenu()
	end
	if layerButtons then
		for name, button in pairs(layerButtons) do
			button:SetEnabled(name ~= layerName)
		end
	end
	revertButton:SetEnabled(Differs())
end

-- Re-merges the lane order with the scanned spells, then draws.
local function Rebuild()
	if frame and frame:IsShown() then
		BuildEntries(layerName)
		Render()
	end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function LayerLabel(name)
	if name == "class" then
		return format("%s (all characters)", UnitClass("player") or "Class")
	end
	return "This character"
end

local function SwitchLayer(name)
	layerName = name
	Rebuild()
end

local function Button(text, width, onClick)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function BuildLayerPicker()
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	if ok and dropdown.SetupMenu then
		dropdown:SetSize(220, 22)
		dropdown:SetupMenu(function(_, root)
			for _, name in ipairs({ "class", "player" }) do
				root:CreateRadio(LayerLabel(name), function()
					return layerName == name
				end, function()
					SwitchLayer(name)
				end)
			end
		end)
		return dropdown
	end
	layerButtons = {}
	local anchor
	for _, name in ipairs({ "class", "player" }) do
		local button = Button(name == "class" and "Class" or "This character", 100, function()
			SwitchLayer(name)
		end)
		layerButtons[name] = button
		if anchor then
			button:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 6)
		end
		anchor = button
	end
end

local function BuildGear(inset)
	local ok, gear = pcall(CreateFrame, "DropdownButton", nil, frame, "UIPanelIconDropdownButtonTemplate")
	if not (ok and gear.SetupMenu) then
		return
	end
	gear:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -8, -8)
	gear:SetupMenu(function(_, root)
		root:CreateButton("Options", function()
			Addon.Options:Open()
		end)
		root:CreateButton("Reset this character to the class", function()
			Addon:ResetPlayerLanes()
		end)
	end)
end

local function Build()
	frame = CreateFrame("Frame", NAME, UIParent, "ButtonFrameTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("FULLSCREEN_DIALOG") -- over Edit Mode's DIALOG
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetTitle then
		frame:SetTitle("Timeline spells")
	elseif frame.TitleText then
		frame.TitleText:SetText("Timeline spells")
	end
	if frame.SetPortraitToUnit then
		frame:SetPortraitToUnit("player")
	end
	frame:SetScript("OnShow", function()
		Addon.EditMode:Deselect() -- our Edit Mode panel makes way
		Scan()
		Snapshot()
		Rebuild()
	end)
	frame:SetScript("OnHide", function()
		StopDrag()
	end)
	frame:RegisterEvent("SPELLS_CHANGED")
	frame:SetScript("OnEvent", function()
		if frame:IsShown() then
			Scan()
			Rebuild()
		end
	end)
	tinsert(UISpecialFrames, NAME) -- Escape closes it
	local inset = frame.Inset or frame

	searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	searchBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 14, -8)
	searchBox:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -40, -8)
	searchBox:SetHeight(20)
	searchBox:SetAutoFocus(false)
	searchBox:HookScript("OnTextChanged", function(self)
		filter = (self:GetText() or ""):lower()
		Render()
	end)
	BuildGear(inset)

	local ok, area = pcall(CreateFrame, "ScrollFrame", nil, frame, "ScrollFrameTemplate")
	if not ok then
		area = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	end
	scroll = area
	scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -34)
	scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 4)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(WIDTH - 60, 1)
	scroll:SetScrollChild(child)

	ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetSize(ICON, ICON)
	ghost:SetFrameStrata("TOOLTIP")
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetAllPoints()
	ghost.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	ghost:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	end)
	ghost:Hide()

	layerDropdown = BuildLayerPicker()
	if layerDropdown then
		layerDropdown:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 6)
	end
	revertButton = Button("Revert", 80, function()
		Addon:SetLayerLanes(layerName, snapshots[layerName] and CopyTable(snapshots[layerName]) or nil)
	end)
	revertButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 6)
	frame:Hide()
end

function LaneWindow:Toggle()
	if not frame then
		Build()
	end
	frame:SetShown(not frame:IsShown())
end

-- Shows the window (the Edit Mode panel's and Options' buttons).
function LaneWindow:Open()
	if not frame then
		Build()
	end
	frame:Show()
end

Addon:OnLaneSetChanged(Rebuild)
