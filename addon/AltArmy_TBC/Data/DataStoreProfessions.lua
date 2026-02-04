-- AltArmy TBC — DataStore module: professions (skills + recipes).
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local SkillTypeToColor = { header = 0, optimal = 1, medium = 2, easy = 3, trivial = 4 }
local SPELL_ID_FIRSTAID = 3273
local SPELL_ID_COOKING = 2550
local SPELL_ID_FISHING = 7732

local headersState = {}
local function SaveTradeSkillHeaders()
    for k in pairs(headersState) do headersState[k] = nil end
    local headerCount = 0
    if not GetNumTradeSkills then return end
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType, _, _, isExpanded = GetTradeSkillInfo(i)
        if skillType == "header" then
            headerCount = headerCount + 1
            if not isExpanded and ExpandTradeSkillSubClass then
                ExpandTradeSkillSubClass(i)
                headersState[headerCount] = true
            end
        end
    end
end

local function RestoreTradeSkillHeaders()
    local headerCount = 0
    if not GetNumTradeSkills then return end
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType = GetTradeSkillInfo(i)
        if skillType == "header" then
            headerCount = headerCount + 1
            if headersState[headerCount] and CollapseTradeSkillSubClass then
                CollapseTradeSkillSubClass(i)
            end
        end
    end
    for k in pairs(headersState) do headersState[k] = nil end
end

function DS:ScanProfessionLinks(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumSkillLines or not GetSkillLineInfo then return end
    char.Professions = char.Professions or {}
    char.Prof1 = nil
    char.Prof2 = nil
    for i = GetNumSkillLines(), 1, -1 do
        local _, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and not isExpanded and ExpandSkillHeader then
            ExpandSkillHeader(i)
        end
    end
    local category
    for i = 1, GetNumSkillLines() do
        local skillName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not skillName then break end
        if isHeader then
            category = skillName
        else
            if category and skillName then
                local isPrimary = (category == "Professions")
                local isSecondary = (category == "Secondary Skills")
                if isPrimary or isSecondary then
                    if skillName == "Secourisme" and GetSpellInfo then
                        skillName = GetSpellInfo(SPELL_ID_FIRSTAID) or skillName
                    end
                    local prof = char.Professions[skillName]
                    if not prof then
                        prof = { rank = 0, maxRank = 0, Recipes = {} }
                        char.Professions[skillName] = prof
                    end
                    prof.rank = rank or 0
                    prof.maxRank = maxRank or 0
                    if isPrimary then prof.isPrimary = true end
                    if isSecondary then prof.isSecondary = true end
                    if isPrimary then
                        if not char.Prof1 then char.Prof1 = skillName
                        else char.Prof2 = skillName end
                    end
                end
            end
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
end

function DS:ScanRecipes(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    local tradeskillName = GetTradeSkillLine and GetTradeSkillLine()
    if not tradeskillName or tradeskillName == "" or tradeskillName == "UNKNOWN" then return end
    if tradeskillName == "Secourisme" and GetSpellInfo then
        tradeskillName = GetSpellInfo(SPELL_ID_FIRSTAID) or tradeskillName
    end
    local numTradeSkills = GetNumTradeSkills and GetNumTradeSkills()
    if not numTradeSkills or numTradeSkills == 0 then return end
    local _, skillType = GetTradeSkillInfo(1)
    if skillType ~= "header" and skillType ~= "subheader" then return end
    local prof = char.Professions[tradeskillName]
    if not prof then
        prof = { rank = 0, maxRank = 0, Recipes = {} }
        char.Professions[tradeskillName] = prof
    end
    prof.Recipes = prof.Recipes or {}
    for k in pairs(prof.Recipes) do prof.Recipes[k] = nil end
    for i = 1, numTradeSkills do
        local _, recipeSkillType = GetTradeSkillInfo(i)
        local color = SkillTypeToColor[recipeSkillType]
        if color and recipeSkillType ~= "header" and recipeSkillType ~= "subheader" then
            local recipeID
            if GetTradeSkillRecipeLink then
                local link = GetTradeSkillRecipeLink(i)
                if link then
                    recipeID = tonumber(link:match("enchant:(%d+)"))
                end
                if not recipeID and GetTradeSkillItemLink then
                    local itemLink = GetTradeSkillItemLink(i)
                    if itemLink then
                        recipeID = tonumber(itemLink:match("item:(%d+)"))
                    end
                end
            elseif GetTradeSkillItemLink then
                local itemLink = GetTradeSkillItemLink(i)
                if itemLink then
                    recipeID = tonumber(itemLink:match("item:(%d+)"))
                end
            end
            if recipeID then
                prof.Recipes[recipeID] = color
            end
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
end

function DS:RunDeferredRecipeScan()
    SaveTradeSkillHeaders()
    self:ScanRecipes()
    RestoreTradeSkillHeaders()
end

function DS:GetProfessions(char)
    return (char and char.Professions) or {}
end

function DS:GetProfession(char, name)
    if not char or not char.Professions or not name then return nil end
    return char.Professions[name]
end

function DS:GetProfession1(char)
    if not char then return 0, 0, nil end
    local name = char.Prof1
    if not name then return 0, 0, nil end
    local prof = char.Professions and char.Professions[name]
    if not prof then return 0, 0, name end
    return prof.rank or 0, prof.maxRank or 0, name
end

function DS:GetProfession2(char)
    if not char then return 0, 0, nil end
    local name = char.Prof2
    if not name then return 0, 0, nil end
    local prof = char.Professions and char.Professions[name]
    if not prof then return 0, 0, name end
    return prof.rank or 0, prof.maxRank or 0, name
end

function DS:GetCookingRank(char)
    if not char or not GetSpellInfo then return 0, 0 end
    local name = GetSpellInfo(SPELL_ID_COOKING)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetFishingRank(char)
    if not char or not GetSpellInfo then return 0, 0 end
    local name = GetSpellInfo(SPELL_ID_FISHING)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetFirstAidRank(char)
    if not char or not GetSpellInfo then return 0, 0 end
    local name = GetSpellInfo(SPELL_ID_FIRSTAID)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetNumRecipes(char, profName)
    if not char or not char.Professions or not profName then return 0 end
    local prof = char.Professions[profName]
    if not prof or not prof.Recipes then return 0 end
    local n = 0
    for _ in pairs(prof.Recipes) do n = n + 1 end
    return n
end

function DS:IsRecipeKnown(char, profName, spellID)
    if not char or not char.Professions or not profName or not spellID then return false end
    local prof = char.Professions[profName]
    if not prof or not prof.Recipes then return false end
    return prof.Recipes[spellID] ~= nil
end
