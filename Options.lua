-- 4everActionTimeline — the Settings category (docs/SPEC.md, Settings
-- surface split). The client's Settings vertical layout (12.x; Forever has
-- no InterfaceOptions_AddCategory) holds the globals: checkboxes, sliders
-- and dropdowns only - the lane list lives in the addon's own window
-- (/actiontimeline config), and nothing dynamic registers here. Proxy
-- settings read and write through Addon:GetSetting / SetSetting, so every
-- change applies live and is stored at the player layer (only when it
-- differs from the default).
--
-- Dropdown contract on this client (4everSwingTimer, verified against the
-- shipped Blizzard_Settings.lua): CreateDropdown's options argument is
-- CALLED - it must be a function returning the entry list.

local Addon = FourEverActionTimeline

local Options = {}
Addon.Options = Options

local VAR_PREFIX = "4everActionTimeline."
local category

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
	Settings.CreateCheckbox(category, Proxy(key, Settings.VarType.Boolean, name), tooltip)
end

local function Slider(key, name, low, high, step, tooltip)
	local options = Settings.CreateSliderOptions(low, high, step)
	if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	Settings.CreateSlider(category, Proxy(key, Settings.VarType.Number, name), options, tooltip)
end

local function Dropdown(key, name, entries, tooltip)
	local function Entries()
		local container = Settings.CreateControlTextContainer()
		for _, entry in ipairs(entries) do
			container:Add(entry[1], entry[2], entry[3], Settings.ControlType and Settings.ControlType.Radio)
		end
		return container:GetData()
	end
	Settings.CreateDropdown(category, Proxy(key, Settings.VarType.String, name), Entries, tooltip)
end

function Options:Init()
	if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	category = Settings.RegisterVerticalLayoutCategory(Addon.name)
	Settings.RegisterAddOnCategory(category)

	Dropdown("visibility", "Show the timeline", {
		{ "combat", "In combat", "Shown while you are in combat." },
		{ "always", "Always", "Always shown." },
		{ "active", "While active", "Shown while anything is on the timeline: a swing, a cast, a GCD, a cooling spell, a recent mark." },
	}, "When the timeline frame is shown. Test mode and Edit Mode always show it.")

	-- Look
	Dropdown("skin", "Skin", {
		{ "native", "Native", "Blizzard's Encounter Timeline and Cooldown Manager art." },
		{ "flat", "Flat", "Plain lines, square icons, thin borders." },
	}, "The timeline's art. A Native element whose art is missing on this client falls back to Flat.")
	Dropdown("orientation", "Orientation", {
		{ "horizontal", "Horizontal", "Past on the left, future on the right; lanes top to bottom." },
		{ "horizontalFlipped", "Horizontal, flipped", "Future on the left, past on the right." },
		{ "vertical", "Vertical", "Future at the top, past at the bottom; lanes left to right." },
		{ "verticalFlipped", "Vertical, flipped", "Future at the bottom, past at the top." },
	}, "Which way time runs. A flip mirrors the time axis only, never the lane order.")

	-- Time and size
	Slider("pastWindow", "Past window (s)", 2, 10, 0.5, "Seconds shown on the past side of the now line.")
	Slider("futureWindow", "Future window (s)", 2, 15, 0.5, "Seconds shown on the future side of the now line. Predictions further away wait at the far edge.")
	Slider("width", "Length", 200, 900, 10, "The timeline's length along the time axis in pixels; the time scale follows from it.")
	Slider("laneHeight", "Lane height", 16, 48, 1, "Lane height in pixels; icons are 2 pixels smaller.")
	Slider("laneSpacing", "Lane spacing", 0, 16, 1, "Space between lanes in pixels. The Native icon frame overhangs its icon by about a fifth of the icon on each side: raise this if neighbouring frames touch.")
	Slider("scale", "Scale", 0.5, 2.0, 0.05, "Overall scale. Place the frame in Edit Mode.")
	Slider("backgroundAlpha", "Lane background", 0, 0.5, 0.05, "A faint band behind each lane (0 = none).")

	-- Lanes
	Checkbox("showMainhand", "Main-hand lane", "The main-hand swing lane (needs a main-hand weapon).")
	Checkbox("showOffhand", "Off-hand lane", "The off-hand swing lane (needs an off-hand weapon, not a shield or held item).")
	Checkbox("showRanged", "Ranged lane", "The ranged swing lane (needs a ranged weapon or wand).")
	Checkbox("showGcd", "GCD lane", "The global cooldown windows.")
	Checkbox("showCasts", "Cast lane", "Your casts and channels.")

	-- GCD length
	Dropdown("gcdOverride", "GCD length", {
		{ "auto", "By power type", "1.0 s for energy users, 1.5 s otherwise (both measured on Forever)." },
		{ "1.5", "1.5 s" },
		{ "1.0", "1.0 s" },
		{ "custom", "Custom", "The custom value below." },
	}, "How long the GCD lane's windows are.")
	Slider("gcdCustom", "Custom GCD (s)", 0.5, 2.0, 0.1, "Used when GCD length is Custom.")

	-- Engine-drawn lanes
	Checkbox("sinkCountdown", "Engine lane countdown",
		"Show the engine's own countdown on engine-drawn lanes (the true remaining time; needs the game's \"show cooldown numbers\" option).")
end

function Options:Open()
	if not category then
		return
	end
	-- OpenToCategory's argument has shifted between client builds: try the
	-- category, then its numeric id (4everSwingTimer's fallback).
	if not pcall(Settings.OpenToCategory, category) then
		pcall(Settings.OpenToCategory, category.GetID and category:GetID() or nil)
	end
end
