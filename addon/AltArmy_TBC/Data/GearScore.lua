-- AltArmy TBC — Gear score providers (item level + optional TacoTip / GearScoreTBCClassic).
-- Requires DataStore.lua and DataStoreEquipment.lua loaded first.
-- luacheck: globals C_AddOns IsAddOnLoaded GetAddOnMetadata DEFAULT_CHAT_FRAME TT_GS
-- luacheck: globals GearScoreCalc GEAR_SCORE_CACHE UnitGUID C_Timer

AltArmy = AltArmy or {}
AltArmy.GearScore = AltArmy.GearScore or {}

local GS = AltArmy.GearScore
local DS = AltArmy.DataStore

local itemScoreCache = {}
local HUNTER_RANGED_MULT = 5.3224
local HUNTER_MELEE_MULT = 0.3164

local LEVEL_PROVIDER = {
    id = "level",
    label = "Character Level",
    shortLabel = "Level",
    sortLabel = "Level",
    isAvailable = function()
        return true
    end,
    scoreChar = function(char)
        if DS and DS.GetCharacterLevel then
            return DS:GetCharacterLevel(char)
        end
        return tonumber(char and char.level) or 0
    end,
}

local ILVL_PROVIDER = {
    id = "ilvl",
    label = "Item Level",
    shortLabel = "Item Level",
    sortLabel = "Avg Item Level",
    isAvailable = function()
        return true
    end,
    scoreChar = function(char)
        if DS and DS.GetAverageItemLevel then
            return DS:GetAverageItemLevel(char)
        end
        return 0
    end,
}

local GSTBC_PROVIDER_ID = "gs:GearScoreTBCClassic"
local GSTBC_ADDON_NAME = "GearScoreTBCClassic"
local GSTBC_SCORE_KEY = "GearScoreTBCClassic"
local GEAR_SCORE_SHORT_LABEL = "Gear Score"

local SUPPORTED_GEARSCORE_ADDONS = {
    GSTBC_ADDON_NAME,
}

local function isAddOnLoaded(name)
    if not name then return false end
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if IsAddOnLoaded then
        return IsAddOnLoaded(name)
    end
    return false
end

local function getAddOnTitle(name)
    if GetAddOnMetadata then
        local title = GetAddOnMetadata(name, "Title")
        if title and title ~= "" then return title end
    end
    return name
end

local function getClassFile(char)
    if not char then return "" end
    if DS and DS.GetCharacterClass then
        local _, classFile = DS:GetCharacterClass(char)
        return (classFile or ""):upper()
    end
    return (char.classFile or ""):upper()
end

local function itemCacheKey(item, providerId)
    if type(item) == "string" then return providerId .. ":" .. item end
    if type(item) == "number" then return providerId .. ":id:" .. tostring(item) end
    return nil
end

local function resolveItemLink(item)
    if type(item) == "string" then
        if item:match("^|c") then return item end
        if GetItemInfo then
            local _, link = GetItemInfo(item)
            if link then return link end
        end
        return item
    end
    if type(item) == "number" and GetItemInfo then
        local _, link = GetItemInfo(item)
        if link then return link end
        return "item:" .. tostring(item)
    end
    return nil
end

local function firstScoreValue(scorer, ...)
    local raw = scorer(...)
    return tonumber(raw) or 0
end

local function cachedScore(providerId, item, scorer)
    local link = resolveItemLink(item)
    if not link then return 0 end
    local key = itemCacheKey(item, providerId)
    if key and itemScoreCache[key] ~= nil then
        return itemScoreCache[key]
    end
    local score = firstScoreValue(scorer, item)
    if key then
        itemScoreCache[key] = score
    end
    return score
end

local function scoreItemTacoTip(item)
    local TT = _G.TT_GS
    if not TT or type(TT.GetItemScore) ~= "function" then return 0 end
    return cachedScore("gs_tacotip", item, function(link)
        return TT:GetItemScore(link)
    end)
end

local function getInventoryItem(char, slot)
    if not char or not char.Inventory then return nil end
    return char.Inventory[slot]
end

local function aggregateGearScore(char, scoreItemFn)
    if not char then return 0 end
    local classFile = getClassFile(char)
    local isHunter = classFile == "HUNTER"
    local total = 0

    local function addSlot(slot, hunterMult)
        local item = getInventoryItem(char, slot)
        if not item then return end
        local score = scoreItemFn(item)
        if score <= 0 then return end
        if hunterMult then
            score = score * hunterMult
        end
        total = total + score
    end

    addSlot(17, isHunter and HUNTER_MELEE_MULT or nil)

    for slot = 1, 18 do
        if slot ~= 4 and slot ~= 17 then
            local hunterMult = nil
            if isHunter then
                if slot == 16 then
                    hunterMult = HUNTER_MELEE_MULT
                elseif slot == 18 then
                    hunterMult = HUNTER_RANGED_MULT
                end
            end
            addSlot(slot, hunterMult)
        end
    end

    return math.floor(total)
end

local function getPersistedGearScoreTBCClassic(char)
    if not char or not char.gearScores then return 0 end
    return tonumber(char.gearScores[GSTBC_SCORE_KEY]) or 0
end

local function hasPersistedGearScoreTBCClassic(char)
    return char and char.gearScores and char.gearScores[GSTBC_SCORE_KEY] ~= nil
end

--- True when GearScoreTBCClassic is loaded this session.
function GS.IsGearScoreTBCClassicAvailable()
    return isAddOnLoaded(GSTBC_ADDON_NAME)
end

--- Read the current player's live score from GearScoreTBCClassic's runtime cache.
--- @return number|nil score, or nil when the addon is unavailable
function GS.ReadLivePlayerScoreTBCClassic()
    local calc = _G.GearScoreCalc
    if not calc or type(calc.OnPlayerEquipmentChanged) ~= "function" then
        return nil
    end
    pcall(calc.OnPlayerEquipmentChanged)
    if not UnitGUID then return nil end
    local guid = UnitGUID("player")
    if not guid then return nil end
    local cache = _G.GEAR_SCORE_CACHE
    if type(cache) ~= "table" then return nil end
    local entry = cache[guid]
    if type(entry) ~= "table" then return nil end
    local score = tonumber(entry[1])
    if score == nil then return nil end
    return score
end

--- Persist the current player's GearScoreTBCClassic value into SavedVariables.
function GS.CaptureCurrentCharacterScore()
    if not GS.IsGearScoreTBCClassicAvailable() then return end
    if not DS or not DS.GetCurrentCharacter then return end
    local char = DS:GetCurrentCharacter()
    if not char then return end

    local score = GS.ReadLivePlayerScoreTBCClassic()
    if type(score) ~= "number" or score < 0 then return end

    if score == 0 and hasPersistedGearScoreTBCClassic(char) then
        local existing = tonumber(char.gearScores[GSTBC_SCORE_KEY]) or 0
        if existing > 0 then return end
    end

    char.gearScores = char.gearScores or {}
    char.gearScores[GSTBC_SCORE_KEY] = math.floor(score)
    char.dataVersions = char.dataVersions or {}
    if DS._DATA_VERSIONS and DS._DATA_VERSIONS.gearScores then
        char.dataVersions.gearScores = DS._DATA_VERSIONS.gearScores
    else
        char.dataVersions.gearScores = 1
    end
    if time then
        char.lastUpdate = time()
    end
end

--- True when a persisted GearScoreTBCClassic value is unavailable for display.
function GS.IsScoreMissing(char, providerId)
    if providerId ~= GSTBC_PROVIDER_ID then return false end
    if not GS.IsGearScoreTBCClassicAvailable() then return false end
    return not hasPersistedGearScoreTBCClassic(char)
end

local function makeGearScoreTBCClassicProvider(label)
    return {
        id = GSTBC_PROVIDER_ID,
        label = label,
        shortLabel = GEAR_SCORE_SHORT_LABEL,
        sortLabel = label,
        isAvailable = function()
            return true
        end,
        scoreChar = function(char)
            return getPersistedGearScoreTBCClassic(char)
        end,
    }
end

local function makeTacoTipProvider()
    return {
        id = "gs_tacotip",
        label = "Gear Score (TacoTip)",
        shortLabel = GEAR_SCORE_SHORT_LABEL,
        sortLabel = "Gear Score (TacoTip)",
        isAvailable = function()
            return true
        end,
        scoreChar = function(char)
            return aggregateGearScore(char, scoreItemTacoTip)
        end,
    }
end

local dynamicProviders = {}

local knownGearScoreAddonSet = {}
for i = 1, #SUPPORTED_GEARSCORE_ADDONS do
    knownGearScoreAddonSet[SUPPORTED_GEARSCORE_ADDONS[i]] = true
end

function GS.IsSupportedGearScoreAddon(name)
    return name and knownGearScoreAddonSet[name] == true
end

local function rebuildDynamicProviders(_reason)
    wipe(dynamicProviders)

    if type(_G.TT_GS) == "table" and type(_G.TT_GS.GetItemScore) == "function" then
        dynamicProviders[#dynamicProviders + 1] = makeTacoTipProvider()
    end

    if isAddOnLoaded(GSTBC_ADDON_NAME) then
        local label = "Gear Score (" .. getAddOnTitle(GSTBC_ADDON_NAME) .. ")"
        dynamicProviders[#dynamicProviders + 1] = makeGearScoreTBCClassicProvider(label)
    end
end

function GS._ClearCache()
    wipe(itemScoreCache)
end

function GS.RefreshProviders(reason)
    rebuildDynamicProviders(reason)
end

function GS.GetAvailableProviders()
    if #dynamicProviders == 0 then
        rebuildDynamicProviders("lazy")
    end
    local list = { LEVEL_PROVIDER, ILVL_PROVIDER }
    for i = 1, #dynamicProviders do
        list[#list + 1] = dynamicProviders[i]
    end
    return list
end

function GS.GetProvider(id)
    if id == "level" then return LEVEL_PROVIDER end
    if id == "ilvl" then return ILVL_PROVIDER end
    if #dynamicProviders == 0 then
        rebuildDynamicProviders("lazy")
    end
    for i = 1, #dynamicProviders do
        if dynamicProviders[i].id == id then
            return dynamicProviders[i]
        end
    end
    if id == "gs_lite" then
        for i = 1, #dynamicProviders do
            if dynamicProviders[i].id:sub(1, 3) == "gs:" then
                return dynamicProviders[i]
            end
        end
    end
    return nil
end

function GS.GetProviderShortLabel(id)
    local provider = GS.GetProvider(id)
    if not provider then return "Item Level" end
    return provider.shortLabel or provider.label
end

function GS.GetSortLabels()
    local labels = {}
    for i = 1, #dynamicProviders do
        labels[#labels + 1] = dynamicProviders[i].sortLabel or dynamicProviders[i].label
    end
    return labels
end

function GS.ScoreCharacter(providerId, char)
    local provider = GS.GetProvider(providerId)
    if not provider or not provider.isAvailable() or not provider.scoreChar then
        return 0
    end
    return provider.scoreChar(char) or 0
end

function GS.DecorateEntry(entry, char)
    entry.scores = entry.scores or {}
    entry.scores["Level"] = LEVEL_PROVIDER.scoreChar(char) or 0
    entry.scores["Avg Item Level"] = ILVL_PROVIDER.scoreChar(char) or 0
    for i = 1, #dynamicProviders do
        local p = dynamicProviders[i]
        local sortKey = p.sortLabel or p.label
        entry.scores[sortKey] = p.scoreChar(char) or 0
    end
end

function GS.GetDisplayScore(entry, providerId)
    local provider = GS.GetProvider(providerId)
    if not provider then return 0 end
    local sortKey = provider.sortLabel or provider.label
    if entry and entry.scores and entry.scores[sortKey] ~= nil then
        return entry.scores[sortKey]
    end
    return 0
end

function GS.FormatDisplayScore(providerId, value)
    if providerId == "ilvl" then
        return tostring(math.floor(tonumber(value) or 0))
    end
    return tostring(math.floor(tonumber(value) or 0))
end

-- GearScoreTBCClassic bracket colors (from GearScoreTBCClassic/GearScoreCalc.lua).
local GSTBC_BRACKET_SIZE = 400
local GSTBC_MAX_SCORE = GSTBC_BRACKET_SIZE * 6 - 1

local GSTBC_GS_Quality = {
    [GSTBC_BRACKET_SIZE * 6] = {
        Red = { A = 0.94, B = GSTBC_BRACKET_SIZE * 5, C = 0.00006, D = 1 },
        Green = { A = 0, B = 0, C = 0, D = 0 },
        Blue = { A = 0.47, B = GSTBC_BRACKET_SIZE * 5, C = 0.00047, D = -1 },
        Description = "Legendary",
    },
    [GSTBC_BRACKET_SIZE * 5] = {
        Red = { A = 0.69, B = GSTBC_BRACKET_SIZE * 4, C = 0.00025, D = 1 },
        Green = { A = 0.97, B = GSTBC_BRACKET_SIZE * 4, C = 0.00096, D = -1 },
        Blue = { A = 0.28, B = GSTBC_BRACKET_SIZE * 4, C = 0.00019, D = 1 },
        Description = "Epic",
    },
    [GSTBC_BRACKET_SIZE * 4] = {
        Red = { A = 0.0, B = GSTBC_BRACKET_SIZE * 3, C = 0.00069, D = 1 },
        Green = { A = 1, B = GSTBC_BRACKET_SIZE * 3, C = 0.00003, D = -1 },
        Blue = { A = 0.5, B = GSTBC_BRACKET_SIZE * 3, C = 0.00022, D = -1 },
        Description = "Superior",
    },
    [GSTBC_BRACKET_SIZE * 3] = {
        Red = { A = 0.12, B = GSTBC_BRACKET_SIZE * 2, C = 0.00012, D = -1 },
        Green = { A = 0, B = GSTBC_BRACKET_SIZE * 2, C = 0.001, D = 1 },
        Blue = { A = 1, B = GSTBC_BRACKET_SIZE * 2, C = 0.00050, D = -1 },
        Description = "Uncommon",
    },
    [GSTBC_BRACKET_SIZE * 2] = {
        Red = { A = 1, B = GSTBC_BRACKET_SIZE, C = 0.00088, D = -1 },
        Green = { A = 1, B = GSTBC_BRACKET_SIZE, C = 0.001, D = -1 },
        Blue = { A = 1, B = 0, C = 0.00000, D = 0 },
        Description = "Common",
    },
    [GSTBC_BRACKET_SIZE] = {
        Red = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Green = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Blue = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Description = "Trash",
    },
}

local function getGearScoreTBCClassicColor(gearScore)
    if not gearScore or gearScore <= 0 then
        return 0.55, 0.55, 0.55
    end
    if gearScore > GSTBC_MAX_SCORE then
        gearScore = GSTBC_MAX_SCORE
    end
    for i = 0, 5 do
        if gearScore > i * GSTBC_BRACKET_SIZE and gearScore <= (i + 1) * GSTBC_BRACKET_SIZE then
            local bracket = GSTBC_GS_Quality[(i + 1) * GSTBC_BRACKET_SIZE]
            local r = bracket.Red.A + ((gearScore - bracket.Red.B) * bracket.Red.C) * bracket.Red.D
            local g = bracket.Blue.A + ((gearScore - bracket.Blue.B) * bracket.Blue.C) * bracket.Blue.D
            local b = bracket.Green.A + ((gearScore - bracket.Green.B) * bracket.Green.C) * bracket.Green.D
            return r, g, b
        end
    end
    return 0.55, 0.55, 0.55
end

local function getTacoTipGearScoreColor(score)
    local TT = _G.TT_GS
    if not TT or type(TT.GetQuality) ~= "function" then return nil end
    local r, g, b = TT:GetQuality(tonumber(score) or score)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return r, g, b
end

--- RGB (0–1) for gear-score display, or nil when provider has no band coloring.
function GS.GetDisplayScoreColor(providerId, score)
    if providerId == "level" or providerId == "ilvl" then
        return nil
    end
    if providerId == "gs_tacotip" then
        return getTacoTipGearScoreColor(score)
    end
    if providerId == GSTBC_PROVIDER_ID then
        return getGearScoreTBCClassicColor(score)
    end
    return nil
end

GS.RefreshProviders("addon-load")

if CreateFrame then
    local captureFrame = CreateFrame("Frame", nil, UIParent)
    captureFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    captureFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    captureFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            GS.CaptureCurrentCharacterScore()
            if C_Timer and C_Timer.After then
                C_Timer.After(3, function()
                    GS.CaptureCurrentCharacterScore()
                end)
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            GS.CaptureCurrentCharacterScore()
        end
    end)
end
