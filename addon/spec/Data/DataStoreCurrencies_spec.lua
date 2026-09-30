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

describe("DataStoreCurrencies ScanCurrencyList", function()
  local DS

  -- Native currency list mock: headers hide their children while collapsed.
  local groups, expandCalls
  local function visible()
    local out = {}
    for _, g in ipairs(groups) do
      out[#out + 1] = { header = g }
      if g.expanded then
        for _, c in ipairs(g.children) do out[#out + 1] = { cur = c } end
      end
    end
    return out
  end

  local function installApi()
    expandCalls = {}
    _G.C_CurrencyInfo = {
      GetCurrencyListSize = function() return #visible() end,
      GetCurrencyListInfo = function(i)
        local v = visible()[i]
        if not v then return nil end
        if v.header then
          return { name = v.header.name, isHeader = true, isHeaderExpanded = v.header.expanded }
        end
        local c = v.cur
        return { name = c.name, isHeader = false, quantity = c.qty, iconFileID = c.icon,
          maxQuantity = c.max, currencyID = c.noId and nil or c.id }
      end,
      GetCurrencyListLink = function(i)
        local v = visible()[i]
        return v and v.cur and ("|Hcurrency:" .. v.cur.id .. "|h[x]|h") or nil
      end,
      GetCurrencyIDFromLink = function(link)
        return tonumber(link:match("currency:(%d+)"))
      end,
      ExpandCurrencyList = function(i, expand)
        local v = visible()[i]
        expandCalls[#expandCalls + 1] = { i, expand }
        if v and v.header then v.header.expanded = expand and true or false end
      end,
    }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.time = _G.time or os.time
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreContainers")
    require("DataStoreCurrencies")
    DS = AltArmy.DataStore
  end)

  local char
  before_each(function()
    groups = {
      { name = "Player vs. Player", expanded = true, children = {
        { id = 1901, name = "Honor Points", qty = 1500, icon = 111, max = 75000 },
        { id = 1900, name = "Arena Points", qty = 0, icon = 112 },
      } },
      { name = "Miscellaneous", expanded = false, children = {
        { id = 3001, name = "Merchant's Favor", qty = 42, icon = 113, noId = true },
      } },
    }
    installApi()
    char = { name = "Alt" }
    AltArmyTBC_Data.CurrencyMeta = nil
  end)

  after_each(function()
    _G.C_CurrencyInfo = nil
  end)

  it("reports the API", function()
    assert.is_true(DS.HasCurrencyListApi())
    _G.C_CurrencyInfo = nil
    assert.is_false(DS.HasCurrencyListApi())
  end)

  it("stores amounts (zeros too), including collapsed groups, via the link when there is no id", function()
    DS:ScanCurrencyList(char)
    assert.are.same({ [1901] = 1500, [1900] = 0, [3001] = 42 }, char.CurrencyList)
    assert.are.equal(DS._DATA_VERSIONS.currencyList, char.dataVersions.currencyList)
  end)

  it("saves account-wide details in native order", function()
    DS:ScanCurrencyList(char)
    local meta = DS:GetCurrencyMeta()
    assert.are.equal("Honor Points", meta[1901].name)
    assert.are.equal(111, meta[1901].icon)
    assert.are.equal(75000, meta[1901].max)
    assert.are.equal("Player vs. Player", meta[1901].header)
    assert.are.equal(1, meta[1901].headerOrder)
    assert.are.equal("Miscellaneous", meta[3001].header)
    assert.are.equal(2, meta[3001].headerOrder)
    assert.is_true(meta[1901].order < meta[1900].order)
  end)

  it("collapses headers that were collapsed before the scan", function()
    DS:ScanCurrencyList(char)
    assert.is_true(groups[1].expanded)
    assert.is_false(groups[2].expanded)
    assert.is_true(#expandCalls >= 2)
  end)

  it("does nothing without the API or a character", function()
    _G.C_CurrencyInfo = nil
    DS:ScanCurrencyList(char)
    assert.is_nil(char.CurrencyList)
    installApi()
    DS:ScanCurrencyList(nil)
  end)

  it("reads amounts back", function()
    DS:ScanCurrencyList(char)
    assert.are.equal(42, DS:GetCurrencyListAmount(char, 3001))
    assert.is_nil(DS:GetCurrencyListAmount(char, 9999))
    assert.is_nil(DS:GetCurrencyListAmount(nil, 3001))
  end)
end)
