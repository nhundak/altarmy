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

local function normalizeKey(name)
    if type(name) ~= "string" then return nil end
    local GTD = AltArmy.GuildTabData
    if GTD and GTD.NormalizeRosterName then
        return GTD.NormalizeRosterName(name)
    end
    local short = name:match("^[^%-]+") or name
    return short:lower()
end

--- Store or update a name→main mapping.
--- opts: guild, origin ("user"|"note"), noteText, noteHash, classFile?, level?
--- Omitting classFile/level preserves any previously stored values for that mapping.
--- When a case-variant of `name` already exists, updates that entry (reuses stored key).
function GMG.SetMapping(name, realm, main, opts)
    if type(name) ~= "string" or name == "" then return end
    if type(main) ~= "string" or main == "" then return end
    realm = realm or "?"
    opts = opts or {}
    local rt = realmTable(realm, true)
    local existing = rt[name]
    local storedKey = name
    -- Reuse an existing case-variant key so we do not create duplicate entries.
    if not existing then
        local nameKey = normalizeKey(name)
        if nameKey then
            for n, e in pairs(rt) do
                if normalizeKey(n) == nameKey then
                    existing = e
                    storedKey = n
                    break
                end
            end
        end
    end
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
    if opts.classFile ~= nil then
        entry.classFile = opts.classFile ~= "" and opts.classFile or nil
    end
    if opts.level ~= nil then
        local lvl = tonumber(opts.level)
        entry.level = (lvl and lvl > 0) and lvl or nil
    end
    if not existing then
        entry.createdAt = ts
    end
    entry.updatedAt = ts
    rt[storedKey] = entry
end

function GMG.GetMapping(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local nameKey = normalizeKey(name)
    local function fromRealm(rt)
        if not rt then return nil end
        local entry = rt[name]
        if entry then return entry end
        if not nameKey then return nil end
        for n, e in pairs(rt) do
            if normalizeKey(n) == nameKey then
                return e
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

function GMG.RemoveMapping(name, realm)
    if type(name) ~= "string" or name == "" then return end
    local rt = realmTable(realm, false)
    if not rt then return end
    if rt[name] then
        rt[name] = nil
        return
    end
    local nameKey = normalizeKey(name)
    if not nameKey then return end
    for n, _ in pairs(rt) do
        if normalizeKey(n) == nameKey then
            rt[n] = nil
            return
        end
    end
end

--- Resolve an alt to its main. A character that is someone's main resolves to itself.
--- When realm is omitted, searches all realms.
--- Lookups are case-insensitive (normalized roster keys).
function GMG.GetMainOf(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local nameKey = normalizeKey(name)
    local function fromRealm(rt)
        if not rt or not nameKey then return nil end
        local entry = rt[name]
        if not entry then
            for n, e in pairs(rt) do
                if normalizeKey(n) == nameKey then
                    entry = e
                    break
                end
            end
        end
        if entry and entry.main then
            return entry.main
        end
        for _, m in pairs(rt) do
            if m and type(m.main) == "string" and normalizeKey(m.main) == nameKey then
                return m.main
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

--- Walk name→main edges until a root (self-main, unmapped, or cycle).
--- On cycle returns the starting `name`. Unknown/unmapped returns `name`.
function GMG.GetUltimateMain(name, realm)
    if type(name) ~= "string" or name == "" then return name end
    local rt = realmTable(realm or "?", false)
    if not rt then return name end
    local current = name
    local seen = {}
    while true do
        local key = normalizeKey(current)
        if not key then return current end
        if seen[key] then
            return name
        end
        seen[key] = true
        local entry = rt[current]
        -- Also try case-insensitive lookup if exact key miss.
        if not entry then
            for n, e in pairs(rt) do
                if normalizeKey(n) == key then
                    entry = e
                    break
                end
            end
        end
        if not entry or type(entry.main) ~= "string" or entry.main == "" then
            return current
        end
        local mainKey = normalizeKey(entry.main)
        if mainKey and mainKey == key then
            return entry.main
        end
        current = entry.main
    end
end

--- Assign `name` under `main`, resolving `main` to its root and reparenting any
--- characters that currently list `name` as their main onto that root.
--- Self-assignment writes an anchor; alts already under `name` stay put.
--- When `main`'s chain already includes `name` (would form a cycle), breaks the
--- cycle by promoting `main` to the new root.
function GMG.AssignToGroup(name, realm, main, opts)
    if type(name) ~= "string" or name == "" then return end
    if type(main) ~= "string" or main == "" then return end
    realm = realm or "?"
    local nameKey = normalizeKey(name)
    local resolved = GMG.GetUltimateMain(main, realm)
    if not resolved or resolved == "" then
        resolved = main
    end
    local root = resolved
    local resolvedKey = normalizeKey(resolved)
    -- Cycle: main's chain already ends at `name`. Promote `main` as the new root.
    if nameKey and resolvedKey and nameKey == resolvedKey and normalizeKey(main) ~= nameKey then
        root = main
    end
    local rootKey = normalizeKey(root)
    GMG.SetMapping(name, realm, root, opts)
    -- Reparent former children of `name` onto `root` (no-op when name is the root,
    -- since they already point at name/root).
    if nameKey and rootKey and nameKey ~= rootKey then
        local rt = realmTable(realm, false)
        if rt then
            local toReparent = {}
            for n, entry in pairs(rt) do
                if entry and type(entry.main) == "string"
                    and normalizeKey(entry.main) == nameKey
                    and normalizeKey(n) ~= nameKey then
                    toReparent[#toReparent + 1] = n
                end
            end
            for _, n in ipairs(toReparent) do
                local entry = rt[n]
                GMG.SetMapping(n, realm, root, {
                    guild = (opts and opts.guild) or (entry and entry.guild),
                    origin = entry and entry.origin,
                })
            end
        end
    end
end

--- Persist a notes/manual-wizard proposal: write the main anchor and new members via
--- AssignToGroup, skip alreadyMapped members, and RemoveMapping for each name in
--- `proposal.removedMappedNames`.
--- Removals are applied before assignments so a remove-then-re-add (name in both
--- `removedMappedNames` and `members`) ends mapped under the proposal main.
--- `classLevelFn(name)` optional → classFile, level.
--- `opts.origin` optional (default "note"); manual wizard passes "user".
function GMG.ApplyProposal(proposal, realm, guild, classLevelFn, opts)
    if type(proposal) ~= "table" then return end
    local main = proposal.main
    if type(main) ~= "string" or main == "" then return end
    realm = realm or "?"
    opts = opts or {}
    local origin = opts.origin or "note"
    local function classLevel(name)
        if type(classLevelFn) == "function" then
            return classLevelFn(name)
        end
        return nil, nil
    end
    for _, removedName in ipairs(proposal.removedMappedNames or {}) do
        if type(removedName) == "string" and removedName ~= "" then
            GMG.RemoveMapping(removedName, realm)
        end
    end
    local mainClass, mainLevel = classLevel(main)
    GMG.AssignToGroup(main, realm, main, {
        guild = guild, origin = origin, classFile = mainClass, level = mainLevel,
    })
    for _, member in ipairs(proposal.members or {}) do
        if member and type(member.name) == "string" and member.name ~= ""
            and not member.alreadyMapped
            and normalizeKey(member.name) ~= normalizeKey(main) then
            local classFile, level = classLevel(member.name)
            GMG.AssignToGroup(member.name, realm, main, {
                guild = guild,
                origin = origin,
                noteText = member.noteText,
                noteHash = member.noteHash,
                classFile = classFile,
                level = level,
            })
        end
    end
end

--- Flat list of { name, realm, main, guild, origin, noteText, noteHash, classFile, level, ... } for a guild.
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
                    classFile = entry.classFile,
                    level = entry.level,
                    createdAt = entry.createdAt,
                    updatedAt = entry.updatedAt,
                }
            end
        end
    end
    return out
end

--- Update stored classFile/level for manual mappings from a roster info map
--- (nameLower -> { classFile, level, name, ... }). Returns count of mappings updated.
--- When realm is omitted, refreshes all realms.
function GMG.RefreshFromRosterInfo(rosterInfoMap, realm)
    if type(rosterInfoMap) ~= "table" then return 0 end
    local d = ensure()
    local updated = 0
    local function refreshRealm(rt)
        if not rt then return end
        for name, entry in pairs(rt) do
            if type(entry) == "table" then
                local infoKey = string.lower(name)
                local GTD = AltArmy.GuildTabData
                if GTD and GTD.NormalizeRosterName then
                    infoKey = GTD.NormalizeRosterName(name) or infoKey
                end
                local info = rosterInfoMap[infoKey]
                if type(info) == "table" then
                    local changed = false
                    if type(info.classFile) == "string" and info.classFile ~= ""
                        and entry.classFile ~= info.classFile then
                        entry.classFile = info.classFile
                        changed = true
                    end
                    local lvl = tonumber(info.level)
                    if lvl and lvl > 0 and entry.level ~= lvl then
                        entry.level = lvl
                        changed = true
                    end
                    if changed then
                        entry.updatedAt = now()
                        updated = updated + 1
                    end
                end
            end
        end
    end
    if realm ~= nil then
        refreshRealm(d.manual[realm])
    else
        for _, rt in pairs(d.manual) do
            refreshRealm(rt)
        end
    end
    return updated
end

--- True when addon-received (or local) character data covers this name+realm.
function GMG.IsShadowed(name, realm)
    local GSD = AltArmy.GuildShareData
    if not GSD or not GSD.GetCharacter then return false end
    return GSD.GetCharacter(name, realm) ~= nil
end

--- Remove every mapping whose main equals `main` (case-insensitive). Returns count removed.
function GMG.RemoveGroup(main, realm)
    if type(main) ~= "string" or main == "" then return 0 end
    local mainKey = normalizeKey(main)
    local removed = 0
    local d = ensure()
    local function purgeRealm(rt)
        if not rt then return end
        for name, entry in pairs(rt) do
            if entry and type(entry.main) == "string"
                and normalizeKey(entry.main) == mainKey then
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
--- Comparison is case-insensitive (normalized roster keys).
function GMG.RetireIfAgrees(name, realm, effectiveMain)
    local entry = GMG.GetMapping(name, realm)
    if not entry then return false end
    local mappedKey = normalizeKey(entry.main)
    local effectiveKey = normalizeKey(effectiveMain)
    if mappedKey and effectiveKey and mappedKey == effectiveKey then
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
