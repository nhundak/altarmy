-- AltArmy TBC — optional CraftLib bridge for recipe skill levels and difficulty bands.

AltArmy = AltArmy or {}
AltArmy.RecipeCraftLib = AltArmy.RecipeCraftLib or {}

local RCL = AltArmy.RecipeCraftLib

local lookupCache = {}
local profKeyCache = {}
-- Static CraftLib fields keyed by profession+recipeID(+resultItemID); difficulty stays per skillRank.
local enrichStaticCache = {}

local MAX_TBC_SKILL = 375
local SPELL_ID_POISONS = 2842

local function isPoisonsProfession(professionName)
    if not professionName or professionName == "" then
        return false
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.ResolveProfessionKey and SS.ResolveProfessionKey(professionName) == "poisons" then
        return true
    end
    if GetSpellInfo then
        local poisonsName = GetSpellInfo(SPELL_ID_POISONS)
        if poisonsName and poisonsName == professionName then
            local alchemyName = GetSpellInfo(2259)
            if alchemyName and alchemyName == poisonsName then
                return false
            end
            return true
        end
    end
    return professionName == "Poisons"
end

local KNOWN_SOURCE_TYPES = {
    trainer = true,
    vendor = true,
    quest = true,
    drop = true,
    reputation = true,
    starter = true,
}

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
    local D = AltArmy and AltArmy.Debug
    if D and D.IsPretendCraftLibNotInstalled and D.IsPretendCraftLibNotInstalled() then
        return false
    end
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
    local range = recipe.skillRange
    if not range then
        return nil
    end
    for _, key in ipairs({ "orange", "yellow", "green", "gray" }) do
        local threshold = tonumber(range[key])
        if RCL.IsValidSkillRequired(threshold) then
            return threshold
        end
    end
    -- CraftLib uses orange=0 for some recipes; 75 is the documented learn threshold.
    if tonumber(range.orange) == 0 then
        return 75
    end
    return nil
end

function RCL.GetDifficultyColorHex(difficulty)
    if not difficulty then
        return nil
    end
    return DIFFICULTY_HEX[difficulty]
end

local SOURCE_TYPE_ALIASES = {
    world_drop = "drop",
}

local function normalizeSourceKey(raw)
    if raw == nil then
        return nil
    end
    local key = string.lower(tostring(raw))
    if key == "" then
        return nil
    end
    key = SOURCE_TYPE_ALIASES[key] or key
    if KNOWN_SOURCE_TYPES[key] then
        return key
    end
    return nil
end

function RCL.NormalizeRecipeSource(source)
    if source == nil then
        return nil
    end
    if type(source) == "table" then
        return normalizeSourceKey(source.type)
    end
    if type(source) == "string" then
        return normalizeSourceKey(source)
    end
    return nil
end

function RCL.NormalizeRecipeExpansion(expansion)
    if expansion == nil then
        return nil
    end
    if type(expansion) == "number" then
        if expansion == 0 then
            return "vanilla"
        end
        if expansion == 1 or expansion == 2 then
            return "tbc"
        end
        return nil
    end
    local key = string.lower(tostring(expansion))
    if key == "classic" or key == "vanilla" then
        return "vanilla"
    end
    if key == "tbc" or key == "burning_crusade" or key == "burning crusade" then
        return "tbc"
    end
    return nil
end

function RCL.GetReagentList(recipe)
    local out = {}
    if not recipe or not recipe.reagents then
        return out
    end
    for _, reagent in ipairs(recipe.reagents) do
        local itemId = tonumber(reagent.itemId)
        if itemId then
            local count = tonumber(reagent.count) or 1
            if count <= 0 then
                count = 1
            end
            out[#out + 1] = { itemId = itemId, count = count }
        end
    end
    return out
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
    if isPoisonsProfession(professionName) then
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

local function EnrichStaticCacheKey(professionName, recipeID, resultItemID)
    return tostring(professionName or "") .. ":"
        .. tostring(recipeID or "") .. ":" .. tostring(resultItemID or "")
end

local function ApplyEnrichStatic(entry, cached)
    entry.recipeReagents = nil
    if cached.miss then
        entry.recipeSkillRequired = nil
        entry.difficulty = nil
        entry.recipeSource = nil
        entry.recipeExpansion = nil
        return entry
    end
    entry.recipeSource = cached.recipeSource
    entry.recipeExpansion = cached.recipeExpansion
    entry.recipeSkillRequired = cached.recipeSkillRequired
    if cached.resultItemID and not entry.resultItemID then
        entry.resultItemID = cached.resultItemID
    end
    if cached.recipeSkillRequired and cached.recipe then
        entry.difficulty = RCL.GetDifficulty(cached.recipe, entry.skillRank or 0)
    else
        entry.difficulty = nil
    end
    return entry
end

--- Enrich a search recipe entry with CraftLib metadata (mutates entry).
--- Static fields are cached by recipe identity; difficulty is recomputed from skillRank.
--- Does not populate recipeReagents (unused by Search/Guild UI; avoids alloc on large result sets).
function RCL.EnrichEntry(entry)
    if not entry or not RCL.IsAvailable() then
        return entry
    end
    local cacheKey = EnrichStaticCacheKey(entry.professionName, entry.recipeID, entry.resultItemID)
    local cached = enrichStaticCache[cacheKey]
    if cached then
        return ApplyEnrichStatic(entry, cached)
    end
    entry.recipeSkillRequired = nil
    entry.difficulty = nil
    entry.recipeSource = nil
    entry.recipeExpansion = nil
    entry.recipeReagents = nil
    local recipe = RCL.LookupRecipe(entry.professionName, entry.recipeID, entry.resultItemID)
    if not recipe then
        enrichStaticCache[cacheKey] = { miss = true }
        return entry
    end
    entry.recipeSource = RCL.NormalizeRecipeSource(recipe.source)
    entry.recipeExpansion = RCL.NormalizeRecipeExpansion(recipe.expansion)
    if not entry.resultItemID then
        local productId = tonumber(recipe.itemId)
        if productId then
            entry.resultItemID = productId
        end
    end
    local req = RCL.ExtractSkillRequired(recipe)
    if req then
        entry.recipeSkillRequired = req
        entry.difficulty = RCL.GetDifficulty(recipe, entry.skillRank or 0)
    end
    enrichStaticCache[cacheKey] = {
        recipe = recipe,
        recipeSource = entry.recipeSource,
        recipeExpansion = entry.recipeExpansion,
        recipeSkillRequired = entry.recipeSkillRequired,
        resultItemID = entry.resultItemID,
    }
    return entry
end

--- Colored skill cell text: recipeRequired/playerSkill, or player skill only when unknown.
function RCL.FormatSkillCell(recipeRequired, playerSkill, difficulty)
    local req = tonumber(recipeRequired)
    local rank = tonumber(playerSkill) or 0
    if not RCL.IsValidSkillRequired(req) then
        if rank > 0 then
            return tostring(rank)
        end
        return "—"
    end
    local hex = RCL.GetDifficultyColorHex(difficulty) or "ffffffff"
    return string.format("|c%s%d|r/%d", hex, req, rank)
end

local DIFFICULTY_HARDNESS = { orange = 1, yellow = 2, green = 3, gray = 4 }

--- Hardest difficulty among a list (`orange` > `yellow` > `green` > `gray`).
--- Ignores nil/unknown values; returns nil when none are valid.
function RCL.PickHardestDifficulty(difficulties)
    if type(difficulties) ~= "table" then
        return nil
    end
    local best
    local bestOrd
    for i = 1, #difficulties do
        local d = difficulties[i]
        local ord = d and DIFFICULTY_HARDNESS[d]
        if ord and (not bestOrd or ord < bestOrd) then
            best = d
            bestOrd = ord
        end
    end
    return best
end

--- Collapsed multi-guildmate skill cell: colored recipeRequired/***, or "*" when unknown.
function RCL.FormatCollapsedSkillCell(recipeRequired, difficulty)
    local req = tonumber(recipeRequired)
    if not RCL.IsValidSkillRequired(req) then
        return "*"
    end
    local hex = RCL.GetDifficultyColorHex(difficulty) or "ffffffff"
    return string.format("|c%s%d|r/***", hex, req)
end

function RCL.ClearCaches()
    clearTable(lookupCache)
    clearTable(profKeyCache)
    clearTable(enrichStaticCache)
end

--- Test helper: drop LookupRecipe cache while keeping enrichStaticCache.
function RCL._ClearLookupCacheOnlyForTests()
    clearTable(lookupCache)
end

RCL._LookupRecipeUncached = LookupRecipeUncached
RCL._IsPoisonsProfession = isPoisonsProfession
