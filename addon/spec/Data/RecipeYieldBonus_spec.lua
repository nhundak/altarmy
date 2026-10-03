--[[
  Unit tests for RecipeYieldBonus.lua.
  Run from project root: npm test
]]

describe("RecipeYieldBonus", function()
  local RYB
  local CD

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("Debug")
    require("CooldownData")
    require("RecipeInfo")
    package.loaded["RecipeYieldBonus"] = nil
    require("RecipeYieldBonus")
    RYB = AltArmy.RecipeYieldBonus
    CD = AltArmy.CooldownData
    assert.truthy(RYB)
  end)

  before_each(function()
    AltArmy.RecipeData = nil
    _G.GetItemInfo = nil
    _G.GetSpellInfo = nil
    _G.AltArmyTBC_Options = {}
    _G.AltArmyTBC_Data = {}
    _G.AltArmyTBC_GuildData = nil
    if AltArmy.Debug and AltArmy.Debug.Ensure then
      AltArmy.Debug.Ensure()
    end
    if AltArmy.RecipeInfo and AltArmy.RecipeInfo.ClearCaches then
      AltArmy.RecipeInfo.ClearCaches()
    end
  end)

  local function enableRecipeData()
    AltArmy.RecipeData = { recipes = {} }
  end

  describe("IsFeatureEnabled", function()
    it("returns false without recipe data", function()
      assert.is_false(RYB.IsFeatureEnabled())
    end)

    it("returns true when recipe data is loaded", function()
      enableRecipeData()
      assert.is_true(RYB.IsFeatureEnabled())
    end)
  end)

  describe("ResolveRecipeBonusLabel", function()
    it("maps cloth craft spell ids", function()
      assert.are.equal("Spellfire", RYB.ResolveRecipeBonusLabel(31373, nil))
      assert.are.equal("Shadoweave", RYB.ResolveRecipeBonusLabel(36686, nil))
      assert.are.equal("Mooncloth", RYB.ResolveRecipeBonusLabel(26751, nil))
    end)

    it("maps transmute spell ids", function()
      assert.are.equal("Transmute", RYB.ResolveRecipeBonusLabel(29688, nil))
      assert.is_true(CD.TRANSMUTE_SPELL_SET[29688] == true)
    end)

    it("maps potion and elixir/flask via GetItemInfo subclass", function()
      _G.GetItemInfo = function(itemId)
        if itemId == 22838 then
          -- Haste Potion
          return "Haste Potion", nil, 1, 1, 1, "Consumable", "Potion",
            5, "", nil, 0, 0, 1
        end
        if itemId == 13511 then
          -- Flask of Distilled Wisdom
          return "Flask of Distilled Wisdom", nil, 1, 1, 1, "Consumable", "Flask",
            5, "", nil, 0, 0, 3
        end
        if itemId == 22825 then
          return "Elixir of Healing Power", nil, 1, 1, 1, "Consumable", "Elixir",
            5, "", nil, 0, 0, 2
        end
        return nil
      end
      assert.are.equal("Potion", RYB.ResolveRecipeBonusLabel(99901, 22838))
      assert.are.equal("Elixir", RYB.ResolveRecipeBonusLabel(99902, 13511))
      assert.are.equal("Elixir", RYB.ResolveRecipeBonusLabel(99903, 22825))
    end)

    it("returns nil for unknown / non-bonus recipes", function()
      _G.GetItemInfo = function(itemId)
        if itemId == 6370 then
          return "Blackmouth Oil", nil, 1, 1, 1, "Consumable", "Other",
            5, "", nil, 0, 0, 8
        end
        return nil
      end
      assert.is_nil(RYB.ResolveRecipeBonusLabel(99999, 6370))
      assert.is_nil(RYB.ResolveRecipeBonusLabel(nil, nil))
    end)
  end)

  describe("FormatSpecialistPrefixMarkup", function()
    it("returns upgrade-badge green plus markup", function()
      assert.are.equal("|cff33ff33+|r ", RYB.FormatSpecialistPrefixMarkup())
    end)
  end)

  describe("GetMatchingSpecLabel", function()
    it("returns the spec when feature is on and recipe bonus matches", function()
      enableRecipeData()
      assert.are.equal("Potion", RYB.GetMatchingSpecLabel({
        _aaYieldBonusMatch = true,
        _aaCharSpecLabel = "Potion",
      }))
    end)

    it("returns nil when the character spec does not match the recipe", function()
      enableRecipeData()
      assert.is_nil(RYB.GetMatchingSpecLabel({
        _aaYieldBonusMatch = false,
        _aaCharSpecLabel = "Potion",
      }))
    end)

    it("returns nil without recipe data", function()
      assert.is_nil(RYB.GetMatchingSpecLabel({
        _aaYieldBonusMatch = true,
        _aaCharSpecLabel = "Potion",
      }))
    end)

    it("returns nil when the entry has no matching spec label", function()
      enableRecipeData()
      assert.is_nil(RYB.GetMatchingSpecLabel({ _aaYieldBonusMatch = true }))
      assert.is_nil(RYB.GetMatchingSpecLabel(nil))
    end)
  end)

  describe("StampEntry", function()
    it("no-ops without recipe data", function()
      local entry = {
        recipeID = 31373,
        characterName = "Tailor",
        professionName = "Tailoring",
        specialization = "Spellfire",
      }
      RYB.StampEntry(entry)
      assert.is_nil(entry._aaYieldBonusMatch)
      assert.is_nil(entry._aaRecipeBonusLabel)
    end)

    it("stamps match when char spec equals recipe bonus", function()
      enableRecipeData()
      local entry = {
        recipeID = 31373,
        characterName = "Tailor",
        realm = "R",
        professionName = "Tailoring",
        professionKey = "tailoring",
        isGuild = true,
      }
      _G.AltArmyTBC_GuildData = {
        chars = {
          R = {
            Tailor = {
              name = "Tailor",
              Professions = {
                tailoring = { key = "tailoring", name = "Tailoring", spec = "Spellfire", Recipes = {} },
              },
            },
          },
        },
      }
      RYB.StampEntry(entry)
      assert.are.equal("Spellfire", entry._aaRecipeBonusLabel)
      assert.are.equal("Spellfire", entry._aaCharSpecLabel)
      assert.is_true(entry._aaYieldBonusMatch)
    end)

    it("stamps non-match when char has a different spec", function()
      enableRecipeData()
      local entry = {
        recipeID = 31373,
        characterName = "Tailor",
        realm = "R",
        professionKey = "tailoring",
        isGuild = true,
      }
      _G.AltArmyTBC_GuildData = {
        chars = {
          R = {
            Tailor = {
              name = "Tailor",
              Professions = {
                tailoring = { key = "tailoring", spec = "Mooncloth", Recipes = {} },
              },
            },
          },
        },
      }
      RYB.StampEntry(entry)
      assert.are.equal("Spellfire", entry._aaRecipeBonusLabel)
      assert.are.equal("Mooncloth", entry._aaCharSpecLabel)
      assert.is_false(entry._aaYieldBonusMatch)
    end)
  end)
end)
