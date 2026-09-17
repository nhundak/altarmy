--[[
  Unit tests for DataStoreItemSpellCompat.lua (legacy-global vs. C_Item/C_Spell fallback).
  Run from project root: npm test
]]

describe("DataStoreItemSpellCompat", function()
  local DS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME or { AddMessage = function() end }
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreItemSpellCompat")
    DS = AltArmy.DataStore
  end)

  before_each(function()
    _G.GetItemInfo = nil
    _G.GetItemInfoInstant = nil
    _G.GetItemStats = nil
    _G.IsUsableItem = nil
    _G.GetSpellInfo = nil
    _G.GetSpellLink = nil
    _G.C_Item = nil
    _G.C_Spell = nil
  end)

  describe("CompatGetItemInfo", function()
    it("prefers the legacy global when present", function()
      _G.GetItemInfo = function(item) return "LegacyName", "link:" .. tostring(item) end
      _G.C_Item = { GetItemInfo = function() return "ShouldNotBeUsed" end }
      local name, link = DS.CompatGetItemInfo(123)
      assert.are.equal("LegacyName", name)
      assert.are.equal("link:123", link)
    end)

    it("falls back to C_Item.GetItemInfo when the legacy global is absent", function()
      _G.C_Item = { GetItemInfo = function(item) return "CItemName", "link:" .. tostring(item) end }
      local name, link = DS.CompatGetItemInfo(456)
      assert.are.equal("CItemName", name)
      assert.are.equal("link:456", link)
    end)

    it("returns nil when neither API exists", function()
      assert.is_nil(DS.CompatGetItemInfo(1))
    end)
  end)

  describe("CompatGetSpellInfo", function()
    it("prefers the legacy global when present", function()
      _G.GetSpellInfo = function(id) return "LegacyRank", "Rank 1", "icon", 0, 0, 0, id end
      _G.C_Spell = { GetSpellInfo = function() return { name = "ShouldNotBeUsed" } end }
      local name = DS.CompatGetSpellInfo(99)
      assert.are.equal("LegacyRank", name)
    end)

    it("falls back to C_Spell.GetSpellInfo, unpacked to the legacy tuple shape", function()
      _G.C_Spell = {
        GetSpellInfo = function(id)
          return { name = "Fireball", iconID = 135812, castTime = 2500, minRange = 0, maxRange = 40, spellID = id }
        end,
      }
      local name, rank, icon, castTime, minRange, maxRange, spellID = DS.CompatGetSpellInfo(133)
      assert.are.equal("Fireball", name)
      assert.is_nil(rank)
      assert.are.equal(135812, icon)
      assert.are.equal(2500, castTime)
      assert.are.equal(0, minRange)
      assert.are.equal(40, maxRange)
      assert.are.equal(133, spellID)
    end)

    it("returns nil when neither API exists", function()
      assert.is_nil(DS.CompatGetSpellInfo(1))
    end)
  end)

  describe("CompatGetSpellLink", function()
    it("falls back to C_Spell.GetSpellLink when the legacy global is absent", function()
      _G.C_Spell = { GetSpellLink = function(id) return "spelllink:" .. tostring(id) end }
      assert.are.equal("spelllink:7", DS.CompatGetSpellLink(7))
    end)
  end)

  describe("CompatIsUsableItem", function()
    it("falls back to C_Item.IsUsableItem when the legacy global is absent", function()
      _G.C_Item = { IsUsableItem = function() return true, false end }
      local usable, noMana = DS.CompatIsUsableItem(1)
      assert.is_true(usable)
      assert.is_false(noMana)
    end)
  end)

  describe("CompatGetItemStats", function()
    it("falls back to C_Item.GetItemStats when the legacy global is absent", function()
      _G.C_Item = { GetItemStats = function() return { ITEM_MOD_STAMINA_SHORT = 5 } end }
      local stats = DS.CompatGetItemStats("itemlink")
      assert.are.equal(5, stats.ITEM_MOD_STAMINA_SHORT)
    end)
  end)

  describe("CompatGetItemInfoInstant", function()
    it("falls back to C_Item.GetItemInfoInstant when the legacy global is absent", function()
      _G.C_Item = { GetItemInfoInstant = function(id) return id, "Weapon", "Sword", nil, "icon" end }
      local itemID, itemType, itemSubType, _, icon = DS.CompatGetItemInfoInstant(42)
      assert.are.equal(42, itemID)
      assert.are.equal("Weapon", itemType)
      assert.are.equal("Sword", itemSubType)
      assert.are.equal("icon", icon)
    end)
  end)
end)
