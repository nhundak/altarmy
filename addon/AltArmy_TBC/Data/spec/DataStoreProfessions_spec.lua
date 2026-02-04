--[[
  Unit tests for DataStoreProfessions.lua (getters).
  Run from project root: npm test
]]

describe("DataStoreProfessions", function()
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
    require("DataStoreProfessions")
    DS = AltArmy.DataStore
  end)

  describe("GetProfessions", function()
    it("returns empty when char nil", function()
      assert.are.same({}, DS:GetProfessions(nil))
    end)
    it("returns char.Professions or empty", function()
      local profs = { Mining = { rank = 300, maxRank = 375 } }
      local char = { Professions = profs }
      assert.are.same(profs, DS:GetProfessions(char))
      assert.are.same({}, DS:GetProfessions({}))
    end)
  end)

  describe("GetProfession", function()
    it("returns nil when char or name nil", function()
      assert.is_nil(DS:GetProfession(nil, "Mining"))
      assert.is_nil(DS:GetProfession({ Professions = {} }, nil))
    end)
    it("returns profession table when present", function()
      local prof = { rank = 300, maxRank = 375 }
      local char = { Professions = { Mining = prof } }
      assert.are.same(prof, DS:GetProfession(char, "Mining"))
    end)
  end)

  describe("GetProfession1 / GetProfession2", function()
    it("returns 0, 0, nil when char nil", function()
      local r, m, n = DS:GetProfession1(nil)
      assert.are.equal(0, r)
      assert.are.equal(0, m)
      assert.is_nil(n)
    end)
    it("returns rank, maxRank, name for Prof1", function()
      local char = { Prof1 = "Mining", Professions = { Mining = { rank = 300, maxRank = 375 } } }
      local r, m, n = DS:GetProfession1(char)
      assert.are.equal(300, r)
      assert.are.equal(375, m)
      assert.are.equal("Mining", n)
    end)
    it("returns 0, 0, name when prof missing", function()
      local char = { Prof1 = "Mining", Professions = {} }
      local r, m, n = DS:GetProfession1(char)
      assert.are.equal(0, r)
      assert.are.equal(0, m)
      assert.are.equal("Mining", n)
    end)
    it("GetProfession2 returns rank, maxRank, name", function()
      local char = { Prof2 = "Herbalism", Professions = { Herbalism = { rank = 350, maxRank = 375 } } }
      local r, m, n = DS:GetProfession2(char)
      assert.are.equal(350, r)
      assert.are.equal(375, m)
      assert.are.equal("Herbalism", n)
    end)
  end)

  describe("GetNumRecipes", function()
    it("returns 0 when char or profName nil", function()
      assert.are.equal(0, DS:GetNumRecipes(nil, "Mining"))
      assert.are.equal(0, DS:GetNumRecipes({ Professions = {} }, nil))
    end)
    it("returns count of Recipes", function()
      local char = { Professions = { Mining = { Recipes = { [1] = 1, [2] = 1, [3] = 1 } } } }
      assert.are.equal(3, DS:GetNumRecipes(char, "Mining"))
    end)
    it("returns 0 when prof or Recipes missing", function()
      assert.are.equal(0, DS:GetNumRecipes({ Professions = {} }, "Mining"))
      assert.are.equal(0, DS:GetNumRecipes({ Professions = { Mining = {} } }, "Mining"))
    end)
  end)

  describe("IsRecipeKnown", function()
    it("returns false when char or profName or spellID nil", function()
      assert.is_false(DS:IsRecipeKnown(nil, "Mining", 123))
      assert.is_false(DS:IsRecipeKnown({ Professions = {} }, nil, 123))
      assert.is_false(DS:IsRecipeKnown({ Professions = {} }, "Mining", nil))
    end)
    it("returns true when recipe in prof.Recipes", function()
      local char = { Professions = { Mining = { Recipes = { [123] = 1 } } } }
      assert.is_true(DS:IsRecipeKnown(char, "Mining", 123))
    end)
    it("returns false when recipe not in prof.Recipes", function()
      local char = { Professions = { Mining = { Recipes = { [123] = 1 } } } }
      assert.is_false(DS:IsRecipeKnown(char, "Mining", 999))
    end)
  end)
end)
