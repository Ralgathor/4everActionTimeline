-- 4everActionTimeline — the Settings category (docs/SPEC.md, Settings
-- surface split). The client's Settings vertical layout (12.x; Forever has
-- no InterfaceOptions_AddCategory) holds the globals: checkboxes, sliders
-- and dropdowns only - the frame's own settings live in the Edit Mode
-- panel, the lane list in the spell window (/actiontimeline config), and
-- nothing dynamic registers here. Proxy
-- settings read and write through Addon:GetSetting / SetSetting, so every
-- change applies live and is stored at the player layer (only when it
-- differs from the default). The category links to the other places the
-- timeline is configured (the spell window, Edit Mode), under section
-- headers; a setting that only matters under another one hangs off it.
--
-- Dropdown contract on this client (4everSwingTimer, verified against the
-- shipped Blizzard_Settings.lua): CreateDropdown's options argument is
-- CALLED - it must be a function returning the entry list.

local Addon = FourEverActionTimeline

local Options = {}
Addon.Options = Options

local VAR_PREFIX = "4everActionTimeline."
local category, layout

local function Proxy(key, varType, name)
	return Settings.RegisterProxySetting(category, VAR_PREFIX .. key, varType, name, Addon.DEFAULTS[key],
		function()
			return Addon:GetSetting(key)
		end,
		function(value)
			Addon:SetSetting(key, value)
		end)
end

local function Checkbox(key, name, tooltip)
	return Settings.CreateCheckbox(category, Proxy(key, Settings.VarType.Boolean, name), tooltip)
end

local function Slider(key, name, low, high, step, tooltip)
	local options = Settings.CreateSliderOptions(low, high, step)
	if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	return Settings.CreateSlider(category, Proxy(key, Settings.VarType.Number, name), options, tooltip)
end

local function Dropdown(key, name, entries, tooltip)
	local function Entries()
		local container = Settings.CreateControlTextContainer()
		for _, entry in ipairs(entries) do
			container:Add(entry[1], entry[2], entry[3], Settings.ControlType and Settings.ControlType.Radio)
		end
		return container:GetData()
	end
	return Settings.CreateDropdown(category, Proxy(key, Settings.VarType.String, name), Entries, tooltip)
end

-- A section header; the layout's AddInitializer and the header initializer
-- are nil-guarded (the category still builds without them).
local function Header(text, tooltip)
	if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text, tooltip))
	end
end

-- A row with a button on it.
local function Link(name, buttonText, onClick, tooltip)
	if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
	end
end

-- The control is usable only while `enabled()` is true.
local function DependsOn(initializer, parent, enabled)
	if initializer and parent and initializer.SetParentInitializer then
		initializer:SetParentInitializer(parent, enabled)
	end
end

function Options:Init()
	if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	category, layout = Settings.RegisterVerticalLayoutCategory(Addon.name)
	Settings.RegisterAddOnCategory(category)

	Header("Windows", "Where the timeline is placed and which spells it shows.")
	Link("Timeline spells", "Open", function()
		Addon.LaneWindow:Open()
	end, "Choose the spells on the timeline, their order, manual cooldowns and engine lanes.")
	Header("Position and size", "Open Edit Mode (Esc, then Edit Mode) and click the timeline: its panel holds the position, scale, opacity, length, bar height, past and future windows, engine lane spacing, visibility, orientation, ready row side, skin, GCD style and seconds scale.")

	Header("Lanes")
	Checkbox("showMainhand", "Main-hand lane", "The main-hand swing lane (needs a main-hand weapon).")
	Checkbox("showOffhand", "Off-hand lane", "The off-hand swing lane (needs an off-hand weapon, not a shield or held item).")
	Checkbox("showRanged", "Ranged lane", "The ranged swing lane (needs a ranged weapon or wand).")
	Checkbox("showGcd", "GCD lane", "The global cooldown windows.")
	Checkbox("showCasts", "Cast lane", "Your casts and channels.")

	Header("Global cooldown")
	local gcdLength = Dropdown("gcdOverride", "GCD length", {
		{ "auto", "By power type", "1.0 s for energy users, 1.5 s otherwise (both measured on Forever)." },
		{ "1.5", "1.5 s" },
		{ "1.0", "1.0 s" },
		{ "custom", "Custom", "The custom value below." },
	}, "How long the GCD lane's windows are.")
	DependsOn(Slider("gcdCustom", "Custom GCD (s)", 0.5, 2.0, 0.1, "Used when GCD length is Custom."), gcdLength, function()
		return Addon:GetSetting("gcdOverride") == "custom"
	end)

	Header("Engine lanes")
	Checkbox("sinkCountdown", "Engine lane countdown",
		"Show the engine's own countdown on engine-drawn lanes (the true remaining time; needs the game's \"show cooldown numbers\" option).")
end

function Options:Open()
	if not category then
		return
	end
	-- OpenToCategory takes the category's numeric id on this client (it hands
	-- it to C_SettingsUtil.OpenSettingsPanel). Passing the category object
	-- first failed there after opening the panel on Blizzard's own pages
	-- under this addon's taint, so their Social page called a protected
	-- function (IsUserOAuthed: ADDON_ACTION_FORBIDDEN). The id goes first;
	-- the object only on a build without one.
	local id = category.GetID and category:GetID() or category.ID
	if id then
		pcall(Settings.OpenToCategory, id)
	else
		pcall(Settings.OpenToCategory, category)
	end
end
