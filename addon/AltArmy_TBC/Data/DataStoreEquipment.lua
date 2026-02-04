-- AltArmy TBC — DataStore module: equipment (inventory slots 1-19).
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local NUM_EQUIPMENT_SLOTS = 19

local function IsEnchanted(link)
    if not link or type(link) ~= "string" then return false end
    if link:match("item:%d+:0:0:0:0:0:0:%d+:%d+:0:0") then return false end
    return true
end
DS._IsEnchanted = IsEnchanted

function DS:ScanEquipment(_self)
    local char = GetCurrentCharTable()
    if not char or not GetInventoryItemLink then return end
    char.Inventory = char.Inventory or {}
    for slot = 1, NUM_EQUIPMENT_SLOTS do
        local link = GetInventoryItemLink("player", slot)
        if link then
            if IsEnchanted(link) then
                char.Inventory[slot] = link
            else
                local id = tonumber(link:match("item:(%d+)"))
                char.Inventory[slot] = id
            end
        else
            char.Inventory[slot] = nil
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.equipment = DATA_VERSIONS.equipment
end

function DS:GetInventory(char)
    return (char and char.Inventory) or {}
end

function DS:GetInventoryItem(char, slot)
    if not char or not char.Inventory then return nil end
    return char.Inventory[slot]
end

function DS:GetInventoryItemCount(char, itemID)
    if not char or not char.Inventory or not itemID then return 0 end
    local count = 0
    for _, v in pairs(char.Inventory) do
        if type(v) == "number" and v == itemID then
            count = count + 1
        elseif type(v) == "string" and tonumber(v:match("item:(%d+)")) == itemID then
            count = count + 1
        end
    end
    return count
end

function DS:IterateInventory(char, callback)
    if not char or not char.Inventory or not callback then return end
    for slot, itemIDOrLink in pairs(char.Inventory) do
        if itemIDOrLink and callback(slot, itemIDOrLink) then
            return
        end
    end
end

function DS:GetAverageItemLevel(char)
    if not char or not char.Inventory then return 0 end
    if not GetItemInfo then return 0 end
    local totalLevel = 0
    local count = 0
    for slot = 1, NUM_EQUIPMENT_SLOTS do
        local item = char.Inventory[slot]
        if item then
            local _, _, _, iLevel = GetItemInfo(item)
            if iLevel and type(iLevel) == "number" then
                totalLevel = totalLevel + iLevel
                count = count + 1
            end
        end
    end
    if count == 0 then return 0 end
    return totalLevel / count
end
