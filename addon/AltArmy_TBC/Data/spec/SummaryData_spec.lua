--[[
  Unit tests for SummaryData.lua (formatting helpers).
  Run from project root: npm test
]]

describe("SummaryData", function()
  local SD

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("SummaryData")
    SD = AltArmy.SummaryData
  end)

  describe("GetMoneyString", function()
    it("formats copper only", function()
      local s = SD.GetMoneyString(99)
      assert.truthy(s:find("99"))
      assert.truthy(s:find("|t"))
    end)
    it("formats silver and copper when no gold", function()
      local s = SD.GetMoneyString(150)
      assert.truthy(s:find("1"))
      assert.truthy(s:find("50"))
    end)
    it("formats gold, silver, copper", function()
      local s = SD.GetMoneyString(10000)
      assert.truthy(s:find("1"))
      assert.truthy(s:find("0"))
    end)
    it("treats nil as 0", function()
      local s = SD.GetMoneyString(nil)
      assert.truthy(s:find("0"))
    end)
  end)

  describe("FormatRestXp", function()
    it("returns empty string for nil", function()
      assert.are.equal(SD.FormatRestXp(nil), "")
    end)
    it("rounds to one decimal", function()
      assert.are.equal(SD.FormatRestXp(50.34), "50.3%")
      assert.are.equal(SD.FormatRestXp(50.36), "50.4%")
    end)
    it("formats integer rate", function()
      assert.are.equal(SD.FormatRestXp(100), "100.0%")
    end)
  end)

  describe("GetTimeString", function()
    it("uses fallback when SecondsToTime missing", function()
      local old = _G.SecondsToTime
      _G.SecondsToTime = nil
      local s = SD.GetTimeString(0)
      assert.truthy(s:find("0"))
      assert.truthy(s:find("m"))
      _G.SecondsToTime = old
    end)
    it("fallback formats days and hours", function()
      local old = _G.SecondsToTime
      _G.SecondsToTime = nil
      local s = SD.GetTimeString(90061)
      assert.truthy(s:find("1d") or s:find("1"))
      _G.SecondsToTime = old
    end)
    it("treats nil as 0", function()
      local old = _G.SecondsToTime
      _G.SecondsToTime = nil
      local s = SD.GetTimeString(nil)
      assert.truthy(#s > 0)
      _G.SecondsToTime = old
    end)
  end)

  describe("FormatLastOnline", function()
    it("returns Online when isCurrent", function()
      assert.are.equal(SD.FormatLastOnline(nil, true), "Online")
      assert.are.equal(SD.FormatLastOnline(0, true), "Online")
    end)
    it("returns Unknown when lastLogout is nil", function()
      assert.are.equal(SD.FormatLastOnline(nil, false), "Unknown")
    end)
    it("returns Unknown when lastLogout >= sentinel", function()
      assert.are.equal(SD.FormatLastOnline(5000000000, false), "Unknown")
      assert.are.equal(SD.FormatLastOnline(6000000000, false), "Unknown")
    end)
    it("returns Just now when ago < 60 seconds", function()
      local old = _G.time
      _G.time = function() return 100 end
      assert.are.equal(SD.FormatLastOnline(50, false), "Just now")
      _G.time = old
    end)
    it("returns Xm ago when ago in minutes", function()
      local old = _G.time
      _G.time = function() return 1000 end
      local s = SD.FormatLastOnline(100)
      assert.truthy(s:find("ago"))
      assert.truthy(s:find("m") or s:find("h") or s:find("d"))
      _G.time = old
    end)
  end)

  describe("GetMissingDataInfo", function()
    local DS

    before_each(function()
      DS = _G.AltArmy.DataStore
      if not DS then
        _G.AltArmy.DataStore = {}
        DS = _G.AltArmy.DataStore
      end
    end)

    it("returns no missing when char is nil", function()
      local oldGetCharacter = DS and DS.GetCharacter
      DS.GetCharacter = function(_, _name, _realm) return nil end
      local out = SD.GetMissingDataInfo("Alice", "Realm1")
      assert.is_false(out.hasMissing)
      assert.are.same(out.instructions, {})
      if oldGetCharacter then DS.GetCharacter = oldGetCharacter end
    end)

    it("returns no missing when all modules have data", function()
      local char = {
        dataVersions = {
          character = 1, containers = 1, equipment = 1, professions = 1,
          reputations = 1, mail = 1, auctions = 1, currencies = 1,
        },
        Professions = { Alchemy = { rank = 100, maxRank = 300, Recipes = { [1] = true } } },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local out = SD.GetMissingDataInfo("Alice", "Realm1")
      assert.is_false(out.hasMissing)
      assert.are.same(out.instructions, {})
    end)

    it("adds Skills instruction when professions module missing (current character)", function()
      local char = { dataVersions = { character = 1, containers = 1, equipment = 1 } }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, _c) return {} end
      DS.GetNumRecipes = function() return 0 end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Skills") then found = true break end
      end
      assert.is_true(found, "expected an instruction containing 'Skills'")
    end)

    it("adds Log in with this character when alt has missing data", function()
      local char = { dataVersions = { character = 1 } }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, _c) return {} end
      DS.GetNumRecipes = function() return 0 end
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Alice" or nil end
      _G.GetRealmName = function() return "Realm1" end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Log in with this character") then found = true break end
      end
      assert.is_true(found, "expected 'Log in with this character' for alt")
    end)

    it("adds Open your Alchemy window when profession has no recipes", function()
      local char = {
        dataVersions = { character = 1, professions = 1 },
        Professions = { Alchemy = { rank = 50, maxRank = 300, Recipes = {} } },
      }
      DS.GetCharacter = function(_, _name, _realm) return char end
      DS.HasModuleData = function(_, c, mod) return (c.dataVersions and c.dataVersions[mod]) == 1 end
      DS.GetProfessions = function(_, c) return c.Professions or {} end
      DS.GetNumRecipes = function(_, c, profName)
        local p = c.Professions and c.Professions[profName]
        if not p or not p.Recipes then return 0 end
        local n = 0
        for _ in pairs(p.Recipes) do n = n + 1 end
        return n
      end
      local out = SD.GetMissingDataInfo("Bob", "Realm1")
      assert.is_true(out.hasMissing)
      local found = false
      for _, line in ipairs(out.instructions) do
        if line:find("Alchemy") then found = true break end
      end
      assert.is_true(found, "expected an instruction containing 'Alchemy'")
    end)
  end)
end)
