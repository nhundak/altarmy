-- AltArmy TBC — DataStore module: auctions and bids.
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local function IsAuctionSold(saleStatus)
    return saleStatus and saleStatus == 1
end

function DS:ScanAuctions(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumAuctionItems or GetNumAuctionItems("owner") == nil then return end
    char.Auctions = char.Auctions or {}
    for k in pairs(char.Auctions) do char.Auctions[k] = nil end
    local numAuctions = GetNumAuctionItems("owner")
    for i = 1, numAuctions do
        local name, _, count, _, _, _, _, _, _, buyoutPrice, bidAmount, _, _, _, _, saleStatus, itemID =
            GetAuctionItemInfo("owner", i)
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

function DS:ScanBids(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    if not GetNumAuctionItems or GetNumAuctionItems("bidder") == nil then return end
    char.Bids = char.Bids or {}
    for k in pairs(char.Bids) do char.Bids[k] = nil end
    local numBids = GetNumAuctionItems("bidder")
    for i = 1, numBids do
        local name, _, count, _, _, _, _, _, _, buyoutPrice, bidPrice, _, _, ownerName, _, _, itemID =
            GetAuctionItemInfo("bidder", i)
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

function DS:GetNumAuctions(_self, char)
    if not char or not char.Auctions then return 0 end
    return #char.Auctions
end

function DS:GetAuctionInfo(_self, char, index)
    if not char or not char.Auctions or not index or index < 1 or index > #char.Auctions then
        return nil, nil, nil, nil, nil
    end
    local data = char.Auctions[index]
    if not data then return nil, nil, nil, nil, nil end
    return data.itemID, data.count, data.bidAmount, data.buyoutAmount, data.timeLeft
end

function DS:GetNumBids(_self, char)
    if not char or not char.Bids then return 0 end
    return #char.Bids
end

function DS:GetBidInfo(_self, char, index)
    if not char or not char.Bids or not index or index < 1 or index > #char.Bids then
        return nil, nil, nil, nil, nil, nil
    end
    local data = char.Bids[index]
    if not data then return nil, nil, nil, nil, nil, nil end
    return data.itemID, data.count, data.bidAmount, data.buyoutAmount, data.timeLeft, data.seller
end

function DS:GetAuctionItemCount(_self, char, itemID)
    if not char or not itemID then return 0 end
    local count = 0
    if char.Auctions then
        for _, v in ipairs(char.Auctions) do
            if v.itemID == itemID then count = count + (v.count or 1) end
        end
    end
    return count
end
