-- AltArmy TBC — the CraftPlan context for the realm's characters (Economy tab: Craftsman's Writs and Waylaid
-- Crates): who knows which recipe, each one's vendor discount, how many of an item they hold. The recipes
-- come from a generated module's ITEMS, RECIPES and ByOutput (Writs.lua, WaylaidCrates.lua); the
-- characters from the DataStore passed in.

if not AltArmy then return end

AltArmy.CraftContext = AltArmy.CraftContext or {}
local CX = AltArmy.CraftContext

-- The vendor discounts (see docs/tabs/economy.md): Bartering's ranks, and the city factions' Honored
-- discount, assumed once a character is Honored with any of them. Looked up when used: the modules
-- naming them may load after this one.
local BARTERING_SPELL = 1225459
local BARTERING_PER_RANK = 0.05
local CITY_FACTIONS = { 47, 54, 68, 69, 72, 76, 81, 530 }
local HONORED, CITY_DISCOUNT = 6, 0.10

--- A character's vendor discount, 0..1.
function CX.Discount(char)
    if not char then return 0 end
    local bartering = AltArmy.DataStoreLegacy and AltArmy.DataStoreLegacy.SPELL_BARTERING or BARTERING_SPELL
    local factions = AltArmy.ProfitExport and AltArmy.ProfitExport.CITY_FACTIONS or CITY_FACTIONS
    local d = 0
    local legacy = char.legacyTalents
    if type(legacy) == "table" and type(legacy.spells) == "table" then
        d = d + BARTERING_PER_RANK * (tonumber(legacy.spells[bartering]) or 0)
    end
    local reps = char.Reputations
    if type(reps) == "table" then
        for _, factionID in ipairs(factions) do
            local r = reps[factionID]
            if type(r) == "table" and (tonumber(r.s) or 0) >= HONORED then
                d = d + CITY_DISCOUNT
                break
            end
        end
    end
    return math.min(d, 1)
end

--- True for a stored recipe row that is the recipe itself, not an alias key of it.
local function IsPrimary(spell, data)
    return type(data) ~= "table" or data.primaryRecipeID == nil or data.primaryRecipeID == spell
end

--- The CraftPlan context for `ds`'s characters on `realm` of `faction`, pricing from `book`, with the
--- recipes of `data` (a module with ITEMS, RECIPES and ByOutput): who knows which recipe (the highest
--- skilled, then A-Z), each one's discount, how many of an item they hold (`heldBy`). Second result: each
--- character's class file by name.
function CX.Build(ds, realm, faction, book, data)
    local chars = {}
    for _, char in pairs(ds:GetCharacters(realm)) do
        if type(char) == "table" and char.name and (char.faction or faction) == faction then
            chars[char.name] = char
        end
    end
    local known = {}
    for name, char in pairs(chars) do
        for _, prof in pairs(ds:GetProfessions(char)) do
            local rank = tonumber(prof.rank) or 0
            for spell, recipe in pairs(prof.Recipes or {}) do
                if data.RECIPES[spell] and IsPrimary(spell, recipe) then
                    local cur = known[spell]
                    if not cur or rank > cur.rank or (rank == cur.rank and name < cur.name) then
                        known[spell] = { name = name, rank = rank }
                    end
                end
            end
        end
    end
    local current = ds:GetCurrentPlayerName()
    local discounts, classOf = {}, {}
    for name, char in pairs(chars) do
        classOf[name] = char.classFile
    end
    local ctx = {
        book = book, items = data.ITEMS, recipes = data.RECIPES, byOutput = data.ByOutput,
        current = current,
        knownBy = function(spell)
            local k = known[spell]
            return k and k.name or nil
        end,
        discountOf = function(name)
            name = name or current
            if discounts[name] == nil then discounts[name] = CX.Discount(chars[name]) end
            return discounts[name]
        end,
        heldBy = function(itemID)
            local held = 0
            for _, char in pairs(chars) do
                held = held + (ds:GetTotalItemCount(char, itemID) or 0)
            end
            return held
        end,
    }
    return ctx, classOf
end
