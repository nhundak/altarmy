-- AltArmy TBC — searches the auction house through Auctionator's temporary shopping list (the same
-- MultiSearchAdvanced API its crafting window "Search" button uses). Needs Auctionator and an open auction house.
-- luacheck: globals Auctionator AuctionHouseFrame AuctionFrame

if not AltArmy then return end

AltArmy.AuctionatorSearch = AltArmy.AuctionatorSearch or {}
local AZ = AltArmy.AuctionatorSearch

-- Auctionator names the temporary list after this: "Alt Army (temporary)".
local CALLER_ID = "Alt Army"

local function searchApi()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and api.MultiSearchAdvanced
end

local function isShown(f)
    return f ~= nil and f.IsShown ~= nil and f:IsShown() == true
end

--- True when Auctionator is loaded and the auction house (modern or legacy) is open.
function AZ.IsAvailable()
    if not searchApi() then return false end
    return isShown(AuctionHouseFrame) or isShown(AuctionFrame)
end

--- Run `terms` ({ searchString, quantity?, isExact? }[]) as an Auctionator temporary shopping list.
--- Returns true when the search started.
function AZ.Search(terms)
    if type(terms) ~= "table" or #terms == 0 or not AZ.IsAvailable() then return false end
    local ok = pcall(searchApi(), CALLER_ID, terms)
    return ok
end
