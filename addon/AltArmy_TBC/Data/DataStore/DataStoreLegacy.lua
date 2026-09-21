-- AltArmy TBC — Legacy Talent tracking (WoW Forever's account-wide Legacy Points system).
-- Requires DataStore.lua loaded first.
--
-- Speculative API surface: as of 2026-09-21, Blizzard has published no addon-facing documentation
-- for the Legacy system (see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Legacy Talents"). The
-- best community evidence (Thunderz96/forever-addon-kit, a beta addon-dev findings repo) confirms
-- only that "both [class talents and Legacy trees] run on Retail's trait system (C_Traits)" and
-- that the panel opens via ToggleLegacySystemUI at level 25 — no confirmed config/tree/node IDs or
-- exact function signatures exist yet. This module calls the same C_Traits chain Retail's own class
-- talent trees use (GetNodeInfo/GetEntryInfo/GetDefinitionInfo), behind existence checks and pcall
-- throughout, so a wrong guess makes it silently capture nothing rather than error — same
-- "existence check over version check" house style as DataStoreTalents.lua's C_SpecializationInfo
-- fallback. Every candidate is also tracked in ApiCheck.lua so a real Forever login can confirm or
-- correct these guesses via /altarmy debug apicheck.
-- luacheck: globals C_Traits C_ClassTalents C_Spell GetSpellInfo C_EventUtils

if not AltArmy or not AltArmy.DataStore then return end

AltArmy.DataStoreLegacy = AltArmy.DataStoreLegacy or {}

local DS = AltArmy.DataStore
local DL = AltArmy.DataStoreLegacy
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

-- Rest-XP legacy talent: no confirmed node ID, so matched by resolved spell/entry name instead (see
-- module header). "Well Rested" (WoW Forever's Legacy Adventure tree, per Wowhead/Icy Veins Legacy
-- System guides): +4% rested-XP cap and +4% rested-XP accumulation rate per rank, up to 5 ranks
-- (20% at max rank). English name only — no locale handling, since none of the sources this doc
-- cites confirm localized strings yet.
DL.REST_TALENT_NAMES = { "Well Rested" }
DL.REST_TALENT_PERCENT_PER_RANK = 0.04
DL.REST_TALENT_MAX_RANK = 5

local function API_GetActiveConfigID()
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
        if ok and configID then return configID end
    end
    return nil
end

local function getSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then return info.name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok then return name end
    end
    return nil
end

local function isRestTalentName(name)
    if not name then return false end
    for i = 1, #DL.REST_TALENT_NAMES do
        if name == DL.REST_TALENT_NAMES[i] then return true end
    end
    return false
end

--- Resolves a node's display name via its first entry's definition/spell, existence-checked and
--- pcall-guarded throughout the C_Traits call chain (GetNodeInfo -> entryIDs -> GetEntryInfo ->
--- definitionID -> GetDefinitionInfo -> spellID/overriddenName). Returns nil if any link is missing.
local function resolveNodeName(configID, nodeID)
    if not C_Traits or not C_Traits.GetNodeInfo then return nil end
    local ok, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or not nodeInfo or not nodeInfo.entryIDs or not nodeInfo.entryIDs[1] then return nil end
    if not C_Traits.GetEntryInfo then return nil end
    local okEntry, entryInfo = pcall(C_Traits.GetEntryInfo, configID, nodeInfo.entryIDs[1])
    if not okEntry or not entryInfo or not entryInfo.definitionID then return nil end
    if not C_Traits.GetDefinitionInfo then return nil end
    local okDef, defInfo = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
    if not okDef or not defInfo then return nil end
    if defInfo.overriddenName and defInfo.overriddenName ~= "" then return defInfo.overriddenName end
    return getSpellName(defInfo.spellID)
end

local function getNodeRank(configID, nodeID)
    if not C_Traits or not C_Traits.GetNodeInfo then return 0 end
    local ok, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
    if not ok or not nodeInfo then return 0 end
    return tonumber(nodeInfo.activeRank or nodeInfo.currentRank) or 0
end

--- True when the C_Traits call chain this module relies on is present at all (regardless of
--- whether a config/tree actually resolves) — lets callers distinguish "API missing entirely"
--- (e.g. TBC Classic) from "API present, nothing spent yet".
function DL.HasTraitsApi()
    return C_Traits ~= nil and C_Traits.GetTreeNodes ~= nil and C_Traits.GetNodeInfo ~= nil
end

--- Scans every node across every tree of the active trait config, returning nodeID->rank for every
--- node with at least one point spent, the total ranks spent, and the rank of the rest-XP legacy
--- talent if one was found by name. Returns nil (not an empty result) when the API chain, the
--- active config, or the config's tree list can't be resolved at all, so callers can tell
--- "nothing captured because unavailable" apart from "captured, zero spent".
function DL.ScanActiveConfig()
    if not DL.HasTraitsApi() then return nil end
    local configID = API_GetActiveConfigID()
    if not configID then return nil end
    if not C_Traits.GetConfigInfo then return nil end
    local ok, configInfo = pcall(C_Traits.GetConfigInfo, configID)
    if not ok or not configInfo or not configInfo.treeIDs then return nil end

    local nodes, totalRanks, restRank = {}, 0, 0
    for _, treeID in ipairs(configInfo.treeIDs) do
        local okNodes, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
        if okNodes and nodeIDs then
            for _, nodeID in ipairs(nodeIDs) do
                local rank = getNodeRank(configID, nodeID)
                if rank > 0 then
                    nodes[nodeID] = rank
                    totalRanks = totalRanks + rank
                    if isRestTalentName(resolveNodeName(configID, nodeID)) then
                        restRank = rank
                    end
                end
            end
        end
    end
    return { nodes = nodes, totalRanksSpent = totalRanks, restRank = restRank }
end

function DS:ScanLegacyTalents(_self)
    local char = GetCurrentCharTable and GetCurrentCharTable() or nil
    if not char then return end
    local result = DL.ScanActiveConfig()
    if not result then
        -- Leave any previously-captured data alone; nil just means the API wasn't
        -- resolvable this scan (e.g. TBC Classic, or the guess above needs correcting).
        return
    end
    char.legacyTalents = result
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.legacyTalents = (DATA_VERSIONS and DATA_VERSIONS.legacyTalents) or 1
    char.lastUpdate = time and time() or char.lastUpdate
end

--- Rest-XP multiplier (cap and accumulation rate) from the captured "Well Rested" legacy talent
--- rank; 1 (no change) when unavailable, unscanned, or zero ranks spent. See DataStoreCharacter.lua
--- GetRestXp/GetStoredRestXp.
function DL.GetRestXpMultiplier(char)
    local rank = tonumber(char and char.legacyTalents and char.legacyTalents.restRank) or 0
    if rank <= 0 then return 1 end
    if rank > DL.REST_TALENT_MAX_RANK then rank = DL.REST_TALENT_MAX_RANK end
    return 1 + (rank * DL.REST_TALENT_PERCENT_PER_RANK)
end

if CreateFrame then
    local legacyFrame = CreateFrame("Frame")

    --- Same SafeRegisterEvent pattern as DataStoreTalents.lua / DataStore.lua: TRAIT_CONFIG_UPDATED
    --- doesn't exist on TBC Classic, so this must never hard-error RegisterEvent there.
    local function SafeRegisterLegacyEvent(eventName)
        if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(eventName) then
            return
        end
        pcall(legacyFrame.RegisterEvent, legacyFrame, eventName)
    end

    SafeRegisterLegacyEvent("PLAYER_ENTERING_WORLD")
    SafeRegisterLegacyEvent("TRAIT_CONFIG_UPDATED")
    legacyFrame:SetScript("OnEvent", function()
        if DS.ScanLegacyTalents then
            DS:ScanLegacyTalents()
        end
    end)
end
