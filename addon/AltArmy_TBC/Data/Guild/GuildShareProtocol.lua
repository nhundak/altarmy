-- AltArmy TBC — Guild data sharing: wire protocol (pure build/parse of payloads).
-- No frames, no comm, no libs. Only shares privacy-limited fields:
--   identity (name/realm/class/faction), level, average item level, self-declared main +
--   display name, and professions (locale-safe key + skill rank + primary recipe IDs).
-- Average item level is a single derived number (used to guess a main, like level); it never
-- includes the underlying items/gear. Explicitly never includes items/gear/bank/mail/money/
-- played/rest/cooldowns/reagents/gearscore/reputation.
--
-- Presence versions:
--   v1 (legacy inbound): fat chars with embedded profession summaries.
--   v2 (outbound + inbound): slim chars with identity + checksum `ch`; profs via CC whisper.
-- Recipe payloads stay at RECIPES_VERSION (1).

if not AltArmy then return end

AltArmy.GuildShareProtocol = AltArmy.GuildShareProtocol or {}
local P = AltArmy.GuildShareProtocol

P.PRESENCE_V1 = 1
P.PRESENCE_V2 = 2
P.RECIPES_VERSION = 1
-- Legacy alias used by older call sites / tests that still refer to P.VERSION for recipes.
P.VERSION = P.RECIPES_VERSION

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

local function mixString(h, s)
    s = tostring(s or "")
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 2147483647
    end
    return (h * 33 + 1) % 2147483647 -- separator
end

local function mixNumber(h, n)
    n = tonumber(n) or 0
    -- Keep sign bit out of range issues; fold as integer.
    if n < 0 then n = -n end
    n = math.floor(n) % 2147483647
    return (h * 33 + n) % 2147483647
end

--- Deterministic checksum over identity + profession summary fields (change detector for CQ).
--- @param card table { classFile, faction, level, itemLevel, profs[] }
function P.HashCharacterCard(card)
    local h = 5381
    if type(card) ~= "table" then return h end
    h = mixString(h, card.classFile)
    h = mixString(h, card.faction)
    h = mixNumber(h, card.level or 0)
    h = mixNumber(h, card.itemLevel or 0)
    local profs = {}
    for _, pr in ipairs(card.profs or {}) do
        if type(pr) == "table" and pr.key then
            profs[#profs + 1] = pr
        end
    end
    table.sort(profs, function(a, b) return (a.key or "") < (b.key or "") end)
    for _, pr in ipairs(profs) do
        h = mixString(h, pr.key)
        h = mixNumber(h, pr.rank or 0)
        h = mixNumber(h, pr.count or 0)
        h = mixNumber(h, pr.rv or 0)
        h = mixString(h, pr.spec or "")
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

local function identityAndProfsForChar(entryName, entryRealm, char)
    local level = (char and char.level) or 0
    local itemLevel = averageItemLevel(char)
    local classFile = char and char.classFile
    local faction = char and char.faction
    local profs = P.BuildProfessionSummaries(char)
    local ch = P.HashCharacterCard({
        classFile = classFile,
        faction = faction,
        level = level,
        itemLevel = itemLevel,
        profs = profs,
    })
    return {
        name = entryName or (char and char.name),
        realm = entryRealm or (char and char.realm),
        classFile = classFile,
        faction = faction,
        level = level,
        itemLevel = itemLevel,
        profs = profs,
        ch = ch,
    }
end

--- Slim v2 presence payload broadcast on login / roster change (identity + checksum, no profs).
--- @param chars table[] entries { name, realm, char } (from GuildShareSettings resolvers)
--- @param mainName string|nil self-declared main for this realm/guild
--- @param displayName string|nil optional display name for the main
function P.BuildPresence(chars, mainName, displayName)
    local msg = { v = P.PRESENCE_V2, main = mainName, displayName = displayName, chars = {} }
    for _, entry in ipairs(chars or {}) do
        local char = entry.char
        if char then
            local built = identityAndProfsForChar(entry.name, entry.realm, char)
            msg.chars[#msg.chars + 1] = {
                name = built.name,
                realm = built.realm,
                classFile = built.classFile,
                faction = built.faction,
                level = built.level,
                itemLevel = built.itemLevel,
                ch = built.ch,
            }
        end
    end
    return msg
end

--- Profession card for one character (whispered CC response).
function P.BuildCharCard(name, realm, char)
    local built = identityAndProfsForChar(name, realm, char)
    return {
        v = P.PRESENCE_V2,
        name = built.name,
        realm = built.realm,
        classFile = built.classFile,
        faction = built.faction,
        level = built.level,
        itemLevel = built.itemLevel,
        ch = built.ch,
        profs = built.profs,
    }
end

--- Request profession card for one character (whispered CQ).
function P.BuildCharCardRequest(name, realm)
    return { v = P.PRESENCE_V2, name = name, realm = realm }
end

--- Full recipe payload for one character (pulled on demand), keyed by profession.
function P.BuildRecipes(name, realm, char)
    local msg = { v = P.RECIPES_VERSION, name = name, realm = realm, profs = {} }
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

local function parseProfSummaries(rawProfs)
    local profs = {}
    if type(rawProfs) ~= "table" then return profs end
    for _, pr in ipairs(rawProfs) do
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
    return profs
end

--- Validate + normalize an inbound presence. Returns a clean table or nil.
--- Accepts legacy fat v1 and slim v2. Drops malformed char/prof entries.
function P.ParsePresence(msg)
    if type(msg) ~= "table" then return nil end
    local ver = msg.v
    if ver ~= P.PRESENCE_V1 and ver ~= P.PRESENCE_V2 then return nil end
    if type(msg.chars) ~= "table" then return nil end
    local displayName = isNonEmptyString(msg.displayName) and msg.displayName or nil
    local GSS = AltArmy.GuildShareSettings
    if displayName and GSS and GSS.NormalizeDisplayName then
        displayName = GSS.NormalizeDisplayName(displayName)
    end
    local out = {
        v = ver,
        main = isNonEmptyString(msg.main) and msg.main or nil,
        displayName = displayName,
        -- Login announces ask peers to whisper their presence even when data is unchanged.
        login = msg.login == true or nil,
        chars = {},
    }
    for _, c in ipairs(msg.chars) do
        if type(c) == "table" and isNonEmptyString(c.name) then
            local entry = {
                name = c.name,
                realm = isNonEmptyString(c.realm) and c.realm or nil,
                classFile = isNonEmptyString(c.classFile) and c.classFile or nil,
                faction = isNonEmptyString(c.faction) and c.faction or nil,
                level = tonumber(c.level) or 0,
                itemLevel = tonumber(c.itemLevel) or 0,
                profs = {},
            }
            if ver == P.PRESENCE_V1 then
                entry.profs = parseProfSummaries(c.profs)
            else
                local ch = tonumber(c.ch)
                if ch then entry.ch = ch end
            end
            out.chars[#out.chars + 1] = entry
        end
    end
    return out
end

--- Validate + normalize an inbound CQ payload.
function P.ParseCharCardRequest(msg)
    if type(msg) ~= "table" or msg.v ~= P.PRESENCE_V2 then return nil end
    if not isNonEmptyString(msg.name) then return nil end
    return {
        v = P.PRESENCE_V2,
        name = msg.name,
        realm = isNonEmptyString(msg.realm) and msg.realm or nil,
    }
end

--- Validate + normalize an inbound CC payload.
function P.ParseCharCard(msg)
    if type(msg) ~= "table" or msg.v ~= P.PRESENCE_V2 then return nil end
    if not isNonEmptyString(msg.name) or type(msg.profs) ~= "table" then return nil end
    local ch = tonumber(msg.ch)
    if not ch then return nil end
    return {
        v = P.PRESENCE_V2,
        name = msg.name,
        realm = isNonEmptyString(msg.realm) and msg.realm or nil,
        classFile = isNonEmptyString(msg.classFile) and msg.classFile or nil,
        faction = isNonEmptyString(msg.faction) and msg.faction or nil,
        level = tonumber(msg.level) or 0,
        itemLevel = tonumber(msg.itemLevel) or 0,
        ch = ch,
        profs = parseProfSummaries(msg.profs),
    }
end

--- Validate + normalize an inbound recipe payload. Returns a clean table or nil.
function P.ParseRecipes(msg)
    if type(msg) ~= "table" or msg.v ~= P.RECIPES_VERSION then return nil end
    if not isNonEmptyString(msg.name) or type(msg.profs) ~= "table" then return nil end
    local out = {
        v = P.RECIPES_VERSION,
        name = msg.name,
        realm = isNonEmptyString(msg.realm) and msg.realm or nil,
        profs = {},
    }
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
