-- AltArmy TBC — Local-only manual main/alt groupings for non-addon guildmates.
-- Stored under AltArmyTBC_GuildData.manual (sibling of .chars), never broadcast.
-- Precedence elsewhere: local > received (addon) > manual. Addon data shadows
-- (does not delete) these mappings until RetireIfAgrees confirms the same main.

if not AltArmy then return end

AltArmy.GuildManualGroups = AltArmy.GuildManualGroups or {}
local GMG = AltArmy.GuildManualGroups

local function now()
    return (time and time()) or 0
end

local function ensure()
    _G.AltArmyTBC_GuildData = _G.AltArmyTBC_GuildData or {}
    local d = _G.AltArmyTBC_GuildData
    d.manual = d.manual or {}
    return d
end
GMG._Ensure = ensure

local function realmTable(realm, create)
    local d = ensure()
    if not d.manual[realm] and create then
        d.manual[realm] = {}
    end
    return d.manual[realm]
end

--- Store or update a name→main mapping.
--- opts: guild, origin ("user"|"note"), noteText, noteHash
function GMG.SetMapping(name, realm, main, opts)
    if type(name) ~= "string" or name == "" then return end
    if type(main) ~= "string" or main == "" then return end
    realm = realm or "?"
    opts = opts or {}
    local rt = realmTable(realm, true)
    local existing = rt[name]
    local ts = now()
    local entry = existing or {}
    entry.main = main
    entry.guild = opts.guild or entry.guild
    entry.origin = opts.origin or entry.origin or "user"
    if opts.noteText ~= nil then
        entry.noteText = opts.noteText
    end
    if opts.noteHash ~= nil then
        entry.noteHash = opts.noteHash
    end
    if not existing then
        entry.createdAt = ts
    end
    entry.updatedAt = ts
    rt[name] = entry
end

function GMG.GetMapping(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local rt = realmTable(realm, false)
    return rt and rt[name] or nil
end

function GMG.RemoveMapping(name, realm)
    if type(name) ~= "string" or name == "" then return end
    local rt = realmTable(realm, false)
    if rt then
        rt[name] = nil
    end
end

--- Resolve an alt to its main. A character that is someone's main resolves to itself.
--- When realm is omitted, searches all realms.
function GMG.GetMainOf(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local function fromRealm(rt)
        if not rt then return nil end
        local entry = rt[name]
        if entry and entry.main then
            return entry.main
        end
        for _, m in pairs(rt) do
            if m and m.main == name then
                return name
            end
        end
        return nil
    end
    if realm then
        return fromRealm(realmTable(realm, false))
    end
    local d = ensure()
    for _, rt in pairs(d.manual) do
        local hit = fromRealm(rt)
        if hit then return hit end
    end
    return nil
end

--- Flat list of { name, realm, main, guild, origin, noteText, noteHash, ... } for a guild.
function GMG.GetMappingsForGuild(guild)
    local out = {}
    if type(guild) ~= "string" or guild == "" then return out end
    local d = ensure()
    for realm, rt in pairs(d.manual) do
        for name, entry in pairs(rt) do
            if entry and entry.guild == guild then
                out[#out + 1] = {
                    name = name,
                    realm = realm,
                    main = entry.main,
                    guild = entry.guild,
                    origin = entry.origin,
                    noteText = entry.noteText,
                    noteHash = entry.noteHash,
                    createdAt = entry.createdAt,
                    updatedAt = entry.updatedAt,
                }
            end
        end
    end
    return out
end

--- True when addon-received (or local) character data covers this name+realm.
function GMG.IsShadowed(name, realm)
    local GSD = AltArmy.GuildShareData
    if not GSD or not GSD.GetCharacter then return false end
    return GSD.GetCharacter(name, realm) ~= nil
end

--- Remove every mapping whose main equals `main`. Returns count removed.
function GMG.RemoveGroup(main, realm)
    if type(main) ~= "string" or main == "" then return 0 end
    local removed = 0
    local d = ensure()
    local function purgeRealm(rt)
        if not rt then return end
        for name, entry in pairs(rt) do
            if entry and entry.main == main then
                rt[name] = nil
                removed = removed + 1
            end
        end
    end
    if realm then
        purgeRealm(d.manual[realm])
    else
        for _, rt in pairs(d.manual) do
            purgeRealm(rt)
        end
    end
    return removed
end

--- Delete the mapping when addon data confirms the same main. Returns true if removed.
function GMG.RetireIfAgrees(name, realm, effectiveMain)
    local entry = GMG.GetMapping(name, realm)
    if not entry then return false end
    if entry.main == effectiveMain then
        GMG.RemoveMapping(name, realm)
        return true
    end
    return false
end

function GMG.ClearGuild(guild)
    if type(guild) ~= "string" or guild == "" then return end
    local d = ensure()
    for _, rt in pairs(d.manual) do
        for name, entry in pairs(rt) do
            if entry and entry.guild == guild then
                rt[name] = nil
            end
        end
    end
end

function GMG.ClearAll()
    local d = ensure()
    d.manual = {}
end
