--[[
  Unit tests for DataStoreCurrencies.lua (GetCurrencyCount, GetAllCurrencies).
  Run from project root: npm test
]]

describe("DataStoreCurrencies", function()
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
    require("DataStoreCurrencies")
    DS = AltArmy.DataStore
  end)

  describe("GetCurrencyCount", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(DS:GetCurrencyCount(nil, 29434), 0)
    end)
    it("returns 0 when itemID is nil", function()
      assert.are.equal(DS:GetCurrencyCount({ Currencies = {} }, nil), 0)
    end)
    it("returns from Currencies when present", function()
      assert.are.equal(DS:GetCurrencyCount({ Currencies = { [29434] = 10 } }, 29434), 10)
    end)
    it("falls back to GetContainerItemCount when not in Currencies", function()
      local char = {
        Currencies = {},
        Containers = { [0] = { items = { [1] = { itemID = 29434, count = 5 } }, links = {} } },
      }
      assert.are.equal(5, DS:GetCurrencyCount(char, 29434))
    end)
  end)

  describe("GetAllCurrencies", function()
    it("returns empty when char is nil", function()
      assert.are.same(DS:GetAllCurrencies(nil), {})
    end)
    it("returns copy of Currencies", function()
      local cur = { [29434] = 5, [20558] = 10 }
      local char = { Currencies = cur }
      local out = DS:GetAllCurrencies(char)
      assert.are.same(cur, out)
      assert.is_true(out ~= cur)
    end)
    it("returns empty when Currencies nil", function()
      assert.are.same(DS:GetAllCurrencies({}), {})
    end)
  end)
end)
