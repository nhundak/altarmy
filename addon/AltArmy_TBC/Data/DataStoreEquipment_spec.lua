--[[
  Unit tests for DataStoreEquipment.lua (_IsEnchanted, GetInventoryItemCount).
  Run from project root: npm test
]]

describe("DataStoreEquipment", function()
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
    require("DataStoreEquipment")
    DS = AltArmy.DataStore
  end)

  describe("_IsEnchanted", function()
    it("returns false for nil or non-string", function()
      assert.is_false(DS._IsEnchanted(nil))
      assert.is_false(DS._IsEnchanted(123))
    end)
    it("returns false for unenchanted link pattern", function()
      assert.is_false(DS._IsEnchanted("item:12345:0:0:0:0:0:0:100:200:0:0"))
    end)
    it("returns true for enchanted link", function()
      assert.is_true(DS._IsEnchanted("item:12345:0:0:0:0:0:0:100:200:0:1"))
      assert.is_true(DS._IsEnchanted("item:12345:1:2:3:4:5:6:7:8:9:10"))
    end)
  end)

  describe("GetInventoryItemCount", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(0, DS:GetInventoryItemCount(nil, 12345))
    end)
    it("returns 0 when itemID is nil", function()
      assert.are.equal(0, DS:GetInventoryItemCount({ Inventory = { [1] = 12345 } }, nil))
    end)
    it("counts number slots matching itemID", function()
      local char = { Inventory = { [1] = 100, [2] = 100, [3] = 200 } }
      assert.are.equal(2, DS:GetInventoryItemCount(char, 100))
      assert.are.equal(1, DS:GetInventoryItemCount(char, 200))
      assert.are.equal(0, DS:GetInventoryItemCount(char, 999))
    end)
    it("counts link slots by extracted itemID", function()
      local char = { Inventory = { [1] = "item:100:0:0:0:0:0:0:0:0:0:0" } }
      assert.are.equal(1, DS:GetInventoryItemCount(char, 100))
    end)
  end)
end)
