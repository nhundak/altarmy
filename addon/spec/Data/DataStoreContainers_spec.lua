--[[
  Unit tests for DataStoreContainers.lua (GetContainerItemCount, IterateContainerSlots).
  Run from project root: npm test
]]

describe("DataStoreContainers", function()
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
    require("DataStoreContainers")
    require("DataStoreMail")
    DS = AltArmy.DataStore
  end)

  describe("GetContainerItemCount", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(0, DS:GetContainerItemCount(nil, 100))
    end)
    it("returns 0 when itemID is nil", function()
      assert.are.equal(0, DS:GetContainerItemCount({ Containers = {} }, nil))
    end)
    it("returns 0 when Containers empty", function()
      assert.are.equal(0, DS:GetContainerItemCount({ Containers = {} }, 100))
    end)
    it("sums count across bags for itemID", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 5 }, [2] = { itemID = 200, count = 1 } } },
          [1] = { items = { [1] = { itemID = 100, count = 3 } } },
        },
      }
      assert.are.equal(8, DS:GetContainerItemCount(char, 100))
      assert.are.equal(1, DS:GetContainerItemCount(char, 200))
      assert.are.equal(0, DS:GetContainerItemCount(char, 999))
    end)
    it("treats missing count as 1", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100 } } },
        },
      }
      assert.are.equal(1, DS:GetContainerItemCount(char, 100))
    end)
  end)

  describe("GetTotalItemCount", function()
    it("sums containers + mail", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } } },
        },
        Mails = {
          { itemID = 100, count = 3 },
          { itemID = 200, count = 9 },
        },
      }
      assert.are.equal(5, DS:GetTotalItemCount(char, 100))
      assert.are.equal(9, DS:GetTotalItemCount(char, 200))
    end)

    it("treats missing mail module as 0 (still counts containers)", function()
      local old = DS.GetMailItemCount
      DS.GetMailItemCount = nil
      local char = { Containers = { [0] = { items = { [1] = { itemID = 100, count = 2 } } } } }
      assert.are.equal(2, DS:GetTotalItemCount(char, 100))
      DS.GetMailItemCount = old
    end)
  end)

  describe("GetBagItemCount", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(0, DS:GetBagItemCount(nil, 100))
    end)
    it("returns 0 when itemID is nil", function()
      assert.are.equal(0, DS:GetBagItemCount({ Containers = {} }, nil))
    end)
    it("sums across bags but excludes bank containers", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } } },
          [1] = { items = { [1] = { itemID = 100, count = 3 } } },
          [-1] = { items = { [1] = { itemID = 100, count = 5 } } }, -- bank container
          [5] = { items = { [1] = { itemID = 100, count = 7 } } }, -- bank bag range
        },
      }
      assert.are.equal(5, DS:GetBagItemCount(char, 100))
    end)
  end)

  describe("IterateContainerSlots", function()
    it("does nothing when char is nil", function()
      local n = 0
      DS:IterateContainerSlots(nil, function() n = n + 1 end)
      assert.are.equal(0, n)
    end)
    it("does nothing when callback is nil", function()
      local char = { Containers = { [0] = { items = { [1] = { itemID = 1 } } } } }
      DS:IterateContainerSlots(char, nil)
    end)
    it("invokes callback for each slot with item", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } }, links = { [1] = "link1" } },
          [1] = { items = { [1] = { itemID = 200, count = 1 } }, links = {} },
        },
      }
      local calls = {}
      DS:IterateContainerSlots(char, function(bagID, slot, itemID, count, link)
        table.insert(calls, { bagID = bagID, slot = slot, itemID = itemID, count = count, link = link })
        return false
      end)
      assert.are.equal(2, #calls)
      assert.are.equal(0, calls[1].bagID)
      assert.are.equal(1, calls[1].slot)
      assert.are.equal(100, calls[1].itemID)
      assert.are.equal(2, calls[1].count)
      assert.are.equal("link1", calls[1].link)
      assert.are.equal(200, calls[2].itemID)
    end)
    it("stops when callback returns true", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100 }, [2] = { itemID = 200 } }, links = {} },
        },
      }
      local n = 0
      DS:IterateContainerSlots(char, function()
        n = n + 1
        return true
      end)
      assert.are.equal(1, n)
    end)
  end)

  describe("IterateBagSlots", function()
    it("invokes callback only for bag containers", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } }, links = { [1] = "link1" } },
          [-1] = { items = { [1] = { itemID = 200, count = 1 } }, links = { [1] = "bank" } },
        },
      }
      local calls = {}
      DS:IterateBagSlots(char, function(bagID, slot, itemID, count, link)
        table.insert(calls, { bagID = bagID, slot = slot, itemID = itemID, count = count, link = link })
        return false
      end)
      assert.are.equal(1, #calls)
      assert.are.equal(0, calls[1].bagID)
      assert.are.equal(100, calls[1].itemID)
      assert.are.equal("link1", calls[1].link)
    end)
  end)

  describe("IterateBankSlots", function()
    it("invokes callback only for bank containers", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 2 } }, links = { [1] = "bag" } },
          [-1] = { items = { [1] = { itemID = 200, count = 1 } }, links = { [1] = "bank" } },
          ["5"] = { items = { [1] = { itemID = 300, count = 1 } }, links = { [1] = "bank5" } },
        },
      }
      local calls = {}
      DS:IterateBankSlots(char, function(bagID, slot, itemID, count, link)
        table.insert(calls, { bagID = bagID, slot = slot, itemID = itemID, count = count, link = link })
        return false
      end)
      assert.are.equal(2, #calls)
      assert.are.equal(-1, calls[1].bagID)
      assert.are.equal(200, calls[1].itemID)
      assert.are.equal("bank", calls[1].link)
      assert.are.equal(5, calls[2].bagID)
      assert.are.equal(300, calls[2].itemID)
    end)
  end)

  describe("ScanBank", function()
    it("preserves saved bank slots when the bank is closed", function()
      _G.UnitName = function() return "Banker" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == -1 then return 28 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      DS.IsBankOpen = function() return false end
      local char = DS:GetCurrentCharacter()
      char.Containers = {
        [-1] = {
          items = { [1] = { itemID = 100, count = 1 } },
          links = { [1] = "|Hitem:100:0|h[Bank Item]|h" },
        },
      }
      DS:ScanBank()
      assert.are.equal(100, char.Containers[-1].items[1].itemID)
      assert.are.equal("|Hitem:100:0|h[Bank Item]|h", char.Containers[-1].links[1])
    end)
  end)
end)
