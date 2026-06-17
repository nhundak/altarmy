-- AltArmy TBC — optional CraftLib bridge for recipe skill levels and difficulty bands.

AltArmy = AltArmy or {}
AltArmy.RecipeCraftLib = AltArmy.RecipeCraftLib or {}

local RCL = AltArmy.RecipeCraftLib

local lookupCache = {}
local profKeyCache = {}

local MAX_TBC_SKILL = 375

local function clearTable(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

-- AARRGGBB (WoW |cAARRGGBB format)
local DIFFICULTY_HEX = {
    orange = "ffff8040",
    yellow = "ffffff00",
    green = "ff40ff40",
    gray = "ff808080",
}

local function CraftLibApi()
    return _G.CraftLib
end

local function SpellIdFromItem(itemId)
    if not itemId or not GetItemSpell then
        return nil
    end
    local _, spellId = GetItemSpell(itemId)
    return spellId
end

function RCL.IsAvailable()
    local cl = CraftLibApi()
    if not cl or type(cl.IsReady) ~= "function" then
        return false
    end
    return cl:IsReady() and true or false
end

function RCL.IsValidSkillRequired(value)
    local n = tonumber(value)
    return n ~= nil and n >= 1 and n <= MAX_TBC_SKILL
end

function RCL.ExtractSkillRequired(recipe)
    if not recipe then
        return nil
    end
    local req = tonumber(recipe.skillRequired)
    if RCL.IsValidSkillRequired(req) then
        return req
    end
    return nil
end

function RCL.GetDifficultyColorHex(difficulty)
    if not difficulty then
        return nil
    end
    return DIFFICULTY_HEX[difficulty]
end

function RCL.ResolveProfessionKey(professionName)
    if not professionName or professionName == "" then
        return nil
    end
    local cached = profKeyCache[professionName]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    if not RCL.IsAvailable() then
        profKeyCache[professionName] = false
        return nil
    end
    local CraftLib = CraftLibApi()
    for key, data in pairs(CraftLib:GetProfessions()) do
        if data.name == professionName then
            profKeyCache[professionName] = key
            return key
        end
        if data.id and GetSpellInfo then
            local spellName = GetSpellInfo(data.id)
            if spellName and spellName == professionName then
                profKeyCache[professionName] = key
                return key
            end
        end
    end
    profKeyCache[professionName] = false
    return nil
end

local function LookupRecipeByItemId(CraftLib, itemId)
    if not itemId then
        return nil
    end
    local recipe = CraftLib:GetRecipeByItemId(itemId)
    if recipe then
        return recipe
    end
    local producers = CraftLib:GetRecipeByProduct(itemId)
    if producers and producers[1] and producers[1].recipe then
        return producers[1].recipe
    end
    return nil
end

local function LookupRecipeBySpellId(CraftLib, profKey, spellId)
    if not spellId then
        return nil
    end
    if profKey then
        local recipe = CraftLib:GetRecipeBySpellId(profKey, spellId)
        if recipe then
            return recipe
        end
    end
    for key in pairs(CraftLib:GetProfessions()) do
        local recipe = CraftLib:GetRecipeBySpellId(key, spellId)
        if recipe then
            return recipe
        end
    end
    return nil
end

local function LookupRecipeUncached(professionName, recipeID, resultItemID)
    if not RCL.IsAvailable() then
        return nil
    end
    local CraftLib = CraftLibApi()
    local profKey = RCL.ResolveProfessionKey(professionName)

    if recipeID then
        local recipe = LookupRecipeBySpellId(CraftLib, profKey, recipeID)
        if recipe then
            return recipe
        end
        local spellFromItem = SpellIdFromItem(recipeID)
        if spellFromItem and spellFromItem ~= recipeID then
            recipe = LookupRecipeBySpellId(CraftLib, profKey, spellFromItem)
            if recipe then
                return recipe
            end
        end
        recipe = LookupRecipeByItemId(CraftLib, recipeID)
        if recipe then
            return recipe
        end
    end

    if resultItemID and resultItemID ~= recipeID then
        local recipe = LookupRecipeByItemId(CraftLib, resultItemID)
        if recipe then
            return recipe
        end
        local spellFromResult = SpellIdFromItem(resultItemID)
        if spellFromResult then
            recipe = LookupRecipeBySpellId(CraftLib, profKey, spellFromResult)
            if recipe then
                return recipe
            end
        end
    end

    return nil
end

function RCL.LookupRecipe(professionName, recipeID, resultItemID)
    if not recipeID then
        return nil
    end
    local cacheKey = tostring(professionName or "") .. ":"
        .. tostring(recipeID) .. ":" .. tostring(resultItemID or "")
    if lookupCache[cacheKey] ~= nil then
        if lookupCache[cacheKey] == false then
            return nil
        end
        return lookupCache[cacheKey]
    end
    local recipe = LookupRecipeUncached(professionName, recipeID, resultItemID)
    lookupCache[cacheKey] = recipe or false
    return recipe
end

function RCL.GetDifficulty(recipe, playerSkill)
    if not recipe then
        return nil
    end
    local skill = tonumber(playerSkill) or 0
    local CraftLib = CraftLibApi()
    if CraftLib and type(CraftLib.GetRecipeDifficulty) == "function" then
        return CraftLib:GetRecipeDifficulty(recipe, skill)
    end
    local range = recipe.skillRange
    if not range then
        return "gray"
    end
    if skill < (range.yellow or 0) then
        return "orange"
    elseif skill < (range.green or 0) then
        return "yellow"
    elseif skill < (range.gray or 0) then
        return "green"
    end
    return "gray"
end

--- Enrich a search recipe entry with CraftLib metadata (mutates entry).
function RCL.EnrichEntry(entry)
    if not entry or not RCL.IsAvailable() then
        return entry
    end
    entry.recipeSkillRequired = nil
    entry.difficulty = nil
    local recipe = RCL.LookupRecipe(entry.professionName, entry.recipeID, entry.resultItemID)
    local req = RCL.ExtractSkillRequired(recipe)
    if req then
        entry.recipeSkillRequired = req
        entry.difficulty = RCL.GetDifficulty(recipe, entry.skillRank or 0)
    end
    return entry
end

--- Colored skill cell text: recipeRequired/playerSkill, or player skill only when unknown.
function RCL.FormatSkillCell(recipeRequired, playerSkill, difficulty)
    local req = tonumber(recipeRequired)
    local rank = tonumber(playerSkill) or 0
    if not RCL.IsValidSkillRequired(req) then
        return tostring(rank)
    end
    local hex = RCL.GetDifficultyColorHex(difficulty) or "ffffffff"
    return string.format("|c%s%d|r/%d", hex, req, rank)
end

function RCL.ClearCaches()
    clearTable(lookupCache)
    clearTable(profKeyCache)
end

RCL._LookupRecipeUncached = LookupRecipeUncached
