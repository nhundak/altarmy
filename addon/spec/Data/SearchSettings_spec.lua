--[[
  Unit tests for SearchSettings.lua.
  Run from project root: npm test
]]

describe("SearchSettings", function()
  local SS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_SearchSettings = nil
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("SearchSettings")
    SS = AltArmy.SearchSettings
  end)

  before_each(function()
    _G.AltArmyTBC_SearchSettings = nil
  end)

  it("applies defaults for recipe level filter", function()
    local f = SS.GetRecipeLevelFilter()
    assert.are.equal(0, f.min)
    assert.are.equal(375, f.max)
    assert.is_false(SS.IsRecipeLevelFilterActive(f))
  end)

  it("clamps min and max to 0-375", function()
    _G.AltArmyTBC_SearchSettings = {
      recipeLevelFilter = { min = -5, max = 999 },
    }
    local f = SS.GetRecipeLevelFilter()
    assert.are.equal(0, f.min)
    assert.are.equal(375, f.max)
  end)

  it("swaps min and max when inverted", function()
    _G.AltArmyTBC_SearchSettings = {
      recipeLevelFilter = { min = 300, max = 100 },
    }
    local f = SS.GetRecipeLevelFilter()
    assert.are.equal(100, f.min)
    assert.are.equal(300, f.max)
    assert.is_true(SS.IsRecipeLevelFilterActive(f))
  end)

  it("treats non-default min or max as an active filter", function()
    SS.SetRecipeLevelFilterMin(200)
    assert.is_true(SS.IsRecipeLevelFilterActive())
    _G.AltArmyTBC_SearchSettings = nil
    SS.SetRecipeLevelFilterMax(300)
    assert.is_true(SS.IsRecipeLevelFilterActive())
  end)

  it("resets recipe level filter to 0-375", function()
    SS.SetRecipeLevelFilterMin(200)
    SS.SetRecipeLevelFilterMax(300)
    SS.ResetRecipeLevelFilter()
    local f = SS.GetRecipeLevelFilter()
    assert.are.equal(0, f.min)
    assert.are.equal(375, f.max)
    assert.is_false(SS.IsRecipeLevelFilterActive(f))
  end)
end)
