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

  describe("ScanEquipment", function()
    local oldGetInventoryItemLink, oldUnitName, oldGetRealmName, oldTime

    before_each(function()
      oldGetInventoryItemLink = _G.GetInventoryItemLink
      oldUnitName = _G.UnitName
      oldGetRealmName = _G.GetRealmName
      oldTime = _G.time
      _G.UnitName = function() return "EquipTest" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.time = function() return 99999 end
    end)

    after_each(function()
      _G.GetInventoryItemLink = oldGetInventoryItemLink
      _G.UnitName = oldUnitName
      _G.GetRealmName = oldGetRealmName
      _G.time = oldTime
    end)

    it("does not clear Inventory when every equipment slot returns nil", function()
      local char = DS:GetCurrentCharacter()
      char.Inventory = {
        [1] = "|Hitem:100:0|h[Kept Helmet]|h",
        [16] = "|Hitem:200:0|h[Kept Sword]|h",
      }
      char.dataVersions = { equipment = 1 }
      char.lastUpdate = 1

      _G.GetInventoryItemLink = function() return nil end
      DS:ScanEquipment()

      assert.are.equal("|Hitem:100:0|h[Kept Helmet]|h", char.Inventory[1])
      assert.are.equal("|Hitem:200:0|h[Kept Sword]|h", char.Inventory[16])
      assert.are.equal(1, char.lastUpdate)
    end)

    it("updates Inventory when at least one slot has a link", function()
      local char = DS:GetCurrentCharacter()
      char.Inventory = { [1] = "|Hitem:100:0|h[Old Helmet]|h" }

      _G.GetInventoryItemLink = function(_, slot)
        if slot == 1 then return "|Hitem:111:0|h[New Helmet]|h" end
        return nil
      end
      DS:ScanEquipment()

      assert.are.equal("|Hitem:111:0|h[New Helmet]|h", char.Inventory[1])
      assert.is_nil(char.Inventory[16])
      assert.are.equal(99999, char.lastUpdate)
    end)
  end)
end)
