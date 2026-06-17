-- AltArmy TBC — Search tab settings (AltArmyTBC_SearchSettings).

AltArmy = AltArmy or {}
AltArmy.SearchSettings = AltArmy.SearchSettings or {}

local SS = AltArmy.SearchSettings

local MIN_RECIPE_LEVEL = 0
local MAX_RECIPE_LEVEL = 375

local function clampLevel(value, default)
    local n = math.floor(tonumber(value) or default or MIN_RECIPE_LEVEL)
    if n < MIN_RECIPE_LEVEL then
        return MIN_RECIPE_LEVEL
    end
    if n > MAX_RECIPE_LEVEL then
        return MAX_RECIPE_LEVEL
    end
    return n
end

function SS.GetSearchSettings()
    _G.AltArmyTBC_SearchSettings = _G.AltArmyTBC_SearchSettings or {}
    local s = _G.AltArmyTBC_SearchSettings
    s.recipeLevelFilter = s.recipeLevelFilter or {}
    local f = s.recipeLevelFilter
    f.min = clampLevel(f.min, MIN_RECIPE_LEVEL)
    f.max = clampLevel(f.max, MAX_RECIPE_LEVEL)
    if f.min > f.max then
        f.min, f.max = f.max, f.min
    end
    return s
end

function SS.GetRecipeLevelFilter()
    return SS.GetSearchSettings().recipeLevelFilter
end

--- True when min/max differ from the full-range defaults (0–375 includes all recipes).
function SS.IsRecipeLevelFilterActive(filter)
    filter = filter or SS.GetRecipeLevelFilter()
    return filter.min ~= MIN_RECIPE_LEVEL or filter.max ~= MAX_RECIPE_LEVEL
end

function SS.SetRecipeLevelFilterMin(minLevel)
    SS.GetRecipeLevelFilter().min = clampLevel(minLevel, MIN_RECIPE_LEVEL)
    SS.GetSearchSettings()
end

function SS.SetRecipeLevelFilterMax(maxLevel)
    SS.GetRecipeLevelFilter().max = clampLevel(maxLevel, MAX_RECIPE_LEVEL)
    SS.GetSearchSettings()
end

SS.MIN_RECIPE_LEVEL = MIN_RECIPE_LEVEL
SS.MAX_RECIPE_LEVEL = MAX_RECIPE_LEVEL
