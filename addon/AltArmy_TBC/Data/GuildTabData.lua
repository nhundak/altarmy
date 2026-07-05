-- AltArmy TBC — Guild tab: pure grouping / sorting / filtering / formatting helpers.
-- No frames or comm; consumes the flat member list from GuildShareData.GetGuildMembersForDisplay
-- and produces the main-grouped, sorted, filtered view the Guild tab UI renders.

if not AltArmy then return end

AltArmy.GuildTabData = AltArmy.GuildTabData or {}
local GTD = AltArmy.GuildTabData

local GRAY = "|cff808080"
local SEARCH_MATCH_COLOR = "|cff00ff00"

--- Trim and lowercase a guild-tab search query; empty string when absent.
function GTD.NormalizeSearchQuery(query)
    local trimmed = query and query:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return "" end
    return trimmed:lower()
end

--- Highlight every case-insensitive substring match in bright green; other segments use
--- `formatSegment(text, classFile)` when supplied (typically class-colored name text).
function GTD.FormatTextWithSearchHighlight(text, classFile, query, formatSegment)
    text = text or "?"
    query = GTD.NormalizeSearchQuery(query)
    if query == "" then
        if formatSegment then return formatSegment(text, classFile) end
        return text
    end

    local lowerText = text:lower()
    local parts = {}
    local pos = 1
    while pos <= #text do
        local matchStart, matchEnd = lowerText:find(query, pos, true)
        if not matchStart then
            local rest = text:sub(pos)
            if rest ~= "" then
                parts[#parts + 1] = formatSegment and formatSegment(rest, classFile) or rest
            end
            break
        end
        if matchStart > pos then
            local before = text:sub(pos, matchStart - 1)
            parts[#parts + 1] = formatSegment and formatSegment(before, classFile) or before
        end
        parts[#parts + 1] = SEARCH_MATCH_COLOR .. text:sub(matchStart, matchEnd) .. "|r"
        pos = matchEnd + 1
    end
    return table.concat(parts)
end

local function nameMatchesQuery(name, query)
    return query ~= "" and (name or ""):lower():find(query, 1, true) ~= nil
end

local function professionMatchesQuery(prof, query)
    if nameMatchesQuery(prof.name, query) then return true end
    if prof.spec and nameMatchesQuery(prof.spec, query) then return true end
    return false
end

local function entryMatchesQuery(entry, query)
    if nameMatchesQuery(entry.name, query) then return true end
    for _, prof in ipairs(GTD.GetPrimaryProfessions(entry)) do
        if professionMatchesQuery(prof, query) then return true end
    end
    return false
end

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

--- Filter groups by a search query (empty/nil returns all groups unchanged).
--- Omits groups with no match on preferred name, main name, any character name, or profession.
--- When preferred or main name matches, all characters in the group are shown; otherwise only
--- characters matching on name or profession are included.
function GTD.FilterGroups(groups, query)
    local q = GTD.NormalizeSearchQuery(query)
    if q == "" then return groups end
    local out = {}
    for _, g in ipairs(groups or {}) do
        local preferredMatch = nameMatchesQuery(g.preferredName, q)
        local mainMatch = nameMatchesQuery(g.main, q)
        local groupNameMatch = preferredMatch or mainMatch
        local matchedMembers = {}
        if groupNameMatch then
            for _, m in ipairs(g.members or {}) do
                matchedMembers[#matchedMembers + 1] = m
            end
        else
            for _, m in ipairs(g.members or {}) do
                if entryMatchesQuery(m, q) then
                    matchedMembers[#matchedMembers + 1] = m
                end
            end
        end
        if groupNameMatch or #matchedMembers > 0 then
            out[#out + 1] = {
                main = g.main,
                preferredName = g.preferredName,
                classFile = g.classFile,
                members = matchedMembers,
                characterCount = #matchedMembers,
            }
        end
    end
    return out
end

--- Main-row label: "{preferred name} -- {N} character(s)". When `formatName` is supplied
--- the preferred name is colored (by the main's class); the count suffix stays plain.
--- Optional `query` highlights matching substrings in the preferred name.
function GTD.FormatMainRowLabel(group, formatName, query)
    local count = group.characterCount or #(group.members or {})
    local noun = count == 1 and "character" or "characters"
    local name = group.preferredName or group.main or "?"
    if query and GTD.NormalizeSearchQuery(query) ~= "" then
        name = GTD.FormatTextWithSearchHighlight(name, group.classFile, query, formatName)
    elseif formatName then
        name = formatName(name, group.classFile)
    end
    return name .. " " .. count .. " " .. noun
end

--- Character name column: class-colored name + gray "(level N)".
--- Optional `query` highlights matching substrings in the character name.
function GTD.FormatCharacterName(entry, formatName, query)
    local name = entry.name or "?"
    local namePart
    if query and GTD.NormalizeSearchQuery(query) ~= "" then
        namePart = GTD.FormatTextWithSearchHighlight(name, entry.classFile, query, formatName)
    elseif formatName then
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
--- Optional `query` highlights matching substrings in profession names and specializations.
--- Empty string when the character has no primary crafting professions.
function GTD.FormatProfessions(entry, query)
    local activeQuery = query and GTD.NormalizeSearchQuery(query) or ""
    local parts = {}
    for _, prof in ipairs(GTD.GetPrimaryProfessions(entry)) do
        local profName = prof.name
        if activeQuery ~= "" then
            profName = GTD.FormatTextWithSearchHighlight(prof.name, nil, activeQuery)
        end
        local spec = ""
        if prof.spec and prof.spec ~= "" then
            local specText = prof.spec
            if activeQuery ~= "" then
                specText = GTD.FormatTextWithSearchHighlight(prof.spec, nil, activeQuery)
            end
            spec = " \226\128\148 " .. specText
        end
        parts[#parts + 1] = profName .. spec .. " " .. GRAY .. "(" .. prof.rank .. ")|r"
    end
    return table.concat(parts, ", ")
end
