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
