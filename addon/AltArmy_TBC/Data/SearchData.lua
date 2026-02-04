-- AltArmy TBC — Search data layer: item search across all characters (bags + bank).
-- Uses AltArmy.DataStore IterateContainerSlots; builds flat list for Search tab.

AltArmy.SearchData = AltArmy.SearchData or {}

local SD = AltArmy.SearchData
local BANK_CONTAINER = -1
local MIN_BANK_BAG_ID = 5
local MAX_BANK_BAG_ID = 11

--- Determine location string from bagID: "bag" for 0-4, "bank" for -1 or 5-11.
local function LocationFromBagID(bagID)
    if bagID == BANK_CONTAINER or (bagID >= MIN_BANK_BAG_ID and bagID <= MAX_BANK_BAG_ID) then
        return "bank"
    end
    return "bag"
end
SD._LocationFromBagID = LocationFromBagID

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

--- Search: query can be item name (partial, case-insensitive) or item ID (number or string digits).
--- Returns list of entries matching query: { characterName, realm, itemID, itemLink, count, location, ... }.
function SD.Search(query)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}
    end
    local all = SD.GetAllContainerSlots()
    local results = {}
    local queryLower = type(query) == "string" and query:lower() or nil
    local queryID = nil
    if type(query) == "number" then
        queryID = query
    elseif type(query) == "string" and query:match("^%d+$") then
        queryID = tonumber(query)
    end
    for _, entry in ipairs(all) do
        local match = false
        if queryID ~= nil and entry.itemID == queryID then
            match = true
        elseif queryLower then
            local name = GetItemName(entry.itemID, entry.itemLink)
            if name and name:lower():find(queryLower, 1, true) then
                match = true
            end
            if not match and entry.itemLink and entry.itemLink:lower():find(queryLower, 1, true) then
                match = true
            end
        end
        if match then
            local itemName = GetItemName(entry.itemID, entry.itemLink)
            entry.itemName = itemName
            table.insert(results, entry)
        end
    end
    return results
end

--- Aggregate search results by (itemID, characterName, realm): sum count, keep first link.
--- Returns list of { characterName, realm, itemID, itemLink, count, location, itemName }.
function SD.SearchGroupedByCharacter(query)
    local raw = SD.Search(query)
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

--- Aggregate by (itemID, characterName, realm, location); sort by name match, then char total, then bags before bank.
--- Returns list of { itemID, itemLink, itemName, characterName, realm, location, count }.
function SD.SearchWithLocationGroups(query)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}
    end
    local raw = SD.Search(query)
    local queryLower = type(query) == "string" and query:lower() or ""

    -- Aggregate by (itemID, characterName, realm, location)
    local byKey = {}
    local charTotals = {} -- key = itemID .. "\t" .. characterName .. "\t" .. realm -> total count (bags + bank)
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
        -- bags before bank: "bag" < "bank"
        return (a.location or "bag") < (b.location or "bag")
    end)

    -- Remove temporary sort fields before return (optional; UI doesn't need them)
    for _, row in ipairs(list) do
        row.charTotal = nil
        row.matchScore = nil
    end
    return list
end
