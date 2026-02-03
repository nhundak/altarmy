-- AltArmy TBC — Internal character data store.
-- Persists character data to SavedVariables (AltArmyTBC_Data), shared across all characters on the account.
-- TBC-compatible; no external DataStore dependency.

if not AltArmy then return end

AltArmy.DataStore = AltArmy.DataStore or {}

local DS = AltArmy.DataStore
local MAX_LEVEL = MAX_PLAYER_LEVEL or 70
local MAX_LOGOUT_SENTINEL = 5000000000

-- TBC bag IDs: 0 = backpack, 1-4 = bags; bank: -1 = main bank (when open), 5-11 = bank bags
local NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4
local MIN_BANK_BAG_ID = 5
local MAX_BANK_BAG_ID = 11
local BANK_CONTAINER = -1
local BACKPACK_FALLBACK_SLOTS = 16 -- TBC backpack size when GetContainerNumSlots(0) returns 0

-- Bag API: use C_Container if present (some Classic clients expose it), else globals
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

-- Ensure SavedVariables structure (runs at load; SV are already loaded)
AltArmyTBC_Data = AltArmyTBC_Data or {}
AltArmyTBC_Data.Characters = AltArmyTBC_Data.Characters or {}

AltArmy.DB = AltArmyTBC_Data

local function GetCurrentName()
    if UnitName then
        local name = UnitName("player")
        if name and name ~= "" then return name end
    end
    return GetUnitName and GetUnitName("player") or ""
end

local function GetCurrentRealm()
    return (GetRealmName and GetRealmName()) or ""
end

--- Get or create the current character's data table.
local function GetCurrentCharTable()
    local realm = GetCurrentRealm()
    local name = GetCurrentName()
    if not realm or not name or name == "" then return nil end
    if not AltArmyTBC_Data.Characters[realm] then
        AltArmyTBC_Data.Characters[realm] = {}
    end
    local char = AltArmyTBC_Data.Characters[realm][name]
    if not char then
        char = {}
        AltArmyTBC_Data.Characters[realm][name] = char
    end
    return char
end

--- Scan current character's basic info (name, realm, class, race, faction, level, money, XP, rest).
local function ScanCharacter()
    local char = GetCurrentCharTable()
    if not char then return end
    char.name = GetCurrentName()
    char.realm = GetCurrentRealm()
    char.level = (UnitLevel and UnitLevel("player")) or 0
    char.money = (GetMoney and GetMoney()) or 0
    char.lastUpdate = time()
    if UnitClass then
        local loc, eng = UnitClass("player")
        char.class = loc
        char.classFile = eng and eng:upper() or ""
    else
        char.class = ""
        char.classFile = ""
    end
    if UnitRace then
        char.race = UnitRace("player") or ""
    else
        char.race = ""
    end
    if UnitFactionGroup then
        char.faction = UnitFactionGroup("player") or ""
    else
        char.faction = ""
    end
    if GetMoney then
        char.money = GetMoney()
    end
    if UnitXP and UnitXPMax then
        char.xp = UnitXP("player") or 0
        char.xpMax = UnitXPMax("player") or 0
    else
        char.xp = 0
        char.xpMax = 0
    end
    if GetXPExhaustion then
        char.restXP = GetXPExhaustion() or 0
    else
        char.restXP = 0
    end
    if char.level == MAX_LEVEL then
        char.restXP = 0
    end
end

-- --- Containers (bags + bank) ---
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

--- Scan a single container (bag or bank bag). Uses resolved bag API; sizeOverride forces slot count (e.g. 16 for backpack when API returns 0).
local function ScanContainer(char, bagID, sizeOverride)
    local numSlots = sizeOverride or GetNumSlots(bagID)
    if not numSlots or numSlots <= 0 then return end
    if not GetItemLink then return end -- no link API at all
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

--- Scan bags 0-4 (backpack + bags). Backpack (0) uses BACKPACK_FALLBACK_SLOTS when API returns 0 (TBC Classic timing).
local function ScanBags(char)
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
    -- Update bag summary: total slots and free slots
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
end

--- Scan bank (main -1 and bags 5-11). Only valid when bank is open.
local function ScanBank(char)
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
end

-- --- Equipment (Inventory) ---
local NUM_EQUIPMENT_SLOTS = 19

--- Returns true if link has enchant/gem data (store full link; else store itemID only).
local function IsEnchanted(link)
    if not link or type(link) ~= "string" then return false end
    if link:match("item:%d+:0:0:0:0:0:0:%d+:%d+:0:0") then return false end
    return true
end

--- Scan equipped gear into char.Inventory. Slots 1-19 (TBC). Ranged slot holds ranged/relics; ammo omitted. Store link if enchanted, else itemID.
local function ScanEquipment(char)
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
end

--- API: GetRealms() — returns { ["RealmName"] = true, ... }
function DS:GetRealms()
    local out = {}
    for realm in pairs(AltArmyTBC_Data.Characters) do
        out[realm] = true
    end
    return out
end

--- API: GetCharacters(realm) — returns { ["CharName"] = charData, ... }
function DS:GetCharacters(realm)
    if not realm then return {} end
    return AltArmyTBC_Data.Characters[realm] or {}
end

--- API: GetCharacter(name, realm) — returns charData table or nil
function DS:GetCharacter(name, realm)
    if not name or not realm then return nil end
    local realmTable = AltArmyTBC_Data.Characters[realm]
    return realmTable and realmTable[name] or nil
end

--- API: GetCurrentCharacter() — returns current character's data table
function DS:GetCurrentCharacter()
    return GetCurrentCharTable()
end

--- Per-character getters (take charData table)
function DS:GetCharacterName(char)
    return char and char.name or ""
end

function DS:GetCharacterLevel(char)
    return (char and char.level) or 0
end

function DS:GetMoney(char)
    return (char and char.money) or 0
end

function DS:GetPlayTime(char)
    return (char and char.played) or 0
end

function DS:GetLastLogout(char)
    return (char and char.lastLogout) or MAX_LOGOUT_SENTINEL
end

function DS:GetCharacterClass(char)
    if not char then return "", "" end
    return char.class or "", char.classFile or ""
end

function DS:GetCharacterFaction(char)
    return (char and char.faction) or ""
end

--- Containers: GetContainers(char) -> char.Containers; GetContainer(char, bagID); GetContainerItemCount(char, itemID); IterateContainerSlots(char, callback).
function DS:GetContainers(char)
    return (char and char.Containers) or {}
end

function DS:GetContainer(char, bagID)
    if not char or not char.Containers then return nil end
    return char.Containers[bagID]
end

--- Total count of itemID in bags + bank for this character.
function DS:GetContainerItemCount(char, itemID)
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

--- Optional: total bag slots and free slots (from bagInfo).
function DS:GetNumBagSlots(char)
    if not char or not char.bagInfo then return 0 end
    return char.bagInfo.totalSlots or 0
end

function DS:GetNumFreeBagSlots(char)
    if not char or not char.bagInfo then return 0 end
    return char.bagInfo.freeSlots or 0
end

--- Iterate all container slots (bags + bank). callback(bagID, slot, itemID, count, link). Return true to stop.
function DS:IterateContainerSlots(char, callback)
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

--- Refresh current character's bags (and bagInfo). Call before search so current char data is up to date.
function DS:ScanCurrentCharacterBags()
    local char = GetCurrentCharTable()
    if char then
        ScanBags(char)
    end
end

--- Scan current character's bags now (for temporary manual "Scan bags now" button).
function DS:ScanBagsAndLog()
    local char = GetCurrentCharTable()
    if not char then
        return
    end
    ScanBags(char)
end

--- Equipment: GetInventory(char), GetInventoryItem(char, slot), GetInventoryItemCount(char, itemID), IterateInventory(char, callback).
function DS:GetInventory(char)
    return (char and char.Inventory) or {}
end

function DS:GetInventoryItem(char, slot)
    if not char or not char.Inventory then return nil end
    return char.Inventory[slot]
end

--- Count of equipped items with this itemID (usually 0 or 1).
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

--- Iterate equipment. callback(slot, itemIDOrLink). Return true to stop.
function DS:IterateInventory(char, callback)
    if not char or not char.Inventory or not callback then return end
    for slot, itemIDOrLink in pairs(char.Inventory) do
        if itemIDOrLink and callback(slot, itemIDOrLink) then
            return
        end
    end
end

--- Average item level of equipped gear (slots 1–19). Uses GetItemInfo item level (4th return). Returns 0 if no equipment.
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

--- Stored rest XP rate as percentage (0–100). Simple: restXP / (xpMax * 1.5) * 100.
--- Use this for the raw saved value only; use GetRestXp for "rest now" (predicted).
function DS:GetStoredRestXp(char)
    if not char or char.level == MAX_LEVEL then return 0 end
    local xpMax = char.xpMax or 0
    local restXP = char.restXP or 0
    if xpMax <= 0 then return 0 end
    local maxRest = xpMax * 1.5
    return math.min(100, (restXP / maxRest) * 100)
end

--- Rest XP rate as percentage (0–100) *now*: predicted for alts, or use saved rate when no lastLogout.
--- Formula: 8 hours rested = 5% of current level; max rest = 150% of level (1.5 levels). Time since
--- last logout earns rest at that rate (assumes character is resting when offline). Adapted from
--- DataStore_Characters (Thaoky). For current character (no lastLogout), returns saved rate.
function DS:GetRestXp(char)
    if not char or char.level == MAX_LEVEL then return 0 end
    local xpMax = char.xpMax or 0
    local restXP = char.restXP or 0
    if xpMax <= 0 then return 0 end
    local maxRest = xpMax * 1.5
    local lastLogout = char.lastLogout or MAX_LOGOUT_SENTINEL
    if lastLogout >= MAX_LOGOUT_SENTINEL then
        return math.min(100, (restXP / maxRest) * 100)
    end
    local oneXPBubble = xpMax / 20
    local elapsed = time() - lastLogout
    local numXPBubbles = elapsed / 28800
    local xpEarnedResting = numXPBubbles * oneXPBubble
    if xpEarnedResting < 0 then xpEarnedResting = 0 end
    if (restXP + xpEarnedResting) > maxRest then
        xpEarnedResting = maxRest - restXP
    end
    local predictedRestXP = restXP + xpEarnedResting
    local rate = (predictedRestXP / maxRest) * 100
    return math.min(100, rate)
end

-- Event frame
local frame = CreateFrame("Frame", nil, UIParent)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("TIME_PLAYED_MSG")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")
frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

local loginFired = false
local isBankOpen = false

-- Deferred bag scan: bags often aren't ready at PLAYER_ENTERING_WORLD. DataStore_Containers delays 3s after login
-- (see https://github.com/Thaoky/DataStore_Containers). We do the same: wait 3s then run initial scan (no C_Timer in TBC, use OnUpdate).
local BAG_SCAN_DELAY = 3
local bagScanFrame = CreateFrame("Frame", nil, UIParent)
bagScanFrame:SetScript("OnUpdate", nil)
bagScanFrame.elapsed = 0

local function runLoginBagScan()
    local char = GetCurrentCharTable()
    if not char then return end
    ScanBags(char)
end

frame:SetScript("OnEvent", function(_, event, addonName, a1)
    if event == "ADDON_LOADED" and addonName == "AltArmy_TBC" then
        AltArmyTBC_Data.Characters = AltArmyTBC_Data.Characters or {}
        GetCurrentCharTable()
        return
    end
    if event == "PLAYER_LOGIN" then
        if not loginFired and RequestTimePlayed then
            RequestTimePlayed()
            loginFired = true
        end
        return
    end
    if event == "PLAYER_ALIVE" or event == "PLAYER_ENTERING_WORLD" then
        ScanCharacter()
        local char = GetCurrentCharTable()
        if char then
            ScanEquipment(char)
            -- Delay initial bag scan 3s after login (like DataStore_Containers) so bag API is ready
            bagScanFrame.elapsed = 0
            bagScanFrame:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = self.elapsed + elapsed
                if self.elapsed >= BAG_SCAN_DELAY then
                    self:SetScript("OnUpdate", nil)
                    runLoginBagScan()
                end
            end)
        end
        return
    end
    if event == "BAG_UPDATE" then
        local char = GetCurrentCharTable()
        if not char then return end
        local bagID = a1
        if type(bagID) == "number" then
            if bagID >= 0 and bagID <= NUM_BAG_SLOTS then
                ScanContainer(char, bagID)
                ScanBags(char)
            elseif isBankOpen and (bagID == BANK_CONTAINER or (bagID >= MIN_BANK_BAG_ID and bagID <= MAX_BANK_BAG_ID)) then
                ScanContainer(char, bagID)
                ScanBank(char)
            end
        else
            ScanBags(char)
            if isBankOpen then ScanBank(char) end
        end
        return
    end
    if event == "BANKFRAME_OPENED" then
        isBankOpen = true
        local char = GetCurrentCharTable()
        if char then ScanBank(char) end
        return
    end
    if event == "BANKFRAME_CLOSED" then
        isBankOpen = false
        return
    end
    if event == "PLAYERBANKSLOTS_CHANGED" then
        if isBankOpen then
            local char = GetCurrentCharTable()
            if char then ScanBank(char) end
        end
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        local char = GetCurrentCharTable()
        if char then ScanEquipment(char) end
        return
    end
    if event == "PLAYER_LOGOUT" then
        local char = GetCurrentCharTable()
        if char then
            char.lastLogout = time()
            char.lastUpdate = time()
        end
        return
    end
    if event == "PLAYER_MONEY" then
        local char = GetCurrentCharTable()
        if char and GetMoney then
            char.money = GetMoney()
        end
        return
    end
    if event == "PLAYER_XP_UPDATE" then
        local char = GetCurrentCharTable()
        if char then
            if UnitXP and UnitXPMax then
                char.xp = UnitXP("player") or 0
                char.xpMax = UnitXPMax("player") or 0
            end
            if GetXPExhaustion then
                char.restXP = GetXPExhaustion() or 0
            end
            if char.level == MAX_LEVEL then
                char.restXP = 0
            end
        end
        return
    end
    if event == "PLAYER_LEVEL_UP" then
        local char = GetCurrentCharTable()
        if char and UnitLevel then
            char.level = UnitLevel("player")
            if char.level == MAX_LEVEL then
                char.restXP = 0
            end
        end
        return
    end
    if event == "TIME_PLAYED_MSG" then
        local char = GetCurrentCharTable()
        -- First event arg is total time played (seconds)
        if char and addonName and type(addonName) == "number" then
            char.played = addonName
        end
        return
    end
end)
frame:RegisterEvent("PLAYER_LOGIN")
