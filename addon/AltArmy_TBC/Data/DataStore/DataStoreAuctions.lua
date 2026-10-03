-- AltArmy TBC — DataStore module: auctions and bids.
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local function IsAuctionSold(saleStatus)
    return saleStatus and saleStatus == 1
end
DS._IsAuctionSold = IsAuctionSold

-- Legacy GetNumAuctionItems/GetAuctionItemInfo are absent on some clients (e.g. WoW Forever
-- beta — see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md); C_AuctionHouse is the retail/Forever-
-- shaped replacement, ported from Thaoky's DataStore_Auctions (github.com/Thaoky/DataStore_Auctions)
-- which we verified against live retail source. Checked dynamically on every call, never captured
-- as a load-time upvalue (see this file's Reputations counterpart for why that broke tests/fallback).
-- Both scan loops below stay synchronous (no async AH query needed) — C_AuctionHouse.GetNumOwnedAuctions
-- / GetOwnedAuctionInfo read from data the client already pushed via the OWNED_AUCTIONS_UPDATED /
-- BIDS_UPDATED events (see DataStore.lua's dispatch), the same "event fires, then read a snapshot"
-- shape as the legacy GetNumAuctionItems/GetAuctionItemInfo pair.
function DS.HasOwnedAuctionsApi()
    return GetNumAuctionItems ~= nil or (C_AuctionHouse ~= nil and C_AuctionHouse.GetNumOwnedAuctions ~= nil)
end

function DS.HasBidAuctionsApi()
    return GetNumAuctionItems ~= nil or (C_AuctionHouse ~= nil and C_AuctionHouse.GetNumBids ~= nil)
end

local function API_GetNumOwnedAuctions()
    if GetNumAuctionItems then return GetNumAuctionItems("owner") end
    if C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions then return C_AuctionHouse.GetNumOwnedAuctions() end
    return nil
end

--- Returns itemID, count, bidAmount, buyoutAmount, timeLeft for one owned-auction row (already
--- skips sold rows), or nil if the row is sold/unavailable. timeLeft is raw seconds here (both
--- the legacy and C_AuctionHouse "owned auctions" APIs report real seconds for this call) — see
--- API_GetBidAuctionInfo below for a documented unit mismatch on the bids side.
local function API_GetOwnedAuctionInfo(index)
    if GetAuctionItemInfo then
        local name, _, count, _, _, _, _, _, _, buyoutPrice, bidAmount, _, _, _, _, saleStatus, itemID =
            GetAuctionItemInfo("owner", index)
        if not name or not itemID or IsAuctionSold(saleStatus) then return nil end
        local timeLeft = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("owner", index) or 0
        return itemID, count or 1, bidAmount or 0, buyoutPrice or 0, timeLeft
    end
    if C_AuctionHouse and C_AuctionHouse.GetOwnedAuctionInfo then
        local info = C_AuctionHouse.GetOwnedAuctionInfo(index)
        if not info or not info.itemKey or not info.itemKey.itemID or IsAuctionSold(info.status) then
            return nil
        end
        return info.itemKey.itemID, info.quantity or 1, info.bidAmount or 0, info.buyoutAmount or 0,
            info.timeLeftSeconds or 0
    end
end

local function API_GetNumBidAuctions()
    if GetNumAuctionItems then return GetNumAuctionItems("bidder") end
    if C_AuctionHouse and C_AuctionHouse.GetNumBids then return C_AuctionHouse.GetNumBids() end
    return nil
end

--- Returns itemID, count, bidAmount, buyoutAmount, timeLeft, seller for one bid row, or nil if
--- unavailable. Known Blizzard-side quirk (present in both API generations, ported as-is from
--- Thaoky's DataStore_Auctions rather than "fixed"): timeLeft here is a coarse 1-4 time-left band
--- (Blizzard's AuctionItemTimeLeft/BidInfo shape), not the raw-seconds value API_GetOwnedAuctionInfo
--- returns above — callers already treat this as a band (see GetBidInfo's docstring below).
local function API_GetBidAuctionInfo(index)
    if GetAuctionItemInfo then
        local name, _, count, _, _, _, _, _, _, buyoutPrice, bidPrice, _, _, ownerName, _, _, itemID =
            GetAuctionItemInfo("bidder", index)
        if not name then return nil end
        if not itemID and GetAuctionItemLink then
            local link = GetAuctionItemLink("bidder", index)
            if link and not link:match("battlepet:") then
                itemID = tonumber(link:match("item:(%d+)"))
            end
        end
        if not itemID then return nil end
        local timeLeft = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("bidder", index) or 0
        return itemID, count or 1, bidPrice or 0, buyoutPrice or 0, timeLeft, ownerName
    end
    if C_AuctionHouse and C_AuctionHouse.GetBidInfo then
        local info = C_AuctionHouse.GetBidInfo(index)
        if not info or not info.itemKey or not info.itemKey.itemID then return nil end
        -- Thaoky's DataStore_Auctions maps info.bidder to the "seller" position here (matching the
        -- legacy ownerName slot) — ported as-is; not independently re-derived from Blizzard's docs.
        return info.itemKey.itemID, info.quantity or 1, info.bidAmount or 0, info.buyoutAmount or 0,
            info.timeLeft, info.bidder
    end
end

function DS:ScanAuctions(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    if not DS.HasOwnedAuctionsApi() then return end
    local numAuctions = API_GetNumOwnedAuctions()
    if numAuctions == nil then return end
    char.Auctions = char.Auctions or {}
    for k in pairs(char.Auctions) do char.Auctions[k] = nil end
    for i = 1, numAuctions do
        local itemID, count, bidAmount, buyoutAmount, timeLeft = API_GetOwnedAuctionInfo(i)
        if itemID then
            table.insert(char.Auctions, {
                itemID = itemID,
                count = count,
                bidAmount = bidAmount,
                buyoutAmount = buyoutAmount,
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

--- Bid rows' `timeLeft` is a 1-4 band (short/medium/long/verylong), not raw seconds — see
--- API_GetBidAuctionInfo above. This is a pre-existing shape carried over unchanged, not introduced
--- by the C_AuctionHouse fallback.
function DS:ScanBids(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    if not DS.HasBidAuctionsApi() then return end
    local numBids = API_GetNumBidAuctions()
    if numBids == nil then return end
    char.Bids = char.Bids or {}
    for k in pairs(char.Bids) do char.Bids[k] = nil end
    for i = 1, numBids do
        local itemID, count, bidAmount, buyoutAmount, timeLeft, seller = API_GetBidAuctionInfo(i)
        if itemID then
            table.insert(char.Bids, {
                itemID = itemID,
                count = count,
                bidAmount = bidAmount,
                buyoutAmount = buyoutAmount,
                timeLeft = timeLeft,
                seller = seller,
                lastScan = time(),
            })
        end
    end
    char.lastAuctionScan = time()
    char.lastUpdate = time()
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.auctions = DATA_VERSIONS.auctions
end

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
