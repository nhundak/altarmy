--[[
  Unit tests for DataStoreCharacter.lua (rest XP, getters).
  Run from project root: npm test
]]

describe("DataStoreCharacter", function()
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
    require("DataStoreCharacter")
    DS = AltArmy.DataStore
  end)

  describe("GetStoredRestXp", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(DS:GetStoredRestXp(nil), 0)
    end)
    it("returns 0 at max level", function()
      assert.are.equal(DS:GetStoredRestXp({ level = 70, xpMax = 1000, restXP = 500 }), 0)
    end)
    it("returns 0 when xpMax <= 0", function()
      assert.are.equal(DS:GetStoredRestXp({ level = 1, xpMax = 0, restXP = 100 }), 0)
    end)
    it("returns min(100, (restXP/maxRest)*100)", function()
      local char = { level = 1, xpMax = 1000, restXP = 750 }
      local maxRest = 1000 * 1.5
      local expected = math.min(100, (750 / maxRest) * 100)
      assert.are.equal(expected, DS:GetStoredRestXp(char))
    end)
    it("caps at 100", function()
      local char = { level = 1, xpMax = 1000, restXP = 2000 }
      assert.are.equal(100, DS:GetStoredRestXp(char))
    end)
  end)

  describe("GetRestXp", function()
    it("returns 0 when char is nil", function()
      assert.are.equal(DS:GetRestXp(nil), 0)
    end)
    it("returns 0 at max level", function()
      assert.are.equal(DS:GetRestXp({ level = 70, xpMax = 1000, restXP = 500 }), 0)
    end)
    it("uses stored rate when lastLogout >= sentinel", function()
      local char = { level = 1, xpMax = 1000, restXP = 750, lastLogout = 5000000000 }
      local maxRest = 1000 * 1.5
      local expected = math.min(100, (750 / maxRest) * 100)
      assert.are.equal(expected, DS:GetRestXp(char))
    end)
  end)

  describe("getters", function()
    it("GetCharacterName returns name or empty", function()
      assert.are.equal("Alice", DS:GetCharacterName({ name = "Alice" }))
      assert.are.equal("", DS:GetCharacterName(nil))
      assert.are.equal("", DS:GetCharacterName({}))
    end)
    it("GetCharacterLevel returns level or 0", function()
      assert.are.equal(60, DS:GetCharacterLevel({ level = 60 }))
      assert.are.equal(0, DS:GetCharacterLevel(nil))
    end)
    it("GetMoney returns money or 0", function()
      assert.are.equal(1000, DS:GetMoney({ money = 1000 }))
      assert.are.equal(0, DS:GetMoney(nil))
    end)
    it("GetPlayTime returns played or 0", function()
      assert.are.equal(3600, DS:GetPlayTime({ played = 3600 }))
      assert.are.equal(0, DS:GetPlayTime(nil))
    end)
    it("GetLastLogout returns lastLogout or sentinel", function()
      assert.are.equal(123, DS:GetLastLogout({ lastLogout = 123 }))
      assert.are.equal(5000000000, DS:GetLastLogout(nil))
    end)
    it("GetCharacterClass returns class and classFile", function()
      local a, b = DS:GetCharacterClass({ class = "Warrior", classFile = "WARRIOR" })
      assert.are.equal("Warrior", a)
      assert.are.equal("WARRIOR", b)
      local c, d = DS:GetCharacterClass(nil)
      assert.are.equal("", c)
      assert.are.equal("", d)
    end)
    it("GetCharacterFaction returns faction or empty", function()
      assert.are.equal("Alliance", DS:GetCharacterFaction({ faction = "Alliance" }))
      assert.are.equal("", DS:GetCharacterFaction(nil))
    end)
  end)
end)
