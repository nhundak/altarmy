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
    it("includes keyring container", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 100, count = 1 } } },
          [-2] = { items = { [1] = { itemID = 100, count = 4 } } },
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
          [-2] = { items = { [1] = { itemID = 300, count = 1 } }, links = { [1] = "key" } },
        },
      }
      local calls = {}
      DS:IterateBagSlots(char, function(bagID, slot, itemID, count, link)
        table.insert(calls, { bagID = bagID, slot = slot, itemID = itemID, count = count, link = link })
        return false
      end)
      assert.are.equal(2, #calls)
      assert.are.equal(0, calls[1].bagID)
      assert.are.equal(100, calls[1].itemID)
      assert.are.equal("link1", calls[1].link)
      assert.are.equal(-2, calls[2].bagID)
      assert.are.equal(300, calls[2].itemID)
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

  describe("ScanBags keyring", function()
    it("records keyring slots in char.Containers", function()
      _G.UnitName = function() return "KeyringTest" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == -2 then return 32 end
        return 0
      end
      _G.GetContainerItemLink = function(bagID, slot)
        if bagID == -2 and slot == 1 then return "|Hitem:12345:0|h[Test Key]|h" end
        return nil
      end
      _G.GetContainerItemInfo = function(bagID, slot)
        if bagID == -2 and slot == 1 then return "Test Key", 1 end
        return nil
      end
      _G.time = function() return 12345 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.truthy(char.Containers[-2])
      assert.are.equal(12345, char.Containers[-2].items[1].itemID)
      assert.are.equal("|Hitem:12345:0|h[Test Key]|h", char.Containers[-2].links[1])
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

    it("stores bank bag identity when bank is open", function()
      _G.UnitName = function() return "Banker" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = function(bagID)
        if bagID == 5 then return 67 end
        return nil
      end
      _G.GetInventoryItemLink = function(_, invSlot)
        if invSlot == 67 then return "|Hitem:21841:0|h[Netherweave Bag]|h" end
        return nil
      end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == -1 then return 28 end
        if bagID == 5 then return 16 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      DS.IsBankOpen = function() return true end
      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBank()
      assert.are.equal(21841, char.Containers[5].bagItemID)
      assert.are.equal("|Hitem:21841:0|h[Netherweave Bag]|h", char.Containers[5].bagLink)
    end)

    it("does not clear bank bag identity when bank is closed", function()
      _G.UnitName = function() return "Banker" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetContainerNumSlots = function() return 0 end
      DS.IsBankOpen = function() return false end
      local char = DS:GetCurrentCharacter()
      char.Containers = {
        [5] = {
          bagItemID = 21841,
          bagLink = "|Hitem:21841:0|h[Netherweave Bag]|h",
          items = { [1] = { itemID = 100, count = 1 } },
          links = { [1] = "|Hitem:100:0|h[Bank Item]|h" },
        },
      }
      DS:ScanBank()
      assert.are.equal(21841, char.Containers[5].bagItemID)
      assert.are.equal(100, char.Containers[5].items[1].itemID)
    end)
  end)

  describe("equipped bag identity", function()
    it("ScanBags stores bagLink/bagItemID for bags 1-4", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = function(bagID)
        return 19 + bagID -- bag 1 -> 20, etc.
      end
      _G.GetInventoryItemLink = function(_, invSlot)
        if invSlot == 20 then return "|Hitem:21841:0|h[Netherweave Bag]|h" end
        if invSlot == 21 then return "|Hitem:14156:0|h[Bottomless Bag]|h" end
        return nil
      end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == 1 then return 16 end
        if bagID == 2 then return 18 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.is_nil(char.Containers[0].bagItemID)
      assert.are.equal(21841, char.Containers[1].bagItemID)
      assert.are.equal("|Hitem:21841:0|h[Netherweave Bag]|h", char.Containers[1].bagLink)
      assert.are.equal(14156, char.Containers[2].bagItemID)
      assert.is_nil(char.Containers[3])
      assert.is_nil(char.Containers[4])
    end)

    it("ScanBags stores identity via GetInventorySlotInfo when ContainerIDToInventoryID is missing", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = nil
      _G.C_Container = nil
      _G.GetInventorySlotInfo = function(slotName)
        if slotName == "Bag0Slot" then return 20 end
        if slotName == "Bag1Slot" then return 21 end
        return nil
      end
      _G.GetInventoryItemLink = function(_, invSlot)
        if invSlot == 20 then return "|Hitem:21843:0|h[Imbued Netherweave Bag]|h" end
        return nil
      end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == 1 then return 18 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.are.equal(21843, char.Containers[1].bagItemID)
      assert.are.equal("|Hitem:21843:0|h[Imbued Netherweave Bag]|h", char.Containers[1].bagLink)
    end)

    it("ScanBags stores identity via C_Container.ContainerIDToInventoryID", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = nil
      _G.GetInventorySlotInfo = nil
      _G.C_Container = {
        ContainerIDToInventoryID = function(bagID) return 19 + bagID end,
        GetContainerNumSlots = function(bagID)
          if bagID == 0 then return 16 end
          if bagID == 1 then return 18 end
          return 0
        end,
        GetContainerItemLink = function() return nil end,
        GetContainerNumFreeSlots = function() return 0 end,
      }
      _G.GetInventoryItemLink = function(_, invSlot)
        if invSlot == 20 then return "|Hitem:21843:0|h[Imbued Netherweave Bag]|h" end
        return nil
      end
      _G.GetContainerNumSlots = nil
      _G.GetContainerItemLink = nil
      _G.GetContainerItemInfo = nil
      _G.GetContainerNumFreeSlots = nil
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.are.equal(21843, char.Containers[1].bagItemID)
    end)

    it("ScanBags uses GetInventoryItemID when the item link is not ready", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.C_Container = nil
      _G.ContainerIDToInventoryID = function(bagID) return 19 + bagID end
      _G.GetInventoryItemLink = function() return nil end
      _G.GetInventoryItemID = function(_, invSlot)
        if invSlot == 20 then return 21843 end
        return nil
      end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == 1 then return 18 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {}
      DS:ScanBags()

      assert.are.equal(21843, char.Containers[1].bagItemID)
    end)

    it("preserves bag identity when a bag still has slots but inventory APIs return nil", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.C_Container = nil
      _G.ContainerIDToInventoryID = function(bagID) return 19 + bagID end
      _G.GetInventoryItemLink = function() return nil end
      _G.GetInventoryItemID = function() return nil end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        if bagID == 1 then return 18 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {
        [1] = {
          bagItemID = 21843,
          bagLink = "|Hitem:21843:0|h[Imbued Netherweave Bag]|h",
          items = {},
          links = {},
        },
      }
      DS:ScanBags()

      assert.are.equal(21843, char.Containers[1].bagItemID)
      assert.are.equal("|Hitem:21843:0|h[Imbued Netherweave Bag]|h", char.Containers[1].bagLink)
    end)

    it("clears identity and contents when an inventory bag slot is empty", function()
      _G.UnitName = function() return "BagChar" end
      _G.GetRealmName = function() return "TestRealm" end
      _G.ContainerIDToInventoryID = function(bagID) return 19 + bagID end
      _G.GetInventoryItemLink = function() return nil end
      _G.GetContainerNumSlots = function(bagID)
        if bagID == 0 then return 16 end
        return 0
      end
      _G.GetContainerItemLink = function() return nil end
      _G.GetContainerItemInfo = function() return nil end
      _G.GetContainerNumFreeSlots = function() return 0 end
      _G.time = function() return 1 end

      local char = DS:GetCurrentCharacter()
      char.Containers = {
        [1] = {
          bagItemID = 21841,
          bagLink = "|Hitem:21841:0|h[Netherweave Bag]|h",
          items = { [1] = { itemID = 2589, count = 5 } },
          links = { [1] = "|Hitem:2589:0|h[Linen Cloth]|h" },
        },
      }
      DS:ScanBags()

      assert.is_nil(char.Containers[1].bagItemID)
      assert.is_nil(char.Containers[1].bagLink)
      assert.is_nil(char.Containers[1].items[1])
      assert.is_nil(char.Containers[1].links[1])
    end)

    it("IterateEquippedBags yields only slots with a bag item", function()
      local char = {
        Containers = {
          [0] = { items = { [1] = { itemID = 1, count = 1 } }, links = {} },
          [1] = {
            bagItemID = 21841,
            bagLink = "|Hitem:21841:0|h[Netherweave Bag]|h",
            items = { [1] = { itemID = 2589, count = 2 } },
            links = { [1] = "cloth" },
          },
          [5] = {
            bagItemID = 14156,
            bagLink = "|Hitem:14156:0|h[Bottomless Bag]|h",
            items = {},
            links = {},
          },
          [-1] = { items = { [1] = { itemID = 100, count = 1 } }, links = {} },
        },
      }
      local calls = {}
      DS:IterateEquippedBags(char, function(bagID, itemID, link)
        table.insert(calls, { bagID = bagID, itemID = itemID, link = link })
        return false
      end)
      assert.are.equal(2, #calls)
      local byBag = {}
      for _, c in ipairs(calls) do byBag[c.bagID] = c end
      assert.are.equal(21841, byBag[1].itemID)
      assert.are.equal(14156, byBag[5].itemID)
    end)

    it("IterateContainerSlots does not yield equipped bag items", function()
      local char = {
        Containers = {
          [1] = {
            bagItemID = 21841,
            bagLink = "|Hitem:21841:0|h[Netherweave Bag]|h",
            items = { [1] = { itemID = 2589, count = 2 } },
            links = { [1] = "cloth" },
          },
        },
      }
      local itemIDs = {}
      DS:IterateContainerSlots(char, function(_, _, itemID)
        table.insert(itemIDs, itemID)
        return false
      end)
      assert.are.same({ 2589 }, itemIDs)
      assert.are.equal(2, DS:GetContainerItemCount(char, 2589))
      assert.are.equal(0, DS:GetContainerItemCount(char, 21841))
    end)
  end)
end)
