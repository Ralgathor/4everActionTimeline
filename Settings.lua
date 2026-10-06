-- 4everActionTimeline — settings resolution.
-- The Settings-category globals resolve shipped defaults -> player layer
-- (docs/SPEC.md, Storage model). The player layer stores only values that
-- differ from the default, so a release that improves a default reaches
-- everyone who never changed it. The lane set's three-layer resolve
-- (ADR-0002) joins in M4.

local Addon = FourEverActionTimeline

local DEFAULTS = {
	pastWindow = 5, -- seconds left of the now line
	futureWindow = 5, -- seconds right of the now line
	width = 420, -- pixels; the time scale follows from it
	laneHeight = 26, -- pixels; icons are laneHeight - 2
	laneSpacing = 4,
	scale = 1.0,
	visibility = "combat", -- "combat" | "always" | "active"
	backgroundAlpha = 0, -- a faint band behind each lane
}
Addon.DEFAULTS = DEFAULTS

function Addon:GetSetting(key)
	local layer = self.playerLayer and self.playerLayer.settings
	local value = layer and layer[key]
	if value == nil then
		value = DEFAULTS[key]
	end
	return value
end

function Addon:SetSetting(key, value)
	assert(DEFAULTS[key] ~= nil, "unknown setting " .. tostring(key))
	local player = self.playerLayer
	if not player then
		return
	end
	player.settings = player.settings or {}
	if value == DEFAULTS[key] then
		value = nil
	end
	player.settings[key] = value
	if self.Renderer then
		self.Renderer:MarkLayoutDirty()
		self.Renderer:UpdateVisibility()
	end
end
