-- AltArmy TBC — Search data layer (unique-name scan + byId expand).
-- Public API used by SearchEngine / TabSearch / NetWorth / DataStore invalidation.

AltArmy = AltArmy or {}
AltArmy.SearchData = AltArmy.SearchData or {}

local SD = AltArmy.SearchData

local BANK_CONTAINER = -1
local KEYRING_CONTAINER = -2
local MIN_BANK_BAG_ID = 5
local MAX_BANK_BAG_ID = 11

local caches = {
    rawSlots = nil,
    rawLocalRecipes = nil,
    rawGuildRecipes = nil,
    itemIndex = nil,
    localRecipeIndex = nil,
    guildRecipeIndex = nil,
    itemNameCache = {},
    recipeNameCache = {},
    searchableTextCache = {},
    itemMemo = {},
    localRecipeMemo = {},
    guildRecipeMemo = {},
    recipeVisualCache = {},
}

local function LocationFromBagID(bagID)
    if bagID == KEYRING_CONTAINER then
        return "keyring"
    end
    if bagID == BANK_CONTAINER or (bagID >= MIN_BANK_BAG_ID and bagID <= MAX_BANK_BAG_ID) then
        return "bank"
    end
    return "bag"
end

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
    if itemID and caches.itemNameCache[itemID] and caches.itemNameCache[itemID].name then
        return caches.itemNameCache[itemID].name
    end
    local name = ResolveItemName(itemID, link)
    if itemID and name then
        caches.itemNameCache[itemID] = {
            name = name,
            nameLower = name:lower(),
        }
    end
    return name
end

local function GetCachedItemNameLower(itemID, link)
    if itemID and caches.itemNameCache[itemID] and caches.itemNameCache[itemID].nameLower then
        return caches.itemNameCache[itemID].nameLower
    end
    local name = GetCachedItemName(itemID, link)
    return name and name:lower() or nil
end

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

local function GetCachedRecipeNameLower(recipeID)
    if not recipeID then return nil end
    local cached = caches.recipeNameCache[recipeID]
    if cached then
        return cached.nameLower
    end
    local name = ResolveRecipeName(recipeID)
    caches.recipeNameCache[recipeID] = {
        name = name,
        nameLower = name and name:lower() or nil,
    }
    return name and name:lower() or nil
end

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
                            classFile = classFile,
                        })
                    end
                end
            end
            pushMailRows(charData.Mails)
            pushMailRows(charData.MailCache)
        end
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

local function IsRecipeAliasId(recipeID, data)
    if type(data) ~= "table" or not data.primaryRecipeID then
        return false
    end
    return data.primaryRecipeID ~= recipeID
end

local function BuildLocalRecipes()
    local list = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter or not DS.GetCharacterName
        or not DS.GetCharacterClass or not DS.GetProfessions then
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
    return list
end

local function ShouldIncludeGuildRecipes()
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.CanShowIncludeGuildmatesToggle and not SS.CanShowIncludeGuildmatesToggle() then
        return false
    end
    if SS and SS.IsIncludeGuildmatesEnabled then
        return SS.IsIncludeGuildmatesEnabled()
    end
    return true
end

local function BuildGuildRecipes()
    local list = {}
    if not ShouldIncludeGuildRecipes() then
        return list
    end
    local data = _G.AltArmyTBC_GuildData
    if not data or type(data.chars) ~= "table" then
        return list
    end
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
    return list
end

local function CompareRecipeRowsWithinId(a, b)
    local aGuild = a.isGuild and true or false
    local bGuild = b.isGuild and true or false
    if aGuild ~= bGuild then
        return not aGuild
    end
    local ca = a.characterName or ""
    local cb = b.characterName or ""
    if ca ~= cb then
        return ca < cb
    end
    return false
end

--- Public slot list (stubbable in tests). Cached until NotifyContainerDataChanged.
function SD.GetAllContainerSlots()
    if caches.rawSlots then
        return caches.rawSlots
    end
    caches.rawSlots = BuildAllContainerSlots()
    return caches.rawSlots
end

--- Public local recipe list (stubbable in tests).
function SD.GetAllRecipes()
    if caches.rawLocalRecipes then
        return caches.rawLocalRecipes
    end
    caches.rawLocalRecipes = BuildLocalRecipes()
    return caches.rawLocalRecipes
end

--- Public guild recipe list (stubbable in tests).
function SD.GetAllGuildRecipes()
    if caches.rawGuildRecipes then
        return caches.rawGuildRecipes
    end
    caches.rawGuildRecipes = BuildGuildRecipes()
    return caches.rawGuildRecipes
end

local function EnsureItemIndex()
    if caches.itemIndex then
        return caches.itemIndex
    end
    local SI = AltArmy.SearchIndex
    local slots = SD.GetAllContainerSlots()
    for i = 1, #slots do
        local e = slots[i]
        local name = GetCachedItemName(e.itemID, e.itemLink)
        e.itemName = name
        e.itemNameLower = name and name:lower() or nil
    end
    caches.itemIndex = SI.BuildIndex(slots, {
        getId = function(e) return e.itemID end,
        getNameLower = function(e)
            return e.itemNameLower or GetCachedItemNameLower(e.itemID, e.itemLink)
        end,
    })
    caches.itemMemo = {}
    return caches.itemIndex
end

local function EnsureLocalRecipeIndex()
    if caches.localRecipeIndex then
        return caches.localRecipeIndex
    end
    local SI = AltArmy.SearchIndex
    local recipes = SD.GetAllRecipes()
    caches.localRecipeIndex = SI.BuildIndex(recipes, {
        getId = function(e) return e.recipeID end,
        getNameLower = function(e)
            return GetCachedRecipeNameLower(e.recipeID)
        end,
        compareWithinId = CompareRecipeRowsWithinId,
    })
    caches.localRecipeMemo = {}
    return caches.localRecipeIndex
end

local function EnsureGuildRecipeIndex()
    if caches.guildRecipeIndex then
        return caches.guildRecipeIndex
    end
    local SI = AltArmy.SearchIndex
    local recipes = SD.GetAllGuildRecipes()
    caches.guildRecipeIndex = SI.BuildIndex(recipes, {
        getId = function(e) return e.recipeID end,
        getNameLower = function(e)
            return GetCachedRecipeNameLower(e.recipeID)
        end,
        compareWithinId = CompareRecipeRowsWithinId,
    })
    caches.guildRecipeMemo = {}
    return caches.guildRecipeIndex
end

function SD.ClearCaches()
    caches.rawSlots = nil
    caches.rawLocalRecipes = nil
    caches.rawGuildRecipes = nil
    caches.itemIndex = nil
    caches.localRecipeIndex = nil
    caches.guildRecipeIndex = nil
    caches.itemNameCache = {}
    caches.recipeNameCache = {}
    caches.searchableTextCache = {}
    caches.itemMemo = {}
    caches.localRecipeMemo = {}
    caches.guildRecipeMemo = {}
    caches.recipeVisualCache = {}
    local SP = AltArmy.SearchPresent
    if SP and SP.ClearVisualCache then
        SP.ClearVisualCache()
    end
end

function SD.NotifyContainerDataChanged()
    caches.rawSlots = nil
    caches.itemIndex = nil
    caches.itemMemo = {}
end

function SD.NotifyRecipesChanged()
    caches.rawLocalRecipes = nil
    caches.rawGuildRecipes = nil
    caches.localRecipeIndex = nil
    caches.guildRecipeIndex = nil
    caches.localRecipeMemo = {}
    caches.guildRecipeMemo = {}
end

function SD._ParseItemSearchQuery(query)
    return AltArmy.SearchQuery.ParseQuery(query)
end

function SD._EnsureItemName(entry)
    if not entry then return nil end
    if not entry.itemName then
        entry.itemName = GetCachedItemName(entry.itemID, entry.itemLink)
    end
    if entry.itemName and not entry.itemNameLower then
        entry.itemNameLower = entry.itemName:lower()
    end
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

local _scanTooltip
local function getScanTooltip()
    if _scanTooltip then return _scanTooltip end
    _scanTooltip = CreateFrame("GameTooltip", "AltArmyTBC_ScanTooltipV2", UIParent, "GameTooltipTemplate")
    return _scanTooltip
end

function SD._GetSearchableTextForItem(itemID, itemLink)
    if caches.searchableTextCache[itemID] then
        return caches.searchableTextCache[itemID]
    end
    local name = GetCachedItemName(itemID, itemLink)
    if not name then return nil end
    if InCombatLockdown and InCombatLockdown() then
        local result = name:lower()
        caches.searchableTextCache[itemID] = result
        return result
    end
    local lines = { name }
    if itemLink and itemLink ~= "" then
        pcall(function()
            local tip = getScanTooltip()
            tip:SetOwner(UIParent, "ANCHOR_NONE")
            tip:ClearLines()
            tip:SetHyperlink(itemLink)
            tip:Show()
            local numLines = tip:NumLines()
            local tooltipName = tip:GetName()
            for i = 2, math.min(numLines, 20) do
                local lineText = _G[tooltipName .. "TextLeft" .. i]
                if lineText then
                    local text = lineText:GetText()
                    if text and text ~= "" then
                        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                        table.insert(lines, text)
                    end
                end
            end
            tip:Hide()
        end)
    end
    local result = table.concat(lines, " "):lower()
    caches.searchableTextCache[itemID] = result
    return result
end

function SD._AggregateAndSort(raw, queryLower)
    return AltArmy.SearchPresent.AggregateItemRows(raw, queryLower)
end

function SD.GetSearchTailDebounceSecs(trimmedQuery)
    if not trimmedQuery or trimmedQuery == "" then
        return 0
    end
    local len = #trimmedQuery
    if len <= 1 then
        return 0.4
    end
    if len == 2 then
        return 0.1
    end
    return 0
end

function SD.SearchItems(query, skipTooltip)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}, {}
    end
    local SQ = AltArmy.SearchQuery
    local SP = AltArmy.SearchPresent
    local index = EnsureItemIndex()
    local queryLower, queryID = SQ.ParseQuery(query)
    local raw = SQ.MatchAndExpandItems(index, queryLower, queryID, caches.itemMemo)
    local mainRows = SP.AggregateItemRows(raw, queryLower or "")
    local tooltipOnlyRows = {}
    if queryLower and not skipTooltip then
        local matches = {}
        local seen = {}
        for i = 1, #raw do
            seen[raw[i]] = true
        end
        for i = 1, #index.entries do
            local entry = index.entries[i]
            if entry and not seen[entry] then
                local text = SD._GetSearchableTextForItem(entry.itemID, entry.itemLink)
                if text and text:find(queryLower, 1, true) then
                    SD._EnsureItemName(entry)
                    matches[#matches + 1] = entry
                end
            end
        end
        tooltipOnlyRows = SP.AggregateItemRows(matches, queryLower)
    end
    return mainRows, tooltipOnlyRows
end

local function ApplyRecipeFilters(results)
    local SS = AltArmy and AltArmy.SearchSettings
    local settings = SS and SS.GetSearchSettings and SS.GetSearchSettings() or nil
    if not settings then
        return results
    end
    local SP = AltArmy.SearchPresent
    if SP and SP.ApplyRecipeSearchFilters then
        return SP.ApplyRecipeSearchFilters(results, settings)
    end
    return results
end

local function NeedsCraftLibEnrichForFilters(settings)
    local SP = AltArmy.SearchPresent
    if SP and SP.NeedsCraftLibEnrichForFilters then
        return SP.NeedsCraftLibEnrichForFilters(settings)
    end
    return false
end

local function EnrichRecipeList(list)
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    if not RCL or not RCL.EnrichEntry then
        return list
    end
    for i = 1, #(list or {}) do
        local entry = list[i]
        if entry and not entry._aaCraftEnriched then
            RCL.EnrichEntry(entry)
            entry._aaCraftEnriched = true
        end
    end
    return list
end

function SD.SearchRecipes(query)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}
    end
    local SQ = AltArmy.SearchQuery
    local index = EnsureLocalRecipeIndex()
    local queryLower = type(query) == "string" and query:lower() or ""
    local results = SQ.MatchAndExpandRecipes(index, queryLower, caches.localRecipeMemo)
    local SS = AltArmy and AltArmy.SearchSettings
    local settings = SS and SS.GetSearchSettings and SS.GetSearchSettings() or nil
    if NeedsCraftLibEnrichForFilters(settings) then
        EnrichRecipeList(results)
    end
    return ApplyRecipeFilters(results)
end

function SD.SearchGuildRecipes(query)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}
    end
    local SQ = AltArmy.SearchQuery
    local index = EnsureGuildRecipeIndex()
    local queryLower = type(query) == "string" and query:lower() or ""
    local results = SQ.MatchAndExpandRecipes(index, queryLower, caches.guildRecipeMemo)
    local SS = AltArmy and AltArmy.SearchSettings
    local settings = SS and SS.GetSearchSettings and SS.GetSearchSettings() or nil
    if NeedsCraftLibEnrichForFilters(settings) then
        EnrichRecipeList(results)
    end
    return ApplyRecipeFilters(results)
end

function SD.MergeRecipeSearchResults(localList, guildList)
    local out = {}
    local n = 0
    for i = 1, #(localList or {}) do
        n = n + 1
        out[n] = localList[i]
    end
    for i = 1, #(guildList or {}) do
        n = n + 1
        out[n] = guildList[i]
    end
    return out
end

function SD.SortItemResults(list, sortKey, ascending)
    return AltArmy.SearchPresent.SortItemResults(list, sortKey, ascending)
end

function SD.SortRecipeResults(list, sortKey, ascending, craftLibAvailable)
    return AltArmy.SearchPresent.SortRecipeResults(list, sortKey, ascending, craftLibAvailable)
end

function SD.CollapseGuildRecipeRows(sortedList, expandedSet)
    return AltArmy.SearchPresent.CollapseGuildRecipeRows(sortedList, expandedSet)
end

function SD.EnrichRecipeEntry(entry)
    if not entry or entry._aaCraftEnriched then
        return entry
    end
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    if RCL and RCL.EnrichEntry then
        RCL.EnrichEntry(entry)
    end
    entry._aaCraftEnriched = true
    return entry
end

SD._EnrichRecipeEntry = SD.EnrichRecipeEntry

function SD.EnsureRecipeDisplayCache(entry)
    local SP = AltArmy.SearchPresent
    if SP and SP.EnsureRecipeDisplayCache then
        return SP.EnsureRecipeDisplayCache(entry)
    end
    return entry
end

function SD.StartRecipeResultPrewarm(list)
    local ST = AltArmy.SearchTasks
    if not ST or not list or #list == 0 then
        return
    end
    local index = 1
    local chunk = 40
    ST.Enqueue(function()
        local last = math.min(index + chunk - 1, #list)
        for j = index, last do
            SD.EnrichRecipeEntry(list[j])
            SD.EnsureRecipeDisplayCache(list[j])
        end
        index = last + 1
        return index > #list
    end)
end

function SD.StopRecipeResultPrewarm()
    local ST = AltArmy.SearchTasks
    if ST and ST.BumpGeneration then
        ST.BumpGeneration()
    end
end

function SD.IsRecipeResultPrewarmRunning()
    local ST = AltArmy.SearchTasks
    return ST and ST.IsBusy and ST.IsBusy() or false
end

function SD._TickRecipeResultPrewarmForTests()
    local ST = AltArmy.SearchTasks
    if ST and ST.TickForTests then
        ST.TickForTests()
    end
end


------------------------------------------------------------------------
-- Compatibility / public helpers
------------------------------------------------------------------------

function SD.Search(query, skipTooltip)
    return SD.SearchItems(query, skipTooltip)
end

--- Location-grouped search. Calls Search (stubbable), then aggregates both result lists.
function SD.SearchWithLocationGroups(query, skipTooltip)
    local main, tip = SD.Search(query, skipTooltip)
    local queryLower = type(query) == "string" and query:lower() or ""
    local SP = AltArmy.SearchPresent
    if not SP or not SP.AggregateItemRows then
        return main or {}, tip or {}
    end
    return SP.AggregateItemRows(main or {}, queryLower), SP.AggregateItemRows(tip or {}, queryLower)
end

function SD.ClearSearchCaches()
    SD.ClearCaches()
end

function SD.ClearSearchableTextCache()
    caches.searchableTextCache = {}
end

SD.InvalidateContainerSlotsCache = SD.NotifyContainerDataChanged
SD.InvalidateRecipesCache = SD.NotifyRecipesChanged

function SD._IsRecipeAliasId(recipeID, data)
    return IsRecipeAliasId(recipeID, data)
end

--- Test/helper: filter a recipe list by query and sort by recipe name (own before guild).
function SD._FilterAndSortRecipes(list, query)
    local queryLower = type(query) == "string" and query:lower() or ""
    local filtered = {}
    for i = 1, #(list or {}) do
        local entry = list[i]
        if entry then
            local nameLower = GetCachedRecipeNameLower(entry.recipeID)
            entry.recipeNameLower = nameLower
            if queryLower == "" or (nameLower and nameLower:find(queryLower, 1, true)) then
                filtered[#filtered + 1] = entry
            end
        end
    end
    return SD.SortRecipeResults(filtered, "Recipe", true, false)
end

function SD.StartIndexPrewarm()
    local ST = AltArmy.SearchTasks
    if not ST then
        return
    end
    ST.Enqueue(function()
        EnsureItemIndex()
        return true
    end)
    ST.Enqueue(function()
        EnsureLocalRecipeIndex()
        return true
    end)
    ST.Enqueue(function()
        EnsureGuildRecipeIndex()
        return true
    end)
end

function SD.StopIndexPrewarm()
    local ST = AltArmy.SearchTasks
    if ST and ST.BumpGeneration then
        ST.BumpGeneration()
    end
end

function SD.IsIndexPrewarmRunning()
    local ST = AltArmy.SearchTasks
    return ST and ST.IsBusy and ST.IsBusy() or false
end

function SD._LocationFromBagID(bagID)
    return LocationFromBagID(bagID)
end

function SD._LocationSortKey(location)
    if location == "bag" then return 1 end
    if location == "keyring" then return 2 end
    if location == "bank" then return 3 end
    if location == "equipped" then return 4 end
    if location == "mail" then return 5 end
    return 99
end

function SD._GetNameMatchScore(itemName, queryLower)
    if not itemName or not queryLower or queryLower == "" then
        return 0
    end
    local nameLower = itemName:lower()
    if nameLower == queryLower then return 3 end
    if nameLower:sub(1, #queryLower) == queryLower then return 2 end
    if nameLower:find(queryLower, 1, true) then return 1 end
    return 0
end

function SD._ApplyRecipeSearchFilters(results, settings)
    local SP = AltArmy.SearchPresent
    if SP and SP.ApplyRecipeSearchFilters then
        return SP.ApplyRecipeSearchFilters(results, settings)
    end
    return results
end

function SD._NeedsCraftLibEnrichForFilters(settings)
    local SP = AltArmy.SearchPresent
    if SP and SP.NeedsCraftLibEnrichForFilters then
        return SP.NeedsCraftLibEnrichForFilters(settings)
    end
    return false
end

function SD._FilterRecipesByLevel(results, filter)
    local SP = AltArmy.SearchPresent
    return SP and SP._FilterRecipesByLevel and SP._FilterRecipesByLevel(results, filter) or results
end

function SD._FilterRecipesByDifficulty(results, filter)
    local SP = AltArmy.SearchPresent
    return SP and SP._FilterRecipesByDifficulty and SP._FilterRecipesByDifficulty(results, filter) or results
end

function SD._FilterRecipesBySource(results, filter)
    local SP = AltArmy.SearchPresent
    return SP and SP._FilterRecipesBySource and SP._FilterRecipesBySource(results, filter) or results
end

function SD._FilterRecipesByProfession(results, filter)
    local SP = AltArmy.SearchPresent
    return SP and SP._FilterRecipesByProfession and SP._FilterRecipesByProfession(results, filter) or results
end

function SD.SearchGroupedByCharacter(query)
    local raw = SD.Search(query, true)
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
        list[#list + 1] = v
    end
    return list
end

local function SearchDebugEnabled()
    local Dbg = AltArmy and AltArmy.Debug
    return Dbg and Dbg.IsSearchEnabled and Dbg.IsSearchEnabled()
end

function SD.BeginScrollPaintDebug()
    if not SearchDebugEnabled() then return nil end
    if debugprofilestart then debugprofilestart() end
    return { itemRows = 0, recipeRows = 0, tooltipRows = 0 }
end

function SD.EndScrollPaintDebug(stats)
    if not stats or not SearchDebugEnabled() then return false end
    return false
end

function SD.NoteScrollItemPaint(stats)
    if stats then stats.itemRows = (stats.itemRows or 0) + 1 end
end

function SD.NoteScrollRecipePaint(stats, _)
    if stats then stats.recipeRows = (stats.recipeRows or 0) + 1 end
end

function SD.NoteScrollTooltipPaint(stats)
    if stats then stats.tooltipRows = (stats.tooltipRows or 0) + 1 end
end

local _cacheEventFrame = CreateFrame("Frame")
_cacheEventFrame:RegisterEvent("PLAYER_LOGOUT")
_cacheEventFrame:SetScript("OnEvent", function()
    SD.ClearSearchCaches()
end)

local _prewarmLoginFrame = CreateFrame("Frame")
_prewarmLoginFrame:RegisterEvent("PLAYER_LOGIN")
_prewarmLoginFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        SD.StartIndexPrewarm()
    end
end)
