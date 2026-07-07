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

--- Placeholder for the per-character recipe search field in the Guild tab (plain name, not class-colored).
function GTD.FormatRecipeSearchPlaceholder(characterName)
    local name = characterName
    if not name or name == "" then
        name = "this character"
    end
    return "Search for recipes on " .. name
end

--- Filter recipe rows by case-insensitive substring on resolved recipe name.
function GTD.FilterRecipesBySearch(recipes, query, getRecipeName)
    local q = GTD.NormalizeSearchQuery(query)
    if q == "" then
        return recipes or {}
    end
    local out = {}
    for _, recipe in ipairs(recipes or {}) do
        local name = getRecipeName and getRecipeName(recipe) or ""
        if (name or ""):lower():find(q, 1, true) then
            out[#out + 1] = recipe
        end
    end
    return out
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

--- A character's primary crafting professions (rank > 0), each { key, name, rank, spec }, sorted by
--- highest skill rank first, then alphabetically by name for ties.
function GTD.GetPrimaryProfessions(entry)
    local out = {}
    local profs = entry and entry.Professions
    if type(profs) ~= "table" then return out end
    for key, prof in pairs(profs) do
        if GTD.PRIMARY_PROFESSION_KEYS[key] and (prof.rank or 0) > 0 then
            out[#out + 1] = {
                key = key,
                name = prof.name or key,
                rank = prof.rank or 0,
                spec = prof.spec,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

local function findProfessionByKey(char, profKey)
    if not char or type(char.Professions) ~= "table" or not profKey then return nil end
    local prof = char.Professions[profKey]
    if prof then return prof end
    local SS = AltArmy.SearchSettings
    local label = SS and SS.PROFESSION_LABELS and SS.PROFESSION_LABELS[profKey]
    if label and char.Professions[label] then
        return char.Professions[label]
    end
    for name, p in pairs(char.Professions) do
        local key = (SS and SS.ResolveProfessionKey and SS.ResolveProfessionKey(name)) or name
        if key == profKey then return p end
    end
    return nil
end

local function buildRecipeList(prof)
    local P = AltArmy.GuildShareProtocol
    local ids = (P and P.GetPrimaryRecipeIDs and P.GetPrimaryRecipeIDs(prof)) or {}
    local out = {}
    local recipes = prof and prof.Recipes or {}
    for _, id in ipairs(ids) do
        local data = recipes[id]
        local resultItemID
        if type(data) == "table" and data.resultItemID then
            resultItemID = data.resultItemID
        end
        out[#out + 1] = { recipeID = id, resultItemID = resultItemID }
    end
    return out
end

--- Resolve full character data for recipe lookup (DataStore for local, GuildShareData otherwise).
function GTD.GetStoredCharacter(entry)
    if not entry or not entry.name then return nil end
    if entry.source == "local" then
        local DS = AltArmy.DataStore
        if DS and DS.GetCharacters then
            local chars = DS:GetCharacters(entry.realm)
            return chars and chars[entry.name] or nil
        end
        return nil
    end
    local GSD = AltArmy.GuildShareData
    return GSD and GSD.GetCharacter and GSD.GetCharacter(entry.name, entry.realm) or nil
end

--- Enrich a guild-tab recipe row with optional CraftLib skill metadata (mutates entry).
function GTD.EnrichRecipeEntry(recipe, professionName, skillRank)
    local entry = {
        recipeID = recipe and recipe.recipeID,
        resultItemID = recipe and recipe.resultItemID,
        professionName = professionName,
        skillRank = skillRank or 0,
    }
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    if RCL and RCL.EnrichEntry then
        RCL.EnrichEntry(entry)
    end
    return entry
end

--- Skill column text for a recipe row (same formatting as Search recipe results).
function GTD.FormatRecipeSkillCell(recipe, professionName, skillRank)
    local entry = GTD.EnrichRecipeEntry(recipe, professionName, skillRank)
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    if RCL and RCL.FormatSkillCell then
        return RCL.FormatSkillCell(entry.recipeSkillRequired, entry.skillRank, entry.difficulty)
    end
    return tostring(entry.skillRank or 0)
end

local DIFFICULTY_SORT_ORDER = { orange = 1, yellow = 2, green = 3, gray = 4 }

local function cmpValues(a, b)
    if a < b then return -1 end
    if a > b then return 1 end
    return 0
end

local function recipeNameLower(recipe, getRecipeName)
    if getRecipeName then
        return (getRecipeName(recipe) or ""):lower()
    end
    return ""
end

--- Sort recipe rows for the guild recipe list (`sortKey`: "recipe" or "skill").
function GTD.SortRecipes(recipes, sortKey, ascending, opts)
    local out = {}
    for i = 1, #(recipes or {}) do
        out[i] = recipes[i]
    end
    if #out < 2 then
        return out
    end
    opts = opts or {}
    local profName = opts.professionName
    local skillRank = opts.skillRank or 0
    local getRecipeName = opts.getRecipeName
    local key = sortKey == "skill" and "skill" or "recipe"

    table.sort(out, function(a, b)
        local cmp = 0
        if key == "skill" then
            local entryA = GTD.EnrichRecipeEntry(a, profName, skillRank)
            local entryB = GTD.EnrichRecipeEntry(b, profName, skillRank)
            local reqA = entryA.recipeSkillRequired
            local reqB = entryB.recipeSkillRequired
            if reqA == nil and reqB == nil then
                cmp = 0
            elseif reqA == nil then
                cmp = 1
            elseif reqB == nil then
                cmp = -1
            else
                cmp = cmpValues(reqA, reqB)
                if cmp == 0 then
                    local ordA = DIFFICULTY_SORT_ORDER[entryA.difficulty] or 99
                    local ordB = DIFFICULTY_SORT_ORDER[entryB.difficulty] or 99
                    cmp = cmpValues(ordA, ordB)
                end
            end
        end
        if cmp == 0 then
            cmp = cmpValues(recipeNameLower(a, getRecipeName), recipeNameLower(b, getRecipeName))
        end
        if cmp == 0 then
            cmp = cmpValues(a.recipeID or 0, b.recipeID or 0)
        end
        if not ascending then
            cmp = -cmp
        end
        return cmp < 0
    end)
    return out
end

--- Primary (non-alias) recipes for one profession, sorted by recipe id.
function GTD.GetProfessionRecipes(entry, profKey)
    if not entry or not profKey or profKey == "" then return {} end
    local char = GTD.GetStoredCharacter(entry)
    local prof
    if char then
        prof = findProfessionByKey(char, profKey)
    end
    if not prof and entry.Professions then
        prof = entry.Professions[profKey]
    end
    if not prof then return {} end
    return buildRecipeList(prof)
end

local function formatNamePart(entry, formatName)
    local name = entry.name or "?"
    if formatName then
        return formatName(name, entry.classFile)
    end
    local CC = AltArmy.ClassColor
    return (CC and CC.formatName and CC.formatName(name, entry.classFile)) or name
end

--- Class-colored character name for detail headers (no level suffix).
function GTD.FormatCharacterTitle(entry, formatName)
    return formatNamePart(entry, formatName)
end

--- Message when a character has no primary crafting professions.
function GTD.FormatNoProfessionsMessage(entry, formatName)
    return formatNamePart(entry, formatName) .. " has not picked professions yet"
end

--- Sorted unique guild names from account characters that have a guild set.
function GTD.CollectAccountGuilds()
    local seen = {}
    local out = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter then return out end
    DS:ForEachCharacter(function(_, _, charData)
        local guild = charData and charData.guildName
        if guild and guild ~= "" and not seen[guild] then
            seen[guild] = true
            out[#out + 1] = guild
        end
    end)
    table.sort(out, function(a, b)
        return a:lower() < b:lower()
    end)
    return out
end

--- When the account has exactly one guild, return it for automatic browse selection.
function GTD.GetAutoBrowseGuild(guilds)
    if type(guilds) ~= "table" or #guilds ~= 1 then return nil end
    return guilds[1]
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

--- Preferred name for a main group row (class-colored when formatName is supplied).
--- Optional `query` highlights matching substrings in the preferred name.
function GTD.FormatMainRowName(group, formatName, query)
    local name = group.preferredName or group.main or "?"
    if query and GTD.NormalizeSearchQuery(query) ~= "" then
        return GTD.FormatTextWithSearchHighlight(name, group.classFile, query, formatName)
    end
    if formatName then
        return formatName(name, group.classFile)
    end
    return name
end

--- Character-count suffix for a main group row (plain text).
function GTD.FormatMainRowCount(group)
    local count = group.characterCount or #(group.members or {})
    local noun = count == 1 and "character" or "characters"
    return count .. " " .. noun
end

--- Main-row label: "{preferred name} -- {N} character(s)". When `formatName` is supplied
--- the preferred name is colored (by the main's class); the count suffix stays plain.
--- Optional `query` highlights matching substrings in the preferred name.
function GTD.FormatMainRowLabel(group, formatName, query)
    return GTD.FormatMainRowName(group, formatName, query) .. " " .. GTD.FormatMainRowCount(group)
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
