-- AltArmy TBC — Guild data sharing: received guildmate data store.
-- Persists to AltArmyTBC_GuildData, kept fully separate from AltArmyTBC_Data so guild
-- data never contaminates account data and can be wiped independently.
-- Structure: AltArmyTBC_GuildData.chars[realm][charName] = { identity + main + Professions }.

if not AltArmy then return end

AltArmy.GuildShareData = AltArmy.GuildShareData or {}
local GSD = AltArmy.GuildShareData

local function now()
    return (time and time()) or 0
end

local function ensure()
    _G.AltArmyTBC_GuildData = _G.AltArmyTBC_GuildData or {}
    local d = _G.AltArmyTBC_GuildData
    d.chars = d.chars or {}
    return d
end
GSD._Ensure = ensure

local function realmTable(realm, create)
    local d = ensure()
    if not d.chars[realm] and create then
        d.chars[realm] = {}
    end
    return d.chars[realm]
end

--- Pick an implicit main from a candidate list ({ name, char }) so a person's characters
--- still group together when no main was declared. Reuses the onboarding ranking when the UI
--- helper is loaded; otherwise ranks by level, then item level, then name. `opts` (optional)
--- overrides the stat accessors — used for received data whose stats live on the char entry.
local function pickMain(candidates, opts)
    if #candidates == 0 then return nil end
    local GSO = AltArmy.GuildShareOnboarding
    if GSO and GSO.PickDefaultMain then
        local pick = GSO.PickDefaultMain(candidates, opts)
        if pick then return pick end
    end
    local getLevel = (opts and opts.getLevel) or function(c) return (c and c.level) or 0 end
    local getItemLevel = (opts and opts.getItemLevel)
        or function(c) return (c and c.itemLevel) or 0 end
    local best
    for _, cand in ipairs(candidates) do
        if not best then
            best = cand
        else
            local bl, cl = getLevel(best.char), getLevel(cand.char)
            local bi, ci = getItemLevel(best.char), getItemLevel(cand.char)
            local better = cl > bl
                or (cl == bl and ci > bi)
                or (cl == bl and ci == bi and (cand.name or "") < (best.name or ""))
            if better then best = cand end
        end
    end
    return best and best.name or nil
end

--- Implicit main for the local account (chars are DataStore tables ranked by the onboarding
--- accessors: level, gear score, item level, name).
local function defaultLocalMain(entries)
    local candidates = {}
    for _, e in ipairs(entries) do
        candidates[#candidates + 1] = { name = e.name, char = e.char }
    end
    return pickMain(candidates, nil)
end
GSD._DefaultLocalMain = defaultLocalMain

-- Received chars carry only level + item level (no local gear-score provider); rank on those.
local RECEIVED_MAIN_OPTS = {
    getLevel = function(c) return (c and c.level) or 0 end,
    getGearScore = function() return 0 end,
    getItemLevel = function(c) return (c and c.itemLevel) or 0 end,
}

--- Implicit main for a received presence that didn't declare one (chars are payload entries).
local function defaultReceivedMain(chars)
    local candidates = {}
    for _, c in ipairs(chars or {}) do
        candidates[#candidates + 1] = { name = c.name, char = c }
    end
    return pickMain(candidates, RECEIVED_MAIN_OPTS)
end
GSD._DefaultReceivedMain = defaultReceivedMain

GSD.RECIPE_REQUEST_BACKOFF_SEC = 3600

local function profSummaryMatches(storedProf, parsedProf)
    if not storedProf or not parsedProf then return false end
    return storedProf.rank == (parsedProf.rank or 0)
        and storedProf.count == (parsedProf.count or 0)
        and storedProf.rv == (parsedProf.rv or 0)
        and storedProf.spec == parsedProf.spec
end

local function charPresenceMatches(stored, parsedChar)
    if not stored or not parsedChar then return false end
    if stored.classFile ~= parsedChar.classFile then return false end
    if stored.faction ~= parsedChar.faction then return false end
    if stored.level ~= (parsedChar.level or 0) then return false end
    if stored.itemLevel ~= (parsedChar.itemLevel or 0) then return false end

    local storedProfs = stored.Professions or {}
    local parsedProfs = parsedChar.profs or {}
    if #parsedProfs ~= 0 then
        local seen = {}
        for _, pr in ipairs(parsedProfs) do
            if not profSummaryMatches(storedProfs[pr.key], pr) then
                return false
            end
            seen[pr.key] = true
        end
        for key in pairs(storedProfs) do
            if not seen[key] then return false end
        end
    elseif next(storedProfs) ~= nil then
        return false
    end
    return true
end
GSD._CharPresenceMatches = charPresenceMatches

--- True when an inbound (parsed) presence matches what is already stored for its chars.
--- Empty presence matches only when this sender has no stored characters on the realm
--- (peers use empty presence to clear after opting out of sharing).
function GSD.PresenceMatchesStored(sender, presence, realm)
    if not presence or type(presence.chars) ~= "table" then
        return false
    end
    realm = realm or "?"
    local rt = realmTable(realm, false)
    if #presence.chars == 0 then
        if not rt or not sender then return true end
        for _, entry in pairs(rt) do
            if entry and entry.source == sender then
                return false
            end
        end
        return true
    end
    local effectiveMain = presence.main or defaultReceivedMain(presence.chars)
    local mainDeclared = presence.main ~= nil
    local displayName = presence.displayName
    local inPresence = {}
    for _, c in ipairs(presence.chars) do
        inPresence[c.name] = true
        local stored = GSD.GetCharacter(c.name, realm)
        if not stored then return false end
        if stored.main ~= effectiveMain then return false end
        if (stored.mainDeclared == true) ~= mainDeclared then return false end
        if stored.displayName ~= displayName then return false end
        if not charPresenceMatches(stored, c) then return false end
    end
    -- A char previously shared by this sender but omitted from the new presence is a change.
    if rt and sender then
        for name, entry in pairs(rt) do
            if entry and entry.source == sender and not inPresence[name] then
                return false
            end
        end
    end
    return true
end

--- Store an inbound (already parsed) presence for a guild on a realm.
--- Preserves previously pulled recipes when the advertised version is unchanged.
--- Characters previously received from `sender` that are absent from this presence
--- (including an empty char list after opt-out) are removed.
function GSD.SaveReceived(sender, presence, guild, realm)
    if not presence or type(presence.chars) ~= "table" then return end
    realm = realm or "?"
    local rt = realmTable(realm, true)
    local ts = now()
    -- Honor a sender-declared main; otherwise guess one so their alts still group together.
    local mainDeclared = presence.main ~= nil
    local effectiveMain = presence.main or defaultReceivedMain(presence.chars)
    local keep = {}
    for _, c in ipairs(presence.chars) do
        local existing = rt[c.name]
        local entry = existing or {}
        entry.name = c.name
        entry.realm = realm
        entry.classFile = c.classFile
        entry.faction = c.faction
        entry.level = c.level or 0
        entry.itemLevel = c.itemLevel or 0
        if guild then
            entry.guildName = guild
        end
        entry.main = effectiveMain
        entry.displayName = presence.displayName
        entry.isMain = (effectiveMain ~= nil and c.name == effectiveMain)
        entry.mainDeclared = mainDeclared
        entry.source = sender
        entry.receivedAt = ts

        -- Merge profession summaries; drop stale recipes when the advertised version changed.
        local newProfs = {}
        for _, pr in ipairs(c.profs or {}) do
            local prev = entry.Professions and entry.Professions[pr.key]
            local prof = {
                key = pr.key,
                name = pr.name or pr.key,
                rank = pr.rank or 0,
                count = pr.count or 0,
                rv = pr.rv or 0,
                spec = pr.spec,
            }
            if prev and prev.Recipes and prev.recipesRv == prof.rv then
                prof.Recipes = prev.Recipes
                prof.recipesRv = prev.recipesRv
            end
            if prev and prev.rv == prof.rv and prev.recipesRequestedAt then
                prof.recipesRequestedAt = prev.recipesRequestedAt
            end
            newProfs[pr.key] = prof
        end
        entry.Professions = newProfs
        rt[c.name] = entry
        keep[c.name] = true
    end
    if sender then
        for name, entry in pairs(rt) do
            if entry and entry.source == sender and not keep[name] then
                rt[name] = nil
            end
        end
    end
end

--- Store a pulled recipe payload; reconstructs a minimal Recipes map ({ [id] = { primaryRecipeID = id } }).
function GSD.SaveRecipes(realm, payload)
    if not payload or not payload.name or type(payload.profs) ~= "table" then return end
    local rt = realmTable(realm, false)
    local entry = rt and rt[payload.name]
    if not entry then return end
    entry.Professions = entry.Professions or {}
    local P = AltArmy.GuildShareProtocol
    for _, pr in ipairs(payload.profs) do
        local prof = entry.Professions[pr.key]
        if not prof then
            prof = { key = pr.key, name = pr.key, rank = 0, count = 0, rv = 0 }
            entry.Professions[pr.key] = prof
        end
        local recipes = {}
        for _, id in ipairs(pr.ids or {}) do
            recipes[id] = { primaryRecipeID = id }
        end
        prof.Recipes = recipes
        prof.count = #(pr.ids or {})
        prof.recipesRv = P and P.HashRecipeIDs(pr.ids or {}) or 0
    end
end

-- *** Getters ***

function GSD.GetCharacter(name, realm)
    local rt = realmTable(realm, false)
    return rt and rt[name] or nil
end

--- Find a stored character by name. When realm is omitted, searches all realms.
function GSD.FindCharacter(name, realm)
    if realm then
        return GSD.GetCharacter(name, realm)
    end
    local d = ensure()
    for _, rt in pairs(d.chars) do
        local hit = rt[name]
        if hit then return hit end
    end
    return nil
end

--- All stored characters in a guild (across realms), as a flat list.
function GSD.GetGuildMembers(guild)
    local out = {}
    local d = ensure()
    for _, rt in pairs(d.chars) do
        for _, entry in pairs(rt) do
            if entry.guildName == guild then
                out[#out + 1] = entry
            end
        end
    end
    return out
end

local function professionsFromChar(char)
    local profs = {}
    local P = AltArmy.GuildShareProtocol
    if not P or not P.BuildProfessionSummaries then return profs end
    for _, pr in ipairs(P.BuildProfessionSummaries(char)) do
        profs[pr.key] = {
            key = pr.key,
            name = pr.name or pr.key,
            rank = pr.rank or 0,
            count = pr.count or 0,
            rv = pr.rv or 0,
            spec = pr.spec,
        }
    end
    return profs
end

--- Build a guild-tab member entry from local account data (not received over comm).
--- `mainDeclared` is true when `mainName` came from the player's saved main setting.
function GSD.BuildLocalMemberEntry(name, realm, char, guild, mainName, displayName, mainDeclared)
    local charName = (char and char.name) or name
    return {
        name = charName,
        realm = realm,
        classFile = char and char.classFile or "",
        faction = char and char.faction or "",
        level = (char and char.level) or 0,
        guildName = guild,
        main = mainName,
        displayName = displayName,
        isMain = (mainName ~= nil and charName == mainName),
        mainDeclared = mainDeclared and true or false,
        source = "local",
        Professions = professionsFromChar(char),
    }
end

--- Account characters in `guild` on `realm` formatted for the guild tab.
function GSD.GetLocalGuildMembers(guild, realm)
    local out = {}
    if not guild then return out end
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS._CurrentRealm and not realm then
        realm = GSS._CurrentRealm()
    end
    realm = realm or ""
    local displayName = GSS and GSS.GetDisplayName and GSS.GetDisplayName(realm) or nil
    local entries = (GSS and GSS.GetAllGuildedCharacters
        and GSS.GetAllGuildedCharacters(guild, realm)) or {}
    -- Without an explicit main, group everyone under an implicit default main.
    local savedMain = GSS and GSS.GetMain and GSS.GetMain(realm) or nil
    local mainDeclared = savedMain ~= nil
    local mainName = savedMain or defaultLocalMain(entries)
    for _, entry in ipairs(entries) do
        out[#out + 1] = GSD.BuildLocalMemberEntry(
            entry.name, entry.realm, entry.char, guild, mainName, displayName, mainDeclared)
    end
    return out
end

--- Account characters in `guild` across every stored realm (for browsing when not guilded).
function GSD.GetLocalGuildMembersAllRealms(guild)
    local out = {}
    if not guild then return out end
    local DS = AltArmy.DataStore
    if not DS or not DS.GetRealms then return out end
    for realm in pairs(DS:GetRealms()) do
        for _, entry in ipairs(GSD.GetLocalGuildMembers(guild, realm)) do
            out[#out + 1] = entry
        end
    end
    return out
end

local function memberKey(entry)
    return (entry.realm or "") .. "\0" .. (entry.name or "")
end

--- Received guildmates plus local account characters (local wins on name+realm conflict).
--- When `allLocalRealms` is true, merges local account characters from every realm.
function GSD.GetGuildMembersForDisplay(guild, realm, allLocalRealms)
    local byKey = {}
    for _, entry in ipairs(GSD.GetGuildMembers(guild)) do
        byKey[memberKey(entry)] = entry
    end
    if allLocalRealms then
        for _, entry in ipairs(GSD.GetLocalGuildMembersAllRealms(guild)) do
            byKey[memberKey(entry)] = entry
        end
    else
        for _, entry in ipairs(GSD.GetLocalGuildMembers(guild, realm)) do
            byKey[memberKey(entry)] = entry
        end
    end
    local out = {}
    for _, entry in pairs(byKey) do
        out[#out + 1] = entry
    end
    return out
end

--- Resolve an alt to its main. A main resolves to itself. Unknown characters return nil.
function GSD.GetMainOf(name, realm)
    -- If a realm is supplied, use it; otherwise search all realms.
    local function fromEntry(entry)
        if not entry then return nil end
        return entry.main or entry.name
    end
    if realm then
        return fromEntry(GSD.GetCharacter(name, realm))
    end
    local d = ensure()
    for _, rt in pairs(d.chars) do
        local hit = fromEntry(rt[name])
        if hit then return hit end
    end
    return nil
end

--- Professions map for a stored character (each prof may carry a Recipes map once pulled).
function GSD.GetRecipesFor(name, realm)
    local entry = GSD.GetCharacter(name, realm)
    return entry and entry.Professions or {}
end

--- Profession keys for a character whose recipe lists still need to be pulled.
function GSD.GetProfessionsNeedingRecipes(name, realm, nowTs)
    nowTs = nowTs or now()
    local out = {}
    local entry = GSD.GetCharacter(name, realm)
    if not entry or not entry.Professions then return out end
    local backoff = GSD.RECIPE_REQUEST_BACKOFF_SEC or 3600
    for key, prof in pairs(entry.Professions) do
        if not prof.Recipes or prof.recipesRv ~= prof.rv then
            local requestedAt = prof.recipesRequestedAt
            local inBackoff = requestedAt and (nowTs - requestedAt) < backoff
            if not inBackoff then
                out[#out + 1] = key
            end
        end
    end
    table.sort(out)
    return out
end

--- Record that recipe lists were requested for the given profession keys.
function GSD.MarkRecipesRequested(name, realm, profKeys, nowTs)
    if type(profKeys) ~= "table" or #profKeys == 0 then return end
    local entry = GSD.GetCharacter(name, realm)
    if not entry or not entry.Professions then return end
    nowTs = nowTs or now()
    for _, key in ipairs(profKeys) do
        local prof = entry.Professions[key]
        if prof then
            prof.recipesRequestedAt = nowTs
        end
    end
end

-- *** Purging ***

function GSD.PurgeGuild(guild)
    local d = ensure()
    for _, rt in pairs(d.chars) do
        for name, entry in pairs(rt) do
            if entry.guildName == guild then
                rt[name] = nil
            end
        end
    end
end

--- Remove entries older than maxAgeSeconds. Returns the number removed.
function GSD.PurgeStale(maxAgeSeconds, nowTs)
    nowTs = nowTs or now()
    local removed = 0
    local d = ensure()
    for _, rt in pairs(d.chars) do
        for name, entry in pairs(rt) do
            local ts = entry.receivedAt or 0
            if (nowTs - ts) > maxAgeSeconds then
                rt[name] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

function GSD.PurgeAll()
    local d = ensure()
    d.chars = {}
end

--- Remove every stored character whose effective main equals `main`.
--- When `realm` is set, only that realm is searched. Returns the number removed.
function GSD.RemoveGroup(main, realm)
    if type(main) ~= "string" or main == "" then return 0 end
    local removed = 0
    local d = ensure()
    local function purgeRealmTable(rt)
        if not rt then return end
        for name, entry in pairs(rt) do
            local entryMain = (entry and (entry.main or entry.name)) or name
            if entryMain == main then
                rt[name] = nil
                removed = removed + 1
            end
        end
    end
    if realm then
        purgeRealmTable(d.chars[realm])
    else
        for _, rt in pairs(d.chars) do
            purgeRealmTable(rt)
        end
    end
    return removed
end
