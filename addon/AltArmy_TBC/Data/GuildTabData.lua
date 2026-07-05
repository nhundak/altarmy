-- AltArmy TBC — Guild tab: pure grouping / sorting / filtering / formatting helpers.
-- No frames or comm; consumes the flat member list from GuildShareData.GetGuildMembersForDisplay
-- and produces the main-grouped, sorted, filtered view the Guild tab UI renders.

if not AltArmy then return end

AltArmy.GuildTabData = AltArmy.GuildTabData or {}
local GTD = AltArmy.GuildTabData

local GRAY = "|cff808080"

-- Crafting professions shown on character rows. Gathering + secondary skills
-- (cooking, first aid, fishing, mining, herbalism, skinning, riding) and poisons are omitted.
GTD.PRIMARY_PROFESSION_KEYS = {
    alchemy = true,
    blacksmithing = true,
    enchanting = true,
    engineering = true,
    jewelcrafting = true,
    leatherworking = true,
    tailoring = true,
}

--- A character's primary crafting professions (rank > 0), each { name, rank, spec }, sorted by
--- highest skill rank first, then alphabetically by name for ties.
function GTD.GetPrimaryProfessions(entry)
    local out = {}
    local profs = entry and entry.Professions
    if type(profs) ~= "table" then return out end
    for key, prof in pairs(profs) do
        if GTD.PRIMARY_PROFESSION_KEYS[key] and (prof.rank or 0) > 0 then
            out[#out + 1] = { name = prof.name or key, rank = prof.rank or 0, spec = prof.spec }
        end
    end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

--- Group a flat member list by main character, producing sorted groups.
--- Each group: { main, preferredName, characterCount, classFile, members = { sorted } }.
function GTD.GroupMembersByMain(members)
    local groups = {}
    local order = {}
    for _, m in ipairs(members or {}) do
        local mainKey = m.main or m.name
        local g = groups[mainKey]
        if not g then
            g = { main = mainKey, members = {} }
            groups[mainKey] = g
            order[#order + 1] = g
        end
        g.members[#g.members + 1] = m
    end

    for _, g in ipairs(order) do
        table.sort(g.members, function(a, b)
            local la, lb = a.level or 0, b.level or 0
            if la ~= lb then return la > lb end
            return (a.name or "") < (b.name or "")
        end)
        for _, m in ipairs(g.members) do
            if m.isMain or m.name == g.main then
                g.preferredName = m.displayName or m.main
                g.classFile = m.classFile
                break
            end
        end
        g.preferredName = g.preferredName or g.main
        g.characterCount = #g.members
    end

    table.sort(order, function(a, b)
        return (a.preferredName or ""):lower() < (b.preferredName or ""):lower()
    end)
    return order
end

--- Case-insensitive substring match against preferred name, main name, and alt names.
local function groupMatchesQuery(group, query)
    if (group.preferredName or ""):lower():find(query, 1, true) then return true end
    if (group.main or ""):lower():find(query, 1, true) then return true end
    for _, m in ipairs(group.members or {}) do
        if (m.name or ""):lower():find(query, 1, true) then return true end
    end
    return false
end

--- Filter groups by a search query (empty/nil returns all groups unchanged).
function GTD.FilterGroups(groups, query)
    local trimmed = query and query:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return groups end
    trimmed = trimmed:lower()
    local out = {}
    for _, g in ipairs(groups or {}) do
        if groupMatchesQuery(g, trimmed) then
            out[#out + 1] = g
        end
    end
    return out
end

--- Main-row label: "{preferred name} -- {N} character(s)". When `formatName` is supplied
--- the preferred name is colored (by the main's class); the count suffix stays plain.
function GTD.FormatMainRowLabel(group, formatName)
    local count = group.characterCount or #(group.members or {})
    local noun = count == 1 and "character" or "characters"
    local name = group.preferredName or group.main or "?"
    if formatName then
        name = formatName(name, group.classFile)
    end
    return name .. " " .. count .. " " .. noun
end

--- Character name column: class-colored name + gray "(level N)".
function GTD.FormatCharacterName(entry, formatName)
    local name = entry.name or "?"
    local namePart
    if formatName then
        namePart = formatName(name, entry.classFile)
    else
        local CC = AltArmy.ClassColor
        namePart = (CC and CC.formatName and CC.formatName(name, entry.classFile)) or name
    end
    local level = math.floor(tonumber(entry.level) or 0)
    return namePart .. " " .. GRAY .. "(level " .. level .. ")|r"
end

--- Professions column: "Name — Spec (rank), ..." with the specialization (when present) after
--- an em dash in the default (white) color and the gray skill level in parentheses.
--- Empty string when the character has no primary crafting professions.
function GTD.FormatProfessions(entry)
    local parts = {}
    for _, prof in ipairs(GTD.GetPrimaryProfessions(entry)) do
        local spec = (prof.spec and prof.spec ~= "") and (" \226\128\148 " .. prof.spec) or ""
        parts[#parts + 1] = prof.name .. spec .. " " .. GRAY .. "(" .. prof.rank .. ")|r"
    end
    return table.concat(parts, ", ")
end
