-- AltArmy TBC — Internal character data store.
-- Persists character data to SavedVariables (AltArmyTBC_Data), shared across all characters on the account.
-- TBC-compatible; no external DataStore dependency.

if not AltArmy then return end

AltArmy.DataStore = AltArmy.DataStore or {}

local DS = AltArmy.DataStore
local MAX_LEVEL = MAX_PLAYER_LEVEL or 70
local MAX_LOGOUT_SENTINEL = 5000000000

-- Current data format versions for each module (see Data/DATA_VERSIONS.md).
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
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.character = DATA_VERSIONS.character
end

--- One-time migration: stamp version 1 for existing data that predates versioning.
local function MigrateDataVersions()
    for realm, chars in pairs(AltArmyTBC_Data.Characters or {}) do
        for name, char in pairs(chars) do
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
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.containers = DATA_VERSIONS.containers
    ScanCurrencies()
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
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.containers = DATA_VERSIONS.containers
    ScanCurrencies()
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
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.equipment = DATA_VERSIONS.equipment
end

-- --- Professions ---
local SkillTypeToColor = { header = 0, optimal = 1, medium = 2, easy = 3, trivial = 4 }
local SPELL_ID_FIRSTAID = 3273
local SPELL_ID_COOKING = 2550
local SPELL_ID_FISHING = 7732

--- Scan profession list from skill lines (rank, maxRank, Prof1/Prof2). Does not scan recipes.
local function ScanProfessionLinks()
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumSkillLines or not GetSkillLineInfo then return end
    char.Professions = char.Professions or {}
    char.Prof1 = nil
    char.Prof2 = nil
    -- Expand all skill headers
    for i = GetNumSkillLines(), 1, -1 do
        local _, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and not isExpanded and ExpandSkillHeader then
            ExpandSkillHeader(i)
        end
    end
    local category
    for i = 1, GetNumSkillLines() do
        local skillName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not skillName then break end
        if isHeader then
            category = skillName
        else
            if category and skillName then
                -- "Professions" = primary, "Secondary Skills" = secondary (Cooking, Fishing, First Aid)
                local isPrimary = (category == "Professions")
                local isSecondary = (category == "Secondary Skills")
                if isPrimary or isSecondary then
                    if skillName == "Secourisme" and GetSpellInfo then
                        skillName = GetSpellInfo(SPELL_ID_FIRSTAID) or skillName
                    end
                    local prof = char.Professions[skillName]
                    if not prof then
                        prof = { rank = 0, maxRank = 0, Recipes = {} }
                        char.Professions[skillName] = prof
                    end
                    prof.rank = rank or 0
                    prof.maxRank = maxRank or 0
                    if isPrimary then prof.isPrimary = true end
                    if isSecondary then prof.isSecondary = true end
                    if isPrimary then
                        if not char.Prof1 then char.Prof1 = skillName
                        else char.Prof2 = skillName end
                    end
                end
            end
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
end

--- Save/restore trade skill UI state (headers) so we can expand all and scan.
local headersState = {}
local function SaveTradeSkillHeaders()
    for k in pairs(headersState) do headersState[k] = nil end
    local headerCount = 0
    if not GetNumTradeSkills then return end
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType, _, _, isExpanded = GetTradeSkillInfo(i)
        if skillType == "header" then
            headerCount = headerCount + 1
            if not isExpanded and ExpandTradeSkillSubClass then
                ExpandTradeSkillSubClass(i)
                headersState[headerCount] = true
            end
        end
    end
end
local function RestoreTradeSkillHeaders()
    local headerCount = 0
    if not GetNumTradeSkills then return end
    for i = GetNumTradeSkills(), 1, -1 do
        local _, skillType = GetTradeSkillInfo(i)
        if skillType == "header" then
            headerCount = headerCount + 1
            if headersState[headerCount] and CollapseTradeSkillSubClass then
                CollapseTradeSkillSubClass(i)
            end
        end
    end
    for k in pairs(headersState) do headersState[k] = nil end
end

--- Scan recipes for the currently open trade skill. Call with trade skill window open.
local function ScanRecipes()
    local char = GetCurrentCharTable()
    if not char then return end
    local tradeskillName = GetTradeSkillLine and GetTradeSkillLine()
    if not tradeskillName or tradeskillName == "" or tradeskillName == "UNKNOWN" then return end
    if tradeskillName == "Secourisme" and GetSpellInfo then
        tradeskillName = GetSpellInfo(SPELL_ID_FIRSTAID) or tradeskillName
    end
    local numTradeSkills = GetNumTradeSkills and GetNumTradeSkills()
    if not numTradeSkills or numTradeSkills == 0 then return end
    local _, skillType = GetTradeSkillInfo(1)
    if skillType ~= "header" and skillType ~= "subheader" then return end
    local prof = char.Professions[tradeskillName]
    if not prof then
        prof = { rank = 0, maxRank = 0, Recipes = {} }
        char.Professions[tradeskillName] = prof
    end
    prof.Recipes = prof.Recipes or {}
    for k in pairs(prof.Recipes) do prof.Recipes[k] = nil end
    local GetRecipeLink = GetTradeSkillRecipeLink or GetTradeSkillItemLink
    for i = 1, numTradeSkills do
        local skillName, skillType = GetTradeSkillInfo(i)
        local color = SkillTypeToColor[skillType]
        if color and skillType ~= "header" and skillType ~= "subheader" then
            local recipeID
            if GetTradeSkillRecipeLink then
                local link = GetTradeSkillRecipeLink(i)
                if link then
                    recipeID = tonumber(link:match("enchant:(%d+)"))
                end
                if not recipeID and GetTradeSkillItemLink then
                    local itemLink = GetTradeSkillItemLink(i)
                    if itemLink then
                        recipeID = tonumber(itemLink:match("item:(%d+)"))
                    end
                end
            elseif GetTradeSkillItemLink then
                local itemLink = GetTradeSkillItemLink(i)
                if itemLink then
                    recipeID = tonumber(itemLink:match("item:(%d+)"))
                end
            end
            if recipeID then
                prof.Recipes[recipeID] = color
            end
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.professions = DATA_VERSIONS.professions
end

local tradeSkillScanFrame = CreateFrame("Frame", nil, UIParent)
tradeSkillScanFrame:SetScript("OnUpdate", nil)
tradeSkillScanFrame.elapsed = 0
local TRADE_SKILL_SCAN_DELAY = 0.5

local function runDeferredRecipeScan()
    SaveTradeSkillHeaders()
    ScanRecipes()
    RestoreTradeSkillHeaders()
end

-- --- Reputations ---
-- TBC standing tier thresholds (bottom of each tier): Hated=0, Hostile=36000, Unfriendly=78000, Neutral=108000, Friendly=129000, Honored=150000, Revered=171000, Exalted=192000
local FACTION_STANDING_THRESHOLDS = { 0, 36000, 78000, 108000, 129000, 150000, 171000, 192000 }
local FACTION_STANDING_LABELS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

local factionHeadersState = {}
local function SaveFactionHeaders()
    for k in pairs(factionHeadersState) do factionHeadersState[k] = nil end
    local headerCount = 0
    if not GetNumFactions then return end
    for i = GetNumFactions(), 1, -1 do
        local _, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i)
        if isHeader then
            headerCount = headerCount + 1
            if isCollapsed and ExpandFactionHeader then
                ExpandFactionHeader(i)
                factionHeadersState[headerCount] = true
            end
        end
    end
end
local function RestoreFactionHeaders()
    local headerCount = 0
    if not GetNumFactions then return end
    for i = GetNumFactions(), 1, -1 do
        local _, _, _, _, _, _, _, _, isHeader = GetFactionInfo(i)
        if isHeader then
            headerCount = headerCount + 1
            if factionHeadersState[headerCount] and CollapseFactionHeader then
                CollapseFactionHeader(i)
            end
        end
    end
    for k in pairs(factionHeadersState) do factionHeadersState[k] = nil end
end

--- Scan all faction reputations. Expands headers, scans, restores.
local function ScanReputations()
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumFactions or not GetFactionInfo then return end
    char.Reputations = char.Reputations or {}
    for k in pairs(char.Reputations) do char.Reputations[k] = nil end
    SaveFactionHeaders()
    for i = 1, GetNumFactions() do
        local name, _, standingID, barMin, barMax, barValue, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
        if not isHeader and factionID and factionID > 0 then
            local earned
            if standingID and barMin and barValue then
                local threshold = FACTION_STANDING_THRESHOLDS[standingID]
                if threshold then
                    earned = threshold + (barValue - barMin)
                else
                    earned = barValue
                end
            else
                earned = 0
            end
            char.Reputations[factionID] = earned
        end
    end
    RestoreFactionHeaders()
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.reputations = DATA_VERSIONS.reputations
end

-- --- Mail ---
local MAIL_ICON_COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local MAIL_ICON_NOTE = "Interface\\Icons\\INV_Misc_Note_01"
local ATTACHMENTS_MAX_SEND = 12

--- Scan mailbox into char.Mails. Call when mailbox is open.
local function ScanMailbox()
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetInboxNumItems then return end
    char.Mails = char.Mails or {}
    for k in pairs(char.Mails) do char.Mails[k] = nil end
    local numItems = GetInboxNumItems()
    if numItems == 0 then
        char.lastMailCheck = time()
        char.dataVersions = char.dataVersions or {}
        char.dataVersions.mail = DATA_VERSIONS.mail
        return
    end
    if CheckInbox then CheckInbox() end
    for i = 1, numItems do
        local _, stationaryIcon, mailSender, mailSubject, mailMoney, _, daysLeft, numAttachments, _, wasReturned = GetInboxHeaderInfo(i)
        daysLeft = daysLeft or 30
        if numAttachments and numAttachments > 0 then
            for attachIndex = 1, ATTACHMENTS_MAX_SEND do
                local itemName, itemID, icon, count = GetInboxItem(i, attachIndex)
                if itemName and itemID then
                    local link = GetInboxItemLink and GetInboxItemLink(i, attachIndex)
                    table.insert(char.Mails, {
                        icon = icon or MAIL_ICON_NOTE,
                        itemID = itemID,
                        count = count or 1,
                        sender = mailSender,
                        link = link,
                        money = 0,
                        subject = mailSubject,
                        lastCheck = time(),
                        daysLeft = daysLeft,
                        returned = wasReturned,
                    })
                end
            end
        end
        local inboxText
        if GetInboxText then inboxText = GetInboxText(i) end
        if (mailMoney and mailMoney > 0) or (inboxText and inboxText ~= "") then
            local mailIcon = (mailMoney and mailMoney > 0) and MAIL_ICON_COIN or (stationaryIcon or MAIL_ICON_NOTE)
            table.insert(char.Mails, {
                icon = mailIcon,
                itemID = nil,
                count = nil,
                sender = mailSender,
                link = nil,
                money = mailMoney or 0,
                subject = mailSubject,
                text = inboxText,
                lastCheck = time(),
                daysLeft = daysLeft,
                returned = wasReturned,
            })
        end
    end
    char.lastMailCheck = time()
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.mail = DATA_VERSIONS.mail
end

-- --- Auctions ---
local function IsAuctionSold(saleStatus)
    return saleStatus and saleStatus == 1
end

--- Scan owned auctions into char.Auctions.
local function ScanAuctions()
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumAuctionItems or GetNumAuctionItems("owner") == nil then return end
    char.Auctions = char.Auctions or {}
    for k in pairs(char.Auctions) do char.Auctions[k] = nil end
    local numAuctions = GetNumAuctionItems("owner")
    for i = 1, numAuctions do
        local name, _, count, _, _, _, _, startPrice, _, buyoutPrice, bidAmount, highBidder, _, _, _, saleStatus, itemID = GetAuctionItemInfo("owner", i)
        if name and itemID and not IsAuctionSold(saleStatus) then
            local timeLeft = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("owner", i) or 0
            table.insert(char.Auctions, {
                itemID = itemID,
                count = count or 1,
                bidAmount = bidAmount or 0,
                buyoutAmount = buyoutPrice or 0,
                timeLeft = timeLeft,
                lastScan = time(),
            })
        end
    end
    char.lastAuctionScan = time()
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.auctions = DATA_VERSIONS.auctions
end

--- Scan bids into char.Bids.
local function ScanBids()
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumAuctionItems or GetNumAuctionItems("bidder") == nil then return end
    char.Bids = char.Bids or {}
    for k in pairs(char.Bids) do char.Bids[k] = nil end
    local numBids = GetNumAuctionItems("bidder")
    for i = 1, numBids do
        local name, _, count, _, _, _, _, _, _, buyoutPrice, bidPrice, _, _, ownerName, _, _, itemID = GetAuctionItemInfo("bidder", i)
        if name then
            if not itemID and GetAuctionItemLink then
                local link = GetAuctionItemLink("bidder", i)
                if link and not link:match("battlepet:") then
                    itemID = tonumber(link:match("item:(%d+)"))
                end
            end
            if itemID then
                local timeLeft = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("bidder", i) or 0
                table.insert(char.Bids, {
                    itemID = itemID,
                    count = count or 1,
                    bidAmount = bidPrice or 0,
                    buyoutAmount = buyoutPrice or 0,
                    timeLeft = timeLeft,
                    seller = ownerName,
                    lastScan = time(),
                })
            end
        end
    end
    char.lastAuctionScan = time()
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.auctions = DATA_VERSIONS.auctions
end

-- --- Currencies (TBC: currency items in bags/bank) ---
local CURRENCY_ITEM_IDS = {
    29434,  -- Badge of Justice
    20558,  -- Warsong Gulch Mark of Honor
    20559,  -- Arathi Basin Mark of Honor
    20560,  -- Alterac Valley Mark of Honor
    29024,  -- Eye of the Storm Mark of Honor
    43228,  -- Stone Keeper's Shard
    37836,  -- Venture Coin
}

--- Scan known currency item counts from containers into char.Currencies. Call after ScanBags/ScanBank.
local function ScanCurrencies()
    local char = GetCurrentCharTable()
    if not char then return end
    char.Currencies = char.Currencies or {}
    for k in pairs(char.Currencies) do char.Currencies[k] = nil end
    for _, itemID in ipairs(CURRENCY_ITEM_IDS) do
        local count = DS:GetContainerItemCount(char, itemID)
        if count > 0 then
            char.Currencies[itemID] = count
        end
    end
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.currencies = DATA_VERSIONS.currencies
end

local function GetReputationLimits(earned)
    local bottom, top = 0, 42000
    for i = 1, #FACTION_STANDING_THRESHOLDS do
        if earned >= FACTION_STANDING_THRESHOLDS[i] then
            bottom = FACTION_STANDING_THRESHOLDS[i]
        end
    end
    for i = 1, #FACTION_STANDING_THRESHOLDS - 1 do
        if FACTION_STANDING_THRESHOLDS[i] == bottom then
            top = FACTION_STANDING_THRESHOLDS[i + 1]
            break
        end
    end
    if top == 0 then top = 42000 end
    return bottom, top
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

--- Data versioning: check if character has ever been scanned for a module.
function DS:HasModuleData(char, moduleName)
    if not char or not moduleName then return false end
    local v = (char.dataVersions and char.dataVersions[moduleName]) or 0
    return v > 0
end

--- Data versioning: get version number for a module (0 if never scanned).
function DS:GetDataVersion(char, moduleName)
    if not char or not moduleName then return 0 end
    return (char.dataVersions and char.dataVersions[moduleName]) or 0
end

--- Data versioning: true if character data is outdated (version < current).
function DS:NeedsRescan(char, moduleName)
    if not char or not moduleName then return true end
    local current = DATA_VERSIONS[moduleName]
    if not current then return false end
    return (DS:GetDataVersion(char, moduleName) or 0) < current
end

--- Data versioning: get all module versions for a character.
function DS:GetAllDataVersions(char)
    if not char then return {} end
    local out = {}
    for k, v in pairs(char.dataVersions or {}) do
        out[k] = v
    end
    return out
end

--- Professions: GetProfessions(char), GetProfession(char, name), GetProfession1/2, GetCookingRank, GetFishingRank, GetFirstAidRank, GetNumRecipes, IsRecipeKnown.
function DS:GetProfessions(char)
    return (char and char.Professions) or {}
end

function DS:GetProfession(char, name)
    if not char or not char.Professions or not name then return nil end
    return char.Professions[name]
end

function DS:GetProfession1(char)
    if not char then return 0, 0, nil end
    local name = char.Prof1
    if not name then return 0, 0, nil end
    local prof = char.Professions and char.Professions[name]
    if not prof then return 0, 0, name end
    return prof.rank or 0, prof.maxRank or 0, name
end

function DS:GetProfession2(char)
    if not char then return 0, 0, nil end
    local name = char.Prof2
    if not name then return 0, 0, nil end
    local prof = char.Professions and char.Professions[name]
    if not prof then return 0, 0, name end
    return prof.rank or 0, prof.maxRank or 0, name
end

function DS:GetCookingRank(char)
    if not char or not GetSpellInfo then return 0, 0 end
    local name = GetSpellInfo(SPELL_ID_COOKING)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetFishingRank(char)
    if not char or not GetSpellInfo then return 0, 0 end
    local name = GetSpellInfo(SPELL_ID_FISHING)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetFirstAidRank(char)
    if not char or not GetSpellInfo then return 0, 0 end
    local name = GetSpellInfo(SPELL_ID_FIRSTAID)
    local prof = name and char.Professions and char.Professions[name]
    if not prof then return 0, 0 end
    return prof.rank or 0, prof.maxRank or 0
end

function DS:GetNumRecipes(char, profName)
    if not char or not char.Professions or not profName then return 0 end
    local prof = char.Professions[profName]
    if not prof or not prof.Recipes then return 0 end
    local n = 0
    for _ in pairs(prof.Recipes) do n = n + 1 end
    return n
end

function DS:IsRecipeKnown(char, profName, spellID)
    if not char or not char.Professions or not profName or not spellID then return false end
    local prof = char.Professions[profName]
    if not prof or not prof.Recipes then return false end
    return prof.Recipes[spellID] ~= nil
end

--- Reputations: GetReputations(char), GetReputationInfo(char, factionID), IterateReputations(char, callback).
function DS:GetReputations(char)
    return (char and char.Reputations) or {}
end

function DS:GetReputationInfo(char, factionID)
    if not char or not char.Reputations or not factionID then return nil, 0, 0, 0 end
    local earned = char.Reputations[factionID]
    if earned == nil then return nil, 0, 0, 0 end
    local bottom, top = GetReputationLimits(earned)
    local standing = FACTION_STANDING_LABELS[1]
    for i = 1, #FACTION_STANDING_THRESHOLDS do
        if FACTION_STANDING_THRESHOLDS[i] == bottom then
            standing = FACTION_STANDING_LABELS[i] or standing
            break
        end
    end
    local repEarned = earned - bottom
    local nextLevel = top - bottom
    local rate = (nextLevel > 0) and (repEarned / nextLevel * 100) or 100
    return standing, repEarned, nextLevel, rate
end

function DS:IterateReputations(char, callback)
    if not char or not char.Reputations or not callback then return end
    for factionID, earned in pairs(char.Reputations) do
        local standing, repEarned, nextLevel, rate = DS:GetReputationInfo(char, factionID)
        if callback(factionID, earned, standing, repEarned, nextLevel, rate) then
            return
        end
    end
end

--- Mail: GetNumMails(char), GetMailInfo(char, index), GetMailItemCount(char, itemID), GetMailboxLastVisit(char).
function DS:GetNumMails(char)
    if not char or not char.Mails then return 0 end
    return #char.Mails
end

function DS:GetMailInfo(char, index)
    if not char or not char.Mails or not index or index < 1 or index > #char.Mails then
        return nil, nil, nil, nil, nil, nil, nil, nil
    end
    local data = char.Mails[index]
    if not data then return nil, nil, nil, nil, nil, nil, nil, nil end
    local daysLeft = data.daysLeft
    local lastCheck = data.lastCheck or 0
    if daysLeft and lastCheck then
        daysLeft = daysLeft - (time() - lastCheck) / 86400
    end
    return data.icon, data.count, data.link, data.money, data.subject, data.sender, daysLeft, data.returned
end

function DS:GetMailItemCount(char, itemID)
    if not char or not char.Mails or not itemID then return 0 end
    local count = 0
    for _, v in ipairs(char.Mails) do
        if v.itemID == itemID then
            count = count + (v.count or 1)
        end
    end
    return count
end

function DS:GetMailboxLastVisit(char)
    if not char then return 0 end
    return char.lastMailCheck or 0
end

--- Auctions: GetNumAuctions(char), GetAuctionInfo(char, index), GetNumBids(char), GetBidInfo(char, index), GetAuctionItemCount(char, itemID).
function DS:GetNumAuctions(char)
    if not char or not char.Auctions then return 0 end
    return #char.Auctions
end

function DS:GetAuctionInfo(char, index)
    if not char or not char.Auctions or not index or index < 1 or index > #char.Auctions then
        return nil, nil, nil, nil, nil
    end
    local data = char.Auctions[index]
    if not data then return nil, nil, nil, nil, nil end
    return data.itemID, data.count, data.bidAmount, data.buyoutAmount, data.timeLeft
end

function DS:GetNumBids(char)
    if not char or not char.Bids then return 0 end
    return #char.Bids
end

function DS:GetBidInfo(char, index)
    if not char or not char.Bids or not index or index < 1 or index > #char.Bids then
        return nil, nil, nil, nil, nil, nil
    end
    local data = char.Bids[index]
    if not data then return nil, nil, nil, nil, nil, nil end
    return data.itemID, data.count, data.bidAmount, data.buyoutAmount, data.timeLeft, data.seller
end

function DS:GetAuctionItemCount(char, itemID)
    if not char or not itemID then return 0 end
    local count = 0
    if char.Auctions then
        for _, v in ipairs(char.Auctions) do
            if v.itemID == itemID then count = count + (v.count or 1) end
        end
    end
    return count
end

--- Currencies: GetCurrencyCount(char, itemID), GetAllCurrencies(char). TBC: currency items in bags/bank.
function DS:GetCurrencyCount(char, itemID)
    if not char or not itemID then return 0 end
    if char.Currencies and char.Currencies[itemID] then
        return char.Currencies[itemID]
    end
    return DS:GetContainerItemCount(char, itemID)
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
local REPUTATION_SCAN_THROTTLE = 3
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
        ScanCharacter()
        local char = GetCurrentCharTable()
        if char then
            ScanEquipment(char)
            if GetNumSkillLines and GetSkillLineInfo then
                ScanProfessionLinks()
            end
            if GetNumFactions and GetFactionInfo then
                ScanReputations()
            end
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
    if event == "SKILL_LINES_CHANGED" then
        local char = GetCurrentCharTable()
        if char and GetNumSkillLines and GetSkillLineInfo then
            ScanProfessionLinks()
        end
        return
    end
    if event == "TRADE_SKILL_SHOW" then
        isTradeSkillOpen = true
        local char = GetCurrentCharTable()
        if char and GetNumSkillLines and GetSkillLineInfo then
            ScanProfessionLinks()
        end
        tradeSkillScanFrame.elapsed = 0
        tradeSkillScanFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed >= TRADE_SKILL_SCAN_DELAY then
                self:SetScript("OnUpdate", nil)
                if GetNumTradeSkills and GetTradeSkillLine then
                    runDeferredRecipeScan()
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
        if isTradeSkillOpen then
            local char = GetCurrentCharTable()
            if char and GetNumTradeSkills and GetTradeSkillLine then
                SaveTradeSkillHeaders()
                ScanRecipes()
                RestoreTradeSkillHeaders()
            end
        end
        return
    end
    if event == "CHAT_MSG_SKILL" then
        local char = GetCurrentCharTable()
        if char and GetNumSkillLines and GetSkillLineInfo then
            ScanProfessionLinks()
        end
        return
    end
    if event == "UPDATE_FACTION" then
        local now = time()
        if now - lastReputationScan >= REPUTATION_SCAN_THROTTLE then
            lastReputationScan = now
            local char = GetCurrentCharTable()
            if char and GetNumFactions and GetFactionInfo then
                ScanReputations()
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
        if char and GetInboxNumItems then
            ScanMailbox()
        end
        return
    end
    if event == "MAIL_CLOSED" then
        isMailOpen = false
        local char = GetCurrentCharTable()
        if char and GetInboxNumItems then
            ScanMailbox()
        end
        return
    end
    if event == "AUCTION_HOUSE_SHOW" then
        isAuctionHouseOpen = true
        local char = GetCurrentCharTable()
        if char and GetNumAuctionItems then
            ScanAuctions()
            ScanBids()
        end
        return
    end
    if event == "AUCTION_HOUSE_CLOSED" then
        isAuctionHouseOpen = false
        return
    end
    if event == "AUCTION_OWNED_LIST_UPDATE" then
        if isAuctionHouseOpen then
            local char = GetCurrentCharTable()
            if char and GetNumAuctionItems then ScanAuctions() end
        end
        return
    end
    if event == "AUCTION_BIDDER_LIST_UPDATE" then
        if isAuctionHouseOpen then
            local char = GetCurrentCharTable()
            if char and GetNumAuctionItems then ScanBids() end
        end
        return
    end
    if event == "BAG_UPDATE" then
        local char = GetCurrentCharTable()
        if not char then return end
        if isMailOpen and GetInboxNumItems then
            ScanMailbox()
        end
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
