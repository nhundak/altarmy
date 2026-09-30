-- AltArmy TBC — DataStore module: currencies (TBC currency items in bags/bank).
-- Requires DataStore.lua (core) and DataStoreContainers.lua (GetContainerItemCount) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local CURRENCY_ITEM_IDS = {
    29434,  -- Badge of Justice
    20558,  -- Warsong Gulch Mark of Honor
    20559,  -- Arathi Basin Mark of Honor
    20560,  -- Alterac Valley Mark of Honor
    29024,  -- Eye of the Storm Mark of Honor
    43228,  -- Stone Keeper's Shard
    37836,  -- Venture Coin
}

function DS:ScanCurrencies()
    local char = GetCurrentCharTable()
    if not char then return end
    char.Currencies = char.Currencies or {}
    for k in pairs(char.Currencies) do char.Currencies[k] = nil end
    for _, itemID in ipairs(CURRENCY_ITEM_IDS) do
        local count = self:GetContainerItemCount(char, itemID)
        if count > 0 then
            char.Currencies[itemID] = count
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.currencies = DATA_VERSIONS.currencies
end

function DS:GetCurrencyCount(char, itemID)
    if not char or not itemID then return 0 end
    if char.Currencies and char.Currencies[itemID] then
        return char.Currencies[itemID]
    end
    return self:GetContainerItemCount(char, itemID)
end

function DS:GetAllCurrencies(char)
    if not char then return {} end
    local out = {}
    if char.Currencies then
        for id, count in pairs(char.Currencies) do
            out[id] = count
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Native currency list (C_CurrencyInfo; WoW Forever's Character window Currency tab).
-- Per character: char.CurrencyList[currencyID] = quantity (0 kept, as the native tab lists it).
-- Account-wide: AltArmyTBC_Data.CurrencyMeta[currencyID] = { name, icon, max, header, headerOrder, order }.
-- ---------------------------------------------------------------------------

function DS.HasCurrencyListApi()
    local C = _G.C_CurrencyInfo
    return type(C) == "table" and type(C.GetCurrencyListSize) == "function"
        and type(C.GetCurrencyListInfo) == "function"
end

function DS:GetCurrencyMeta()
    AltArmyTBC_Data.CurrencyMeta = AltArmyTBC_Data.CurrencyMeta or {}
    return AltArmyTBC_Data.CurrencyMeta
end

function DS:GetCurrencyListAmount(char, currencyID)
    if not char or not currencyID or not char.CurrencyList then return nil end
    return char.CurrencyList[currencyID]
end

local function currencyIdAt(C, index, info)
    if info.currencyID then return info.currencyID end
    if C.GetCurrencyListLink and C.GetCurrencyIDFromLink then
        local link = C.GetCurrencyListLink(index)
        if link then return C.GetCurrencyIDFromLink(link) end
    end
    return nil
end

-- Expanding headers fires CURRENCY_DISPLAY_UPDATE, which asks for another scan: ignore it meanwhile.
local scanningCurrencyList = false

--- Reads the whole list: expands collapsed headers, then collapses them again so the native tab
--- looks as the player left it. Returns { [currencyID] = quantity }.
local function readCurrencyList(meta)
    local C = _G.C_CurrencyInfo
    local collapsed = {}
    if C.ExpandCurrencyList then
        -- Expanding shifts later indices, so restart the walk after each expand.
        local expanded = true
        local guard = 0
        while expanded and guard < 100 do
            expanded = false
            guard = guard + 1
            for i = 1, C.GetCurrencyListSize() or 0 do
                local info = C.GetCurrencyListInfo(i)
                if info and info.isHeader and not info.isHeaderExpanded then
                    collapsed[info.name or ""] = true
                    C.ExpandCurrencyList(i, true)
                    expanded = true
                    break
                end
            end
        end
    end

    local amounts = {}
    local header, headerOrder = nil, 0
    local size = C.GetCurrencyListSize() or 0
    for i = 1, size do
        local info = C.GetCurrencyListInfo(i)
        if info and info.isHeader then
            header = info.name
            headerOrder = headerOrder + 1
        elseif info then
            local id = currencyIdAt(C, i, info)
            if id then
                amounts[id] = tonumber(info.quantity) or 0
                meta[id] = {
                    name = info.name,
                    icon = info.iconFileID,
                    max = (tonumber(info.maxQuantity) or 0) > 0 and info.maxQuantity or nil,
                    header = header,
                    headerOrder = headerOrder,
                    order = i,
                }
            end
        end
    end

    if C.ExpandCurrencyList and next(collapsed) then
        -- From the end, so collapsing a header doesn't shift the ones still to visit.
        for i = C.GetCurrencyListSize() or 0, 1, -1 do
            local info = C.GetCurrencyListInfo(i)
            if info and info.isHeader and info.isHeaderExpanded and collapsed[info.name or ""] then
                C.ExpandCurrencyList(i, false)
            end
        end
    end
    return amounts
end

--- Scan the current character's currencies (or `char`, for tests).
function DS:ScanCurrencyList(char)
    if scanningCurrencyList or not DS.HasCurrencyListApi() then return end
    char = char or GetCurrentCharTable()
    if not char then return end
    scanningCurrencyList = true
    local ok, amounts = pcall(readCurrencyList, self:GetCurrencyMeta())
    scanningCurrencyList = false
    if not ok or type(amounts) ~= "table" then return end

    char.CurrencyList = amounts
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.currencyList = DATA_VERSIONS.currencyList
    if self.FireCurrencyListChanged then self:FireCurrencyListChanged() end
end

-- Listeners (the Economy tab's Currency grid) run after each scan.
local currencyListeners = {}
function DS:OnCurrencyListChanged(fn)
    currencyListeners[#currencyListeners + 1] = fn
end
function DS:FireCurrencyListChanged()
    for _, fn in ipairs(currencyListeners) do pcall(fn) end
end

-- CURRENCY_DISPLAY_UPDATE fires in bursts: scan once, shortly after the last one.
local CURRENCY_SCAN_DELAY = 0.5
local currencyScanPending = false
function DS:RequestCurrencyListScan()
    if not DS.HasCurrencyListApi() or scanningCurrencyList then return end
    local timer = _G.C_Timer
    if not (timer and timer.After) then
        self:ScanCurrencyList()
        return
    end
    if currencyScanPending then return end
    currencyScanPending = true
    timer.After(CURRENCY_SCAN_DELAY, function()
        currencyScanPending = false
        DS:ScanCurrencyList()
    end)
end
