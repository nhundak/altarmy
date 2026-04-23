-- AltArmy TBC — Search data layer: item search across all characters (bags + bank).
-- Uses AltArmy.DataStore IterateContainerSlots; builds flat list for Search tab.

AltArmy.SearchData = AltArmy.SearchData or {}

local SD = AltArmy.SearchData
local BANK_CONTAINER = -1
local MIN_BANK_BAG_ID = 5
local MAX_BANK_BAG_ID = 11

-- In-memory cache: itemID (number) -> lowercased searchable string (name + tooltip lines).
-- Cleared on PLAYER_LOGOUT so it doesn't carry state across sessions.
local _searchableTextCache = {}

function SD.ClearSearchableTextCache()
    _searchableTextCache = {}
end

local _cacheEventFrame = CreateFrame("Frame")
_cacheEventFrame:RegisterEvent("PLAYER_LOGOUT")
_cacheEventFrame:SetScript("OnEvent", function()
    SD.ClearSearchableTextCache()
end)

-- Private tooltip frame for scanning item text.
-- Using a dedicated frame (not GameTooltip) prevents other addons from injecting their
-- extra lines via GameTooltip hooks (e.g. inventory-tracking addons that add character
-- info to every tooltip). Only Blizzard's native tooltip lines are populated here.
local _scanTooltip = CreateFrame("GameTooltip", "AltArmyTBC_ScanTooltip", UIParent, "GameTooltipTemplate")

--- Determine location string from bagID: "bag" for 0-4, "bank" for -1 or 5-11.
local function LocationFromBagID(bagID)
    if bagID == BANK_CONTAINER or (bagID >= MIN_BANK_BAG_ID and bagID <= MAX_BANK_BAG_ID) then
        return "bank"
    end
    return "bag"
end
SD._LocationFromBagID = LocationFromBagID

local function LocationSortKey(location)
    if location == "bag" then return 1 end
    if location == "bank" then return 2 end
    if location == "mail" then return 3 end
    return 99
end
SD._LocationSortKey = LocationSortKey

--- Build flat list of all container slots across all characters.
--- Each entry: { characterName, realm, itemID, itemLink, count, location, bagID, slot }.
function SD.GetAllContainerSlots()
    local list = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.GetRealms or not DS.GetCharacters
        or not DS.IterateContainerSlots or not DS.GetCharacterName then
        return list
    end
    -- Refresh current character's bags so we have up-to-date data
    -- (PLAYER_ENTERING_WORLD may fire before bags are ready)
    if DS.ScanCurrentCharacterBags then
        DS:ScanCurrentCharacterBags()
    end
    for realm in pairs(DS:GetRealms()) do
        for charName, charData in pairs(DS:GetCharacters(realm)) do
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
        end
    end
    return list
end

--- Get item name from itemID or link (for search). Returns nil if not cached.
local function GetItemName(itemID, link)
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

--- Build and cache a searchable string for an item: lowercased item name + all tooltip left-column lines.
--- Returns a string on success, or nil if the item name cannot be resolved.
--- Exposed as SD._GetSearchableTextForItem so tests can stub it without touching GameTooltip.
function SD._GetSearchableTextForItem(itemID, itemLink)
    if _searchableTextCache[itemID] then
        return _searchableTextCache[itemID]
    end
    local name = GetItemName(itemID, itemLink)
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
function SD.Search(query, skipTooltip)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}, {}
    end
    local all = SD.GetAllContainerSlots()
    local mainResults = {}
    local tooltipOnlyResults = {}
    local queryLower = type(query) == "string" and query:lower() or nil
    local queryID = nil
    if type(query) == "number" then
        queryID = query
    elseif type(query) == "string" and query:match("^%d+$") then
        queryID = tonumber(query)
    end
    for _, entry in ipairs(all) do
        local mainMatch = false
        if queryID ~= nil and entry.itemID == queryID then
            mainMatch = true
        elseif queryLower then
            local name = GetItemName(entry.itemID, entry.itemLink)
            if name and name:lower():find(queryLower, 1, true) then
                mainMatch = true
            end
            if not mainMatch and entry.itemLink and entry.itemLink:lower():find(queryLower, 1, true) then
                mainMatch = true
            end
        end
        if mainMatch then
            entry.itemName = entry.itemName or GetItemName(entry.itemID, entry.itemLink)
            table.insert(mainResults, entry)
        elseif queryLower and not skipTooltip then
            local searchableText = SD._GetSearchableTextForItem(entry.itemID, entry.itemLink)
            if searchableText and searchableText:find(queryLower, 1, true) then
                entry.itemName = entry.itemName or GetItemName(entry.itemID, entry.itemLink)
                table.insert(tooltipOnlyResults, entry)
            end
        end
    end
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

--- Aggregate by (itemID, characterName, realm, location); sort by name match, then char total, then bags before bank.
--- Returns two lists: mainRows and tooltipOnlyRows (same row shape as before).
--- Pass skipTooltip=true to skip tooltip scanning (tooltipOnlyRows will be empty).
function SD.SearchWithLocationGroups(query, skipTooltip)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}, {}
    end
    local mainResults, tooltipOnlyResults = SD.Search(query, skipTooltip)
    local queryLower = type(query) == "string" and query:lower() or ""

    local mainRows = AggregateAndSort(mainResults, queryLower)
    local tooltipOnlyRows = AggregateAndSort(tooltipOnlyResults, queryLower)
    return mainRows, tooltipOnlyRows
end

--- Build flat list of all known recipes across all characters.
--- Each entry: { characterName, realm, classFile, professionName, skillRank, recipeID }.
function SD.GetAllRecipes()
    local list = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.GetRealms or not DS.GetCharacters or not DS.GetCharacterName
        or not DS.GetCharacterClass or not DS.GetProfessions then
        return list
    end
    for realm in pairs(DS:GetRealms()) do
        for charName, charData in pairs(DS:GetCharacters(realm)) do
            if charData then
                local professions = DS:GetProfessions(charData)
                if professions then
                    local characterName = DS:GetCharacterName(charData) or charName
                    local _, classFile = DS:GetCharacterClass(charData)
                    for profName, prof in pairs(professions) do
                        if prof and prof.Recipes then
                            local skillRank = prof.rank or 0
                            for recipeID, data in pairs(prof.Recipes) do
                                if recipeID then
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
        end
    end
    return list
end

--- Get recipe name from recipeID (spell first, then item). Returns nil if not resolved.
local function GetRecipeName(recipeID)
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

--- Search recipes by name (partial, case-insensitive). Returns list of matching entries.
function SD.SearchRecipes(query)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}
    end
    local all = SD.GetAllRecipes()
    local queryLower = type(query) == "string" and query:lower() or ""
    local results = {}
    for _, entry in ipairs(all) do
        local name = GetRecipeName(entry.recipeID)
        if name and name:lower():find(queryLower, 1, true) then
            table.insert(results, entry)
        end
    end
    table.sort(results, function(a, b)
        local na = GetRecipeName(a.recipeID) or ""
        local nb = GetRecipeName(b.recipeID) or ""
        if na:lower() ~= nb:lower() then return na:lower() < nb:lower() end
        return (a.characterName or "") < (b.characterName or "")
    end)
    return results
end
