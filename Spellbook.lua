-- 4everActionTimeline — spellbook resolution (docs/SPEC.md, Lane set
-- discovery, ADR-0004). A lane is identified by a base (rank 1) spell ID;
-- each session it resolves to the rank the player knows, by name, so rank
-- churn never breaks a lane. The legacy spell-tab functions are gone on
-- Forever (API probe); C_SpellBook and C_Spell are used, nil-guarded.

local Addon = FourEverActionTimeline

local GetSpellName = C_Spell and C_Spell.GetSpellName
local GetSpellInfo = C_Spell and C_Spell.GetSpellInfo
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local IsSpellKnownAPI = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown or IsPlayerSpell
local IsSecret = Addon.Util.IsSecret

local Spellbook = {}
Addon.Spellbook = Spellbook

function Spellbook.IsKnown(spellID)
	return IsSpellKnownAPI and IsSpellKnownAPI(spellID) or false
end

function Spellbook.Name(spellID)
	return GetSpellName and GetSpellName(spellID)
end

function Spellbook.Icon(spellID)
	return GetSpellTexture and GetSpellTexture(spellID)
end

-- The known rank of a base spell: resolved ID and name, or nil (and the
-- name) when the player does not know it.
function Spellbook.Resolve(baseID)
	local name = Spellbook.Name(baseID)
	if not name then
		return nil
	end
	local info = GetSpellInfo and GetSpellInfo(name)
	local id = info and info.spellID
	if id and not IsSecret(id) and Spellbook.IsKnown(id) then
		return id, name
	end
	if Spellbook.IsKnown(baseID) then
		return baseID, name
	end
	return nil, name
end

local GetNumSkillLines = C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
local GetSkillLineInfo = C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo
local GetBookItemInfo = C_SpellBook and C_SpellBook.GetSpellBookItemInfo
local BANK_PLAYER = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local ITEM_SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1

-- Every active spell in the class tabs (not General, not passive), one per
-- name: { id (the lowest rank ID seen), name }, for the lane window.
function Spellbook.ClassSpells()
	local lowest = {}
	if GetNumSkillLines and GetSkillLineInfo and GetBookItemInfo then
		for line = 2, GetNumSkillLines() or 0 do -- line 1 is General
			local info = GetSkillLineInfo(line)
			if info and not info.isGuild and not info.shouldHide then
				local first = (info.itemIndexOffset or 0) + 1
				for slot = first, first + (info.numSpellBookItems or 0) - 1 do
					local item = GetBookItemInfo(slot, BANK_PLAYER)
					local id = item and item.spellID
					if id and not IsSecret(id) and item.itemType == ITEM_SPELL and not item.isPassive then
						local name = Spellbook.Name(id)
						if name and (not lowest[name] or id < lowest[name]) then
							lowest[name] = id
						end
					end
				end
			end
		end
	end
	local spells = {}
	for name, id in pairs(lowest) do
		spells[#spells + 1] = { id = id, name = name }
	end
	table.sort(spells, function(a, b)
		return a.name < b.name
	end)
	return spells
end

-- A spell from a slash argument: an ID, or a spell name the client knows.
-- Returns its ID and name, or nil.
function Spellbook.FromArgument(text)
	local id = tonumber(text)
	if not id then
		local info = GetSpellInfo and GetSpellInfo(text)
		id = info and info.spellID
	end
	if not id or IsSecret(id) then
		return nil
	end
	return id, Spellbook.Name(id)
end
