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

function DS:GetAllCurrencies(_self, char)
    if not char then return {} end
    local out = {}
    if char.Currencies then
        for id, count in pairs(char.Currencies) do
            out[id] = count
        end
    end
    return out
end
