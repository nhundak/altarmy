-- AltArmy TBC — DataStore module: item/spell info compatibility shims.
-- Requires DataStore.lua (core) loaded first.
--
-- Some clients (e.g. WoW Forever beta, interface 16001 — see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md) don't expose the legacy
-- GetItemInfo/GetItemInfoInstant/GetItemStats/IsUsableItem/GetSpellInfo/
-- GetSpellLink globals at all; C_Item/C_Spell are the retail-shaped
-- replacements. These wrappers try the legacy global first (checked
-- dynamically on every call, never captured as a load-time upvalue — see
-- the Reputations lesson in WOW_FOREVER_COMPATIBILITY_RESEARCH.md, a stale
-- captured reference silently breaks both real fallback and unit tests that
-- stub globals after load) and fall back to the namespaced API, returning
-- the SAME tuple shape as the legacy call so callers don't need to change
-- their destructuring/select() logic when switching to these.
--
-- The C_Item field/return shapes are expected to match the legacy globals
-- (both still coexist on real retail as of this writing); the C_Spell
-- fallback is a genuine shape change (table instead of multi-return) and is
-- unpacked here to the legacy positions. None of this is verified against a
-- live Forever client yet — flagged the same way as the rest of that doc.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore

--- Same tuple as legacy GetItemInfo(item):
--- name, link, quality, iLevel, minLevel, itemType, itemSubType, stackCount,
--- equipLoc, texture, sellPrice, classID, subclassID, bindType, expacID,
--- setID, isCraftingReagent
function DS.CompatGetItemInfo(item)
    if GetItemInfo then
        return GetItemInfo(item)
    end
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    end
end

--- Same tuple as legacy GetItemInfoInstant(item):
--- itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
function DS.CompatGetItemInfoInstant(item)
    if GetItemInfoInstant then
        return GetItemInfoInstant(item)
    end
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(item)
    end
end

--- Same as legacy GetItemStats(itemLink[, statTable]) -> table
function DS.CompatGetItemStats(itemLink, statTable)
    if GetItemStats then
        return GetItemStats(itemLink, statTable)
    end
    if C_Item and C_Item.GetItemStats then
        return C_Item.GetItemStats(itemLink, statTable)
    end
end

--- Same as legacy IsUsableItem(item) -> isUsable, notEnoughMana
function DS.CompatIsUsableItem(item)
    if IsUsableItem then
        return IsUsableItem(item)
    end
    if C_Item and C_Item.IsUsableItem then
        return C_Item.IsUsableItem(item)
    end
end

--- Same tuple as legacy GetSpellInfo(spellIDOrName):
--- name, rank, icon, castTime, minRange, maxRange, spellID
--- C_Spell.GetSpellInfo returns a table (name, iconID, castTime, minRange,
--- maxRange, spellID) with no "rank" field (spell ranks are a TBC-and-
--- earlier concept) — rank is always nil via that fallback path.
function DS.CompatGetSpellInfo(spellID)
    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if not info then return nil end
        return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
    end
end

--- Same as legacy GetSpellLink(spellID)
function DS.CompatGetSpellLink(spellID)
    if GetSpellLink then
        return GetSpellLink(spellID)
    end
    if C_Spell and C_Spell.GetSpellLink then
        return C_Spell.GetSpellLink(spellID)
    end
end
