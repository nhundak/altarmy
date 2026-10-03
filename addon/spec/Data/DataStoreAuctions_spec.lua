--[[
  Unit tests for DataStoreAuctions.lua (_IsAuctionSold, getters).
  Run from project root: npm test
]]

describe("DataStoreAuctions", function()
  local DS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreAuctions")
    DS = AltArmy.DataStore
  end)

  describe("_IsAuctionSold", function()
    it("returns true when saleStatus is 1", function()
      assert.is_true(DS._IsAuctionSold(1))
    end)
    it("returns false when saleStatus is 0", function()
      assert.is_false(DS._IsAuctionSold(0))
    end)
    it("returns false when saleStatus is nil", function()
      assert.is_nil(DS._IsAuctionSold(nil))
    end)
    it("returns false for other values", function()
      assert.is_false(DS._IsAuctionSold(2))
    end)
  end)

  describe("ScanAuctions / ScanBids", function()
    local function setCurrentChar()
      _G.UnitName = function() return "TestPlayer" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.time = function() return 5000 end
    end

    before_each(function()
      _G.GetNumAuctionItems = nil
      _G.GetAuctionItemInfo = nil
      _G.GetAuctionItemTimeLeft = nil
      _G.GetAuctionItemLink = nil
      _G.C_AuctionHouse = nil
      setCurrentChar()
    end)

    it("scans owned auctions via the legacy global", function()
      _G.GetNumAuctionItems = function(list) return list == "owner" and 1 or 0 end
      _G.GetAuctionItemInfo = function(list, i)
        if list == "owner" and i == 1 then
          return "Hearthstone", nil, 1, nil, nil, nil, nil, nil, nil, 20, 10, nil, nil, nil, nil, 0, 6948
        end
      end
      _G.GetAuctionItemTimeLeft = function() return 2 end
      DS:ScanAuctions()
      local char = AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal(1, #char.Auctions)
      assert.are.equal(6948, char.Auctions[1].itemID)
      assert.are.equal(10, char.Auctions[1].bidAmount)
      assert.are.equal(20, char.Auctions[1].buyoutAmount)
      assert.are.equal(2, char.Auctions[1].timeLeft)
    end)

    it("falls back to C_AuctionHouse.GetOwnedAuctionInfo when the legacy global is absent", function()
      _G.C_AuctionHouse = {
        GetNumOwnedAuctions = function() return 1 end,
        GetOwnedAuctionInfo = function(i)
          if i == 1 then
            return {
              status = 0,
              itemKey = { itemID = 6948 },
              quantity = 1,
              bidAmount = 10,
              buyoutAmount = 20,
              timeLeftSeconds = 3600,
            }
          end
        end,
      }
      DS:ScanAuctions()
      local char = AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal(1, #char.Auctions)
      assert.are.equal(6948, char.Auctions[1].itemID)
      assert.are.equal(10, char.Auctions[1].bidAmount)
      assert.are.equal(20, char.Auctions[1].buyoutAmount)
      assert.are.equal(3600, char.Auctions[1].timeLeft)
    end)

    it("skips sold rows via C_AuctionHouse.GetOwnedAuctionInfo", function()
      _G.C_AuctionHouse = {
        GetNumOwnedAuctions = function() return 1 end,
        GetOwnedAuctionInfo = function()
          return { status = 1, itemKey = { itemID = 6948 }, quantity = 1 }
        end,
      }
      DS:ScanAuctions()
      local char = AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal(0, #char.Auctions)
    end)

    it("falls back to C_AuctionHouse.GetBidInfo when the legacy global is absent", function()
      _G.C_AuctionHouse = {
        GetNumBids = function() return 1 end,
        GetBidInfo = function(i)
          if i == 1 then
            return {
              itemKey = { itemID = 100 },
              quantity = 1,
              bidAmount = 15,
              buyoutAmount = 25,
              timeLeft = 2,
              bidder = "SomeSeller",
            }
          end
        end,
      }
      DS:ScanBids()
      local char = AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal(1, #char.Bids)
      assert.are.equal(100, char.Bids[1].itemID)
      assert.are.equal(15, char.Bids[1].bidAmount)
      assert.are.equal("SomeSeller", char.Bids[1].seller)
    end)

    it("does nothing when neither API exists", function()
      AltArmyTBC_Data.Characters.TestRealm.TestPlayer.Auctions = "sentinel"
      AltArmyTBC_Data.Characters.TestRealm.TestPlayer.Bids = "sentinel"
      DS:ScanAuctions()
      DS:ScanBids()
      local char = AltArmyTBC_Data.Characters.TestRealm.TestPlayer
      assert.are.equal("sentinel", char.Auctions)
      assert.are.equal("sentinel", char.Bids)
    end)
  end)

  describe("getters", function()
    it("GetNumAuctions returns count or 0", function()
      local charTwo = { Auctions = { {}, {} } }
      assert.are.equal(2, DS:GetNumAuctions(charTwo))
      assert.are.equal(0, DS:GetNumAuctions(nil))
      assert.are.equal(0, DS:GetNumAuctions({}))
    end)
    it("GetAuctionInfo returns itemID, count, bidAmount, buyoutAmount, timeLeft", function()
      local char = { Auctions = { { itemID = 100, count = 5, bidAmount = 10, buyoutAmount = 20, timeLeft = 1 } } }
      local id, count, bid, buyout, left = DS:GetAuctionInfo(char, 1)
      assert.are.equal(100, id)
      assert.are.equal(5, count)
      assert.are.equal(10, bid)
      assert.are.equal(20, buyout)
      assert.are.equal(1, left)
    end)
    it("GetAuctionInfo returns nil when index out of range", function()
      local char = { Auctions = {} }
      local id = DS:GetAuctionInfo(char, 1)
      assert.is_nil(id)
    end)
    it("GetNumBids returns count or 0", function()
      local charOne = { Bids = { {} } }
      assert.are.equal(1, DS:GetNumBids(charOne))
      assert.are.equal(0, DS:GetNumBids(nil))
    end)
    it("GetAuctionItemCount sums count by itemID", function()
      local char = {
        Auctions = {
          { itemID = 100, count = 2 }, { itemID = 100, count = 3 }, { itemID = 200, count = 1 },
        },
      }
      assert.are.equal(5, DS:GetAuctionItemCount(char, 100))
      assert.are.equal(1, DS:GetAuctionItemCount(char, 200))
      assert.are.equal(0, DS:GetAuctionItemCount(char, 999))
    end)
    it("GetAuctionItemCount returns 0 when char or itemID nil", function()
      assert.are.equal(0, DS.GetAuctionItemCount(DS, nil, 100))
      assert.are.equal(0, DS.GetAuctionItemCount(DS, { Auctions = {} }, nil))
    end)
  end)
end)
