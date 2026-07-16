-- AltArmy TBC — Guild data sharing: wire protocol (pure build/parse of payloads).
-- No frames, no comm, no libs. Only shares privacy-limited fields:
--   identity (name/realm/class/faction), level, average item level, self-declared main +
--   display name, and professions (locale-safe key + skill rank + primary recipe IDs).
-- Average item level is a single derived number (used to guess a main, like level); it never
-- includes the underlying items/gear. Explicitly never includes items/gear/bank/mail/money/
-- played/rest/cooldowns/reagents/gearscore/reputation.

if not AltArmy then return end

AltArmy.GuildShareProtocol = AltArmy.GuildShareProtocol or {}
local P = AltArmy.GuildShareProtocol

P.VERSION = 1

--- Resolve a locale-safe profession key from a scanned profession name.
local function professionKey(profName)
    local SS = AltArmy.SearchSettings
    if SS and SS.ResolveProfessionKey then
        local key = SS.ResolveProfessionKey(profName)
        if key then return key end
    end
    return profName
end

--- Whether a recipe id is an alias (crafted-item spell etc.) rather than the craft recipe itself.
local function isAlias(recipeID, data)
    if type(data) ~= "table" or not data.primaryRecipeID then
        return false
    end
    return data.primaryRecipeID ~= recipeID
end

--- Sorted list of primary (non-alias) recipe ids for a profession.
function P.GetPrimaryRecipeIDs(prof)
    local ids = {}
    if prof and prof.Recipes then
        for recipeID, data in pairs(prof.Recipes) do
            if type(recipeID) == "number" and not isAlias(recipeID, data) then
                ids[#ids + 1] = recipeID
            end
        end
    end
    table.sort(ids)
    return ids
end

--- Deterministic, order-independent version hash of a recipe id set (change detector).
function P.HashRecipeIDs(ids)
    local sorted = {}
    for i = 1, #ids do sorted[i] = ids[i] end
    table.sort(sorted)
    local h = 5381
    for i = 1, #sorted do
        h = (h * 33 + sorted[i]) % 2147483647
    end
    return h
end

--- Per-profession summaries for a character: { key, name, rank, count, rv, spec }.
function P.BuildProfessionSummaries(char)
    local out = {}
    local profs = char and char.Professions
    if not profs then return out end
    for profName, prof in pairs(profs) do
        local ids = P.GetPrimaryRecipeIDs(prof)
        out[#out + 1] = {
            key = professionKey(profName),
            name = profName,
            rank = prof.rank or 0,
            count = #ids,
            rv = P.HashRecipeIDs(ids),
            spec = prof.specialization,
        }
    end
    table.sort(out, function(a, b) return (a.key or "") < (b.key or "") end)
    return out
end

--- Average equipped item level for a character (single derived number), rounded to an int.
--- Returns 0 when unavailable so it never surfaces underlying gear.
local function averageItemLevel(char)
    local DS = AltArmy.DataStore
    if DS and DS.GetAverageItemLevel then
        local ilvl = DS:GetAverageItemLevel(char) or 0
        return math.floor(ilvl + 0.5)
    end
    return 0
end

--- Compact presence payload broadcast on login / roster change.
--- @param chars table[] entries { name, realm, char } (from GuildShareSettings resolvers)
--- @param mainName string|nil self-declared main for this realm/guild
--- @param displayName string|nil optional display name for the main
function P.BuildPresence(chars, mainName, displayName)
    local msg = { v = P.VERSION, main = mainName, displayName = displayName, chars = {} }
    for _, entry in ipairs(chars or {}) do
        local char = entry.char
        if char then
            msg.chars[#msg.chars + 1] = {
                name = entry.name or char.name,
                realm = entry.realm or char.realm,
                classFile = char.classFile,
                faction = char.faction,
                level = char.level or 0,
                itemLevel = averageItemLevel(char),
                profs = P.BuildProfessionSummaries(char),
            }
        end
    end
    return msg
end

--- Full recipe payload for one character (pulled on demand), keyed by profession.
function P.BuildRecipes(name, realm, char)
    local msg = { v = P.VERSION, name = name, realm = realm, profs = {} }
    local profs = char and char.Professions
    if profs then
        local list = {}
        for profName, prof in pairs(profs) do
            list[#list + 1] = { key = professionKey(profName), ids = P.GetPrimaryRecipeIDs(prof) }
        end
        table.sort(list, function(a, b) return (a.key or "") < (b.key or "") end)
        msg.profs = list
    end
    return msg
end

-- *** Validation / normalization of inbound (deserialized) payloads ***

local function isNonEmptyString(v)
    return type(v) == "string" and v ~= ""
end

--- Validate + normalize an inbound presence. Returns a clean table or nil.
--- Drops malformed char/prof entries rather than rejecting the whole message.
function P.ParsePresence(msg)
    if type(msg) ~= "table" or msg.v ~= P.VERSION then return nil end
    if type(msg.chars) ~= "table" then return nil end
    local displayName = isNonEmptyString(msg.displayName) and msg.displayName or nil
    local GSS = AltArmy.GuildShareSettings
    if displayName and GSS and GSS.NormalizeDisplayName then
        displayName = GSS.NormalizeDisplayName(displayName)
    end
    local out = {
        v = P.VERSION,
        main = isNonEmptyString(msg.main) and msg.main or nil,
        displayName = displayName,
        -- Login announces ask peers to whisper their presence even when data is unchanged.
        login = msg.login == true or nil,
        chars = {},
    }
    for _, c in ipairs(msg.chars) do
        if type(c) == "table" and isNonEmptyString(c.name) then
            local profs = {}
            if type(c.profs) == "table" then
                for _, pr in ipairs(c.profs) do
                    if type(pr) == "table" and isNonEmptyString(pr.key) then
                        profs[#profs + 1] = {
                            key = pr.key,
                            name = isNonEmptyString(pr.name) and pr.name or pr.key,
                            rank = tonumber(pr.rank) or 0,
                            count = tonumber(pr.count) or 0,
                            rv = tonumber(pr.rv) or 0,
                            spec = isNonEmptyString(pr.spec) and pr.spec or nil,
                        }
                    end
                end
            end
            out.chars[#out.chars + 1] = {
                name = c.name,
                realm = isNonEmptyString(c.realm) and c.realm or nil,
                classFile = isNonEmptyString(c.classFile) and c.classFile or nil,
                faction = isNonEmptyString(c.faction) and c.faction or nil,
                level = tonumber(c.level) or 0,
                itemLevel = tonumber(c.itemLevel) or 0,
                profs = profs,
            }
        end
    end
    return out
end

--- Validate + normalize an inbound recipe payload. Returns a clean table or nil.
function P.ParseRecipes(msg)
    if type(msg) ~= "table" or msg.v ~= P.VERSION then return nil end
    if not isNonEmptyString(msg.name) or type(msg.profs) ~= "table" then return nil end
    local out = { v = P.VERSION, name = msg.name, realm = isNonEmptyString(msg.realm) and msg.realm or nil, profs = {} }
    for _, pr in ipairs(msg.profs) do
        if type(pr) == "table" and isNonEmptyString(pr.key) and type(pr.ids) == "table" then
            local ids = {}
            for _, id in ipairs(pr.ids) do
                if type(id) == "number" then ids[#ids + 1] = id end
            end
            out.profs[#out.profs + 1] = { key = pr.key, ids = ids }
        end
    end
    return out
end
