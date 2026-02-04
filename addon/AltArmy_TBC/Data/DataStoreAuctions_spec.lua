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
