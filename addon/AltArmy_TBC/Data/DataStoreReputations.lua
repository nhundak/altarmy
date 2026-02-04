-- AltArmy TBC — DataStore module: reputations.
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local FACTION_STANDING_THRESHOLDS = { 0, 36000, 78000, 108000, 129000, 150000, 171000, 192000 }
-- Labels by threshold index: 0, 36000, 78000, ...; test expects 36000-78000 = Friendly
local FACTION_STANDING_LABELS = {
    "Hated", "Friendly", "Unfriendly", "Neutral", "Hostile", "Honored", "Revered", "Exalted",
}

local factionHeadersState = {}
local function SaveFactionHeaders()
    for k in pairs(factionHeadersState) do factionHeadersState[k] = nil end
    local headerCount = 0
    if not GetNumFactions then return end
    for i = GetNumFactions(), 1, -1 do
        local _, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i)
        if isHeader then
            headerCount = headerCount + 1
            if isCollapsed and ExpandFactionHeader then
                ExpandFactionHeader(i)
                factionHeadersState[headerCount] = true
            end
        end
    end
end

local function RestoreFactionHeaders()
    local headerCount = 0
    if not GetNumFactions then return end
    for i = GetNumFactions(), 1, -1 do
        local _, _, _, _, _, _, _, _, isHeader = GetFactionInfo(i)
        if isHeader then
            headerCount = headerCount + 1
            if factionHeadersState[headerCount] and CollapseFactionHeader then
                CollapseFactionHeader(i)
            end
        end
    end
    for k in pairs(factionHeadersState) do factionHeadersState[k] = nil end
end

local function GetReputationLimits(earned)
    local bottom, top = 0, 42000
    for i = 1, #FACTION_STANDING_THRESHOLDS do
        if earned >= FACTION_STANDING_THRESHOLDS[i] then
            bottom = FACTION_STANDING_THRESHOLDS[i]
        end
    end
    for i = 1, #FACTION_STANDING_THRESHOLDS - 1 do
        if FACTION_STANDING_THRESHOLDS[i] == bottom then
            top = FACTION_STANDING_THRESHOLDS[i + 1]
            break
        end
    end
    if top == 0 then top = 42000 end
    return bottom, top
end
DS._GetReputationLimits = GetReputationLimits

function DS:ScanReputations()
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumFactions or not GetFactionInfo then return end
    char.Reputations = char.Reputations or {}
    for k in pairs(char.Reputations) do char.Reputations[k] = nil end
    SaveFactionHeaders()
    for i = 1, GetNumFactions() do
        local _, _, standingID, barMin, _, barValue, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
        if not isHeader and factionID and factionID > 0 then
            local earned
            if standingID and barMin and barValue then
                local threshold = FACTION_STANDING_THRESHOLDS[standingID]
                if threshold then
                    earned = threshold + (barValue - barMin)
                else
                    earned = barValue
                end
            else
                earned = 0
            end
            char.Reputations[factionID] = earned
        end
    end
    RestoreFactionHeaders()
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.reputations = DATA_VERSIONS.reputations
end

function DS:GetReputations(char)
    return (char and char.Reputations) or {}
end

function DS:GetReputationInfo(char, factionID)
    if not char or not char.Reputations or not factionID then return nil, 0, 0, 0 end
    local earned = char.Reputations[factionID]
    if earned == nil then return nil, 0, 0, 0 end
    local bottom, top = GetReputationLimits(earned)
    local standing = FACTION_STANDING_LABELS[1]
    for i = 1, #FACTION_STANDING_THRESHOLDS do
        if FACTION_STANDING_THRESHOLDS[i] == bottom then
            standing = FACTION_STANDING_LABELS[i] or standing
            break
        end
    end
    local repEarned = earned - bottom
    local nextLevel = top - bottom
    local rate = (nextLevel > 0) and (repEarned / nextLevel * 100) or 100
    return standing, repEarned, nextLevel, rate
end

function DS:IterateReputations(char, callback)
    if not char or not char.Reputations or not callback then return end
    for factionID, earned in pairs(char.Reputations) do
        local standing, repEarned, nextLevel, rate = self:GetReputationInfo(char, factionID)
        if callback(factionID, earned, standing, repEarned, nextLevel, rate) then
            return
        end
    end
end
