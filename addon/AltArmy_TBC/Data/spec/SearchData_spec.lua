--[[
  Unit tests for SearchData.lua (location, match score, search/aggregation).
  Run from project root: npm test
]]

describe("SearchData", function()
  local SD

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreContainers")
    require("SearchData")
    SD = AltArmy.SearchData
  end)

  describe("_LocationFromBagID", function()
    it("returns bag for 0-4", function()
      assert.are.equal(SD._LocationFromBagID(0), "bag")
      assert.are.equal(SD._LocationFromBagID(1), "bag")
      assert.are.equal(SD._LocationFromBagID(4), "bag")
    end)
    it("returns bank for -1", function()
      assert.are.equal(SD._LocationFromBagID(-1), "bank")
    end)
    it("returns bank for 5-11", function()
      assert.are.equal(SD._LocationFromBagID(5), "bank")
      assert.are.equal(SD._LocationFromBagID(11), "bank")
    end)
  end)

  describe("_GetNameMatchScore", function()
    it("returns 0 for nil or empty", function()
      assert.are.equal(SD._GetNameMatchScore(nil, "x"), 0)
      assert.are.equal(SD._GetNameMatchScore("Foo", ""), 0)
      assert.are.equal(SD._GetNameMatchScore("Foo", nil), 0)
    end)
    it("returns 3 for exact match", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "foo bar"), 3)
    end)
    it("returns 2 for prefix match", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "foo"), 2)
    end)
    it("returns 1 for contains", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "bar"), 1)
    end)
    it("returns 0 when no match", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "baz"), 0)
    end)
  end)

  describe("Search", function()
    it("returns empty for nil query", function()
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return {} end
      assert.are.same(SD.Search(nil), {})
      SD.GetAllContainerSlots = old
    end)
    it("returns empty for whitespace-only query", function()
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return {} end
      assert.are.same(SD.Search("   "), {})
      SD.GetAllContainerSlots = old
    end)
    it("matches by itemID when query is number", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 12345, itemLink = nil, count = 1, location = "bag" },
        { characterName = "B", realm = "R", itemID = 99999, itemLink = nil, count = 1, location = "bag" },
      }
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return list end
      local results = SD.Search(12345)
      SD.GetAllContainerSlots = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].itemID, 12345)
    end)
    it("matches by itemID when query is string digits", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 12345, itemLink = nil, count = 1, location = "bag" },
      }
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return list end
      local results = SD.Search("12345")
      SD.GetAllContainerSlots = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].itemID, 12345)
    end)
  end)

  describe("SearchGroupedByCharacter", function()
    it("aggregates count by character", function()
      local old = SD.Search
      SD.Search = function()
        return {
          { characterName = "A", realm = "R", itemID = 100, count = 2 },
          { characterName = "A", realm = "R", itemID = 100, count = 3 },
        }
      end
      local results = SD.SearchGroupedByCharacter("x")
      SD.Search = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].count, 5)
    end)
  end)

  describe("SearchWithLocationGroups", function()
    it("returns empty for nil query", function()
      assert.are.same(SD.SearchWithLocationGroups(nil), {})
    end)
    it("aggregates by itemID, character, realm, location", function()
      local old = SD.Search
      SD.Search = function()
        return {
          { itemID = 100, itemLink = "x", itemName = "Foo", characterName = "A", realm = "R",
            location = "bag", count = 2, classFile = "" },
          { itemID = 100, itemLink = "x", itemName = "Foo", characterName = "A", realm = "R",
            location = "bag", count = 3, classFile = "" },
        }
      end
      local results = SD.SearchWithLocationGroups("foo")
      SD.Search = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].count, 5)
    end)
  end)
end)
