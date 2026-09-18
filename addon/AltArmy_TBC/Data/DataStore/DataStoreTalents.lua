-- AltArmy TBC — Talent / spec tracking for gear upgrade comparisons.
-- Requires DataStore.lua loaded first.
-- luacheck: globals GetNumTalentTabs GetTalentTabInfo PlayerTalentFrame

if not AltArmy or not AltArmy.DataStore then return end

AltArmy.DataStoreTalents = AltArmy.DataStoreTalents or {}

local DS = AltArmy.DataStore
local DT = AltArmy.DataStoreTalents
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local SPEC_KEYS_BY_CLASS = {
    WARRIOR = { "arms", "fury", "protection" },
    PALADIN = { "holy", "protection", "retribution" },
    HUNTER = { "beast", "marksmanship", "survival" },
    ROGUE = { "assassination", "combat", "subtlety" },
    PRIEST = { "discipline", "holy", "shadow" },
    SHAMAN = { "elemental", "enhancement", "restoration" },
    MAGE = { "arcane", "fire", "frost" },
    WARLOCK = { "affliction", "demonology", "destruction" },
    DRUID = { "balance", "feral", "restoration" },
}

local LEVELING_SPEC_BY_CLASS = {
    WARRIOR = "fury",
    PALADIN = "retribution",
    HUNTER = "beast",
    ROGUE = "combat",
    PRIEST = "shadow",
    SHAMAN = "enhancement",
    MAGE = "frost",
    WARLOCK = "affliction",
    DRUID = "feral",
}

local function normalizeClassFile(classFile)
    return (classFile or ""):upper()
end

--- Tab index (1-based) with the most points spent, or nil if none spent.
function DT.DerivePrimaryTabIndex(tabs)
    if not tabs or #tabs == 0 then return nil end
    local bestIdx, bestPts = nil, 0
    for i = 1, #tabs do
        local pts = tonumber(tabs[i]) or 0
        if pts > bestPts then
            bestPts = pts
            bestIdx = i
        end
    end
    if bestPts <= 0 then return nil end
    return bestIdx
end

function DT.GetSpecKeyForTab(classFile, tabIndex)
    classFile = normalizeClassFile(classFile)
    local list = SPEC_KEYS_BY_CLASS[classFile]
    if not list or not tabIndex then return nil end
    return list[tabIndex]
end

function DT.GetLevelingSpecKey(classFile)
    return LEVELING_SPEC_BY_CLASS[normalizeClassFile(classFile)] or "unknown"
end

--- Level at which TBC Classic characters gain their first talent point / the Talents tab unlocks.
DT.TALENT_UNLOCK_LEVEL = 10

--- Whether a character is high enough level to have any talents to speak of.
function DT.IsTalentEligible(char)
    local level = tonumber(char and char.level) or 0
    return level >= DT.TALENT_UNLOCK_LEVEL
end

function DT.HasTalentData(char)
    if not char or not char.talents or char.talents.tabs == nil then
        return false
    end
    return true
end

--- Returns specKey, isKnown (true when talent data was scanned and primary tab is decisive).
function DT.ResolveSpecKey(char)
    if not char then
        return "unknown", false
    end
    local classFile = normalizeClassFile(char.classFile)
    if DT.HasTalentData(char) and char.talents.specKey then
        local primary = char.talents.primary
        if primary and primary > 0 then
            return char.talents.specKey, true
        end
    end
    return DT.GetLevelingSpecKey(classFile), false
end

function DS:GetCharacterSpec(char)
    return DT.ResolveSpecKey(char)
end

function DS:HasTalentData(char)
    return DT.HasTalentData(char)
end

local function readTalentTabs()
    if not GetNumTalentTabs or not GetTalentTabInfo then return nil end
    local numTabs = GetNumTalentTabs()
    if not numTabs or numTabs <= 0 then return nil end
    local tabs = {}
    for i = 1, numTabs do
        local _, _, _, _, pointsSpent = GetTalentTabInfo(i)
        tabs[i] = tonumber(pointsSpent) or 0
    end
    return tabs
end

function DS:ScanTalents(_self)
    local char = GetCurrentCharTable and GetCurrentCharTable() or nil
    if not char then return end
    local tabs = readTalentTabs()
    if not tabs then return end
    local classFile = normalizeClassFile(char.classFile)
    local primary = DT.DerivePrimaryTabIndex(tabs)
    local specKey = primary and DT.GetSpecKeyForTab(classFile, primary) or nil
    char.talents = {
        tabs = tabs,
        primary = primary,
        specKey = specKey,
    }
    char.dataVersions = char.dataVersions or {}
    if DATA_VERSIONS and DATA_VERSIONS.talents then
        char.dataVersions.talents = DATA_VERSIONS.talents
    else
        char.dataVersions.talents = 1
    end
    char.lastUpdate = time and time() or char.lastUpdate
end

if CreateFrame then
    local talentFrame = CreateFrame("Frame")
    talentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    talentFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    talentFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    -- GetNumTalentTabs/GetTalentTabInfo return no data (numTabs == 0) until the lazy-loaded classic
    -- talent UI has actually been opened once this session — CHARACTER_POINTS_CHANGED/
    -- PLAYER_TALENT_UPDATE alone don't fire from merely opening the window with no points spent, so
    -- without this the "Open your Talents window" instruction never actually clears itself.
    talentFrame:RegisterEvent("ADDON_LOADED")
    talentFrame:SetScript("OnEvent", function(_, event, addonName)
        if event == "PLAYER_ENTERING_WORLD" then
            if DS.ScanTalents then
                DS:ScanTalents()
            end
        elseif event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
            if DS.ScanTalents then
                DS:ScanTalents()
            end
        elseif event == "ADDON_LOADED" and addonName == "Blizzard_TalentUI" then
            if DS.ScanTalents then
                DS:ScanTalents()
            end
            if PlayerTalentFrame and PlayerTalentFrame.HookScript then
                PlayerTalentFrame:HookScript("OnShow", function()
                    if DS.ScanTalents then
                        DS:ScanTalents()
                    end
                end)
            end
        end
    end)
end
