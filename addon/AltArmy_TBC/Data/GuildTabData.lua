-- AltArmy TBC — Guild tab: pure grouping / sorting / filtering / formatting helpers.
-- No frames or comm; consumes the flat member list from GuildShareData.GetGuildMembersForDisplay
-- and produces the main-grouped, sorted, filtered view the Guild tab UI renders.
-- Also provides guild-roster last-online helpers
-- (BuildRosterLastOnlineMap / FormatRosterLastOnline / GetDefaultListSort).

if not AltArmy then return end

AltArmy.GuildTabData = AltArmy.GuildTabData or {}
local GTD = AltArmy.GuildTabData

local GRAY = "|cff808080"
local GUILD_TAG_COLOR = "|cff8ab4f8"
local WHITE = "|cffffffff"
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

--- True when both lists have the same ordered recipeIDs (content equality, not table identity).
--- Used to preserve guild recipe-list scroll across refreshes that rebuild row tables.
function GTD.AreRecipeListsEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        local ai, bi = a[i], b[i]
        if type(ai) ~= "table" or type(bi) ~= "table" then return false end
        local idA, idB = ai.recipeID, bi.recipeID
        if idA ~= idB and tonumber(idA) ~= tonumber(idB) then
            return false
        end
    end
    return true
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

-- Crafting professions (recipe tabs + left side of character-row profession list).
GTD.PRIMARY_PROFESSION_KEYS = {
    alchemy = true,
    blacksmithing = true,
    enchanting = true,
    engineering = true,
    jewelcrafting = true,
    leatherworking = true,
    tailoring = true,
}

-- Gathering professions shown on character rows (right of crafting). Not recipe tabs.
-- Secondary skills (cooking, first aid, fishing, riding), poisons, and lockpicking are omitted.
GTD.GATHERING_PROFESSION_KEYS = {
    herbalism = true,
    mining = true,
    skinning = true,
}

local function sortProfessionsByRankThenName(list)
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.name:lower() < b.name:lower()
    end)
end

--- Map a stored profession table key (or display name) to a stable crafting/gathering key.
--- Returns nil for secondary skills, poisons, lockpicking, and unknown professions.
local function resolveDisplayProfessionKey(key, prof)
    if type(key) ~= "string" or key == "" then return nil end
    if GTD.PRIMARY_PROFESSION_KEYS[key] or GTD.GATHERING_PROFESSION_KEYS[key] then
        return key
    end
    local lower = key:lower()
    if GTD.PRIMARY_PROFESSION_KEYS[lower] or GTD.GATHERING_PROFESSION_KEYS[lower] then
        return lower
    end
    local name = prof and prof.name
    if type(name) == "string" and name ~= "" then
        local nameLower = name:lower()
        if GTD.PRIMARY_PROFESSION_KEYS[nameLower] or GTD.GATHERING_PROFESSION_KEYS[nameLower] then
            return nameLower
        end
    end
    return nil
end

local function collectProfessions(entry, includeGathering)
    local crafting = {}
    local gathering = {}
    local profs = entry and entry.Professions
    if type(profs) ~= "table" then
        return crafting, gathering
    end
    for key, prof in pairs(profs) do
        if (prof.rank or 0) > 0 then
            local resolved = resolveDisplayProfessionKey(key, prof)
            if resolved then
                local row = {
                    key = resolved,
                    name = prof.name or key,
                    rank = prof.rank or 0,
                    spec = prof.spec,
                }
                if GTD.GATHERING_PROFESSION_KEYS[resolved] then
                    if includeGathering then
                        gathering[#gathering + 1] = row
                    end
                else
                    crafting[#crafting + 1] = row
                end
            end
        end
    end
    sortProfessionsByRankThenName(crafting)
    if includeGathering then
        sortProfessionsByRankThenName(gathering)
    end
    return crafting, gathering
end

--- Character-row professions (rank > 0): crafting first, then gathering on the right.
--- Each entry is { key, name, rank, spec }. Within each group: highest rank first, then name.
function GTD.GetPrimaryProfessions(entry)
    local crafting, gathering = collectProfessions(entry, true)
    local out = {}
    for i = 1, #crafting do
        out[#out + 1] = crafting[i]
    end
    for i = 1, #gathering do
        out[#out + 1] = gathering[i]
    end
    return out
end

--- Crafting-only professions for recipe tabs (excludes gathering).
function GTD.GetCraftingProfessions(entry)
    local crafting = collectProfessions(entry, false)
    return crafting
end

local function hasAnyProfessionWithRank(entry)
    local profs = entry and entry.Professions
    if type(profs) ~= "table" then return false end
    for _, prof in pairs(profs) do
        if (prof.rank or 0) > 0 then
            return true
        end
    end
    return false
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

local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- Prefer icons that do not require the item cache (GetItemIcon / GetItemInfoInstant).
local function resolveItemIcon(itemID)
    if not itemID then return nil end
    if GetItemIcon then
        local icon = GetItemIcon(itemID)
        if icon then return icon end
    end
    if GetItemInfoInstant then
        local _, _, _, _, icon = GetItemInfoInstant(itemID)
        if icon then return icon end
    end
    if GetItemInfo then
        local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
        if icon then return icon end
    end
    return nil
end

--- Resolve recipe display name and icon for guild-tab rows.
--- Returns recipeName, iconPath, pendingItemID (item id to watch via GET_ITEM_INFO_RECEIVED, or nil).
function GTD.ResolveRecipeDisplay(recipeID, resultItemID)
    local recipeName = "Recipe " .. tostring(recipeID or "?")
    local iconPath = QUESTION_MARK_ICON
    local pendingItemID = nil

    if GetSpellInfo and recipeID then
        local name = GetSpellInfo(recipeID)
        if name then recipeName = name end
    end
    if recipeName == ("Recipe " .. tostring(recipeID or "?")) and GetItemInfo and recipeID then
        local name = GetItemInfo(recipeID)
        if name then recipeName = name end
    end

    if resultItemID then
        local icon = resolveItemIcon(resultItemID)
        if icon then
            iconPath = icon
        else
            pendingItemID = resultItemID
        end
    elseif recipeID then
        local icon = resolveItemIcon(recipeID)
        if icon then
            iconPath = icon
        elseif GetSpellInfo then
            local _, _, spellIcon = GetSpellInfo(recipeID)
            if spellIcon then
                iconPath = spellIcon
            else
                pendingItemID = recipeID
            end
        else
            pendingItemID = recipeID
        end
    end

    return recipeName, iconPath, pendingItemID
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

--- Default recipe list sort when opening a character's recipes.
--- With CraftLib: required skill descending (highest first). Otherwise: name ascending.
function GTD.GetDefaultRecipeSort(craftLibAvailable)
    if craftLibAvailable then
        return "skill", false
    end
    return "recipe", true
end

--- Default guild list sort.
--- When roster last-online can be looked up (player is in that guild): online ascending
--- (most recently online first). Otherwise: name ascending.
function GTD.GetDefaultListSort(canLookupOnline)
    if canLookupOnline then
        return "online", true
    end
    return "name", true
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
            -- Unknown required skill sorts as 0 (not as "very high").
            local reqA = entryA.recipeSkillRequired or 0
            local reqB = entryB.recipeSkillRequired or 0
            cmp = cmpValues(reqA, reqB)
            if cmp == 0 then
                local ordA = DIFFICULTY_SORT_ORDER[entryA.difficulty] or 99
                local ordB = DIFFICULTY_SORT_ORDER[entryB.difficulty] or 99
                cmp = cmpValues(ordA, ordB)
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

--- Empty-state copy when recipe tabs are unavailable.
--- Truly no professions → "No known professions for {name}".
--- Has professions but none crafting → "{name} has no professions with recipes".
function GTD.FormatNoProfessionsMessage(entry, formatName)
    local name = formatNamePart(entry, formatName)
    if hasAnyProfessionWithRank(entry) then
        return name .. " has no professions with recipes"
    end
    return "No known professions for " .. name
end

--- Empty-state copy when a profession is known but its recipe list is empty.
--- Second line (gray) explains recipes arrive when they open that profession screen.
function GTD.FormatNoProfessionRecipesMessage(entry, formatName, professionName)
    local name = formatNamePart(entry, formatName)
    local profession = (professionName and professionName ~= "") and professionName or "profession"
    return "No known " .. profession .. " recipes for " .. name
        .. "\n\n" .. GRAY .. "Data will be shared when they open their " .. profession .. " screen|r"
end

--- Sorted unique guild names from characters on `realm` that have a guild set.
function GTD.CollectGuildsOnRealm(realm)
    local seen = {}
    local out = {}
    if not realm or realm == "" then return out end
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCharacters then return out end
    for _, charData in pairs(DS:GetCharacters(realm) or {}) do
        local guild = charData and charData.guildName
        if guild and guild ~= "" and not seen[guild] then
            seen[guild] = true
            out[#out + 1] = guild
        end
    end
    table.sort(out, function(a, b)
        return a:lower() < b:lower()
    end)
    return out
end

--- Sorted unique guild names from all account characters that have a guild set.
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

--- True when any stored character on `realm` has a guild membership.
function GTD.HasGuildedCharactersOnRealm(realm)
    return #(GTD.CollectGuildsOnRealm(realm)) > 0
end

--- Guild tab button visibility: feature flag on and at least one guilded character
--- on the current realm.
function GTD.ShouldShowGuildTab(guildShareFlagOn, hasGuildedCharacters)
    if not guildShareFlagOn then return false end
    if not hasGuildedCharacters then return false end
    return true
end

--- Live evaluation using current addon state (current realm only).
function GTD.CanShowGuildTab()
    local D = AltArmy and AltArmy.Debug
    local flagOn = D and D.IsGuildShareEnabled and D.IsGuildShareEnabled() or false
    local realm
    local DS = AltArmy and AltArmy.DataStore
    if DS and DS.GetCurrentPlayerRealm then
        realm = DS:GetCurrentPlayerRealm()
    end
    if not realm or realm == "" then
        realm = (GetRealmName and GetRealmName()) or ""
    end
    return GTD.ShouldShowGuildTab(flagOn, GTD.HasGuildedCharactersOnRealm(realm))
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

-- Age at which received guildmate data is flagged as outdated in the Guild tab (not purged).
GTD.OLD_DATA_AGE_SEC = 60 * 60 * 24 * 14

--- True when a received (non-local) member's data is at least OLD_DATA_AGE_SEC old.
function GTD.IsMemberDataOld(member, nowTs, maxAgeSec)
    if not member or member.source == "local" then return false end
    local receivedAt = member.receivedAt
    if type(receivedAt) ~= "number" then return false end
    nowTs = nowTs or ((time and time()) or 0)
    maxAgeSec = maxAgeSec or GTD.OLD_DATA_AGE_SEC
    return (nowTs - receivedAt) >= maxAgeSec
end

--- True when any member in the group has outdated received data.
function GTD.GroupHasOldData(group, nowTs, maxAgeSec)
    if not group then return false end
    for _, m in ipairs(group.members or {}) do
        if GTD.IsMemberDataOld(m, nowTs, maxAgeSec) then
            return true
        end
    end
    return false
end

--- Tooltip body for the Guild tab old-data warning icon.
function GTD.GetOldDataTooltipText()
    return "This data is more than 14 days old. The guildmate has not shared an update recently."
end

--- True when this character is the player's explicitly marked main (not a deduced grouping main).
function GTD.IsExplicitMain(member)
    return member ~= nil and member.isMain == true and member.mainDeclared == true
end

--- Tooltip for the main-character star.
--- `isOwn == false` → "their"; otherwise "your".
--- @param name string|nil
--- @param classFile string|nil
--- @param isOwn boolean|nil
--- @return string
function GTD.FormatMainStarTooltip(name, classFile, isOwn)
    local CC = AltArmy.ClassColor
    local coloredName = CC and CC.formatName and CC.formatName(name, classFile)
        or ("|cffffffff" .. (name or "?") .. "|r")
    if isOwn == false then
        return coloredName .. " is their main character"
    end
    return coloredName .. " is your main character"
end

--- Present main-star tooltip. opts: name, classFile, isOwn, showConfigureHint
--- @return boolean true if tooltip was shown
function GTD.PresentMainStarTooltip(owner, anchor, opts)
    if not owner or not GameTooltip then return false end
    opts = opts or {}
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(
        GTD.FormatMainStarTooltip(opts.name, opts.classFile, opts.isOwn),
        1, 1, 1, true
    )
    if opts.showConfigureHint then
        GameTooltip:AddLine("Click to configure", 0.5, 0.5, 0.5, true)
    end
    GameTooltip:Show()
    return true
end

--- Display label for a main group: override → preferredName → main.
--- Optional `getOverride(group)` supplies an override when `group.overrideName` is unset.
function GTD.ResolveGroupDisplayName(group, getOverride)
    if not group then return "?" end
    local override = group.overrideName
    if (not override or override == "") and getOverride then
        override = getOverride(group)
    end
    if type(override) == "string" and override ~= "" then
        return override
    end
    return group.preferredName or group.main or "?"
end

--- True when `group.main` is the player's configured main.
function GTD.IsOwnGroup(group, ownMain)
    return group ~= nil and type(ownMain) == "string" and ownMain ~= "" and group.main == ownMain
end

--- Filter groups by a search query (empty/nil returns all groups unchanged).
--- Omits groups with no match on override/preferred/main name, any character name, or profession.
--- When preferred, override, or main name matches, all characters in the group are shown; otherwise only
--- characters matching on name or profession are included.
function GTD.FilterGroups(groups, query)
    local q = GTD.NormalizeSearchQuery(query)
    if q == "" then return groups end
    local out = {}
    for _, g in ipairs(groups or {}) do
        local preferredMatch = nameMatchesQuery(g.preferredName, q)
        local overrideMatch = nameMatchesQuery(g.overrideName, q)
        local mainMatch = nameMatchesQuery(g.main, q)
        local groupNameMatch = preferredMatch or overrideMatch or mainMatch
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
                overrideName = g.overrideName,
                pinned = g.pinned,
                prefsRealm = g.prefsRealm,
                classFile = g.classFile,
                members = matchedMembers,
                characterCount = #matchedMembers,
            }
        end
    end
    return out
end

--- Preferred/override name for a main group row (class-colored when formatName is supplied).
--- Optional `query` highlights matching substrings in the display name.
--- Main-row display name (class-colored). When `isOwn`, appends gray " (you)".
function GTD.FormatMainRowName(group, formatName, query, isOwn)
    local name = GTD.ResolveGroupDisplayName(group)
    local text
    if query and GTD.NormalizeSearchQuery(query) ~= "" then
        text = GTD.FormatTextWithSearchHighlight(name, group.classFile, query, formatName)
    elseif formatName then
        text = formatName(name, group.classFile)
    else
        text = name
    end
    if isOwn then
        text = text .. " " .. GRAY .. "(you)|r"
    end
    return text
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

--- Comparable online-sort value for a roster status.
--- Online is always 0 (least time). Offline uses years→months→days→hours so order matches
--- the displayed unit buckets. Unknown/missing is a large sentinel (most time).
GTD.ROSTER_ONLINE_SORT_UNKNOWN = 2000000000
GTD.ROSTER_ONLINE_SORT_OFFLINE_BASE = 1000000000

function GTD.RosterStatusSortValue(status)
    if not status then
        return GTD.ROSTER_ONLINE_SORT_UNKNOWN
    end
    if status.online then
        return 0
    end
    local years = status.years or 0
    local months = status.months or 0
    local days = status.days or 0
    local hours = status.hours or 0
    return GTD.ROSTER_ONLINE_SORT_OFFLINE_BASE
        + years * 1000000
        + months * 10000
        + days * 100
        + hours
end

--- Comparable online-sort value for a main group (most recent member status).
function GTD.GroupOnlineSortValue(group, rosterByName)
    return GTD.RosterStatusSortValue(GTD.GetGroupLastOnlineStatus(group, rosterByName or {}))
end

--- Comparable online-sort value for one character entry.
function GTD.MemberOnlineSortValue(member, rosterByName)
    if not member or type(rosterByName) ~= "table" then
        return GTD.ROSTER_ONLINE_SORT_UNKNOWN
    end
    local key = GTD.NormalizeRosterName(member.name)
    if not key then
        return GTD.ROSTER_ONLINE_SORT_UNKNOWN
    end
    return GTD.RosterStatusSortValue(rosterByName[key])
end

local function copyGroupWithMembers(group, members)
    return {
        main = group.main,
        preferredName = group.preferredName,
        overrideName = group.overrideName,
        pinned = group.pinned,
        prefsRealm = group.prefsRealm,
        classFile = group.classFile,
        characterCount = group.characterCount or #(members or {}),
        members = members,
    }
end

local function sortMembersForList(members, sortKey, ascending, rosterByName)
    local out = {}
    for i = 1, #(members or {}) do
        out[i] = members[i]
    end
    if #out < 2 then
        return out
    end
    local asc = ascending ~= false
    if sortKey == "online" then
        table.sort(out, function(a, b)
            local va = GTD.MemberOnlineSortValue(a, rosterByName)
            local vb = GTD.MemberOnlineSortValue(b, rosterByName)
            if va ~= vb then
                if asc then return va < vb end
                return va > vb
            end
            local na, nb = (a.name or ""):lower(), (b.name or ""):lower()
            if na ~= nb then return na < nb end
            return (a.name or "") < (b.name or "")
        end)
        return out
    end
    -- Default character order: highest level first, then name.
    table.sort(out, function(a, b)
        local la, lb = a.level or 0, b.level or 0
        if la ~= lb then return la > lb end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

--- Sort main groups for the guild list (`sortKey`: "name", "characterCount", or "online").
--- Optional `rosterByName` is required for meaningful "online" sorting.
--- Returns a new list; does not mutate `groups`. Name is the stable tie-breaker (always A→Z).
--- Pinned groups (`group.pinned`) always sort above unpinned; column sort applies within each bucket.
--- When sorting by online, members within each group are also ordered by last online.
function GTD.SortGroups(groups, sortKey, ascending, rosterByName)
    local out = {}
    for i = 1, #(groups or {}) do
        out[i] = groups[i]
    end
    if #out == 0 then
        return out
    end
    local key = sortKey
    if key ~= "characterCount" and key ~= "online" then
        key = "name"
    end
    local asc = ascending ~= false
    rosterByName = rosterByName or {}

    if #out >= 2 then
        table.sort(out, function(a, b)
            local aPinned = a.pinned and true or false
            local bPinned = b.pinned and true or false
            if aPinned ~= bPinned then
                return aPinned
            end
            local va, vb
            if key == "characterCount" then
                va = a.characterCount or #(a.members or {})
                vb = b.characterCount or #(b.members or {})
            elseif key == "online" then
                va = GTD.GroupOnlineSortValue(a, rosterByName)
                vb = GTD.GroupOnlineSortValue(b, rosterByName)
            else
                va = (GTD.ResolveGroupDisplayName(a)):lower()
                vb = (GTD.ResolveGroupDisplayName(b)):lower()
            end
            if va ~= vb then
                if asc then return va < vb end
                return va > vb
            end
            local na = (GTD.ResolveGroupDisplayName(a)):lower()
            local nb = (GTD.ResolveGroupDisplayName(b)):lower()
            if na ~= nb then
                return na < nb
            end
            return (a.main or "") < (b.main or "")
        end)
    end

    for i = 1, #out do
        local g = out[i]
        out[i] = copyGroupWithMembers(g, sortMembersForList(g.members, key, asc, rosterByName))
    end
    return out
end

--- Strip a realm suffix and lowercase a guild-roster or character name.
function GTD.NormalizeRosterName(name)
    if type(name) ~= "string" then return nil end
    local short = name:match("^[^%-]+") or name
    return short:lower()
end

--- Comparable offline duration in hours (approximate months as 30.5 days).
--- Online / missing status returns 0.
function GTD.RosterOfflineHours(status)
    if not status or status.online then return 0 end
    local years = status.years or 0
    local months = status.months or 0
    local days = status.days or 0
    local hours = status.hours or 0
    return (((years * 12) + months) * 30.5 + days) * 24 + hours
end

--- Display string for a roster last-online status. Empty when status is missing.
--- When `opts.showUnknownWhenMissing` is set, missing status returns gray "Unknown".
function GTD.FormatRosterLastOnline(status, opts)
    if not status then
        if opts and opts.showUnknownWhenMissing then
            return GRAY .. "Unknown|r"
        end
        return ""
    end
    if status.online then return "Online" end
    local years = status.years or 0
    local months = status.months or 0
    local days = status.days or 0
    local hours = status.hours or 0
    if years > 0 then return years .. "y ago" end
    if months > 0 then return months .. "mo ago" end
    if days > 0 then return days .. "d ago" end
    if hours > 0 then return hours .. "h ago" end
    return "< 1h ago"
end

--- Most recent status among a list: any online wins; otherwise shortest offline duration.
function GTD.PickMostRecentRosterStatus(statuses)
    if type(statuses) ~= "table" then return nil end
    local best
    local bestHours
    for _, status in ipairs(statuses) do
        if status then
            if status.online then
                return { online = true }
            end
            local hours = GTD.RosterOfflineHours(status)
            if not bestHours or hours < bestHours then
                bestHours = hours
                best = status
            end
        end
    end
    return best
end

--- Most recent last-online status for a main group, looking up each member in `rosterByName`.
function GTD.GetGroupLastOnlineStatus(group, rosterByName)
    if not group or type(rosterByName) ~= "table" then return nil end
    local statuses = {}
    for _, member in ipairs(group.members or {}) do
        local key = GTD.NormalizeRosterName(member.name)
        if key and key ~= "" then
            statuses[#statuses + 1] = rosterByName[key]
        end
    end
    return GTD.PickMostRecentRosterStatus(statuses)
end

--- Like GetGroupLastOnlineStatus, but also reports which member produced the status.
--- Returns `{ status, memberName, classFile }` or nil.
function GTD.GetGroupMostRecentOnlineDetail(group, rosterByName)
    if not group or type(rosterByName) ~= "table" then return nil end
    local best
    local bestMember
    local bestHours
    for _, member in ipairs(group.members or {}) do
        local key = GTD.NormalizeRosterName(member.name)
        if key and key ~= "" then
            local status = rosterByName[key]
            if status then
                if status.online then
                    return {
                        status = { online = true },
                        memberName = member.name,
                        classFile = member.classFile,
                    }
                end
                local hours = GTD.RosterOfflineHours(status)
                if not bestHours or hours < bestHours then
                    bestHours = hours
                    best = status
                    bestMember = member
                end
            end
        end
    end
    if best and bestMember then
        return {
            status = best,
            memberName = bestMember.name,
            classFile = bestMember.classFile,
        }
    end
    return nil
end

--- Tooltip presence line for a hovered guild character, or nil when roster info is missing.
--- Online is white; last-seen uses the same gray as search Offline. When the most recent
--- presence belongs to a different alt, appends " (as Name)" with Name class-colored via
--- formatName / ClassColor (surrounding text keeps white/gray, including parentheses).
function GTD.FormatGroupPresenceTooltipLine(hoveredName, detail, formatName)
    if not detail or not detail.status then
        return nil
    end
    local prefixColor = detail.status.online and WHITE or GRAY
    local body
    if detail.status.online then
        body = "Online"
    else
        local ago = GTD.FormatRosterLastOnline(detail.status)
        if not ago or ago == "" then
            return nil
        end
        body = "Last seen " .. ago
    end
    local hoverKey = GTD.NormalizeRosterName(hoveredName)
    local memberKey = GTD.NormalizeRosterName(detail.memberName)
    if memberKey and hoverKey and memberKey ~= hoverKey and detail.memberName and detail.memberName ~= "" then
        local asName = detail.memberName
        if formatName then
            asName = formatName(detail.memberName, detail.classFile)
        else
            local CC = AltArmy.ClassColor
            if CC and CC.formatName then
                asName = CC.formatName(detail.memberName, detail.classFile)
            end
        end
        return prefixColor .. body .. " (as |r" .. asName .. prefixColor .. ")|r"
    end
    return prefixColor .. body .. "|r"
end

--- Localized / display class name for tooltip copy.
function GTD.FormatClassDisplayName(classFile)
    if not classFile or classFile == "" then
        return "Unknown"
    end
    local male = _G.LOCALIZED_CLASS_NAMES_MALE
    if male and male[classFile] then
        return male[classFile]
    end
    local female = _G.LOCALIZED_CLASS_NAMES_FEMALE
    if female and female[classFile] then
        return female[classFile]
    end
    return classFile:sub(1, 1):upper() .. classFile:sub(2):lower()
end

--- Search-result character suffix for guildmate recipes: "(Guild Online/Offline)".
--- "Guild" stays in the guild tag color; Online is white, Offline is gray.
function GTD.FormatGuildSearchCharacterSuffix(isOnline)
    if isOnline then
        return GUILD_TAG_COLOR .. " (Guild |r" .. WHITE .. "Online|r" .. GUILD_TAG_COLOR .. ")|r"
    end
    return GUILD_TAG_COLOR .. " (Guild |r" .. GRAY .. "Offline|r" .. GUILD_TAG_COLOR .. ")|r"
end

local function colorTooltipName(name, classFile, formatName)
    if formatName then
        return formatName(name, classFile)
    end
    local CC = AltArmy.ClassColor
    if CC and CC.formatName then
        return CC.formatName(name, classFile)
    end
    return name
end

--- Tooltip lines for a collapsed "Multiple guildmates" recipe search row.
--- `chars` entries: `{ name, classFile, mainName?, mainClassFile?, status? }`.
--- Presence/sort use `c.status` when provided (caller supplies main-group / player presence);
--- otherwise fall back to individual `rosterByName` lookup by character name.
--- Sorted by last online via RosterStatusSortValue: online first (A–Z among online),
--- then shortest offline duration, unknown last (A–Z tie-break within equal status).
--- Character rows are `{ left = namePart, right = presence }` for GameTooltip:AddDoubleLine
--- (names left, times right-aligned). Footer lines are plain strings for AddLine:
--- optional white "...and N others", then gray "Click to expand/collapse".
--- opts.formatName?(name, classFile) optional class-color formatter.
function GTD.BuildCollapsedGuildRecipeTooltipLines(chars, rosterByName, opts)
    if type(chars) ~= "table" or #chars == 0 then
        return {}
    end
    opts = opts or {}
    rosterByName = rosterByName or {}
    local formatName = opts.formatName

    local rows = {}
    for i = 1, #chars do
        local c = chars[i]
        if c and c.name and c.name ~= "" then
            local status = c.status
            if status == nil then
                local key = GTD.NormalizeRosterName(c.name)
                status = key and rosterByName[key] or nil
            end
            local online = status and status.online and true or false
            rows[#rows + 1] = {
                name = c.name,
                classFile = c.classFile,
                mainName = c.mainName,
                mainClassFile = c.mainClassFile,
                online = online,
                status = status,
                -- Finite sort key (avoid math.huge; WoW table.sort mishandles inf).
                sortValue = GTD.RosterStatusSortValue(status),
                sortKey = (c.name or ""):lower(),
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.sortValue ~= b.sortValue then
            return a.sortValue < b.sortValue
        end
        return a.sortKey < b.sortKey
    end)

    local total = #rows
    local showCount = total
    local others = 0
    if total >= 10 then
        showCount = 8
        others = total - 8
    end

    local lines = {}
    for i = 1, showCount do
        local row = rows[i]
        local colored = colorTooltipName(row.name, row.classFile, formatName)
        local left = colored
        local main = row.mainName
        if main and main ~= "" and main:lower() ~= row.name:lower() then
            local mainColored = colorTooltipName(main, row.mainClassFile or row.classFile, formatName)
            left = colored .. " " .. WHITE .. "(|r" .. mainColored .. WHITE .. ")|r"
        end
        local presence
        if row.online then
            presence = WHITE .. "Online|r"
        else
            local ago = GTD.FormatRosterLastOnline(row.status, { showUnknownWhenMissing = true })
            -- FormatRosterLastOnline already wraps Unknown in gray; wrap ago-text ourselves.
            if ago:sub(1, #GRAY) == GRAY then
                presence = ago
            else
                presence = GRAY .. ago .. "|r"
            end
        end
        lines[i] = { left = left, right = presence }
    end
    if others > 0 then
        lines[#lines + 1] = WHITE .. "...and " .. others .. " others|r"
    end
    local hint = (opts.isExpanded and "Click to collapse") or "Click to expand"
    lines[#lines + 1] = GRAY .. hint .. "|r"
    return lines
end

--- Two-line tooltip for an own-account character in search results.
--- opts: name, classFile, level, formatName?, classDisplayName?
--- Returns `{ line1, line2 }` — class-colored name, then "Level N Class".
function GTD.BuildOwnCharacterHoverTooltipLines(opts)
    opts = opts or {}
    local name = opts.name or "?"
    local className = opts.classDisplayName or GTD.FormatClassDisplayName(opts.classFile)
    local level = math.floor(tonumber(opts.level) or 0)
    return {
        colorTooltipName(name, opts.classFile, opts.formatName),
        "Level " .. level .. " " .. className,
    }
end

--- Lines for a search-result guildmate name tooltip.
--- opts: name, preferredName, preferredClassFile?, classFile, level, presenceDetail?,
---       formatName?, classDisplayName?
--- Returns `{ line1, line2, line3? }` (line3 omitted when presence is unknown).
--- Preferred/main name is omitted from line1 when it matches the character name.
--- When shown, preferred name is class-colored (preferredClassFile) with white parentheses.
function GTD.BuildGuildCharacterHoverTooltipLines(opts)
    opts = opts or {}
    local name = opts.name or "?"
    local preferred = opts.preferredName or name
    local formatName = opts.formatName
    local colored = colorTooltipName(name, opts.classFile, formatName)
    local line1 = colored
    if preferred ~= "" and preferred:lower() ~= name:lower() then
        local preferredColored = colorTooltipName(
            preferred, opts.preferredClassFile or opts.classFile, formatName)
        line1 = colored .. " " .. WHITE .. "(|r" .. preferredColored .. WHITE .. ")|r"
    end
    local className = opts.classDisplayName or GTD.FormatClassDisplayName(opts.classFile)
    local level = math.floor(tonumber(opts.level) or 0)
    local line2 = "Level " .. level .. " " .. className
    local line3 = GTD.FormatGroupPresenceTooltipLine(name, opts.presenceDetail, formatName)
    if line3 then
        return {
            line1,
            line2,
            line3,
            presenceOnline = opts.presenceDetail
                and opts.presenceDetail.status
                and opts.presenceDetail.status.online
                and true
                or false,
        }
    end
    return { line1, line2 }
end

--- Gray level suffix for the guild character recipe title: "(level N)" or "(N)".
function GTD.FormatCharacterLevelSuffix(level, mode, grayPrefix)
    local n = math.floor(tonumber(level) or 0)
    local inner = (mode == "short") and tostring(n) or ("level " .. n)
    local body = "(" .. inner .. ")"
    if grayPrefix and grayPrefix ~= "" then
        return " " .. grayPrefix .. body .. "|r"
    end
    return " " .. body
end

--- Which title form fits: "full" ((level N)), "short" ((N)), or "ellipsis" (truncate name + short).
--- fitsFull / fitsShort are booleans from the caller's width measurements.
function GTD.ChooseCharacterTitleLevelMode(fitsFull, fitsShort)
    if fitsFull then return "full" end
    if fitsShort then return "short" end
    return "ellipsis"
end

--- Name to whisper when someone in the viewed character's group is online.
--- Prefer the character currently playing (online roster member); nil when none are online
--- or when viewing one of the player's own (local) characters.
function GTD.ResolveOnlineWhisperTarget(entry, rosterByName, members)
    if not entry or not entry.name then
        return nil
    end
    if entry.source == "local" then
        return nil
    end
    local group
    if type(members) == "table" and GTD.GroupMembersByMain then
        local groups = GTD.GroupMembersByMain(members)
        for _, g in ipairs(groups or {}) do
            for _, m in ipairs(g.members or {}) do
                if m.name == entry.name then
                    group = g
                    break
                end
            end
            if group then break end
        end
    end
    if not group then
        group = { members = { entry }, main = entry.main or entry.name }
    end
    local detail = GTD.GetGroupMostRecentOnlineDetail(group, rosterByName or {})
    if detail and detail.status and detail.status.online and detail.memberName then
        return detail.memberName
    end
    return nil
end

--- Build short-name -> last-online status from guild roster APIs.
--- `api` may override: isInGuild, getNumGuildMembers, getGuildRosterInfo,
--- getGuildRosterLastOnline, normalizeName (defaults to live WoW globals / NormalizeRosterName).
function GTD.BuildRosterLastOnlineMap(api)
    api = api or {}
    local isInGuild = api.isInGuild or IsInGuild
    local getNum = api.getNumGuildMembers or GetNumGuildMembers
    local getInfo = api.getGuildRosterInfo or GetGuildRosterInfo
    local getLast = api.getGuildRosterLastOnline or GetGuildRosterLastOnline
    local normalize = api.normalizeName or GTD.NormalizeRosterName

    local out = {}
    if not isInGuild or not isInGuild() then return out end
    if not getNum or not getInfo then return out end
    local n = getNum()
    if type(n) ~= "number" or n < 1 then return out end
    for i = 1, n do
        local name, _, _, _, _, _, _, _, online = getInfo(i)
        local key = normalize(name)
        if key and key ~= "" then
            if online then
                out[key] = { online = true }
            elseif getLast then
                local years, months, days, hours = getLast(i)
                out[key] = {
                    online = false,
                    years = years or 0,
                    months = months or 0,
                    days = days or 0,
                    hours = hours or 0,
                }
            else
                out[key] = { online = false, years = 0, months = 0, days = 0, hours = 0 }
            end
        end
    end
    return out
end

--- Professions column: "Name — Spec (rank), ..." with the specialization (when present) after
--- an em dash in the default (white) color and the gray skill level in parentheses.
--- Gathering professions are listed after crafting. Optional `query` highlights matching
--- substrings in profession names and specializations.
--- Empty string when the character has no displayable professions.
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
