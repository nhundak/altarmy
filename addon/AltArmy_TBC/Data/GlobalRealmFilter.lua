-- AltArmy TBC — Single global realm filter for Summary/Gear/Reputation/Search/Cooldowns.
-- Saved under AltArmyTBC_Options.realmFilter ("all" | "currentRealm").
-- Default: currentRealm. One-time migration: if realmFilter was never set, use "all" only
-- when every legacy per-tab setting (Summary, Gear, Reputation, Search) was "all".

if not AltArmy then return end

AltArmy.GlobalRealmFilter = AltArmy.GlobalRealmFilter or {}
local G = AltArmy.GlobalRealmFilter

--- @param tab table|nil
--- @return string|nil "all", "currentRealm", or nil if missing / invalid
local function legacyRealmFromTab(tab)
    if type(tab) ~= "table" then
        return nil
    end
    local v = tab.realmFilter
    if v == "all" or v == "currentRealm" then
        return v
    end
    return nil
end

--- Exported for unit tests: four legacy values (each nil | "all" | "currentRealm").
--- @return string "all" or "currentRealm"
function G.ResolveFromLegacyValues(summary, gear, rep, search)
    if summary == "all" and gear == "all" and rep == "all" and search == "all" then
        return "all"
    end
    return "currentRealm"
end

local function readLegacyTabs()
    return
        legacyRealmFromTab(rawget(_G, "AltArmyTBC_SummarySettings")),
        legacyRealmFromTab(rawget(_G, "AltArmyTBC_GearSettings")),
        legacyRealmFromTab(rawget(_G, "AltArmyTBC_ReputationSettings")),
        legacyRealmFromTab(rawget(_G, "AltArmyTBC_SearchSettings"))
end

function G.MigrateFromLegacyIfNeeded()
    local root = rawget(_G, "AltArmyTBC_Options")
    if not root or type(root) ~= "table" then
        return
    end
    if root.realmFilter ~= nil then
        return
    end
    local s, ge, r, se = readLegacyTabs()
    root.realmFilter = G.ResolveFromLegacyValues(s, ge, r, se)
end

function G.Ensure()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    G.MigrateFromLegacyIfNeeded()
    if AltArmyTBC_Options.realmFilter ~= "all" and AltArmyTBC_Options.realmFilter ~= "currentRealm" then
        AltArmyTBC_Options.realmFilter = "currentRealm"
    end
end

--- @return "all"|"currentRealm"
function G.Get()
    G.Ensure()
    return AltArmyTBC_Options.realmFilter
end

--- @param v "all"|"currentRealm"
function G.Set(v)
    G.Ensure()
    if v == "all" or v == "currentRealm" then
        AltArmyTBC_Options.realmFilter = v
    end
end

G.Ensure()
