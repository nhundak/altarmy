--[[
  Unit tests for RecipeCraftLib.lua (CraftLib bridge).
  Run from project root: npm test
]]

describe("RecipeCraftLib", function()
  local RCL

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("RecipeCraftLib")
    RCL = AltArmy.RecipeCraftLib
  end)

  before_each(function()
    _G.CraftLib = nil
    if RCL and RCL.ClearCaches then
      RCL.ClearCaches()
    end
  end)

  describe("IsAvailable", function()
    it("returns false when CraftLib is missing", function()
      assert.is_false(RCL.IsAvailable())
    end)

    it("returns true when CraftLib is ready", function()
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function() return {} end,
      }
      assert.is_true(RCL.IsAvailable())
    end)
  end)

  describe("ResolveProfessionKey", function()
    it("maps localized profession name via GetSpellInfo", function()
      _G.GetSpellInfo = function(id)
        if id == 3273 then return "First Aid" end
        return nil
      end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return {
            firstAid = { id = 3273, name = "First Aid", recipes = {} },
          }
        end,
      }
      assert.are.equal("firstAid", RCL.ResolveProfessionKey("First Aid"))
    end)
  end)

  describe("LookupRecipe", function()
    it("finds recipe by spell id", function()
      _G.GetSpellInfo = function() return "Alchemy" end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return { alchemy = { id = 1, name = "Alchemy", recipes = {} } }
        end,
        GetRecipeBySpellId = function(_, profKey, spellId)
          if profKey == "alchemy" and spellId == 11449 then
            return { id = 11449, skillRequired = 180, skillRange = { yellow = 195, green = 210, gray = 225 } }
          end
          return nil
        end,
        GetRecipeByItemId = function() return nil end,
        GetRecipeByProduct = function() return nil end,
      }
      local recipe = RCL.LookupRecipe("Alchemy", 11449, nil)
      assert.is_not_nil(recipe)
      assert.are.equal(180, recipe.skillRequired)
    end)

    it("finds recipe by crafted item id when spell id lookup fails", function()
      _G.GetSpellInfo = function() return "Tailoring" end
      _G.GetItemSpell = function() return nil end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return { tailoring = { id = 1, name = "Tailoring", recipes = {} } }
        end,
        GetRecipeBySpellId = function() return nil end,
        GetRecipeByItemId = function(_, itemId)
          if itemId == 80240 then
            return { id = 26751, itemId = 80240, skillRequired = 180 }
          end
          return nil
        end,
        GetRecipeByProduct = function() return nil end,
      }
      local recipe = RCL.LookupRecipe("Tailoring", 80240, nil)
      assert.is_not_nil(recipe)
      assert.are.equal(180, recipe.skillRequired)
    end)

    it("resolves spell id from item id via GetItemSpell", function()
      _G.GetSpellInfo = function() return "Engineering" end
      _G.GetItemSpell = function(itemId)
        if itemId == 80240 then return "Recipe Name", 26751 end
        return nil
      end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return { engineering = { id = 1, name = "Engineering", recipes = {} } }
        end,
        GetRecipeBySpellId = function(_, profKey, spellId)
          if profKey == "engineering" and spellId == 26751 then
            return { id = 26751, skillRequired = 200 }
          end
          return nil
        end,
        GetRecipeByItemId = function() return nil end,
        GetRecipeByProduct = function() return nil end,
      }
      local recipe = RCL.LookupRecipe("Engineering", 80240, nil)
      assert.is_not_nil(recipe)
      assert.are.equal(200, recipe.skillRequired)
    end)
  end)

  describe("ExtractSkillRequired", function()
    it("accepts valid TBC skill levels", function()
      assert.are.equal(180, RCL.ExtractSkillRequired({ skillRequired = 180 }))
    end)

    it("rejects spell or item ids masquerading as skill levels", function()
      assert.is_nil(RCL.ExtractSkillRequired({ id = 80240, skillRequired = 80240 }))
      assert.is_nil(RCL.ExtractSkillRequired({ id = 11449, skillRequired = nil }))
    end)

    it("falls back to skillRange thresholds when skillRequired is invalid", function()
      assert.are.equal(375, RCL.ExtractSkillRequired({
        skillRequired = 0,
        skillRange = { orange = 375, yellow = 390, green = 405, gray = 420 },
      }))
    end)

    it("uses 75 when orange threshold is zero and no other band is valid", function()
      assert.are.equal(75, RCL.ExtractSkillRequired({
        skillRequired = nil,
        skillRange = { orange = 0, yellow = 0, green = 0, gray = 0 },
      }))
    end)
  end)

  describe("NormalizeRecipeSource", function()
    it("lowercases known CraftLib source strings", function()
      assert.are.equal("trainer", RCL.NormalizeRecipeSource("TRAINER"))
      assert.are.equal("vendor", RCL.NormalizeRecipeSource("vendor"))
      assert.are.equal("reputation", RCL.NormalizeRecipeSource("REPUTATION"))
    end)

    it("reads type from CraftLib source objects", function()
      assert.are.equal("trainer", RCL.NormalizeRecipeSource({ type = "trainer", npcName = "Any Trainer" }))
      assert.are.equal("vendor", RCL.NormalizeRecipeSource({ type = "VENDOR", itemId = 6325 }))
      assert.are.equal("drop", RCL.NormalizeRecipeSource({ type = "drop", itemId = 16045 }))
      assert.are.equal("drop", RCL.NormalizeRecipeSource({ type = "world_drop", itemId = 16045 }))
    end)

    it("returns nil for unknown or empty source", function()
      assert.is_nil(RCL.NormalizeRecipeSource(nil))
      assert.is_nil(RCL.NormalizeRecipeSource(""))
      assert.is_nil(RCL.NormalizeRecipeSource("DISCOVERY"))
      assert.is_nil(RCL.NormalizeRecipeSource({ type = "DISCOVERY" }))
      assert.is_nil(RCL.NormalizeRecipeSource({ npcName = "Missing type" }))
    end)
  end)

  describe("NormalizeRecipeExpansion", function()
    it("maps vanilla expansion values", function()
      assert.are.equal("vanilla", RCL.NormalizeRecipeExpansion(0))
      assert.are.equal("vanilla", RCL.NormalizeRecipeExpansion("classic"))
      assert.are.equal("vanilla", RCL.NormalizeRecipeExpansion("vanilla"))
    end)

    it("maps tbc expansion values", function()
      assert.are.equal("tbc", RCL.NormalizeRecipeExpansion(1))
      assert.are.equal("tbc", RCL.NormalizeRecipeExpansion(2))
      assert.are.equal("tbc", RCL.NormalizeRecipeExpansion("tbc"))
      assert.are.equal("tbc", RCL.NormalizeRecipeExpansion("burning_crusade"))
    end)

    it("returns nil for unknown expansion", function()
      assert.is_nil(RCL.NormalizeRecipeExpansion(nil))
      assert.is_nil(RCL.NormalizeRecipeExpansion("wotlk"))
    end)
  end)

  describe("GetReagentList", function()
    it("copies itemId and count from CraftLib reagents", function()
      local list = RCL.GetReagentList({
        reagents = {
          { itemId = 123, name = "Herb", count = 2 },
          { itemId = 456, count = 1 },
        },
      })
      assert.are.equal(2, #list)
      assert.are.equal(123, list[1].itemId)
      assert.are.equal(2, list[1].count)
      assert.are.equal(456, list[2].itemId)
      assert.are.equal(1, list[2].count)
    end)

    it("returns empty list when reagents missing", function()
      assert.are.same({}, RCL.GetReagentList({}))
      assert.are.same({}, RCL.GetReagentList(nil))
    end)
  end)

  describe("EnrichEntry", function()
    it("does not set recipeSkillRequired when only recipe id is available", function()
      _G.GetSpellInfo = function() return "Alchemy" end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return { alchemy = { id = 1, name = "Alchemy", recipes = {} } }
        end,
        GetRecipeBySpellId = function(_, _, spellId)
          if spellId == 80240 then
            return { id = 80240, skillRequired = 80240 }
          end
          return nil
        end,
        GetRecipeByItemId = function() return nil end,
        GetRecipeByProduct = function() return nil end,
      }
      local entry = {
        professionName = "Alchemy",
        recipeID = 80240,
        skillRank = 375,
      }
      RCL.EnrichEntry(entry)
      assert.is_nil(entry.recipeSkillRequired)
      assert.is_nil(entry.difficulty)
    end)

    it("sets source expansion and reagents when recipe resolves", function()
      _G.GetSpellInfo = function() return "Alchemy" end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return { alchemy = { id = 1, name = "Alchemy", recipes = {} } }
        end,
        GetRecipeBySpellId = function(_, profKey, spellId)
          if profKey == "alchemy" and spellId == 11449 then
            return {
              id = 11449,
              skillRequired = 180,
              skillRange = { yellow = 195, green = 210, gray = 225 },
              source = { type = "trainer", npcName = "Any Alchemy Trainer" },
              expansion = 1,
              reagents = { { itemId = 999, count = 1 } },
            }
          end
          return nil
        end,
        GetRecipeByItemId = function() return nil end,
        GetRecipeByProduct = function() return nil end,
        GetRecipeDifficulty = function(_, _, skill)
          if skill >= 210 then return "green" end
          return "yellow"
        end,
      }
      local entry = {
        professionName = "Alchemy",
        recipeID = 11449,
        skillRank = 220,
      }
      RCL.EnrichEntry(entry)
      assert.are.equal(180, entry.recipeSkillRequired)
      assert.are.equal("green", entry.difficulty)
      assert.are.equal("trainer", entry.recipeSource)
      assert.are.equal("tbc", entry.recipeExpansion)
      assert.are.equal(1, #entry.recipeReagents)
      assert.are.equal(999, entry.recipeReagents[1].itemId)
    end)

    it("backfills resultItemID from CraftLib itemId when missing", function()
      _G.GetSpellInfo = function() return "Alchemy" end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return { alchemy = { id = 1, name = "Alchemy", recipes = {} } }
        end,
        GetRecipeBySpellId = function(_, profKey, spellId)
          if profKey == "alchemy" and spellId == 7837 then
            return {
              id = 7837,
              itemId = 6370,
              skillRequired = 80,
            }
          end
          return nil
        end,
        GetRecipeByItemId = function() return nil end,
        GetRecipeByProduct = function() return nil end,
      }
      local entry = {
        professionName = "Alchemy",
        recipeID = 7837,
        skillRank = 300,
        isGuild = true,
      }
      RCL.EnrichEntry(entry)
      assert.are.equal(6370, entry.resultItemID)
    end)

    it("does not overwrite an existing resultItemID", function()
      _G.GetSpellInfo = function() return "Alchemy" end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return { alchemy = { id = 1, name = "Alchemy", recipes = {} } }
        end,
        GetRecipeBySpellId = function(_, profKey, spellId)
          if profKey == "alchemy" and spellId == 7837 then
            return {
              id = 7837,
              itemId = 6370,
              skillRequired = 80,
            }
          end
          return nil
        end,
        GetRecipeByItemId = function() return nil end,
        GetRecipeByProduct = function() return nil end,
      }
      local entry = {
        professionName = "Alchemy",
        recipeID = 7837,
        skillRank = 300,
        resultItemID = 9999,
      }
      RCL.EnrichEntry(entry)
      assert.are.equal(9999, entry.resultItemID)
    end)

    it("skips CraftLib lookup for poisons to avoid item id collisions", function()
      _G.GetSpellInfo = function(id)
        if id == 2842 then return "Poisons" end
        return nil
      end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return { tailoring = { id = 1, name = "Tailoring", recipes = {} } }
        end,
        GetRecipeBySpellId = function()
          return nil
        end,
        GetRecipeByItemId = function(_, itemId)
          if itemId == 5763 then
            return {
              id = 999,
              skillRequired = 115,
              skillRange = { orange = 115, yellow = 130, green = 145, gray = 160 },
            }
          end
          return nil
        end,
        GetRecipeByProduct = function() return nil end,
      }
      local entry = {
        professionName = "Poisons",
        recipeID = 5763,
        skillRank = 340,
      }
      RCL.EnrichEntry(entry)
      assert.is_nil(entry.recipeSkillRequired)
      assert.is_nil(entry.difficulty)
      assert.is_nil(entry.recipeSource)
    end)
  end)

  describe("GetDifficulty", function()
    it("returns orange below yellow threshold", function()
      local recipe = { skillRange = { yellow = 200, green = 215, gray = 230 } }
      assert.are.equal("orange", RCL.GetDifficulty(recipe, 180))
      assert.are.equal("yellow", RCL.GetDifficulty(recipe, 205))
      assert.are.equal("green", RCL.GetDifficulty(recipe, 220))
      assert.are.equal("gray", RCL.GetDifficulty(recipe, 240))
    end)
  end)

  describe("FormatSkillCell", function()
    it("returns player skill only when recipe level unknown", function()
      assert.are.equal("375", RCL.FormatSkillCell(nil, 375, nil))
      assert.are.equal("375", RCL.FormatSkillCell(80240, 375, "orange"))
      assert.are.equal("—", RCL.FormatSkillCell(nil, 0, nil))
    end)

    it("returns colored recipe/player when recipe level known", function()
      local text = RCL.FormatSkillCell(180, 375, "yellow")
      assert.is_truthy(text:find("180", 1, true))
      assert.is_truthy(text:find("/375", 1, true))
      assert.is_truthy(text:find("|cffffff00", 1, true))
      assert.is_truthy(text:find("|r/375", 1, true))
    end)
  end)
end)
