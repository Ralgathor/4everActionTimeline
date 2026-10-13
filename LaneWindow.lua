-- 4everActionTimeline — the lane window (/actiontimeline config; docs/SPEC.md,
-- Settings surface split; VISUAL.md, Settings window). The lane list the
-- Settings category cannot hold: every known class spell as a row - enable,
-- engine-drawn lane, manual cooldown, long cooldown - in lane order (enabled first), drag
-- to reorder. It edits one layer at a time (ADR-0002): the class layer
-- (every character of the class) or this character, showing values and
-- order as that layer sees them, with an "overridden" tag where this
-- character overrides and a "new" tag where the class added a spell this
-- character's own order lacks; "Reset character to class" deletes this
-- character's lane settings.
-- Built from plain frames and the basic UI templates only (no ScrollBox):
-- a clipped list scrolled by the mouse wheel. The spellbook is scanned when
-- the window opens (and on SPELLS_CHANGED while open); a lane-set change or
-- a layer switch re-merges the lane order, a scroll only redraws the rows.

local Addon = FourEverActionTimeline
local Spellbook = Addon.Spellbook

local GetCursorPosition = GetCursorPosition

local NAME = "FourEverActionTimelineLanes"
local WIDTH, ROW_HEIGHT, VISIBLE_ROWS = 470, 28, 14
local LIST_TOP, LIST_LEFT = -86, 12
local ICON_CROP = Addon.Util.ICON_CROP

local LaneWindow = {}
Addon.LaneWindow = LaneWindow

local frame, listArea, layerButtons
local rows, entries, classSpells, newForPlayer = {}, {}, {}, {}
local offset, layerName = 0, "class"
local dragFrom

-- ---------------------------------------------------------------------------
-- The list: the lane order's known spells first, then the other class
-- spells by name; a curated spell keeps its curated base ID.
-- ---------------------------------------------------------------------------

local function Scan()
	classSpells = Spellbook.ClassSpells()
	for _, spell in ipairs(classSpells) do
		spell.icon = Spellbook.Icon(spell.id)
	end
end

local function BuildEntries()
	wipe(entries)
	local order
	order, newForPlayer = Addon:LaneOrder(layerName)
	if layerName == "class" then
		newForPlayer = select(2, Addon:LaneOrder())
	end
	local listed = {}
	for _, base in ipairs(order) do
		local id, name = Spellbook.Resolve(base)
		if id and not listed[name] then
			listed[name] = true
			entries[#entries + 1] = { base = base, name = name, icon = Spellbook.Icon(id) }
		end
	end
	local bases = Addon:LaneBasesByName(order)
	for _, spell in ipairs(classSpells) do
		if not listed[spell.name] then
			entries[#entries + 1] = { base = bases[spell.name] or spell.id, name = spell.name, icon = spell.icon }
		end
	end
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

local function Tags(base)
	local tags = {}
	if Addon:LayerHasSpell("player", base) then
		tags[#tags + 1] = layerName == "class" and "|cffffd100overridden here|r" or "|cffffd100overridden|r"
	end
	if newForPlayer[base] then
		tags[#tags + 1] = "|cff66ccffnew|r"
	end
	return table.concat(tags, " ")
end

local Render, Rebuild -- below

local function Index(row)
	return offset + row.slot
end

-- The row under the cursor (a list index), clamped to the list.
local function IndexAtCursor()
	local _, y = GetCursorPosition()
	y = y / listArea:GetEffectiveScale()
	local index = math.floor((listArea:GetTop() - y) / ROW_HEIGHT) + 1 + offset
	return math.max(1, math.min(#entries, index))
end

-- Moves an entry and stores the new lane order at the edited layer.
local function Move(from, to)
	if from == to then
		return
	end
	local entry = table.remove(entries, from)
	table.insert(entries, to, entry)
	local order = {}
	for i, item in ipairs(entries) do
		order[i] = item.base
	end
	Addon:SetLaneOrder(layerName, order)
end

-- A row's flag box (enabled, sink), written at the edited layer.
local function RowCheck(row, key, anchor, relPoint, x)
	local box = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	box:SetSize(24, 24)
	box:SetPoint("LEFT", anchor, relPoint, x, 0)
	box:SetScript("OnClick", function(self)
		Addon:SetLaneValue(layerName, entries[Index(row)].base, key, self:GetChecked())
	end)
	return box
end

local function CreateRow(slot)
	local row = CreateFrame("Frame", nil, listArea)
	row.slot = slot
	row:SetSize(WIDTH - 2 * LIST_LEFT - 8, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, -(slot - 1) * ROW_HEIGHT)
	row:EnableMouse(true)
	row:RegisterForDrag("LeftButton")
	row.band = row:CreateTexture(nil, "BACKGROUND")
	row.band:SetAllPoints()
	row.band:SetColorTexture(1, 1, 1, slot % 2 == 0 and 0.04 or 0)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
	row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetWidth(150)
	row.name:SetJustifyH("LEFT")
	row.tags = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.tags:SetPoint("LEFT", row.name, "RIGHT", 2, 0)
	row.tags:SetWidth(80)
	row.tags:SetJustifyH("LEFT")

	row.enabled = RowCheck(row, "enabled", row, "LEFT", 270)
	row.sink = RowCheck(row, "sink", row.enabled, "RIGHT", 22)
	row.override = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.override:SetSize(44, 20)
	row.override:SetPoint("LEFT", row.sink, "RIGHT", 22, 0)
	row.override:SetAutoFocus(false)
	row.override:SetScript("OnEnterPressed", function(self)
		local seconds = tonumber(self:GetText())
		Addon:SetLaneValue(layerName, entries[Index(row)].base, "override", seconds and seconds > 0 and seconds or nil)
		self:ClearFocus()
	end)
	row.override:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		Render()
	end)
	row.long = RowCheck(row, "long", row.override, "RIGHT", 8)

	row:SetScript("OnDragStart", function()
		dragFrom = Index(row)
		row:SetAlpha(0.5)
	end)
	row:SetScript("OnDragStop", function()
		row:SetAlpha(1)
		Move(dragFrom, IndexAtCursor())
	end)
	return row
end

-- Draws the visible rows from the current entries.
function Render()
	offset = math.max(0, math.min(offset, #entries - VISIBLE_ROWS))
	for slot = 1, VISIBLE_ROWS do
		local row = rows[slot] or CreateRow(slot)
		rows[slot] = row
		local entry = entries[offset + slot]
		if entry then
			local base = entry.base
			row.icon:SetTexture(entry.icon)
			row.name:SetText(entry.name)
			row.tags:SetText(Tags(base))
			row.enabled:SetChecked(Addon:GetLaneValue(base, "enabled", layerName))
			row.sink:SetChecked(Addon:GetLaneValue(base, "sink", layerName))
			row.long:SetChecked(Addon:GetLaneValue(base, "long", layerName))
			if not row.override:HasFocus() then
				local override = Addon:GetLaneValue(base, "override", layerName)
				row.override:SetText(override and tostring(override) or "")
			end
			row:Show()
		else
			row:Hide()
		end
	end
	for name, button in pairs(layerButtons) do
		button:SetEnabled(name ~= layerName)
	end
end

-- Re-merges the lane order with the scanned spells, then draws.
function Rebuild()
	if frame and frame:IsShown() then
		BuildEntries()
		Render()
	end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function Header(text, x)
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT + x, LIST_TOP + 16)
	label:SetText(text)
end

local function Button(text, width, onClick)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function Build()
	frame = CreateFrame("Frame", NAME, UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WIDTH, -LIST_TOP + VISIBLE_ROWS * ROW_HEIGHT + 44)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnShow", function()
		Scan()
		Rebuild()
	end)
	frame:RegisterEvent("SPELLS_CHANGED")
	frame:SetScript("OnEvent", function()
		if frame:IsShown() then
			Scan()
			Rebuild()
		end
	end)
	tinsert(UISpecialFrames, NAME) -- Escape closes it
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText("4everActionTimeline - lanes")

	local editing = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	editing:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT, -34)
	editing:SetText("Editing:")
	layerButtons = {}
	local anchor, gap = editing, 8
	for _, layer in ipairs({ { "class", "Class", 90 }, { "player", "This character", 120 } }) do
		local name = layer[1]
		local button = Button(layer[2], layer[3], function()
			layerName = name
			Rebuild()
		end)
		button:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
		layerButtons[name], anchor, gap = button, button, 4
	end
	local reset = Button("Reset character to class", 170, function()
		Addon:ResetPlayerLanes()
	end)
	reset:SetPoint("LEFT", anchor, "RIGHT", 8, 0)

	Header("Spell", 0)
	Header("On", 268)
	Header("Engine", 306)
	Header("Cooldown (s)", 352)
	Header("Long", 416)

	listArea = CreateFrame("Frame", nil, frame)
	listArea:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT, LIST_TOP)
	listArea:SetSize(WIDTH - 2 * LIST_LEFT, VISIBLE_ROWS * ROW_HEIGHT)
	listArea:SetClipsChildren(true)
	listArea:EnableMouseWheel(true)
	listArea:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Render()
	end)

	local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LIST_LEFT, 12)
	note:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LIST_LEFT, 12)
	note:SetJustifyH("LEFT")
	note:SetText("Drag a row to reorder; the mouse wheel scrolls. Engine: the true remaining cooldown, drawn by the game (at most "
		.. Addon.Sinks.MAX .. "). Cooldown: a manual value for a spell that cannot be learned; empty to clear. Long: no slot in the ready row (cooldowns of 30 s or more count anyway).")
	frame:Hide()
end

function LaneWindow:Toggle()
	if not frame then
		Build()
	end
	frame:SetShown(not frame:IsShown())
end

Addon:OnLaneSetChanged(Rebuild)
