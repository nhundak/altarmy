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

  it("include guildmates defaults to enabled and toggles", function()
    assert.is_true(SS.IsIncludeGuildmatesEnabled())
    SS.SetIncludeGuildmatesEnabled(false)
    assert.is_false(SS.IsIncludeGuildmatesEnabled())
    assert.is_false(AltArmyTBC_SearchSettings.includeGuildmates)
    SS.SetIncludeGuildmatesEnabled(true)
    assert.is_true(SS.IsIncludeGuildmatesEnabled())
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

  it("applies defaults for craft recipe filters", function()
    assert.is_false(SS.IsDifficultyFilterActive())
    assert.is_false(SS.IsSourceFilterActive())
    assert.is_false(SS.IsProfessionFilterActive())
    assert.is_false(SS.IsAnyRecipeFilterActive())
    local diff = SS.GetDifficultyFilter()
    assert.is_true(diff.orange and diff.yellow and diff.green and diff.gray)
    local src = SS.GetSourceFilter()
    for _, key in ipairs(SS.SOURCE_TYPES) do
      assert.is_true(src[key])
    end
    local prof = SS.GetProfessionFilter()
    for _, key in ipairs(SS.PROFESSION_KEYS) do
      assert.is_true(prof[key])
    end
  end)

  it("formats multi-select summary as All or comma-separated labels", function()
    assert.are.equal("All", SS.FormatMultiSelectFilterSummary(
      SS.SOURCE_TYPES,
      { trainer = "Trainer", vendor = "Vendor", quest = "Quest", drop = "Drop", reputation = "Reputation", starter = "Starter" },
      { trainer = true, vendor = true, quest = true, drop = true, reputation = true, starter = true }
    ))
    assert.are.equal("Trainer, Vendor", SS.FormatMultiSelectFilterSummary(
      { "trainer", "vendor", "drop" },
      { trainer = "Trainer", vendor = "Vendor", drop = "Drop" },
      { trainer = true, vendor = true, drop = false }
    ))
    assert.are.equal("None", SS.FormatMultiSelectFilterSummary(
      { "trainer" },
      { trainer = "Trainer" },
      { trainer = false }
    ))
  end)

  it("detects active difficulty filter when a band is disabled", function()
    SS.SetDifficultyBandEnabled("gray", false)
    assert.is_true(SS.IsDifficultyFilterActive())
    assert.is_true(SS.IsAnyRecipeFilterActive())
  end)

  it("detects active source filter when a source is disabled", function()
    SS.SetSourceTypeEnabled("drop", false)
    assert.is_true(SS.IsSourceFilterActive())
  end)

  it("detects active profession filter when a profession is disabled", function()
    SS.SetProfessionEnabled("alchemy", false)
    assert.is_true(SS.IsProfessionFilterActive())
    assert.is_true(SS.IsAnyRecipeFilterActive())
  end)

  it("resolves profession names via spell ids", function()
    SS._ClearProfessionKeyCache()
    _G.GetSpellInfo = function(spellId)
      if spellId == 2259 then return "Alchemy" end
      if spellId == 3908 then return "Tailoring" end
      if spellId == 2842 then return "Poisons" end
      return nil
    end
    assert.are.equal("alchemy", SS.ResolveProfessionKey("Alchemy"))
    assert.are.equal("tailoring", SS.ResolveProfessionKey("Tailoring"))
    assert.are.equal("poisons", SS.ResolveProfessionKey("Poisons"))
    assert.is_nil(SS.ResolveProfessionKey("Unknown Profession"))
    _G.GetSpellInfo = nil
  end)

  it("sorts profession dropdown keys alphabetically by label", function()
    local order = SS.GetProfessionDropdownOrder()
    assert.are.equal("Alchemy", SS.PROFESSION_LABELS[order[1]])
    assert.are.equal("Tailoring", SS.PROFESSION_LABELS[order[#order]])
  end)

  it("resets all recipe filters to defaults", function()
    SS.SetRecipeLevelFilterMin(200)
    SS.SetDifficultyBandEnabled("orange", false)
    SS.SetSourceTypeEnabled("vendor", false)
    SS.SetProfessionEnabled("engineering", false)
    SS.ResetAllRecipeFilters()
    assert.is_false(SS.IsAnyRecipeFilterActive())
    assert.is_true(SS.GetDifficultyFilter().orange)
    assert.is_true(SS.GetSourceFilter().vendor)
    assert.is_true(SS.GetProfessionFilter().engineering)
  end)
end)
