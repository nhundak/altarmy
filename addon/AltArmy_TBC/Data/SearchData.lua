-- AltArmy TBC — Search data layer: item search across all characters (bags + bank).
-- Uses AltArmy.DataStore IterateContainerSlots; builds flat list for Search tab.

AltArmy.SearchData = AltArmy.SearchData or {}

local SD = AltArmy.SearchData
local BANK_CONTAINER = -1
local KEYRING_CONTAINER = -2
local MIN_BANK_BAG_ID = 5
local MAX_BANK_BAG_ID = 11

-- In-memory cache: itemID (number) -> lowercased searchable string (name + tooltip lines).
-- Cleared on PLAYER_LOGOUT so it doesn't carry state across sessions.
local _searchableTextCache = {}
local _containerSlotsCache = nil
local _recipesCache = nil
local _itemNameCache = {}
local _recipeNameCache = {}

--- Query timing debug. Enable: /altarmy debug on, then Interface > AddOns > AltArmy > Debug > search.
--- Uses debugprofilestart/stop (high-resolution) because GetTime() only updates once per frame.
local function SearchDebugEnabled()
    local Dbg = AltArmy and AltArmy.Debug
    return Dbg and Dbg.IsSearchEnabled and Dbg.IsSearchEnabled()
end

local function LogSearchDebug(msg)
    local Dbg = AltArmy and AltArmy.Debug
    if Dbg and Dbg.LogSearch then
        Dbg.LogSearch(msg)
    end
end

local function SearchProfileStart()
    if debugprofilestart then
        debugprofilestart()
    end
end

local function SearchProfileElapsedMs()
    if debugprofilestop then
        return debugprofilestop()
    end
    return 0
end

--- @param query string|number
local function SearchQueryLabel(query)
    if type(query) == "string" then
        if #query > 40 then
            return query:sub(1, 37) .. "..."
        end
        return query
    end
    return tostring(query)
end

function SD.ClearSearchableTextCache()
    _searchableTextCache = {}
end

function SD.InvalidateContainerSlotsCache()
    _containerSlotsCache = nil
end

function SD.InvalidateRecipesCache()
    _recipesCache = nil
end

function SD.NotifyContainerDataChanged()
    SD.InvalidateContainerSlotsCache()
end

function SD.NotifyRecipesChanged()
    SD.InvalidateRecipesCache()
end

function SD.ClearSearchCaches()
    _searchableTextCache = {}
    _containerSlotsCache = nil
    _recipesCache = nil
    _itemNameCache = {}
    _recipeNameCache = {}
end

local _cacheEventFrame = CreateFrame("Frame")
_cacheEventFrame:RegisterEvent("PLAYER_LOGOUT")
_cacheEventFrame:SetScript("OnEvent", function()
    SD.ClearSearchCaches()
end)

-- Private tooltip frame for scanning item text.
-- Using a dedicated frame (not GameTooltip) prevents other addons from injecting their
-- extra lines via GameTooltip hooks (e.g. inventory-tracking addons that add character
-- info to every tooltip). Only Blizzard's native tooltip lines are populated here.
local _scanTooltip = CreateFrame("GameTooltip", "AltArmyTBC_ScanTooltip", UIParent, "GameTooltipTemplate")

--- Determine location string from bagID: "bag" for 0-4, "keyring" for -2, "bank" for -1 or 5-11.
local function LocationFromBagID(bagID)
    if bagID == KEYRING_CONTAINER then
        return "keyring"
    end
    if bagID == BANK_CONTAINER or (bagID >= MIN_BANK_BAG_ID and bagID <= MAX_BANK_BAG_ID) then
        return "bank"
    end
    return "bag"
end
SD._LocationFromBagID = LocationFromBagID

local function LocationSortKey(location)
    if location == "bag" then return 1 end
    if location == "keyring" then return 2 end
    if location == "bank" then return 3 end
    if location == "equipped" then return 4 end
    if location == "mail" then return 5 end
    return 99
end
SD._LocationSortKey = LocationSortKey

--- Build flat list of all container slots across all characters.
--- Each entry: { characterName, realm, itemID, itemLink, count, location, bagID, slot }.
local function BuildAllContainerSlots()
    local list = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter or not DS.IterateContainerSlots or not DS.GetCharacterName then
        return list
    end
    DS:ForEachCharacter(function(realm, charName, charData)
            if charData and DS.IterateContainerSlots then
                local _, classFile = DS:GetCharacterClass(charData)
                DS:IterateContainerSlots(charData, function(bagID, slot, itemID, count, link)
                    table.insert(list, {
                        characterName = DS:GetCharacterName(charData) or charName,
                        realm = realm,
                        itemID = itemID,
                        itemLink = link,
                        count = count or 1,
                        location = LocationFromBagID(bagID),
                        bagID = bagID,
                        slot = slot,
                        classFile = classFile,
                    })
                    return false
                end)
            end

            -- Mail: include per-mail attachment rows (Mails + MailCache) as location="mail"
            if charData and (charData.Mails or charData.MailCache) then
                local characterName = (DS.GetCharacterName and DS:GetCharacterName(charData)) or charName
                local classFile = nil
                if DS.GetCharacterClass then
                    local _, cf = DS:GetCharacterClass(charData)
                    classFile = cf
                end
                local function pushMailRows(rows)
                    for _, m in ipairs(rows or {}) do
                        if m and m.itemID then
                            table.insert(list, {
                                characterName = characterName,
                                realm = realm,
                                itemID = m.itemID,
                                itemLink = m.link,
                                count = m.count or 1,
                                location = "mail",
                                bagID = nil,
                                slot = nil,
                                classFile = classFile,
                            })
                        end
                    end
                end
                pushMailRows(charData.Mails)
                pushMailRows(charData.MailCache)
            end

            -- Equipped gear: include inventory slots as location="equipped"
            if charData and DS.IterateInventory then
                local characterName = (DS.GetCharacterName and DS:GetCharacterName(charData)) or charName
                local classFile = nil
                if DS.GetCharacterClass then
                    local _, cf = DS:GetCharacterClass(charData)
                    classFile = cf
                end
                DS:IterateInventory(charData, function(slot, itemIDOrLink)
                    local link, itemID
                    if type(itemIDOrLink) == "string" then
                        link = itemIDOrLink
                        itemID = tonumber(link:match("item:(%d+)"))
                    else
                        itemID = itemIDOrLink
                    end
                    if itemID then
                        table.insert(list, {
                            characterName = characterName,
                            realm = realm,
                            itemID = itemID,
                            itemLink = link,
                            count = 1,
                            location = "equipped",
                            bagID = nil,
                            slot = slot,
                            classFile = classFile,
                        })
                    end
                    return false
                end)
            end
    end)
    return list
end

function SD.GetAllContainerSlots()
    if _containerSlotsCache then
        return _containerSlotsCache
    end
    _containerSlotsCache = BuildAllContainerSlots()
    return _containerSlotsCache
end

--- Get item name from itemID or link (for search). Returns nil if not cached.
local function ResolveItemName(itemID, link)
    if link and GetItemInfo then
        local name = GetItemInfo(link)
        if name then return name end
    end
    if itemID and GetItemInfo then
        local name = GetItemInfo(itemID)
        if name then return name end
    end
    return nil
end

local function GetCachedItemName(itemID, link)
    if itemID and _itemNameCache[itemID] and _itemNameCache[itemID].name then
        return _itemNameCache[itemID].name
    end
    local name = ResolveItemName(itemID, link)
    if itemID and name then
        _itemNameCache[itemID] = {
            name = name,
            nameLower = name:lower(),
        }
    end
    return name
end

local function GetCachedItemNameLower(itemID, link)
    if itemID and _itemNameCache[itemID] and _itemNameCache[itemID].nameLower then
        return _itemNameCache[itemID].nameLower
    end
    local name = GetCachedItemName(itemID, link)
    if name then
        return name:lower()
    end
    return nil
end

--- Build and cache a searchable string for an item: lowercased item name + all tooltip left-column lines.
--- Returns a string on success, or nil if the item name cannot be resolved.
--- Exposed as SD._GetSearchableTextForItem so tests can stub it without touching GameTooltip.
function SD._GetSearchableTextForItem(itemID, itemLink)
    if _searchableTextCache[itemID] then
        return _searchableTextCache[itemID]
    end
    local name = GetCachedItemName(itemID, itemLink)
    if not name then return nil end

    -- Skip tooltip scan in combat to avoid UI taint.
    if InCombatLockdown and InCombatLockdown() then
        local result = name:lower()
        _searchableTextCache[itemID] = result
        return result
    end

    local lines = { name }
    if itemLink and itemLink ~= "" then
        pcall(function()
            _scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            _scanTooltip:ClearLines()
            _scanTooltip:SetHyperlink(itemLink)
            _scanTooltip:Show()
            local numLines = _scanTooltip:NumLines()
            local tooltipName = _scanTooltip:GetName()
            -- Skip line 1 (item name already included)
            for i = 2, math.min(numLines, 20) do
                local lineText = _G[tooltipName .. "TextLeft" .. i]
                if lineText then
                    local text = lineText:GetText()
                    if text and text ~= "" then
                        -- Strip color codes
                        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                        table.insert(lines, text)
                    end
                end
            end
            _scanTooltip:Hide()
        end)
    end

    local result = table.concat(lines, " "):lower()
    _searchableTextCache[itemID] = result
    return result
end

--- Search: query can be item name (partial, case-insensitive) or item ID (number or string digits).
--- Returns two lists: mainResults (matched by ID/name/link) and tooltipOnlyResults (matched via tooltip text).
--- Pass skipTooltip=true to skip the tooltip scan (tooltipOnlyResults will be empty); use for the immediate
--- search on each keystroke, then run the full search via debounce for tooltip results.
local function ParseItemSearchQuery(query)
    local queryLower = type(query) == "string" and query:lower() or nil
    local queryID = nil
    if type(query) == "number" then
        queryID = query
    elseif type(query) == "string" and query:match("^%d+$") then
        queryID = tonumber(query)
    end
    return queryLower, queryID
end
SD._ParseItemSearchQuery = ParseItemSearchQuery

local function FilterContainerSlots(all, queryLower, queryID, skipTooltip)
    local mainResults = {}
    local tooltipOnlyResults = {}
    for _, entry in ipairs(all) do
        local mainMatch = SD._IsMainSearchMatch(entry, queryLower, queryID)
        if mainMatch then
            SD._EnsureItemName(entry)
            table.insert(mainResults, entry)
        elseif queryLower and not skipTooltip then
            local searchableText = SD._GetSearchableTextForItem(entry.itemID, entry.itemLink)
            if searchableText and searchableText:find(queryLower, 1, true) then
                SD._EnsureItemName(entry)
                table.insert(tooltipOnlyResults, entry)
            end
        end
    end
    return mainResults, tooltipOnlyResults
end
SD._FilterContainerSlots = FilterContainerSlots

function SD._EnsureItemName(entry)
    if not entry then return nil end
    entry.itemName = entry.itemName or GetCachedItemName(entry.itemID, entry.itemLink)
    return entry.itemName
end

function SD._IsMainSearchMatch(entry, queryLower, queryID)
    if not entry then return false end
    if queryID ~= nil and entry.itemID == queryID then
        return true
    end
    if not queryLower then
        return false
    end
    local nameLower = GetCachedItemNameLower(entry.itemID, entry.itemLink)
    if nameLower and nameLower:find(queryLower, 1, true) then
        return true
    end
    if entry.itemLink and entry.itemLink:lower():find(queryLower, 1, true) then
        return true
    end
    return false
end

local function SearchContainerSlots(query, skipTooltip)
    local all = SD.GetAllContainerSlots()
    local queryLower, queryID = ParseItemSearchQuery(query)
    local mainResults, tooltipOnlyResults = FilterContainerSlots(all, queryLower, queryID, skipTooltip)
    return mainResults, tooltipOnlyResults, #all, all
end
SD._SearchContainerSlots = SearchContainerSlots

function SD.Search(query, skipTooltip)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}, {}
    end
    local mainResults, tooltipOnlyResults = SearchContainerSlots(query, skipTooltip)
    return mainResults, tooltipOnlyResults
end

--- Aggregate search results by (itemID, characterName, realm): sum count, keep first link.
--- Returns list of { characterName, realm, itemID, itemLink, count, location, itemName }.
function SD.SearchGroupedByCharacter(query)
    local raw = SD.Search(query)  -- uses only main results
    local byChar = {}
    for _, entry in ipairs(raw) do
        local key = (entry.characterName or "") .. "\t" .. (entry.realm or "") .. "\t" .. (entry.itemID or 0)
        if not byChar[key] then
            byChar[key] = {
                characterName = entry.characterName,
                realm = entry.realm,
                itemID = entry.itemID,
                itemLink = entry.itemLink,
                count = 0,
                location = entry.location,
                itemName = entry.itemName,
            }
        end
        byChar[key].count = byChar[key].count + (entry.count or 1)
    end
    local list = {}
    for _, v in pairs(byChar) do
        table.insert(list, v)
    end
    return list
end

--- Name match score: exact=3, prefix=2, contains=1 (for sort).
local function GetNameMatchScore(itemName, queryLower)
    if not itemName or not queryLower or queryLower == "" then return 0 end
    local nameLower = itemName:lower()
    if nameLower == queryLower then return 3 end
    if nameLower:sub(1, #queryLower) == queryLower then return 2 end
    if nameLower:find(queryLower, 1, true) then return 1 end
    return 0
end
SD._GetNameMatchScore = GetNameMatchScore

--- Aggregate a flat list of search entries by (itemID, characterName, realm, location).
--- Returns an aggregated and sorted list.
local function AggregateAndSort(raw, queryLower)
    local byKey = {}
    local charTotals = {}
    for _, entry in ipairs(raw) do
        local key = (entry.itemID or 0) .. "\t" .. (entry.characterName or "") .. "\t" .. (entry.realm or "")
            .. "\t" .. (entry.location or "bag")
        if not byKey[key] then
            byKey[key] = {
                itemID = entry.itemID,
                itemLink = entry.itemLink,
                itemName = entry.itemName,
                characterName = entry.characterName,
                realm = entry.realm,
                location = entry.location or "bag",
                count = 0,
                classFile = entry.classFile,
            }
        end
        byKey[key].count = byKey[key].count + (entry.count or 1)

        local charKey = (entry.itemID or 0) .. "\t" .. (entry.characterName or "") .. "\t" .. (entry.realm or "")
        charTotals[charKey] = (charTotals[charKey] or 0) + (entry.count or 1)
    end

    local list = {}
    for _, row in pairs(byKey) do
        local charKey = (row.itemID or 0) .. "\t" .. (row.characterName or "") .. "\t" .. (row.realm or "")
        row.charTotal = charTotals[charKey] or 0
        row.matchScore = GetNameMatchScore(row.itemName, queryLower)
        table.insert(list, row)
    end

    table.sort(list, function(a, b)
        if a.matchScore ~= b.matchScore then return a.matchScore > b.matchScore end
        local na, nb = (a.itemName or ""):lower(), (b.itemName or ""):lower()
        if na ~= nb then return na < nb end
        if a.charTotal ~= b.charTotal then return a.charTotal > b.charTotal end
        local la, lb = LocationSortKey(a.location or "bag"), LocationSortKey(b.location or "bag")
        if la ~= lb then return la < lb end
        return (a.location or "bag") < (b.location or "bag")
    end)

    for _, row in ipairs(list) do
        row.charTotal = nil
        row.matchScore = nil
    end
    return list
end
SD._AggregateAndSort = AggregateAndSort

--- Aggregate by (itemID, characterName, realm, location); sort by name match, then char total, then bags before bank.
--- Returns two lists: mainRows and tooltipOnlyRows (same row shape as before).
--- Pass skipTooltip=true to skip tooltip scanning (tooltipOnlyRows will be empty).
function SD.SearchWithLocationGroups(query, skipTooltip)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}, {}
    end
    local debug = SearchDebugEnabled()
    if debug then
        SearchProfileStart()
    end
    local queryLower = type(query) == "string" and query:lower() or ""
    local mainResults, tooltipOnlyResults = SD.Search(query, skipTooltip)
    local mainRows = AggregateAndSort(mainResults, queryLower)
    local tooltipOnlyRows = AggregateAndSort(tooltipOnlyResults, queryLower)
    if debug then
        LogSearchDebug(string.format(
            "  items q=%q ms=%.2f mainRows=%d tooltipRows=%d skipTooltip=%s",
            SearchQueryLabel(query),
            SearchProfileElapsedMs(),
            #mainRows,
            #tooltipOnlyRows,
            tostring(skipTooltip and true or false)
        ))
    end
    return mainRows, tooltipOnlyRows
end

--- Whether recipeID is an alias (e.g. crafted item use spell), not the craft recipe itself.
local function IsRecipeAliasId(recipeID, data)
    if type(data) ~= "table" or not data.primaryRecipeID then
        return false
    end
    return data.primaryRecipeID ~= recipeID
end
SD._IsRecipeAliasId = IsRecipeAliasId

--- Build flat list of all known recipes across all characters.
--- Each entry: { characterName, realm, classFile, professionName, skillRank, recipeID }.
--- Whether guildmate-shared recipes should be merged into recipe results:
--- requires the guildShare feature flag AND the "Include guildmates" search toggle.
local function ShouldIncludeGuildRecipes()
    local D = AltArmy.Debug
    if not (D and D.IsGuildShareEnabled and D.IsGuildShareEnabled()) then
        return false
    end
    local SS = AltArmy.SearchSettings
    if SS and SS.IsIncludeGuildmatesEnabled then
        return SS.IsIncludeGuildmatesEnabled()
    end
    return true
end

--- Append recipes shared by guildmates (from GuildShareData) into the recipe list,
--- tagged isGuild = true with the guildmate's identity. Only primary (non-alias) ids.
local function AppendGuildRecipes(list)
    if not ShouldIncludeGuildRecipes() then return end
    local data = _G.AltArmyTBC_GuildData
    if not data or type(data.chars) ~= "table" then return end
    for realm, chars in pairs(data.chars) do
        for _, entry in pairs(chars) do
            if type(entry) == "table" and entry.Professions then
                for _, prof in pairs(entry.Professions) do
                    if prof.Recipes then
                        for recipeID, rdata in pairs(prof.Recipes) do
                            if recipeID and not IsRecipeAliasId(recipeID, rdata) then
                                table.insert(list, {
                                    characterName = entry.name,
                                    guildDisplayName = entry.displayName or entry.name,
                                    realm = realm,
                                    classFile = entry.classFile,
                                    professionName = prof.name or prof.key,
                                    professionKey = prof.key,
                                    skillRank = prof.rank or 0,
                                    recipeID = recipeID,
                                    isGuild = true,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
end

local function BuildAllRecipes()
    local list = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter or not DS.GetCharacterName
        or not DS.GetCharacterClass or not DS.GetProfessions then
        AppendGuildRecipes(list)
        return list
    end
    DS:ForEachCharacter(function(realm, charName, charData)
            if charData then
                local professions = DS:GetProfessions(charData)
                if professions then
                    local characterName = DS:GetCharacterName(charData) or charName
                    local _, classFile = DS:GetCharacterClass(charData)
                    for profName, prof in pairs(professions) do
                        if prof and prof.Recipes then
                            local skillRank = prof.rank or 0
                            for recipeID, data in pairs(prof.Recipes) do
                                if recipeID and not IsRecipeAliasId(recipeID, data) then
                                    local resultItemID
                                    if type(data) == "table" and data.resultItemID then
                                        resultItemID = data.resultItemID
                                    end
                                    table.insert(list, {
                                        characterName = characterName,
                                        realm = realm,
                                        classFile = classFile,
                                        professionName = profName,
                                        skillRank = skillRank,
                                        recipeID = recipeID,
                                        resultItemID = resultItemID,
                                    })
                                end
                            end
                        end
                    end
                end
            end
    end)
    AppendGuildRecipes(list)
    return list
end

function SD.GetAllRecipes()
    if _recipesCache then
        return _recipesCache
    end
    _recipesCache = BuildAllRecipes()
    return _recipesCache
end

--- Get recipe name from recipeID (spell first, then item). Returns nil if not resolved.
local function ResolveRecipeName(recipeID)
    if not recipeID then return nil end
    if GetSpellInfo then
        local name = GetSpellInfo(recipeID)
        if name and name ~= "" then return name end
    end
    if GetItemInfo then
        local name = GetItemInfo(recipeID)
        if name and name ~= "" then return name end
    end
    return nil
end

local function GetCachedRecipeName(recipeID)
    if not recipeID then return nil end
    if _recipeNameCache[recipeID] and _recipeNameCache[recipeID].name then
        return _recipeNameCache[recipeID].name
    end
    local name = ResolveRecipeName(recipeID)
    if name then
        _recipeNameCache[recipeID] = {
            name = name,
            nameLower = name:lower(),
        }
    else
        _recipeNameCache[recipeID] = {
            name = nil,
            nameLower = nil,
        }
    end
    return name
end

local function GetCachedRecipeNameLower(recipeID)
    if not recipeID then return nil end
    if _recipeNameCache[recipeID] then
        return _recipeNameCache[recipeID].nameLower
    end
    local name = GetCachedRecipeName(recipeID)
    if name then
        return name:lower()
    end
    return nil
end

--- Search recipes by name (partial, case-insensitive). Returns list of matching entries.
local function FilterAndSortRecipes(all, queryLower)
    local results = {}
    for _, entry in ipairs(all) do
        local nameLower = GetCachedRecipeNameLower(entry.recipeID)
        if nameLower and nameLower:find(queryLower, 1, true) then
            entry.recipeNameLower = nameLower
            table.insert(results, entry)
        end
    end
    table.sort(results, function(a, b)
        local na = a.recipeNameLower or ""
        local nb = b.recipeNameLower or ""
        if na ~= nb then return na < nb end
        return (a.characterName or "") < (b.characterName or "")
    end)
    return results
end
SD._FilterAndSortRecipes = FilterAndSortRecipes

local function EnrichRecipeEntry(entry)
    if not entry then
        return entry
    end
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    if RCL and RCL.EnrichEntry then
        RCL.EnrichEntry(entry)
    end
    return entry
end
SD._EnrichRecipeEntry = EnrichRecipeEntry

local function FilterRecipesByLevel(results, filter)
    if not results or not filter then
        return results
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.IsRecipeLevelFilterActive and not SS.IsRecipeLevelFilterActive(filter) then
        return results
    end
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    if not RCL or not RCL.IsAvailable or not RCL.IsAvailable() then
        return results
    end
    local out = {}
    for _, entry in ipairs(results) do
        local req = entry.recipeSkillRequired
        if req == nil then
            out[#out + 1] = entry
        elseif req >= filter.min and req <= filter.max then
            out[#out + 1] = entry
        end
    end
    return out
end
SD._FilterRecipesByLevel = FilterRecipesByLevel

local function CraftLibFiltersAvailable()
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    return RCL and RCL.IsAvailable and RCL.IsAvailable()
end

local function FilterRecipesByDifficulty(results, filter)
    if not results or not filter then
        return results
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.IsDifficultyFilterActive and not SS.IsDifficultyFilterActive(filter) then
        return results
    end
    if not CraftLibFiltersAvailable() then
        return results
    end
    local out = {}
    for _, entry in ipairs(results) do
        local difficulty = entry.difficulty
        if difficulty == nil or filter[difficulty] then
            out[#out + 1] = entry
        end
    end
    return out
end
SD._FilterRecipesByDifficulty = FilterRecipesByDifficulty

local function FilterRecipesBySource(results, filter)
    if not results or not filter then
        return results
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.IsSourceFilterActive and not SS.IsSourceFilterActive(filter) then
        return results
    end
    if not CraftLibFiltersAvailable() then
        return results
    end
    local out = {}
    for _, entry in ipairs(results) do
        local sourceType = entry.recipeSource
        if sourceType == nil or filter[sourceType] then
            out[#out + 1] = entry
        end
    end
    return out
end
SD._FilterRecipesBySource = FilterRecipesBySource

local function FilterRecipesByProfession(results, filter)
    if not results or not filter then
        return results
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.IsProfessionFilterActive and not SS.IsProfessionFilterActive(filter) then
        return results
    end
    local out = {}
    for _, entry in ipairs(results) do
        -- Guild entries already carry a locale-safe profession key; fall back to resolving
        -- from the (localized) profession name for locally scanned recipes.
        local professionKey = entry.professionKey
        if professionKey == nil and SS and SS.ResolveProfessionKey then
            professionKey = SS.ResolveProfessionKey(entry.professionName)
        end
        if professionKey == nil or filter[professionKey] then
            out[#out + 1] = entry
        end
    end
    return out
end
SD._FilterRecipesByProfession = FilterRecipesByProfession

local function ApplyRecipeSearchFilters(results, settings)
    if not results or not settings then
        return results
    end
    results = FilterRecipesByProfession(results, settings.professionFilter)
    if not CraftLibFiltersAvailable() then
        return results
    end
    results = FilterRecipesByLevel(results, settings.recipeLevelFilter)
    results = FilterRecipesByDifficulty(results, settings.difficultyFilter)
    results = FilterRecipesBySource(results, settings.sourceFilter)
    return results
end
SD._ApplyRecipeSearchFilters = ApplyRecipeSearchFilters

function SD.SearchRecipes(query)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}
    end
    local debug = SearchDebugEnabled()
    if debug then
        SearchProfileStart()
    end
    local all = SD.GetAllRecipes()
    local queryLower = type(query) == "string" and query:lower() or ""
    local results = FilterAndSortRecipes(all, queryLower)
    for i = 1, #results do
        EnrichRecipeEntry(results[i])
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.GetSearchSettings then
        results = ApplyRecipeSearchFilters(results, SS.GetSearchSettings())
    end
    if debug then
        LogSearchDebug(string.format(
            "  recipes q=%q ms=%.2f scanned=%d hits=%d",
            SearchQueryLabel(query),
            SearchProfileElapsedMs(),
            #all,
            #results
        ))
    end
    return results
end
