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
local _slotsByItemID = nil
local _itemSuffixArray = nil
local _localRecipesCache = nil
local _localRecipesByID = nil
local _localRecipeSuffixArray = nil
local _guildRecipesCache = nil
local _guildRecipesByID = nil
local _guildRecipeSuffixArray = nil
local _itemNameCache = {}
local _recipeNameCache = {}
local _itemAggregateGroup = nil

-- Background index prewarm (chunked OnUpdate). Packed into one table for the local limit.
local PREWARM_NAME_CHUNK = 200
local PREWARM_SUFFIX_ENTRY_BUDGET = 2000
local PREWARM_SORT_RUN = 200
local PREWARM_SORT_ENTRY_BUDGET = 2000
local PREWARM_RESTART_DEBOUNCE_SEC = 0.5
local _prewarmFrame = CreateFrame("Frame")
local _prewarmRestartFrame = CreateFrame("Frame")
local _prewarm = {
    generation = 0,
    running = false,
    phase = nil,
    nameList = nil,
    nameIndex = 1,
    charOffset = 1,
    suffixArr = nil,
    idKeys = nil,
    idKeyIndex = 1,
    restartRemaining = 0,
    wallStart = 0,
    sortState = nil,
    sortNameCount = 0,
    sortSuffixCount = 0,
    sortWallStart = 0,
}

-- Forward declarations (assigned after Ensure* helpers exist).
local StartIndexPrewarm
local StopIndexPrewarm
local SchedulePrewarmRestart
local FinishItemSuffixArraySync
local FinishLocalRecipeSuffixArraySync
local FinishGuildRecipeSuffixArraySync

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

--- Record elapsed ms since last SearchProfileStart into timings[key], accumulate total, restart profiler.
local function ProfileMark(timings, key)
    if not timings then
        return
    end
    local ms = SearchProfileElapsedMs()
    timings[key] = ms
    timings.total = (timings.total or 0) + ms
    SearchProfileStart()
end

--- Like ProfileMark, but adds to an existing timings[key] (for phases run more than once).
local function ProfileAdd(timings, key)
    if not timings then
        return
    end
    local ms = SearchProfileElapsedMs()
    timings[key] = (timings[key] or 0) + ms
    timings.total = (timings.total or 0) + ms
    SearchProfileStart()
end

local function FormatPhaseMs(timings, key)
    local v = timings and timings[key]
    if type(v) ~= "number" then
        return 0
    end
    return v
end

--- Log index-build timing when search debug is on. Restarts the profiler after logging
--- so nested callers (search) can still measure their own work afterward.
local function LogIndexBuild(kind, ms, detail)
    if not SearchDebugEnabled() then
        return
    end
    if detail and detail ~= "" then
        LogSearchDebug(string.format("  index %s ms=%.2f %s", kind, ms, detail))
    else
        LogSearchDebug(string.format("  index %s ms=%.2f", kind, ms))
    end
    SearchProfileStart()
end

local function CountMapKeys(t)
    local n = 0
    for _ in pairs(t or {}) do
        n = n + 1
    end
    return n
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
    if StopIndexPrewarm then
        StopIndexPrewarm()
    end
    _containerSlotsCache = nil
    _slotsByItemID = nil
    _itemSuffixArray = nil
    _itemAggregateGroup = nil
    if SchedulePrewarmRestart then
        SchedulePrewarmRestart()
    end
end

function SD.InvalidateRecipesCache()
    if StopIndexPrewarm then
        StopIndexPrewarm()
    end
    _localRecipesCache = nil
    _localRecipesByID = nil
    _localRecipeSuffixArray = nil
    _guildRecipesCache = nil
    _guildRecipesByID = nil
    _guildRecipeSuffixArray = nil
    if SchedulePrewarmRestart then
        SchedulePrewarmRestart()
    end
end

function SD.NotifyContainerDataChanged()
    SD.InvalidateContainerSlotsCache()
end

function SD.NotifyRecipesChanged()
    SD.InvalidateRecipesCache()
end

function SD.ClearSearchCaches()
    if StopIndexPrewarm then
        StopIndexPrewarm()
    end
    _prewarmRestartFrame:SetScript("OnUpdate", nil)
    _prewarm.restartRemaining = 0
    _searchableTextCache = {}
    _containerSlotsCache = nil
    _slotsByItemID = nil
    _itemSuffixArray = nil
    _itemAggregateGroup = nil
    _localRecipesCache = nil
    _localRecipesByID = nil
    _localRecipeSuffixArray = nil
    _guildRecipesCache = nil
    _guildRecipesByID = nil
    _guildRecipeSuffixArray = nil
    _itemNameCache = {}
    _recipeNameCache = {}
end

--- Debounce delay (seconds) for tooltip-only search tail.
--- 1 char → 0.4s; 2 chars → 0.1s; 3+ → 0 (start chunked scan immediately).
--- Guild recipes are always searched synchronously with local recipes.
--- @param trimmedQuery string|nil already trimmed query text
--- @return number delay in seconds (0 = run immediately in the same call)
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

--- Build itemID -> { entry, ... } from a flat slot list.
local function BuildSlotsByItemID(list)
    local byID = {}
    for i = 1, #(list or {}) do
        local entry = list[i]
        local id = entry and entry.itemID
        if id then
            local bucket = byID[id]
            if not bucket then
                bucket = {}
                byID[id] = bucket
            end
            bucket[#bucket + 1] = entry
        end
    end
    return byID
end
SD._BuildSlotsByItemID = BuildSlotsByItemID

--- Build recipeID -> { entry, ... } from a flat recipe list.
local function BuildRecipesByID(list)
    local byID = {}
    for i = 1, #(list or {}) do
        local entry = list[i]
        local id = entry and entry.recipeID
        if id then
            local bucket = byID[id]
            if not bucket then
                bucket = {}
                byID[id] = bucket
            end
            bucket[#bucket + 1] = entry
        end
    end
    return byID
end
SD._BuildRecipesByID = BuildRecipesByID

--- Append suffixes for one name into arr, starting at startChar (1-based).
--- Stops after maxEntries new entries. Returns nextChar (or #nameLower+1 when done) and count added.
local function AppendSuffixesForName(arr, nameLower, id, startChar, maxEntries)
    if type(nameLower) ~= "string" or nameLower == "" or not id then
        return 1, 0
    end
    local n = #nameLower
    local added = 0
    local i = startChar or 1
    while i <= n and added < maxEntries do
        arr[#arr + 1] = { suffix = nameLower:sub(i), id = id }
        added = added + 1
        i = i + 1
    end
    return i, added
end
SD._AppendSuffixesForName = AppendSuffixesForName

local function SortSuffixArray(arr)
    table.sort(arr, function(a, b)
        if a.suffix ~= b.suffix then
            return a.suffix < b.suffix
        end
        return (a.id or 0) < (b.id or 0)
    end)
end
SD._SortSuffixArray = SortSuffixArray

local function SuffixEntryLess(a, b)
    if a.suffix ~= b.suffix then
        return a.suffix < b.suffix
    end
    return (a.id or 0) < (b.id or 0)
end

--- Sort inclusive range [lo, hi] via a temporary table (Lua 5.1 has no ranged table.sort).
local function SortSuffixRun(arr, lo, hi)
    if lo >= hi then
        return
    end
    local tmp = {}
    for i = lo, hi do
        tmp[#tmp + 1] = arr[i]
    end
    table.sort(tmp, SuffixEntryLess)
    for i = 1, #tmp do
        arr[lo + i - 1] = tmp[i]
    end
end

--- Merge sorted runs [left, mid] and [mid+1, right] in place using tmp scratch.
local function MergeSuffixRuns(arr, left, mid, right, tmp)
    local i, j, k = left, mid + 1, 1
    while i <= mid and j <= right do
        if SuffixEntryLess(arr[i], arr[j]) then
            tmp[k] = arr[i]
            i = i + 1
        else
            tmp[k] = arr[j]
            j = j + 1
        end
        k = k + 1
    end
    while i <= mid do
        tmp[k] = arr[i]
        i = i + 1
        k = k + 1
    end
    while j <= right do
        tmp[k] = arr[j]
        j = j + 1
        k = k + 1
    end
    for t = 1, k - 1 do
        arr[left + t - 1] = tmp[t]
    end
end

--- Begin a resumable bottom-up sort (runs of PREWARM_SORT_RUN, then merge).
--- @return table state
local function BeginChunkedSuffixSort(arr)
    return {
        arr = arr or {},
        phase = "runs",
        runPos = 1,
        width = PREWARM_SORT_RUN,
        mergePos = 1,
        tmp = {},
        done = false,
    }
end
SD._BeginChunkedSuffixSort = BeginChunkedSuffixSort
SD._PREWARM_SORT_RUN = PREWARM_SORT_RUN

--- Advance chunked sort by about PREWARM_SORT_ENTRY_BUDGET entries.
--- @return boolean done
local function ChunkedSuffixSortStep(state)
    if not state or state.done then
        return true
    end
    local arr = state.arr
    local n = #arr
    if n <= 1 then
        state.done = true
        return true
    end
    local budget = PREWARM_SORT_ENTRY_BUDGET

    if state.phase == "runs" then
        while budget > 0 and state.runPos <= n do
            local lo = state.runPos
            local hi = math.min(lo + PREWARM_SORT_RUN - 1, n)
            SortSuffixRun(arr, lo, hi)
            budget = budget - (hi - lo + 1)
            state.runPos = hi + 1
        end
        if state.runPos <= n then
            return false
        end
        if n <= PREWARM_SORT_RUN then
            state.done = true
            return true
        end
        state.phase = "merge"
        state.width = PREWARM_SORT_RUN
        state.mergePos = 1
    end

    while budget > 0 and state.width < n do
        local left = state.mergePos
        if left > n then
            state.width = state.width * 2
            state.mergePos = 1
        else
            local mid = math.min(left + state.width - 1, n)
            local right = math.min(left + state.width * 2 - 1, n)
            if mid < right then
                MergeSuffixRuns(arr, left, mid, right, state.tmp)
                budget = budget - (right - left + 1)
            end
            state.mergePos = left + state.width * 2
        end
    end

    if state.width >= n then
        state.done = true
        return true
    end
    return false
end
SD._ChunkedSuffixSortStep = ChunkedSuffixSortStep

--- Build suffix array from map id -> nameLower. Entries: { suffix = string, id = number }.
local function BuildSuffixArray(idToNameLower)
    local debug = SearchDebugEnabled()
    if debug then
        SearchProfileStart()
    end
    local arr = {}
    local nameCount = 0
    for id, nameLower in pairs(idToNameLower or {}) do
        nameCount = nameCount + 1
        AppendSuffixesForName(arr, nameLower, id, 1, math.huge)
    end
    SortSuffixArray(arr)
    if debug then
        LogIndexBuild("suffixArray", SearchProfileElapsedMs(), string.format(
            "names=%d suffixes=%d", nameCount, #arr))
    end
    return arr
end
SD._BuildSuffixArray = BuildSuffixArray

local function SuffixHasPrefix(suffix, prefix)
    local plen = #prefix
    return #suffix >= plen and suffix:sub(1, plen) == prefix
end

--- First index where arr[i].suffix >= query (1-based); #arr+1 if none.
local function SuffixArrayLowerBound(arr, query)
    local lo, hi = 1, #arr + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if arr[mid].suffix < query then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo
end

--- First index >= startIdx where suffix does not have query as prefix.
local function SuffixArrayUpperBound(arr, query, startIdx)
    local lo, hi = startIdx, #arr + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if SuffixHasPrefix(arr[mid].suffix, query) then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo
end

--- Returns set map id -> true for IDs whose name contains queryLower as substring.
local function LookupSuffixArrayIds(arr, queryLower)
    local ids = {}
    if not arr or not queryLower or queryLower == "" then
        return ids
    end
    local lo = SuffixArrayLowerBound(arr, queryLower)
    local hi = SuffixArrayUpperBound(arr, queryLower, lo)
    for i = lo, hi - 1 do
        ids[arr[i].id] = true
    end
    return ids
end
SD._LookupSuffixArrayIds = LookupSuffixArrayIds
SD._SuffixArrayLowerBound = SuffixArrayLowerBound
SD._SuffixArrayUpperBound = SuffixArrayUpperBound

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
    local debug = SearchDebugEnabled()
    if debug then
        SearchProfileStart()
    end
    _containerSlotsCache = BuildAllContainerSlots()
    _slotsByItemID = BuildSlotsByItemID(_containerSlotsCache)
    _itemSuffixArray = nil
    _itemAggregateGroup = nil
    if debug then
        LogIndexBuild("containerSlots", SearchProfileElapsedMs(), string.format(
            "slots=%d uniqueItems=%d",
            #_containerSlotsCache,
            CountMapKeys(_slotsByItemID)))
    end
    return _containerSlotsCache
end

local function GetSlotsByItemID()
    if _slotsByItemID then
        return _slotsByItemID
    end
    SD.GetAllContainerSlots()
    return _slotsByItemID or {}
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

--- Lazy: suffix array needs resolved item names (GetItemInfo may be cold at bag-scan time).
local function EnsureItemSuffixArray()
    if _itemSuffixArray then
        return _itemSuffixArray
    end
    return FinishItemSuffixArraySync()
end

local function AppendIndexedRows(dest, rows, seen)
    if not rows then
        return
    end
    for i = 1, #rows do
        local entry = rows[i]
        if entry and not seen[entry] then
            seen[entry] = true
            SD._EnsureItemName(entry)
            dest[#dest + 1] = entry
        end
    end
end

local function FilterContainerSlots(all, queryLower, queryID, skipTooltip, timings)
    local mainResults = {}
    local tooltipOnlyResults = {}
    local seen = {}
    local byID
    local suffixArr
    if _slotsByItemID and _containerSlotsCache and all == _containerSlotsCache then
        byID = _slotsByItemID
        if queryLower then
            suffixArr = EnsureItemSuffixArray()
        end
    else
        byID = BuildSlotsByItemID(all)
        if queryLower then
            local names = {}
            for itemID, rows in pairs(byID) do
                local entry = rows[1]
                local nameLower = GetCachedItemNameLower(itemID, entry and entry.itemLink)
                if nameLower then
                    names[itemID] = nameLower
                end
            end
            suffixArr = BuildSuffixArray(names)
        end
    end
    local matchedIds = {}

    if queryID ~= nil then
        matchedIds[queryID] = true
        AppendIndexedRows(mainResults, byID[queryID], seen)
    end

    if queryLower then
        local ids = LookupSuffixArrayIds(suffixArr, queryLower)
        ProfileMark(timings, "lookup")
        for itemID in pairs(ids) do
            matchedIds[itemID] = true
            AppendIndexedRows(mainResults, byID[itemID], seen)
        end
        -- Link-only fallback for IDs not matched by name (preserves prior :find on itemLink).
        for itemID, rows in pairs(byID) do
            if not matchedIds[itemID] then
                local entry = rows[1]
                if entry and entry.itemLink and entry.itemLink:lower():find(queryLower, 1, true) then
                    matchedIds[itemID] = true
                    AppendIndexedRows(mainResults, rows, seen)
                end
            end
        end
        ProfileMark(timings, "expand")
    elseif timings then
        timings.lookup = 0
        timings.expand = 0
    end

    if queryLower and not skipTooltip then
        for i = 1, #(all or {}) do
            local entry = all[i]
            if entry and not seen[entry] then
                local searchableText = SD._GetSearchableTextForItem(entry.itemID, entry.itemLink)
                if searchableText and searchableText:find(queryLower, 1, true) then
                    SD._EnsureItemName(entry)
                    tooltipOnlyResults[#tooltipOnlyResults + 1] = entry
                end
            end
        end
        ProfileMark(timings, "tooltip")
    end
    return mainResults, tooltipOnlyResults
end
SD._FilterContainerSlots = FilterContainerSlots

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

local function SearchContainerSlots(query, skipTooltip, timings)
    local all = SD.GetAllContainerSlots()
    local queryLower, queryID = ParseItemSearchQuery(query)
    local mainResults, tooltipOnlyResults = FilterContainerSlots(all, queryLower, queryID, skipTooltip, timings)
    return mainResults, tooltipOnlyResults, #all, all
end
SD._SearchContainerSlots = SearchContainerSlots

function SD.Search(query, skipTooltip, timings)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}, {}
    end
    local mainResults, tooltipOnlyResults = SearchContainerSlots(query, skipTooltip, timings)
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
local function GetNameMatchScoreFromLower(nameLower, queryLower)
    if not nameLower or not queryLower or queryLower == "" then
        return 0
    end
    if nameLower == queryLower then
        return 3
    end
    if nameLower:sub(1, #queryLower) == queryLower then
        return 2
    end
    if nameLower:find(queryLower, 1, true) then
        return 1
    end
    return 0
end

local function GetNameMatchScore(itemName, queryLower)
    if not itemName or not queryLower or queryLower == "" then
        return 0
    end
    return GetNameMatchScoreFromLower(itemName:lower(), queryLower)
end
SD._GetNameMatchScore = GetNameMatchScore

local function EnsureNestedMap(parent, key)
    local child = parent[key]
    if not child then
        child = {}
        parent[key] = child
    end
    return child
end

--- Build query-independent item -> character/location group map from a flat slot list.
--- Does not set matchScore (query-specific).
local function BuildItemAggregateGroupFromList(list)
    local byItem = {}
    for i = 1, #(list or {}) do
        local entry = list[i]
        local itemID = entry.itemID or 0
        local item = byItem[itemID]
        if not item then
            if not entry.itemName then
                SD._EnsureItemName(entry)
            elseif not entry.itemNameLower and entry.itemName then
                entry.itemNameLower = entry.itemName:lower()
            end
            local itemName = entry.itemName
            local nameLower = entry.itemNameLower
                or (itemName and itemName:lower())
                or ""
            item = {
                itemID = itemID,
                itemName = itemName,
                itemLink = entry.itemLink,
                nameLower = nameLower,
                chars = {},
            }
            byItem[itemID] = item
        elseif not item.itemLink and entry.itemLink then
            item.itemLink = entry.itemLink
        end

        local realm = entry.realm or ""
        local charName = entry.characterName or ""
        local realmMap = EnsureNestedMap(item.chars, realm)
        local ch = realmMap[charName]
        if not ch then
            ch = {
                classFile = entry.classFile,
                total = 0,
                locs = {},
            }
            realmMap[charName] = ch
        end

        local loc = entry.location or "bag"
        local locRow = ch.locs[loc]
        local count = entry.count or 1
        if not locRow then
            locRow = {
                itemID = itemID,
                itemLink = entry.itemLink or item.itemLink,
                itemName = item.itemName,
                characterName = charName,
                realm = realm,
                location = loc,
                locKey = LocationSortKey(loc),
                count = 0,
                classFile = entry.classFile or ch.classFile,
            }
            ch.locs[loc] = locRow
        end
        locRow.count = locRow.count + count
        ch.total = ch.total + count
    end
    return byItem
end

local function EnsureItemAggregateGroup()
    if _itemAggregateGroup then
        return _itemAggregateGroup
    end
    local debug = SearchDebugEnabled()
    if debug then
        SearchProfileStart()
    end
    local all = SD.GetAllContainerSlots()
    for i = 1, #(all or {}) do
        SD._EnsureItemName(all[i])
    end
    _itemAggregateGroup = BuildItemAggregateGroupFromList(all)
    if debug then
        LogIndexBuild("itemAggregateGroup", SearchProfileElapsedMs(), string.format(
            "uniqueItems=%d", CountMapKeys(_itemAggregateGroup)))
    end
    return _itemAggregateGroup
end
SD._EnsureItemAggregateGroup = EnsureItemAggregateGroup

function SD._GetItemAggregateGroupForTests()
    return _itemAggregateGroup
end

--- Aggregate a flat list of search entries by (itemID, characterName, realm, location).
--- Uses the cached full-inventory group when available (built at prewarm / first ensure);
--- falls back to grouping `raw` when the cache does not cover those item IDs (unit tests).
--- When `timings` is set, accumulates aggGroup / aggScore / aggSort / aggCleanup ms.
local function AggregateAndSort(raw, queryLower, timings)
    local matchedIds = {}
    local nRaw = #(raw or {})
    for i = 1, nRaw do
        matchedIds[raw[i].itemID or 0] = true
    end

    local byItem = _itemAggregateGroup
    if not byItem then
        -- Prefer building the full cache when container slots exist; otherwise group raw only.
        local all = _containerSlotsCache
        if all and #all > 0 then
            byItem = EnsureItemAggregateGroup()
        end
    end

    local items = {}
    if byItem then
        for itemID in pairs(matchedIds) do
            local item = byItem[itemID]
            if item then
                items[#items + 1] = item
            end
        end
    end

    if #items == 0 and nRaw > 0 then
        byItem = BuildItemAggregateGroupFromList(raw)
        for _, item in pairs(byItem) do
            items[#items + 1] = item
        end
    end
    ProfileAdd(timings, "aggGroup")

    for i = 1, #items do
        local item = items[i]
        item.matchScore = GetNameMatchScoreFromLower(item.nameLower, queryLower)
    end
    ProfileAdd(timings, "aggScore")

    table.sort(items, function(a, b)
        if a.matchScore ~= b.matchScore then
            return a.matchScore > b.matchScore
        end
        if a.nameLower ~= b.nameLower then
            return a.nameLower < b.nameLower
        end
        return (a.itemID or 0) < (b.itemID or 0)
    end)

    local list = {}
    for i = 1, #items do
        local item = items[i]
        local rows = {}
        for _, realmMap in pairs(item.chars) do
            for _, ch in pairs(realmMap) do
                for _, locRow in pairs(ch.locs) do
                    locRow.charTotal = ch.total
                    rows[#rows + 1] = locRow
                end
            end
        end
        if #rows > 1 then
            table.sort(rows, function(a, b)
                if a.charTotal ~= b.charTotal then
                    return a.charTotal > b.charTotal
                end
                if a.locKey ~= b.locKey then
                    return a.locKey < b.locKey
                end
                return (a.location or "") < (b.location or "")
            end)
        end
        for j = 1, #rows do
            list[#list + 1] = rows[j]
        end
    end
    ProfileAdd(timings, "aggSort")

    for i = 1, #list do
        list[i].charTotal = nil
    end
    ProfileAdd(timings, "aggCleanup")
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
    local timings = debug and { total = 0 } or nil
    -- Build/reuse query-independent group outside search timing (prewarm usually already did this).
    EnsureItemAggregateGroup()
    if debug then
        SearchProfileStart()
    end
    local queryLower = type(query) == "string" and query:lower() or ""
    local mainResults, tooltipOnlyResults = SD.Search(query, skipTooltip, timings)
    local mainRows = AggregateAndSort(mainResults, queryLower, timings)
    local tooltipOnlyRows = AggregateAndSort(tooltipOnlyResults, queryLower, timings)
    if timings then
        timings.aggregate = FormatPhaseMs(timings, "aggGroup")
            + FormatPhaseMs(timings, "aggScore")
            + FormatPhaseMs(timings, "aggSort")
            + FormatPhaseMs(timings, "aggCleanup")
    end
    if debug then
        LogSearchDebug(string.format(
            "  items q=%q ms=%.2f mainRows=%d tooltipRows=%d skipTooltip=%s"
                .. " lookup=%.2f expand=%.2f aggregate=%.2f"
                .. " aggGroup=%.2f aggScore=%.2f aggSort=%.2f aggCleanup=%.2f",
            SearchQueryLabel(query),
            FormatPhaseMs(timings, "total"),
            #mainRows,
            #tooltipOnlyRows,
            tostring(skipTooltip and true or false),
            FormatPhaseMs(timings, "lookup"),
            FormatPhaseMs(timings, "expand"),
            FormatPhaseMs(timings, "aggregate"),
            FormatPhaseMs(timings, "aggGroup"),
            FormatPhaseMs(timings, "aggScore"),
            FormatPhaseMs(timings, "aggSort"),
            FormatPhaseMs(timings, "aggCleanup")
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
    local SS = AltArmy and AltArmy.SearchSettings
    if SS and SS.CanShowIncludeGuildmatesToggle and not SS.CanShowIncludeGuildmatesToggle() then
        return false
    end
    if SS and SS.IsIncludeGuildmatesEnabled then
        return SS.IsIncludeGuildmatesEnabled()
    end
    return true
end

--- Append recipes shared by guildmates (from GuildShareData) into the recipe list,
--- tagged isGuild = true with the guildmate's identity. Only primary (non-alias) ids.
--- Caller must check ShouldIncludeGuildRecipes before calling.
local function AppendGuildRecipes(list)
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

local function BuildGuildRecipes()
    local list = {}
    AppendGuildRecipes(list)
    return list
end

--- Own-character recipes only (sync search path).
function SD.GetAllRecipes()
    if _localRecipesCache then
        return _localRecipesCache
    end
    local debug = SearchDebugEnabled()
    if debug then
        SearchProfileStart()
    end
    _localRecipesCache = BuildLocalRecipes()
    _localRecipesByID = BuildRecipesByID(_localRecipesCache)
    _localRecipeSuffixArray = nil
    if debug then
        LogIndexBuild("localRecipes", SearchProfileElapsedMs(), string.format(
            "rows=%d uniqueRecipes=%d",
            #_localRecipesCache,
            CountMapKeys(_localRecipesByID)))
    end
    return _localRecipesCache
end

--- Guildmate-shared recipes only (deferred search path). Empty when include-guildmates is off.
function SD.GetAllGuildRecipes()
    if not ShouldIncludeGuildRecipes() then
        return {}
    end
    if _guildRecipesCache then
        return _guildRecipesCache
    end
    local debug = SearchDebugEnabled()
    if debug then
        SearchProfileStart()
    end
    _guildRecipesCache = BuildGuildRecipes()
    _guildRecipesByID = BuildRecipesByID(_guildRecipesCache)
    _guildRecipeSuffixArray = nil
    if debug then
        LogIndexBuild("guildRecipes", SearchProfileElapsedMs(), string.format(
            "rows=%d uniqueRecipes=%d",
            #_guildRecipesCache,
            CountMapKeys(_guildRecipesByID)))
    end
    return _guildRecipesCache
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

local function EnsureRecipeSuffixArray(byID, cachedArr, setCached)
    if cachedArr then
        return cachedArr
    end
    local names = {}
    for recipeID, _ in pairs(byID or {}) do
        local nameLower = GetCachedRecipeNameLower(recipeID)
        if nameLower then
            names[recipeID] = nameLower
        end
    end
    local arr = BuildSuffixArray(names)
    setCached(arr)
    return arr
end

local function EnsureLocalRecipeSuffixArray()
    if _localRecipeSuffixArray then
        return _localRecipeSuffixArray
    end
    return FinishLocalRecipeSuffixArraySync()
end

local function EnsureGuildRecipeSuffixArray()
    if _guildRecipeSuffixArray then
        return _guildRecipeSuffixArray
    end
    return FinishGuildRecipeSuffixArraySync()
end

--- Own characters before guildmates, then character name A-Z (within one recipe ID).
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

local function SortUniqueRecipeIdList(uniqueList)
    table.sort(uniqueList, function(a, b)
        local na = a.nameLower or ""
        local nb = b.nameLower or ""
        if na ~= nb then
            return na < nb
        end
        return (a.id or 0) < (b.id or 0)
    end)
end

--- Append byID rows for each unique ID in order; sort characters within each ID.
local function ExpandSortedRecipeIds(results, uniqueList, byID, seen)
    for i = 1, #uniqueList do
        local u = uniqueList[i]
        local rows = byID and byID[u.id]
        if rows then
            local bucket = {}
            for j = 1, #rows do
                local entry = rows[j]
                if entry and not seen[entry] then
                    bucket[#bucket + 1] = entry
                end
            end
            if #bucket > 1 then
                table.sort(bucket, CompareRecipeRowsWithinId)
            end
            local nameLower = u.nameLower
            for j = 1, #bucket do
                local entry = bucket[j]
                seen[entry] = true
                entry.recipeNameLower = nameLower
                results[#results + 1] = entry
            end
        end
    end
end
SD._SortUniqueRecipeIdList = SortUniqueRecipeIdList
SD._ExpandSortedRecipeIds = ExpandSortedRecipeIds
SD._CompareRecipeRowsWithinId = CompareRecipeRowsWithinId

--- Search recipes by name (partial, case-insensitive). Uses ID index + suffix array when available.
--- Sorts unique recipe IDs by name, then expands character rows (O(U log U + R) vs O(R log R)).
--- Full merged list is sorted once in the UI via SortRecipeResults after local+guild merge.
--- When `timings` is provided, records lookup/sort/expand phase ms (requires profiler already started).
local function FilterAndSortRecipes(all, queryLower, byID, ensureSuffix, timings)
    local results = {}
    local seen = {}
    if byID and ensureSuffix then
        local ids = LookupSuffixArrayIds(ensureSuffix(), queryLower)
        ProfileMark(timings, "lookup")
        local uniqueList = {}
        for recipeID in pairs(ids) do
            local nameLower = GetCachedRecipeNameLower(recipeID)
            if nameLower then
                uniqueList[#uniqueList + 1] = { id = recipeID, nameLower = nameLower }
            end
        end
        SortUniqueRecipeIdList(uniqueList)
        ProfileMark(timings, "sort")
        ExpandSortedRecipeIds(results, uniqueList, byID, seen)
        ProfileMark(timings, "expand")
    else
        if timings then
            timings.lookup = 0
        end
        local uniqueList = {}
        local matchedByID = {}
        for _, entry in ipairs(all or {}) do
            local nameLower = GetCachedRecipeNameLower(entry.recipeID)
            if nameLower and nameLower:find(queryLower, 1, true) then
                local id = entry.recipeID
                local bucket = matchedByID[id]
                if not bucket then
                    bucket = {}
                    matchedByID[id] = bucket
                    uniqueList[#uniqueList + 1] = { id = id, nameLower = nameLower }
                end
                bucket[#bucket + 1] = entry
            end
        end
        SortUniqueRecipeIdList(uniqueList)
        ProfileMark(timings, "sort")
        ExpandSortedRecipeIds(results, uniqueList, matchedByID, seen)
        ProfileMark(timings, "expand")
    end
    return results
end
SD._FilterAndSortRecipes = FilterAndSortRecipes

------------------------------------------------------------------------
-- Chunked index prewarm (started when AltArmy.MainFrame opens)
------------------------------------------------------------------------

local function ResetPrewarmWorkState()
    _prewarm.nameList = nil
    _prewarm.nameIndex = 1
    _prewarm.charOffset = 1
    _prewarm.suffixArr = nil
    _prewarm.idKeys = nil
    _prewarm.idKeyIndex = 1
    _prewarm.sortState = nil
    _prewarm.sortNameCount = 0
    _prewarm.sortSuffixCount = 0
    _prewarm.sortWallStart = 0
    _prewarm.sortChunkMsMax = 0
end

StopIndexPrewarm = function()
    _prewarmFrame:SetScript("OnUpdate", nil)
    _prewarm.running = false
    _prewarm.phase = nil
    _prewarm.wallStart = 0
    ResetPrewarmWorkState()
end

--- Stop prewarm after a successful run and log wall time when search debug is on.
local function FinishIndexPrewarm()
    if SearchDebugEnabled() and _prewarm.running then
        local wallSec = ((GetTime and GetTime()) or 0) - (_prewarm.wallStart or 0)
        LogSearchDebug(string.format("  index prewarm done wallSec=%.2f", wallSec))
    end
    StopIndexPrewarm()
end

local function CollectIdKeys(byID)
    local keys = {}
    for id in pairs(byID or {}) do
        keys[#keys + 1] = id
    end
    return keys
end

local function BeginNameCollection(byID)
    _prewarm.idKeys = CollectIdKeys(byID)
    _prewarm.idKeyIndex = 1
    _prewarm.nameList = {}
end

local function ChunkCollectItemNames()
    local byID = _slotsByItemID or {}
    local keys = _prewarm.idKeys
    local list = _prewarm.nameList
    local processed = 0
    while processed < PREWARM_NAME_CHUNK and _prewarm.idKeyIndex <= #keys do
        local itemID = keys[_prewarm.idKeyIndex]
        _prewarm.idKeyIndex = _prewarm.idKeyIndex + 1
        processed = processed + 1
        local rows = byID[itemID]
        local entry = rows and rows[1]
        local nameLower = GetCachedItemNameLower(itemID, entry and entry.itemLink)
        if nameLower then
            list[#list + 1] = { id = itemID, nameLower = nameLower }
        end
    end
    return _prewarm.idKeyIndex > #keys
end

local function ChunkCollectRecipeNames()
    local keys = _prewarm.idKeys
    local list = _prewarm.nameList
    local processed = 0
    while processed < PREWARM_NAME_CHUNK and _prewarm.idKeyIndex <= #keys do
        local recipeID = keys[_prewarm.idKeyIndex]
        _prewarm.idKeyIndex = _prewarm.idKeyIndex + 1
        processed = processed + 1
        local nameLower = GetCachedRecipeNameLower(recipeID)
        if nameLower then
            list[#list + 1] = { id = recipeID, nameLower = nameLower }
        end
    end
    return _prewarm.idKeyIndex > #keys
end

local function BeginSuffixAppend()
    _prewarm.suffixArr = _prewarm.suffixArr or {}
    _prewarm.nameIndex = 1
    _prewarm.charOffset = 1
end

local function ChunkAppendSuffixes()
    local list = _prewarm.nameList or {}
    local arr = _prewarm.suffixArr
    local budget = PREWARM_SUFFIX_ENTRY_BUDGET
    while budget > 0 and _prewarm.nameIndex <= #list do
        local entry = list[_prewarm.nameIndex]
        local nextChar, added = AppendSuffixesForName(
            arr, entry.nameLower, entry.id, _prewarm.charOffset, budget)
        budget = budget - added
        if nextChar > #entry.nameLower then
            _prewarm.nameIndex = _prewarm.nameIndex + 1
            _prewarm.charOffset = 1
        else
            _prewarm.charOffset = nextChar
        end
    end
    return _prewarm.nameIndex > #list
end

local function FinishSuffixesFromNameList(nameList, startIndex, startChar, existingArr)
    local debug = SearchDebugEnabled()
    if debug then
        SearchProfileStart()
    end
    local arr = existingArr or {}
    local ni = startIndex or 1
    local co = startChar or 1
    while ni <= #(nameList or {}) do
        local entry = nameList[ni]
        AppendSuffixesForName(arr, entry.nameLower, entry.id, co, math.huge)
        ni = ni + 1
        co = 1
    end
    SortSuffixArray(arr)
    if debug then
        LogIndexBuild("suffixArraySyncFinish", SearchProfileElapsedMs(), string.format(
            "names=%d suffixes=%d", #(nameList or {}), #arr))
    end
    return arr
end

FinishItemSuffixArraySync = function()
    if _itemSuffixArray then
        return _itemSuffixArray
    end
    local phase = _prewarm.phase
    local nameList = _prewarm.nameList
    local nameIndex = _prewarm.nameIndex
    local charOffset = _prewarm.charOffset
    local suffixArr = _prewarm.suffixArr
    local idKeys = _prewarm.idKeys
    local idKeyIndex = _prewarm.idKeyIndex
    local wasItemPrewarm = _prewarm.running and phase and phase:find("^item")
    StopIndexPrewarm()

    if wasItemPrewarm and (phase == "itemNames" or phase == "itemSuffixes" or phase == "itemSort") then
        nameList = nameList or {}
        if phase == "itemNames" and idKeys then
            local byID = _slotsByItemID or GetSlotsByItemID()
            for i = idKeyIndex, #idKeys do
                local itemID = idKeys[i]
                local rows = byID[itemID]
                local entry = rows and rows[1]
                local nameLower = GetCachedItemNameLower(itemID, entry and entry.itemLink)
                if nameLower then
                    nameList[#nameList + 1] = { id = itemID, nameLower = nameLower }
                end
            end
            nameIndex = 1
            charOffset = 1
            suffixArr = {}
        end
        if phase == "itemSort" and suffixArr then
            local debug = SearchDebugEnabled()
            if debug then
                SearchProfileStart()
            end
            SortSuffixArray(suffixArr)
            _itemSuffixArray = suffixArr
            if debug then
                LogIndexBuild("suffixArraySyncSort", SearchProfileElapsedMs(), string.format(
                    "suffixes=%d", #suffixArr))
            end
        else
            _itemSuffixArray = FinishSuffixesFromNameList(nameList, nameIndex, charOffset, suffixArr)
        end
    else
        local byID = GetSlotsByItemID()
        local names = {}
        for itemID, rows in pairs(byID) do
            local entry = rows[1]
            local nameLower = GetCachedItemNameLower(itemID, entry and entry.itemLink)
            if nameLower then
                names[itemID] = nameLower
            end
        end
        _itemSuffixArray = BuildSuffixArray(names)
    end
    StartIndexPrewarm()
    return _itemSuffixArray
end

FinishLocalRecipeSuffixArraySync = function()
    if _localRecipeSuffixArray then
        return _localRecipeSuffixArray
    end
    if not _localRecipesByID then
        SD.GetAllRecipes()
    end
    local phase = _prewarm.phase
    local nameList = _prewarm.nameList
    local nameIndex = _prewarm.nameIndex
    local charOffset = _prewarm.charOffset
    local suffixArr = _prewarm.suffixArr
    local idKeys = _prewarm.idKeys
    local idKeyIndex = _prewarm.idKeyIndex
    local wasLocalPrewarm = _prewarm.running and phase and phase:find("^local")
    StopIndexPrewarm()

    if wasLocalPrewarm and (phase == "localNames" or phase == "localSuffixes" or phase == "localSort") then
        nameList = nameList or {}
        if phase == "localNames" and idKeys then
            for i = idKeyIndex, #idKeys do
                local recipeID = idKeys[i]
                local nameLower = GetCachedRecipeNameLower(recipeID)
                if nameLower then
                    nameList[#nameList + 1] = { id = recipeID, nameLower = nameLower }
                end
            end
            nameIndex = 1
            charOffset = 1
            suffixArr = {}
        end
        if phase == "localSort" and suffixArr then
            local debug = SearchDebugEnabled()
            if debug then
                SearchProfileStart()
            end
            SortSuffixArray(suffixArr)
            _localRecipeSuffixArray = suffixArr
            if debug then
                LogIndexBuild("suffixArraySyncSort", SearchProfileElapsedMs(), string.format(
                    "suffixes=%d", #suffixArr))
            end
        else
            _localRecipeSuffixArray = FinishSuffixesFromNameList(nameList, nameIndex, charOffset, suffixArr)
        end
    else
        EnsureRecipeSuffixArray(_localRecipesByID, nil, function(arr)
            _localRecipeSuffixArray = arr
        end)
    end
    StartIndexPrewarm()
    return _localRecipeSuffixArray
end

FinishGuildRecipeSuffixArraySync = function()
    if _guildRecipeSuffixArray then
        return _guildRecipeSuffixArray
    end
    if not ShouldIncludeGuildRecipes() then
        _guildRecipeSuffixArray = {}
        return _guildRecipeSuffixArray
    end
    if not _guildRecipesByID then
        SD.GetAllGuildRecipes()
    end
    local phase = _prewarm.phase
    local nameList = _prewarm.nameList
    local nameIndex = _prewarm.nameIndex
    local charOffset = _prewarm.charOffset
    local suffixArr = _prewarm.suffixArr
    local idKeys = _prewarm.idKeys
    local idKeyIndex = _prewarm.idKeyIndex
    local wasGuildPrewarm = _prewarm.running and phase and phase:find("^guild")
    StopIndexPrewarm()

    if wasGuildPrewarm and (phase == "guildNames" or phase == "guildSuffixes" or phase == "guildSort") then
        nameList = nameList or {}
        if phase == "guildNames" and idKeys then
            for i = idKeyIndex, #idKeys do
                local recipeID = idKeys[i]
                local nameLower = GetCachedRecipeNameLower(recipeID)
                if nameLower then
                    nameList[#nameList + 1] = { id = recipeID, nameLower = nameLower }
                end
            end
            nameIndex = 1
            charOffset = 1
            suffixArr = {}
        end
        if phase == "guildSort" and suffixArr then
            local debug = SearchDebugEnabled()
            if debug then
                SearchProfileStart()
            end
            SortSuffixArray(suffixArr)
            _guildRecipeSuffixArray = suffixArr
            if debug then
                LogIndexBuild("suffixArraySyncSort", SearchProfileElapsedMs(), string.format(
                    "suffixes=%d", #suffixArr))
            end
        else
            _guildRecipeSuffixArray = FinishSuffixesFromNameList(nameList, nameIndex, charOffset, suffixArr)
        end
    else
        EnsureRecipeSuffixArray(_guildRecipesByID, nil, function(arr)
            _guildRecipeSuffixArray = arr
        end)
    end
    StartIndexPrewarm()
    return _guildRecipeSuffixArray
end

local function PrewarmAdvancePhase()
    local phase = _prewarm.phase
    if phase == "slots" then
        if not _itemSuffixArray then
            _prewarm.phase = "itemNames"
            BeginNameCollection(_slotsByItemID)
        elseif not _itemAggregateGroup then
            _prewarm.phase = "itemAggGroup"
        elseif not _localRecipeSuffixArray then
            _prewarm.phase = "localSlots"
        elseif ShouldIncludeGuildRecipes() and not _guildRecipeSuffixArray then
            _prewarm.phase = "guildSlots"
        else
            FinishIndexPrewarm()
        end
    elseif phase == "itemNames" then
        _prewarm.phase = "itemSuffixes"
        BeginSuffixAppend()
    elseif phase == "itemSuffixes" then
        _prewarm.phase = "itemSort"
    elseif phase == "itemSort" then
        if not _itemAggregateGroup then
            _prewarm.phase = "itemAggGroup"
        elseif not _localRecipeSuffixArray then
            _prewarm.phase = "localSlots"
        elseif ShouldIncludeGuildRecipes() and not _guildRecipeSuffixArray then
            _prewarm.phase = "guildSlots"
        else
            FinishIndexPrewarm()
        end
    elseif phase == "itemAggGroup" then
        if not _localRecipeSuffixArray then
            _prewarm.phase = "localSlots"
        elseif ShouldIncludeGuildRecipes() and not _guildRecipeSuffixArray then
            _prewarm.phase = "guildSlots"
        else
            FinishIndexPrewarm()
        end
    elseif phase == "localSlots" then
        if not _localRecipeSuffixArray then
            _prewarm.phase = "localNames"
            BeginNameCollection(_localRecipesByID)
        elseif ShouldIncludeGuildRecipes() and not _guildRecipeSuffixArray then
            _prewarm.phase = "guildSlots"
        else
            FinishIndexPrewarm()
        end
    elseif phase == "localNames" then
        _prewarm.phase = "localSuffixes"
        BeginSuffixAppend()
    elseif phase == "localSuffixes" then
        _prewarm.phase = "localSort"
    elseif phase == "localSort" then
        if ShouldIncludeGuildRecipes() and not _guildRecipeSuffixArray then
            _prewarm.phase = "guildSlots"
        else
            FinishIndexPrewarm()
        end
    elseif phase == "guildSlots" then
        if not _guildRecipeSuffixArray then
            _prewarm.phase = "guildNames"
            BeginNameCollection(_guildRecipesByID)
        else
            FinishIndexPrewarm()
        end
    elseif phase == "guildNames" then
        _prewarm.phase = "guildSuffixes"
        BeginSuffixAppend()
    elseif phase == "guildSuffixes" then
        _prewarm.phase = "guildSort"
    elseif phase == "guildSort" then
        FinishIndexPrewarm()
    else
        StopIndexPrewarm()
    end
end

--- Run one chunk of the current *Sort phase. Returns true when the sort finished this step.
local function PrewarmChunkedSortStep(logKind, assignResult)
    if not _prewarm.sortState then
        _prewarm.sortNameCount = #(_prewarm.nameList or {})
        _prewarm.sortSuffixCount = #(_prewarm.suffixArr or {})
        _prewarm.sortWallStart = (GetTime and GetTime()) or 0
        _prewarm.sortChunkMsMax = 0
        _prewarm.sortState = BeginChunkedSuffixSort(_prewarm.suffixArr or {})
    end
    local debug = SearchDebugEnabled()
    if debug then
        SearchProfileStart()
    end
    local done = ChunkedSuffixSortStep(_prewarm.sortState)
    if debug then
        local ms = SearchProfileElapsedMs()
        if ms > (_prewarm.sortChunkMsMax or 0) then
            _prewarm.sortChunkMsMax = ms
        end
    end
    if not done then
        return false
    end
    assignResult(_prewarm.suffixArr or {})
    if debug then
        local wallSec = ((GetTime and GetTime()) or 0) - (_prewarm.sortWallStart or 0)
        LogSearchDebug(string.format(
            "  index %s done wallSec=%.2f chunkMsMax=%.2f names=%d suffixes=%d",
            logKind, wallSec, _prewarm.sortChunkMsMax or 0,
            _prewarm.sortNameCount, _prewarm.sortSuffixCount))
    end
    ResetPrewarmWorkState()
    PrewarmAdvancePhase()
    return true
end

local function PrewarmStep()
    if not _prewarm.running then
        return false
    end
    local phase = _prewarm.phase
    if phase == "slots" then
        SD.GetAllContainerSlots()
        PrewarmAdvancePhase()
    elseif phase == "itemNames" then
        if ChunkCollectItemNames() then
            PrewarmAdvancePhase()
        end
    elseif phase == "itemSuffixes" then
        if ChunkAppendSuffixes() then
            PrewarmAdvancePhase()
        end
    elseif phase == "itemSort" then
        PrewarmChunkedSortStep("prewarm itemSuffix", function(arr)
            _itemSuffixArray = arr
        end)
    elseif phase == "itemAggGroup" then
        EnsureItemAggregateGroup()
        PrewarmAdvancePhase()
    elseif phase == "localSlots" then
        SD.GetAllRecipes()
        PrewarmAdvancePhase()
    elseif phase == "localNames" then
        if ChunkCollectRecipeNames() then
            PrewarmAdvancePhase()
        end
    elseif phase == "localSuffixes" then
        if ChunkAppendSuffixes() then
            PrewarmAdvancePhase()
        end
    elseif phase == "localSort" then
        PrewarmChunkedSortStep("prewarm localRecipeSuffix", function(arr)
            _localRecipeSuffixArray = arr
        end)
    elseif phase == "guildSlots" then
        SD.GetAllGuildRecipes()
        PrewarmAdvancePhase()
    elseif phase == "guildNames" then
        if ChunkCollectRecipeNames() then
            PrewarmAdvancePhase()
        end
    elseif phase == "guildSuffixes" then
        if ChunkAppendSuffixes() then
            PrewarmAdvancePhase()
        end
    elseif phase == "guildSort" then
        PrewarmChunkedSortStep("prewarm guildRecipeSuffix", function(arr)
            _guildRecipeSuffixArray = arr
        end)
    else
        StopIndexPrewarm()
    end
    return _prewarm.running
end
SD._PrewarmStep = PrewarmStep

local function PrewarmOnUpdate()
    if not _prewarm.running then
        _prewarmFrame:SetScript("OnUpdate", nil)
        return
    end
    PrewarmStep()
end

StartIndexPrewarm = function()
    if _itemSuffixArray and _itemAggregateGroup and _localRecipeSuffixArray
        and (not ShouldIncludeGuildRecipes() or _guildRecipeSuffixArray) then
        return
    end
    _prewarmRestartFrame:SetScript("OnUpdate", nil)
    _prewarm.restartRemaining = 0
    StopIndexPrewarm()
    _prewarm.generation = _prewarm.generation + 1
    _prewarm.running = true
    _prewarm.wallStart = (GetTime and GetTime()) or 0
    if SearchDebugEnabled() then
        LogSearchDebug("  index prewarm start")
    end
    if not _itemSuffixArray then
        _prewarm.phase = "slots"
    elseif not _itemAggregateGroup then
        _prewarm.phase = "itemAggGroup"
    elseif not _localRecipeSuffixArray then
        _prewarm.phase = "localSlots"
    elseif ShouldIncludeGuildRecipes() and not _guildRecipeSuffixArray then
        _prewarm.phase = "guildSlots"
    else
        _prewarm.running = false
        return
    end
    _prewarmFrame:SetScript("OnUpdate", PrewarmOnUpdate)
end

SchedulePrewarmRestart = function()
    _prewarm.restartRemaining = PREWARM_RESTART_DEBOUNCE_SEC
    _prewarmRestartFrame:SetScript("OnUpdate", function(_, elapsed)
        _prewarm.restartRemaining = _prewarm.restartRemaining - elapsed
        if _prewarm.restartRemaining <= 0 then
            _prewarmRestartFrame:SetScript("OnUpdate", nil)
            StartIndexPrewarm()
        end
    end)
end

function SD.StartIndexPrewarm()
    StartIndexPrewarm()
end

function SD.StopIndexPrewarm()
    StopIndexPrewarm()
end

function SD.IsIndexPrewarmRunning()
    return _prewarm.running and true or false
end

--- Advance debounced prewarm restart (tests); elapsed defaults past the debounce.
function SD._TickPrewarmRestartForTests(elapsed)
    local onUpdate = _prewarmRestartFrame.GetScript and _prewarmRestartFrame:GetScript("OnUpdate")
    if type(onUpdate) ~= "function" then
        -- Spec CreateFrame mocks often no-op SetScript; apply the same restart logic directly.
        if (_prewarm.restartRemaining or 0) > 0 then
            _prewarm.restartRemaining = 0
            StartIndexPrewarm()
        end
        return
    end
    onUpdate(_prewarmRestartFrame, elapsed or (PREWARM_RESTART_DEBOUNCE_SEC + 0.01))
end

-- Start chunked index build at login so Search is warm before the UI opens.
local _prewarmLoginFrame = CreateFrame("Frame")
_prewarmLoginFrame:RegisterEvent("PLAYER_LOGIN")
_prewarmLoginFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        StartIndexPrewarm()
    end
end)

function SD._GetItemSuffixArrayForTests()
    return _itemSuffixArray
end

function SD._GetLocalRecipeSuffixArrayForTests()
    return _localRecipeSuffixArray
end

local DIFFICULTY_SORT_ORDER = { orange = 1, yellow = 2, green = 3, gray = 4 }

local function cmpValues(a, b)
    if a < b then return -1 end
    if a > b then return 1 end
    return 0
end

local function characterSortKey(entry)
    return ((entry.characterName or "") .. "\0" .. (entry.realm or "")):lower()
end

local function buildItemGroupTotals(list)
    local totals = {}
    for _, row in ipairs(list) do
        local key = (row.itemID or 0) .. "\t" .. (row.itemName or "")
        totals[key] = (totals[key] or 0) + (row.count or 1)
    end
    return totals
end

--- Sort item search rows by column (`sortKey`: "Item", "Character", or "Total").
function SD.SortItemResults(list, sortKey, ascending)
    if not list or #list < 2 or not sortKey then
        return list
    end
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    local itemTotals = sortKey == "Total" and buildItemGroupTotals(out) or nil
    local nameKeys = {}
    local charKeys = {}
    for i = 1, #out do
        local row = out[i]
        nameKeys[row] = (row.itemName or ""):lower()
        charKeys[row] = characterSortKey(row)
    end

    table.sort(out, function(a, b)
        local cmp = 0
        if sortKey == "Item" then
            cmp = cmpValues(nameKeys[a], nameKeys[b])
            if cmp == 0 then
                cmp = cmpValues(a.itemID or 0, b.itemID or 0)
            end
        elseif sortKey == "Character" then
            cmp = cmpValues(charKeys[a], charKeys[b])
        elseif sortKey == "Total" then
            local keyA = (a.itemID or 0) .. "\t" .. (a.itemName or "")
            local keyB = (b.itemID or 0) .. "\t" .. (b.itemName or "")
            cmp = cmpValues(itemTotals[keyA] or 0, itemTotals[keyB] or 0)
        end
        if cmp == 0 then
            cmp = cmpValues(nameKeys[a], nameKeys[b])
        end
        if cmp == 0 then
            cmp = cmpValues(charKeys[a], charKeys[b])
        end
        if cmp == 0 then
            cmp = cmpValues(LocationSortKey(a.location or "bag"), LocationSortKey(b.location or "bag"))
        end
        if not ascending then
            cmp = -cmp
        end
        return cmp < 0
    end)
    return out
end

local function recipeSortName(entry)
    local nameLower = entry.recipeNameLower or ""
    return ((entry.professionName or ""):lower() .. "\0" .. nameLower)
end

local function applySortDirection(cmp, ascending)
    if not ascending then
        return -cmp
    end
    return cmp
end

local function compareRequiredSkill(a, b, ascending)
    local reqA = a.recipeSkillRequired
    local reqB = b.recipeSkillRequired
    if reqA == nil and reqB == nil then
        return 0
    end
    if reqA == nil then
        return 1
    end
    if reqB == nil then
        return -1
    end
    local cmp = applySortDirection(cmpValues(reqA, reqB), ascending)
    if cmp ~= 0 then
        return cmp
    end
    local ordA = DIFFICULTY_SORT_ORDER[a.difficulty] or 99
    local ordB = DIFFICULTY_SORT_ORDER[b.difficulty] or 99
    return applySortDirection(cmpValues(ordA, ordB), ascending)
end

local function compareGuildAffiliation(a, b)
    local aGuild = a.isGuild and true or false
    local bGuild = b.isGuild and true or false
    if aGuild == bGuild then
        return 0
    end
    return aGuild and 1 or -1
end

--- Sort by recipe (profession+name): sort unique recipe IDs, then expand rows
--- (own before guild, then character). O(U log U + R) instead of O(R log R).
local function SortRecipeResultsByRecipe(list, ascending)
    local groupsById = {}
    local groups = {}
    for i = 1, #list do
        local row = list[i]
        local id = row.recipeID or 0
        local g = groupsById[id]
        if not g then
            g = {
                id = id,
                key = recipeSortName(row),
                rows = {},
            }
            groupsById[id] = g
            groups[#groups + 1] = g
        end
        g.rows[#g.rows + 1] = row
    end
    table.sort(groups, function(a, b)
        if a.key ~= b.key then
            if ascending then
                return a.key < b.key
            end
            return a.key > b.key
        end
        return a.id < b.id
    end)
    local out = {}
    for i = 1, #groups do
        local rows = groups[i].rows
        if #rows > 1 then
            table.sort(rows, function(a, b)
                local aGuild = a.isGuild and true or false
                local bGuild = b.isGuild and true or false
                if aGuild ~= bGuild then
                    return not aGuild
                end
                local ca = (a.characterName or ""):lower()
                local cb = (b.characterName or ""):lower()
                if ca ~= cb then
                    return ca < cb
                end
                return (a.recipeID or 0) < (b.recipeID or 0)
            end)
        end
        for j = 1, #rows do
            out[#out + 1] = rows[j]
        end
    end
    return out
end

--- Sort recipe search rows by column (`sortKey`: "Recipe", "Character", or "Skill").
--- Skill uses required recipe level when CraftLib is available, otherwise character skill rank.
--- Recipe/Skill tie-breakers: own characters, then guildmates, then character name A-Z.
function SD.SortRecipeResults(list, sortKey, ascending, craftLibAvailable)
    if not list or #list < 2 or not sortKey then
        return list
    end
    if sortKey == "Recipe" then
        return SortRecipeResultsByRecipe(list, ascending ~= false)
    end
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    local useRequiredSkill = sortKey == "Skill" and craftLibAvailable
    if useRequiredSkill then
        for i = 1, #out do
            SD._EnrichRecipeEntry(out[i])
        end
    end
    local useGuildTiebreak = sortKey == "Skill"
    local recipeNameKeys = {}
    local characterNameKeys = {}
    for i = 1, #out do
        local row = out[i]
        recipeNameKeys[row] = recipeSortName(row)
        characterNameKeys[row] = (row.characterName or ""):lower()
    end

    table.sort(out, function(a, b)
        local cmp = 0
        if sortKey == "Character" then
            cmp = applySortDirection(cmpValues(characterNameKeys[a], characterNameKeys[b]), ascending)
            if cmp == 0 then
                cmp = compareGuildAffiliation(a, b)
            end
        elseif sortKey == "Skill" then
            if useRequiredSkill then
                cmp = compareRequiredSkill(a, b, ascending)
            else
                cmp = applySortDirection(cmpValues(a.skillRank or 0, b.skillRank or 0), ascending)
            end
        end
        if cmp ~= 0 then
            return cmp < 0
        end
        if useGuildTiebreak then
            cmp = compareGuildAffiliation(a, b)
            if cmp ~= 0 then
                return cmp < 0
            end
            cmp = cmpValues(characterNameKeys[a], characterNameKeys[b])
            if cmp ~= 0 then
                return cmp < 0
            end
            return (a.recipeID or 0) < (b.recipeID or 0)
        end
        cmp = cmpValues(recipeNameKeys[a], recipeNameKeys[b])
        if cmp ~= 0 then
            return applySortDirection(cmp, ascending) < 0
        end
        return (a.recipeID or 0) < (b.recipeID or 0)
    end)
    return out
end

local function EnrichRecipeEntry(entry)
    if not entry then
        return entry
    end
    if entry._aaCraftEnriched then
        return entry
    end
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    if RCL and RCL.EnrichEntry then
        RCL.EnrichEntry(entry)
    end
    entry._aaCraftEnriched = true
    return entry
end
SD._EnrichRecipeEntry = EnrichRecipeEntry

--- True when search settings require CraftLib fields on every hit (level/difficulty/source).
--- Profession filter does not need enrichment.
local function NeedsCraftLibEnrichForFilters(settings)
    if not settings then
        return false
    end
    local SS = AltArmy and AltArmy.SearchSettings
    if not SS then
        return false
    end
    if SS.IsRecipeLevelFilterActive and SS.IsRecipeLevelFilterActive(settings.recipeLevelFilter) then
        return true
    end
    if SS.IsDifficultyFilterActive and SS.IsDifficultyFilterActive(settings.difficultyFilter) then
        return true
    end
    if SS.IsSourceFilterActive and SS.IsSourceFilterActive(settings.sourceFilter) then
        return true
    end
    return false
end
SD._NeedsCraftLibEnrichForFilters = NeedsCraftLibEnrichForFilters

local function EnrichRecipeList(list)
    for i = 1, #(list or {}) do
        EnrichRecipeEntry(list[i])
    end
    return list
end
SD._EnrichRecipeList = EnrichRecipeList

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
    local timings = debug and { total = 0 } or nil
    if debug then
        SearchProfileStart()
    end
    local all = SD.GetAllRecipes()
    local queryLower = type(query) == "string" and query:lower() or ""
    local results = FilterAndSortRecipes(all, queryLower, _localRecipesByID, EnsureLocalRecipeSuffixArray, timings)
    local SS = AltArmy and AltArmy.SearchSettings
    local settings = SS and SS.GetSearchSettings and SS.GetSearchSettings() or nil
    -- Defer CraftLib enrich to viewport paint unless filters need recipeSkillRequired/difficulty/source.
    if NeedsCraftLibEnrichForFilters(settings) then
        EnrichRecipeList(results)
    end
    ProfileMark(timings, "enrich")
    if settings then
        results = ApplyRecipeSearchFilters(results, settings)
    end
    ProfileMark(timings, "filter")
    if debug then
        LogSearchDebug(string.format(
            "  recipes q=%q ms=%.2f scanned=%d hits=%d lookup=%.2f expand=%.2f sort=%.2f enrich=%.2f filter=%.2f",
            SearchQueryLabel(query),
            FormatPhaseMs(timings, "total"),
            #all,
            #results,
            FormatPhaseMs(timings, "lookup"),
            FormatPhaseMs(timings, "expand"),
            FormatPhaseMs(timings, "sort"),
            FormatPhaseMs(timings, "enrich"),
            FormatPhaseMs(timings, "filter")
        ))
    end
    return results
end

--- Guildmate recipe search (deferred path). Same enrich/filter pipeline as SearchRecipes.
function SD.SearchGuildRecipes(query)
    if not query or (type(query) == "string" and query:match("^%s*$")) then
        return {}
    end
    local debug = SearchDebugEnabled()
    local timings = debug and { total = 0 } or nil
    if debug then
        SearchProfileStart()
    end
    local all = SD.GetAllGuildRecipes()
    local queryLower = type(query) == "string" and query:lower() or ""
    local results = FilterAndSortRecipes(all, queryLower, _guildRecipesByID, EnsureGuildRecipeSuffixArray, timings)
    local SS = AltArmy and AltArmy.SearchSettings
    local settings = SS and SS.GetSearchSettings and SS.GetSearchSettings() or nil
    if NeedsCraftLibEnrichForFilters(settings) then
        EnrichRecipeList(results)
    end
    ProfileMark(timings, "enrich")
    if settings then
        results = ApplyRecipeSearchFilters(results, settings)
    end
    ProfileMark(timings, "filter")
    if debug then
        LogSearchDebug(string.format(
            "  guildRecipes q=%q ms=%.2f scanned=%d hits=%d lookup=%.2f expand=%.2f sort=%.2f enrich=%.2f filter=%.2f",
            SearchQueryLabel(query),
            FormatPhaseMs(timings, "total"),
            #all,
            #results,
            FormatPhaseMs(timings, "lookup"),
            FormatPhaseMs(timings, "expand"),
            FormatPhaseMs(timings, "sort"),
            FormatPhaseMs(timings, "enrich"),
            FormatPhaseMs(timings, "filter")
        ))
    end
    return results
end

--- Append guild recipe rows onto a local result list (does not re-sort).
function SD.MergeRecipeSearchResults(localList, guildList)
    local out = {}
    local n = 0
    if localList then
        for i = 1, #localList do
            n = n + 1
            out[n] = localList[i]
        end
    end
    if guildList then
        for i = 1, #guildList do
            n = n + 1
            out[n] = guildList[i]
        end
    end
    return out
end
