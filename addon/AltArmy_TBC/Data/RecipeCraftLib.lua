-- AltArmy TBC — optional CraftLib bridge for recipe skill levels and difficulty bands.

AltArmy = AltArmy or {}
AltArmy.RecipeCraftLib = AltArmy.RecipeCraftLib or {}

local RCL = AltArmy.RecipeCraftLib

local lookupCache = {}
local profKeyCache = {}

local function clearTable(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local DIFFICULTY_HEX = {
    orange = "ffff8040",
    yellow = "ffffff00",
    green = "ff40c040",
    gray = "ff808080",
}

local function CraftLibApi()
    return _G.CraftLib
end

function RCL.IsAvailable()
    local cl = CraftLibApi()
    if not cl or type(cl.IsReady) ~= "function" then
        return false
    end
    return cl:IsReady() and true or false
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

local function LookupRecipeUncached(professionName, recipeID, resultItemID)
    if not RCL.IsAvailable() then
        return nil
    end
    local CraftLib = CraftLibApi()
    local profKey = RCL.ResolveProfessionKey(professionName)
    if profKey and recipeID then
        local recipe = CraftLib:GetRecipeBySpellId(profKey, recipeID)
        if recipe then
            return recipe
        end
    end
    if resultItemID then
        local recipe = CraftLib:GetRecipeByItemId(resultItemID)
        if recipe then
            return recipe
        end
        local producers = CraftLib:GetRecipeByProduct(resultItemID)
        if producers and producers[1] and producers[1].recipe then
            return producers[1].recipe
        end
    end
    return nil
end

function RCL.LookupRecipe(professionName, recipeID, resultItemID)
    if not recipeID then
        return nil
    end
    local cacheKey = tostring(professionName or "") .. ":" .. tostring(recipeID)
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
    local recipe = RCL.LookupRecipe(entry.professionName, entry.recipeID, entry.resultItemID)
    if recipe then
        entry.recipeSkillRequired = recipe.skillRequired
        entry.difficulty = RCL.GetDifficulty(recipe, entry.skillRank or 0)
    end
    return entry
end

--- Colored skill cell text: recipeRequired/playerSkill, or player skill only when unknown.
function RCL.FormatSkillCell(recipeRequired, playerSkill, difficulty)
    local rank = tonumber(playerSkill) or 0
    if not recipeRequired then
        return tostring(rank)
    end
    local hex = RCL.GetDifficultyColorHex(difficulty) or "ffffffff"
    return string.format("|cff%s%d|r/%d", hex, recipeRequired, rank)
end

function RCL.ClearCaches()
    clearTable(lookupCache)
    clearTable(profKeyCache)
end

RCL._LookupRecipeUncached = LookupRecipeUncached
