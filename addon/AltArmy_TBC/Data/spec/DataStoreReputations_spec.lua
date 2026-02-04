--[[
  Unit tests for DataStoreReputations.lua (GetReputationLimits, GetReputationInfo).
  Run from project root: npm test
]]

describe("DataStoreReputations", function()
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
    require("DataStoreReputations")
    DS = AltArmy.DataStore
  end)

  describe("_GetReputationLimits", function()
    it("returns 0, 36000 for earned 0", function()
      local bottom, top = DS._GetReputationLimits(0)
      assert.are.equal(bottom, 0)
      assert.are.equal(top, 36000)
    end)
    it("returns 36000, 78000 for earned in Friendly range", function()
      local bottom, top = DS._GetReputationLimits(50000)
      assert.are.equal(bottom, 36000)
      assert.are.equal(top, 78000)
    end)
    it("returns 192000, 42000 for exalted (top cap)", function()
      local bottom, top = DS._GetReputationLimits(200000)
      assert.are.equal(bottom, 192000)
      assert.are.equal(top, 42000)
    end)
  end)

  describe("GetReputationInfo", function()
    it("returns nil, 0, 0, 0 when char or faction missing", function()
      local s, re = DS:GetReputationInfo(nil, 1)
      assert.is_nil(s)
      assert.are.equal(0, re)
      s, re = DS:GetReputationInfo({ Reputations = {} }, nil)
      assert.is_nil(s)
      assert.are.equal(0, re)
    end)
    it("returns nil, 0, 0, 0 when faction not in char", function()
      local s, re = DS:GetReputationInfo({ Reputations = {} }, 123)
      assert.is_nil(s)
      assert.are.equal(0, re)
    end)
    it("returns standing, repEarned, nextLevel, rate for known faction", function()
      local char = { Reputations = { [123] = 50000 } }
      local standing, repEarned, nextLevel, rate = DS:GetReputationInfo(char, 123)
      assert.are.equal("Friendly", standing)
      assert.are.equal(50000 - 36000, repEarned)
      assert.are.equal(78000 - 36000, nextLevel)
      assert.truthy(rate > 0 and rate <= 100)
    end)
  end)
end)
