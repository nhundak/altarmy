-- AltArmy TBC — Internal character data store (core).
-- Persists character data to SavedVariables (AltArmyTBC_Data), shared across all characters on the account.
-- Domain modules (DataStoreCharacter, DataStoreContainers, etc.) attach scans and getters to AltArmy.DataStore.
-- TBC-compatible; no external DataStore dependency.

if not AltArmy then return end

AltArmy.DataStore = AltArmy.DataStore or {}

local DS = AltArmy.DataStore

local DATA_VERSIONS = {
    character = 1,
    containers = 1,
    equipment = 1,
    professions = 1,
    reputations = 1,
    mail = 1,
    auctions = 1,
    currencies = 1,
}

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

local function MigrateDataVersions(data)
    data = data or AltArmyTBC_Data
    for _, chars in pairs(data.Characters or {}) do
        for _, char in pairs(chars) do
            char.dataVersions = char.dataVersions or {}
            if char.name and not char.dataVersions.character then
                char.dataVersions.character = 1
            end
            if char.Containers and next(char.Containers) and not char.dataVersions.containers then
                char.dataVersions.containers = 1
            end
            if char.Inventory and next(char.Inventory) and not char.dataVersions.equipment then
                char.dataVersions.equipment = 1
            end
        end
    end
end

DS._GetCurrentCharTable = GetCurrentCharTable
DS._MigrateDataVersions = MigrateDataVersions
DS._DATA_VERSIONS = DATA_VERSIONS

function DS:GetRealms()
    local out = {}
    for realm in pairs(AltArmyTBC_Data.Characters) do
        out[realm] = true
    end
    return out
end

function DS:GetCharacters(realm)
    if not realm then return {} end
    return AltArmyTBC_Data.Characters[realm] or {}
end

function DS:GetCharacter(name, realm)
    if not name or not realm then return nil end
    local realmTable = AltArmyTBC_Data.Characters[realm]
    return realmTable and realmTable[name] or nil
end

function DS:GetCurrentCharacter()
    return GetCurrentCharTable()
end

function DS:HasModuleData(char, moduleName)
    if not char or not moduleName then return false end
    local v = (char.dataVersions and char.dataVersions[moduleName]) or 0
    return v > 0
end

function DS:GetDataVersion(char, moduleName)
    if not char or not moduleName then return 0 end
    return (char.dataVersions and char.dataVersions[moduleName]) or 0
end

function DS:NeedsRescan(char, moduleName)
    if not char or not moduleName then return true end
    local current = DATA_VERSIONS[moduleName]
    if not current then return false end
    return (DS:GetDataVersion(char, moduleName) or 0) < current
end

function DS:GetAllDataVersions(char)
    if not char then return {} end
    local out = {}
    for k, v in pairs(char.dataVersions or {}) do
        out[k] = v
    end
    return out
end

-- Event frame and dispatch
local frame = CreateFrame("Frame", nil, UIParent)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
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
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_CLOSE")
frame:RegisterEvent("TRADE_SKILL_UPDATE")
frame:RegisterEvent("CHAT_MSG_SKILL")
frame:RegisterEvent("UPDATE_FACTION")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("MAIL_CLOSED")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
frame:RegisterEvent("AUCTION_BIDDER_LIST_UPDATE")

local loginFired = false
local isMailOpen = false
local isAuctionHouseOpen = false
local isTradeSkillOpen = false
local lastReputationScan = 0
local isBankOpen = false
local REPUTATION_SCAN_THROTTLE = 3
local BAG_SCAN_DELAY = 3
local TRADE_SKILL_SCAN_DELAY = 0.5

local bagScanFrame = CreateFrame("Frame", nil, UIParent)
bagScanFrame:SetScript("OnUpdate", nil)
bagScanFrame.elapsed = 0

local tradeSkillScanFrame = CreateFrame("Frame", nil, UIParent)
tradeSkillScanFrame:SetScript("OnUpdate", nil)
tradeSkillScanFrame.elapsed = 0

frame:SetScript("OnEvent", function(_, event, addonName, a1)
    if event == "ADDON_LOADED" and addonName == "AltArmy_TBC" then
        AltArmyTBC_Data.Characters = AltArmyTBC_Data.Characters or {}
        GetCurrentCharTable()
        MigrateDataVersions()
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
        if DS.ScanCharacter then DS:ScanCharacter() end
        local char = GetCurrentCharTable()
        if char then
            if DS.ScanEquipment then DS:ScanEquipment() end
            if GetNumSkillLines and GetSkillLineInfo and DS.ScanProfessionLinks then
                DS:ScanProfessionLinks()
            end
            if GetNumFactions and GetFactionInfo and DS.ScanReputations then
                DS:ScanReputations()
            end
            bagScanFrame.elapsed = 0
            bagScanFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= BAG_SCAN_DELAY then
                    f:SetScript("OnUpdate", nil)
                    if DS.ScanBags then DS:ScanBags() end
                end
            end)
        end
        return
    end
    if event == "SKILL_LINES_CHANGED" then
        local char = GetCurrentCharTable()
        if char and GetNumSkillLines and GetSkillLineInfo and DS.ScanProfessionLinks then
            DS:ScanProfessionLinks()
        end
        return
    end
    if event == "TRADE_SKILL_SHOW" then
        isTradeSkillOpen = true
        if GetNumSkillLines and GetSkillLineInfo and DS.ScanProfessionLinks then
            DS:ScanProfessionLinks()
        end
        tradeSkillScanFrame.elapsed = 0
        tradeSkillScanFrame:SetScript("OnUpdate", function(f, elapsed)
            f.elapsed = f.elapsed + elapsed
            if f.elapsed >= TRADE_SKILL_SCAN_DELAY then
                f:SetScript("OnUpdate", nil)
                if GetNumTradeSkills and GetTradeSkillLine and DS.RunDeferredRecipeScan then
                    DS:RunDeferredRecipeScan()
                end
            end
        end)
        return
    end
    if event == "TRADE_SKILL_CLOSE" then
        isTradeSkillOpen = false
        return
    end
    if event == "TRADE_SKILL_UPDATE" then
        if isTradeSkillOpen and DS.RunDeferredRecipeScan then
            DS:RunDeferredRecipeScan()
        end
        return
    end
    if event == "CHAT_MSG_SKILL" then
        local char = GetCurrentCharTable()
        if char and GetNumSkillLines and GetSkillLineInfo and DS.ScanProfessionLinks then
            DS:ScanProfessionLinks()
        end
        return
    end
    if event == "UPDATE_FACTION" then
        local now = time()
        if now - lastReputationScan >= REPUTATION_SCAN_THROTTLE then
            lastReputationScan = now
            local char = GetCurrentCharTable()
            if char and GetNumFactions and GetFactionInfo and DS.ScanReputations then
                DS:ScanReputations()
            end
        end
        return
    end
    if event == "MAIL_SHOW" then
        isMailOpen = true
        return
    end
    if event == "MAIL_INBOX_UPDATE" then
        local char = GetCurrentCharTable()
        if char and GetInboxNumItems and DS.ScanMailbox then
            DS:ScanMailbox()
        end
        return
    end
    if event == "MAIL_CLOSED" then
        isMailOpen = false
        local char = GetCurrentCharTable()
        if char and GetInboxNumItems and DS.ScanMailbox then
            DS:ScanMailbox()
        end
        return
    end
    if event == "AUCTION_HOUSE_SHOW" then
        isAuctionHouseOpen = true
        local char = GetCurrentCharTable()
        if char and GetNumAuctionItems and DS.ScanAuctions and DS.ScanBids then
            DS:ScanAuctions()
            DS:ScanBids()
        end
        return
    end
    if event == "AUCTION_HOUSE_CLOSED" then
        isAuctionHouseOpen = false
        return
    end
    if event == "AUCTION_OWNED_LIST_UPDATE" then
        if isAuctionHouseOpen and DS.ScanAuctions then
            local char = GetCurrentCharTable()
            if char and GetNumAuctionItems then DS:ScanAuctions() end
        end
        return
    end
    if event == "AUCTION_BIDDER_LIST_UPDATE" then
        if isAuctionHouseOpen and DS.ScanBids then
            local char = GetCurrentCharTable()
            if char and GetNumAuctionItems then DS:ScanBids() end
        end
        return
    end
    if event == "BAG_UPDATE" then
        local char = GetCurrentCharTable()
        if not char then return end
        if isMailOpen and GetInboxNumItems and DS.ScanMailbox then
            DS:ScanMailbox()
        end
        local bagID = a1
        local numBagSlots = DS.NUM_BAG_SLOTS or 4
        local bankContainer = DS.BANK_CONTAINER or -1
        local minBankBagId = DS.MIN_BANK_BAG_ID or 5
        local maxBankBagId = DS.MAX_BANK_BAG_ID or 11
        if type(bagID) == "number" then
            if bagID >= 0 and bagID <= numBagSlots then
                if DS.ScanContainer then DS:ScanContainer(char, bagID) end
                if DS.ScanBags then DS:ScanBags() end
            elseif isBankOpen and (bagID == bankContainer or (bagID >= minBankBagId and bagID <= maxBankBagId)) then
                if DS.ScanContainer then DS:ScanContainer(char, bagID) end
                if DS.ScanBank then DS:ScanBank() end
            end
        else
            if DS.ScanBags then DS:ScanBags() end
            if isBankOpen and DS.ScanBank then DS:ScanBank() end
        end
        return
    end
    if event == "BANKFRAME_OPENED" then
        isBankOpen = true
        local char = GetCurrentCharTable()
        if char and DS.ScanBank then DS:ScanBank() end
        return
    end
    if event == "BANKFRAME_CLOSED" then
        isBankOpen = false
        return
    end
    if event == "PLAYERBANKSLOTS_CHANGED" then
        if isBankOpen and DS.ScanBank then
            local char = GetCurrentCharTable()
            if char then DS:ScanBank() end
        end
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        local char = GetCurrentCharTable()
        if char and DS.ScanEquipment then DS:ScanEquipment() end
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
            local maxLevel = DS.MAX_LEVEL or (MAX_PLAYER_LEVEL or 70)
            if char.level == maxLevel then
                char.restXP = 0
            end
        end
        return
    end
    if event == "PLAYER_LEVEL_UP" then
        local char = GetCurrentCharTable()
        if char and UnitLevel then
            char.level = UnitLevel("player")
            local maxLevel = DS.MAX_LEVEL or (MAX_PLAYER_LEVEL or 70)
            if char.level == maxLevel then
                char.restXP = 0
            end
        end
        return
    end
    if event == "TIME_PLAYED_MSG" then
        local char = GetCurrentCharTable()
        if char and addonName and type(addonName) == "number" then
            char.played = addonName
        end
        return
    end
end)
