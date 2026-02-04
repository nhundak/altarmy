-- AltArmy TBC — DataStore module: containers (bags + bank).
-- Requires DataStore.lua (core) and DataStoreCurrencies.lua (for ScanCurrencies) loaded before events run.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4
local MIN_BANK_BAG_ID = 5
local MAX_BANK_BAG_ID = 11
local BANK_CONTAINER = -1
local BACKPACK_FALLBACK_SLOTS = 16

DS.NUM_BAG_SLOTS = NUM_BAG_SLOTS
DS.BANK_CONTAINER = BANK_CONTAINER
DS.MIN_BANK_BAG_ID = MIN_BANK_BAG_ID
DS.MAX_BANK_BAG_ID = MAX_BANK_BAG_ID

local function GetNumSlots(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID)
    end
    return GetContainerNumSlots and GetContainerNumSlots(bagID)
end

local function GetItemLink(bagID, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bagID, slot)
    end
    return GetContainerItemLink and GetContainerItemLink(bagID, slot)
end

local function GetItemInfoForSlot(bagID, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        return info and info.stackCount or 1
    end
    if GetContainerItemInfo then
        local _, count = GetContainerItemInfo(bagID, slot)
        return (count and count > 0) and count or 1
    end
    return 1
end

local function GetContainer(char, bagID)
    if not char then return nil end
    char.Containers = char.Containers or {}
    local bag = char.Containers[bagID]
    if not bag then
        bag = { links = {}, items = {} }
        char.Containers[bagID] = bag
    end
    return bag
end

local function ScanContainer(char, bagID, sizeOverride)
    local numSlots = sizeOverride or GetNumSlots(bagID)
    if not numSlots or numSlots <= 0 then return end
    if not GetItemLink then return end
    local bag = GetContainer(char, bagID)
    bag.links = bag.links or {}
    bag.items = bag.items or {}
    for k in pairs(bag.links) do bag.links[k] = nil end
    for k in pairs(bag.items) do bag.items[k] = nil end
    for slot = 1, numSlots do
        local link = GetItemLink(bagID, slot)
        if link then
            local itemID = tonumber(link:match("item:(%d+)"))
            local count = GetItemInfoForSlot(bagID, slot)
            bag.links[slot] = link
            bag.items[slot] = { itemID = itemID, count = count }
        end
    end
    char.lastUpdate = time()
end

function DS:ScanBags()
    local char = GetCurrentCharTable()
    if not char then return end
    for bagID = 0, NUM_BAG_SLOTS do
        local numSlots = GetNumSlots(bagID)
        if bagID == 0 and (not numSlots or numSlots <= 0) then
            numSlots = BACKPACK_FALLBACK_SLOTS
        end
        if numSlots and numSlots > 0 then
            ScanContainer(char, bagID, numSlots)
        end
    end
    local totalSlots, freeSlots = 0, 0
    local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    for bagID = 0, NUM_BAG_SLOTS do
        local n = GetNumSlots(bagID) or (bagID == 0 and BACKPACK_FALLBACK_SLOTS) or 0
        totalSlots = totalSlots + n
        if getFree and getFree(bagID) then
            freeSlots = freeSlots + getFree(bagID)
        end
    end
    char.bagInfo = { totalSlots = totalSlots, freeSlots = freeSlots }
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.containers = DATA_VERSIONS.containers
    if self.ScanCurrencies then self:ScanCurrencies() end
end

function DS:ScanBank()
    local char = GetCurrentCharTable()
    if not char then return end
    if GetNumSlots(BANK_CONTAINER) and GetNumSlots(BANK_CONTAINER) > 0 then
        ScanContainer(char, BANK_CONTAINER)
    end
    for bagID = MIN_BANK_BAG_ID, MAX_BANK_BAG_ID do
        if GetNumSlots(bagID) and GetNumSlots(bagID) > 0 then
            ScanContainer(char, bagID)
        end
    end
    local totalSlots, freeSlots = 0, 0
    local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if GetNumSlots(BANK_CONTAINER) then
        totalSlots = totalSlots + GetNumSlots(BANK_CONTAINER)
        if getFree and getFree(BANK_CONTAINER) then
            freeSlots = freeSlots + getFree(BANK_CONTAINER)
        end
    end
    for bagID = MIN_BANK_BAG_ID, MAX_BANK_BAG_ID do
        local n = GetNumSlots(bagID) or 0
        totalSlots = totalSlots + n
        if getFree and getFree(bagID) then
            freeSlots = freeSlots + getFree(bagID)
        end
    end
    char.bankInfo = { totalSlots = totalSlots, freeSlots = freeSlots }
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.containers = DATA_VERSIONS.containers
    if self.ScanCurrencies then self:ScanCurrencies() end
end

DS.ScanContainer = function(_self, char, bagID, sizeOverride)
    ScanContainer(char, bagID, sizeOverride)
end

function DS:GetContainers(_self, char)
    return (char and char.Containers) or {}
end

function DS:GetContainer(_self, char, bagID)
    if not char or not char.Containers then return nil end
    return char.Containers[bagID]
end

function DS:GetContainerItemCount(_self, char, itemID)
    if not char or not char.Containers or not itemID then return 0 end
    local total = 0
    for _, bag in pairs(char.Containers) do
        if bag.items then
            for _, slotData in pairs(bag.items) do
                if slotData and slotData.itemID == itemID then
                    total = total + (slotData.count or 1)
                end
            end
        end
    end
    return total
end

function DS:GetNumBagSlots(_self, char)
    if not char or not char.bagInfo then return 0 end
    return char.bagInfo.totalSlots or 0
end

function DS:GetNumFreeBagSlots(_self, char)
    if not char or not char.bagInfo then return 0 end
    return char.bagInfo.freeSlots or 0
end

function DS:IterateContainerSlots(_self, char, callback)
    if not char or not char.Containers or not callback then return end
    for bagID, bag in pairs(char.Containers) do
        if bag and bag.items then
            for slot, slotData in pairs(bag.items) do
                if slotData and slotData.itemID then
                    local link = (bag.links and bag.links[slot]) or nil
                    if callback(bagID, slot, slotData.itemID, slotData.count or 1, link) then
                        return
                    end
                end
            end
        end
    end
end

function DS:ScanCurrentCharacterBags()
    local char = GetCurrentCharTable()
    if char then self:ScanBags() end
end

function DS:ScanBagsAndLog()
    local char = GetCurrentCharTable()
    if char then self:ScanBags() end
end
