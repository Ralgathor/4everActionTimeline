-- 4everActionTimeline — a live action timeline for WoW: Forever.
-- Core: bootstrap, saved variables, library gate, slash commands.
--
-- The addon holds no swing math of its own: all swing state comes from
-- LibClassicSwingTimerAPI events; nothing here reads UnitAttackSpeed or
-- UnitRangedDamage directly. Design: docs/SPEC.md and docs/VISUAL.md.

local ADDON_NAME = "4everActionTimeline"
local LIB_MAJOR = "LibClassicSwingTimerAPI"
-- The embedded pin is the library's v2.2.0 stable release (LibStub MINOR 37).
local REQUIRED_LIB_MINOR = 37
-- Bumped with every saved-variable shape change; Migrate() upgrades older data.
local SCHEMA_VERSION = 1

FourEverActionTimeline = {}
local Addon = FourEverActionTimeline
Addon.name = ADDON_NAME

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
Addon.version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or UNKNOWN or "?"

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------

-- Settings resolve shipped defaults -> class layer -> player layer (ADR-0002):
-- each layer stores only what changed at its level, so the shipped defaults
-- live in code and are never copied into the saved variables. The player
-- layer is keyed by "Name-Realm" and also holds the calibration cache.
local function NewDB()
	return {
		schemaVersion = SCHEMA_VERSION,
		classes = {},
		players = {},
	}
end

local function Migrate(db)
	-- No older schema exists yet; future versions upgrade db here, one step
	-- per version, before stamping the current one.
	db.schemaVersion = SCHEMA_VERSION
end

local function PlayerKey()
	local name, realm = UnitFullName("player")
	return (name or "?") .. "-" .. (realm or GetRealmName() or "?")
end

-- ---------------------------------------------------------------------------
-- Event dispatch
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
Addon.frame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			if type(FourEverActionTimelineDB) ~= "table" then
				FourEverActionTimelineDB = NewDB()
			end
			Migrate(FourEverActionTimelineDB)
			Addon.db = FourEverActionTimelineDB
		end
	elseif event == "PLAYER_LOGIN" then
		Addon:OnEnable()
	elseif event == "PLAYER_REGEN_DISABLED" then
		Addon.inCombat = true
		Addon.Renderer:UpdateVisibility()
	elseif event == "PLAYER_REGEN_ENABLED" then
		Addon.inCombat = false
		Addon.Renderer:UpdateVisibility()
		-- Secret drops are reported once, after the fight, never mid-combat.
		Addon.Util.ReportDrops()
	end
end)

function Addon:OnEnable()
	local _, classToken = UnitClass("player")
	local db = self.db
	db.classes[classToken] = db.classes[classToken] or {}
	local key = PlayerKey()
	db.players[key] = db.players[key] or {}
	self.classLayer = db.classes[classToken]
	self.playerLayer = db.players[key]

	-- Inert load: a missing or too-old library is a chat notice, never an
	-- error (repo convention).
	local lib, minor = LibStub:GetLibrary(LIB_MAJOR, true)
	if not lib then
		self:Print("LibClassicSwingTimerAPI is missing. The timeline is disabled; the library ships embedded, so a reinstall should fix this.")
		return
	elseif minor < REQUIRED_LIB_MINOR then
		self:Print("LibClassicSwingTimerAPI is too old (needs the 2.2.0 Forever support). The timeline is disabled until the library updates.")
		return
	end
	self.lib = lib
	self.libMinor = minor

	-- A /reload mid-fight starts in combat.
	self.inCombat = InCombatLockdown and InCombatLockdown() or false
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	self.Renderer:Init()
	self.Hands:Init(lib)
end

function Addon:Print(message)
	print("|cff33ccff" .. ADDON_NAME .. "|r: " .. message)
end

-- ---------------------------------------------------------------------------
-- Slash commands: /actiontimeline (alias /atl)
-- ---------------------------------------------------------------------------

SLASH_4EVERACTIONTIMELINE1 = "/actiontimeline"
-- Placeholder short alias; uniqueness is checked before the first publish.
SLASH_4EVERACTIONTIMELINE2 = "/atl"

local function PrintPerf()
	local steady, rebuild, layout, widgets, lanes = Addon.Renderer:Perf()
	if steady.count + rebuild.count + layout.count == 0 then
		Addon:Print("no frame-time samples yet: the timeline has not been shown since the last reset.")
		return
	end
	Addon:Print(format("renderer, %d lanes, %d widgets (budget: under 0.3 ms per frame for 15 lanes):", lanes, widgets))
	Addon:Print(format("  frames: %.3f ms average, %.3f ms worst (%d)", steady.average, steady.worst, steady.count))
	Addon:Print(format("  rebuild frames: %.3f ms average, %.3f ms worst (%d)", rebuild.average, rebuild.worst, rebuild.count))
	if layout.count > 0 then
		Addon:Print(format("  layout frames (first show, widget creation): %.3f ms worst (%d)", layout.worst, layout.count))
	end
	Addon.Renderer:ResetPerf()
end

SlashCmdList["4EVERACTIONTIMELINE"] = function(msg)
	local command, rest = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
	if command == "" or command == "status" then
		if Addon.lib then
			Addon:Print("v" .. Addon.version .. " - library MINOR " .. Addon.libMinor .. ". Live: swing lanes. |cffdddddd/actiontimeline test|r shows every mark with fake events; |cffdddddd/actiontimeline test effects|r replays the swing effects.")
			local keys, shown = Addon.Renderer:Status()
			Addon:Print(format("lanes: %s; visibility %s, %s, frame %s.",
				#keys > 0 and table.concat(keys, ", ") or "none",
				Addon:GetSetting("visibility"), Addon.inCombat and "in combat" or "out of combat",
				shown and "shown" or "hidden"))
		else
			Addon:Print("v" .. Addon.version .. " - inert (library missing or too old).")
		end
	elseif command == "help" then
		Addon:Print("Commands: |cffdddddd/actiontimeline|r (status), test [effects | off], perf, help")
	elseif not Addon.lib then
		Addon:Print("inert (library missing or too old): only status and help are available.")
	elseif command == "test" then
		local TestMode = Addon.TestMode
		if rest == "effects" then
			TestMode:StartEffects()
		elseif rest == "off" or (rest == "" and TestMode:IsRunning()) then
			TestMode:Stop()
			TestMode:StopEffects()
		else
			TestMode:Start()
		end
	elseif command == "perf" then
		PrintPerf()
	else
		Addon:Print("Unknown command: " .. command .. ". Try |cffdddddd/actiontimeline help|r")
	end
end
