--[[
  Unit tests for GearScore.lua.
  Run from project root: npm test
]]

describe("GearScore", function()
  local GS
  local DS

  local function mockGetItemInfo(item)
    local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
    local items = {
      [100] = { "Head", nil, 3, 115, nil, "Armor", "Plate", nil, "INVTYPE_HEAD" },
      [101] = { "Chest", nil, 4, 128, nil, "Armor", "Plate", nil, "INVTYPE_CHEST" },
      [102] = { "Shirt", nil, 1, 1, nil, "Armor", "Cloth", nil, "INVTYPE_BODY" },
      [103] = { "Bow", nil, 3, 115, nil, "Weapon", "Bows", nil, "INVTYPE_RANGED" },
      [104] = { "Sword", nil, 3, 115, nil, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPONMAINHAND" },
    }
    local info = items[id]
    if not info then return end
    local link = "|cff|Hitem:" .. tostring(id) .. ":12345:0:0:0|h[" .. info[1] .. "]|h|r"
    return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
  end

  local function mockAddOnLoaded(name)
    return _G._mockLoadedAddons and _G._mockLoadedAddons[name] == true
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    if not _G.wipe then
      _G.wipe = function(t)
        for k in pairs(t) do t[k] = nil end
      end
    end
    _G._mockLoadedAddons = {}
    _G.C_AddOns = {
      IsAddOnLoaded = mockAddOnLoaded,
      GetNumAddOns = function() return 0 end,
      GetAddOnInfo = function() return nil end,
    }
    _G.GetAddOnMetadata = function(name, field)
      if field == "Title" then return name .. " Title" end
    end
    _G.GetItemInfo = mockGetItemInfo
    _G.TT_GS = nil
    _G.GearScoreCalc = nil
    _G.GEAR_SCORE_CACHE = nil
    _G.UnitGUID = function(unit)
      if unit == "player" then return "PlayerGUID-1" end
    end
    _G.UnitName = function(unit)
      if unit == "player" then return "TestChar" end
    end
    _G.GetRealmName = function() return "TestRealm" end
    _G.time = function() return 12345 end
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    package.loaded["GearScore"] = nil
    require("DataStore")
    require("DataStoreCharacter")
    require("DataStoreEquipment")
    require("GearScore")
    GS = AltArmy.GearScore
    DS = AltArmy.DataStore
  end)

  before_each(function()
    _G.TT_GS = nil
    _G.GearScoreCalc = nil
    _G.GEAR_SCORE_CACHE = nil
    _G._mockLoadedAddons = {}
    _G.AltArmyTBC_Data = { Characters = { TestRealm = { TestChar = {} } } }
    if GS and GS._ClearCache then GS._ClearCache() end
    if GS and GS.RefreshProviders then GS.RefreshProviders() end
  end)

  describe("providers", function()
    it("always includes level and ilvl providers", function()
      local providers = GS.GetAvailableProviders()
      assert.is_true(#providers >= 2)
      assert.are.equal("level", providers[1].id)
      assert.are.equal("Character Level", providers[1].label)
      assert.are.equal("ilvl", providers[2].id)
    end)

    it("includes Time Played provider at the end of the list", function()
      local providers = GS.GetAvailableProviders()
      local last = providers[#providers]
      assert.are.equal("played", last.id)
      assert.are.equal("Time Played", last.label)
      assert.are.equal("Time Played", last.sortLabel)
      assert.are.equal("Played", last.shortLabel)
    end)

    it("includes TacoTip provider when TT_GS is available", function()
      _G.TT_GS = {
        GetItemScore = function()
          return 50, 115, 0, 1, 0, "INVTYPE_HEAD"
        end,
      }
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore
      local found = false
      for _, p in ipairs(GS.GetAvailableProviders()) do
        if p.id == "gs_tacotip" then found = true end
      end
      assert.is_true(found)
    end)

    it("includes GearScoreTBCClassic provider when addon is loaded", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      local found = false
      for _, p in ipairs(GS.GetAvailableProviders()) do
        if p.id == "gs:GearScoreTBCClassic" then
          found = true
          assert.are.equal("Gear Score (GearScoreTBCClassic Title)", p.label)
        end
      end
      assert.is_true(found)
    end)

    it("includes separate providers for TacoTip and GearScoreTBCClassic when both are loaded", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      _G.TT_GS = {
        GetItemScore = function()
          return 50, 115, 0, 1, 0, "INVTYPE_HEAD"
        end,
      }
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      local ids = {}
      for _, p in ipairs(GS.GetAvailableProviders()) do
        ids[p.id] = p.label
      end
      assert.is_true(ids["gs_tacotip"] ~= nil)
      assert.is_true(ids["gs:GearScoreTBCClassic"] ~= nil)
    end)

    it("ignores other gearscore-named addons not on the supported list", function()
      _G._mockLoadedAddons["GearScoreClassic+"] = true
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      local ids = {}
      for _, p in ipairs(GS.GetAvailableProviders()) do
        ids[p.id] = true
      end
      assert.is_nil(ids["gs:GearScoreClassic+"])
      assert.is_false(GS.IsSupportedGearScoreAddon("GearScoreClassic+"))
      assert.is_true(GS.IsSupportedGearScoreAddon("GearScoreTBCClassic"))
    end)
  end)

  describe("ScoreCharacter played", function()
    it("returns play time from DataStore", function()
      local char = { played = 7200 }
      assert.are.equal(7200, GS.ScoreCharacter("played", char))
    end)
  end)

  describe("FormatDisplayScore played", function()
    it("formats as single-unit played time", function()
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
      require("SummaryData")
      assert.are.equal("2.0 h", GS.FormatDisplayScore("played", 7200))
      assert.are.equal("2.0 hours", GS.FormatDisplayScore("played", 7200, { playedUnitStyle = "full" }))
    end)
  end)

  describe("ScoreCharacter level", function()
    it("returns character level from stored data", function()
      local char = { level = 68 }
      assert.are.equal(68, GS.ScoreCharacter("level", char))
    end)
  end)

  describe("ScoreCharacter ilvl", function()
    it("matches DS:GetAverageItemLevel", function()
      local char = {
        Inventory = {
          [1] = 100,
          [5] = 101,
          [4] = 102,
          [19] = 102,
        },
      }
      local expected = DS:GetAverageItemLevel(char)
      assert.are.equal(expected, GS.ScoreCharacter("ilvl", char))
    end)
  end)

  describe("GearScoreTBCClassic capture and persist", function()
    it("ReadLivePlayerScoreTBCClassic calls OnPlayerEquipmentChanged and returns cached score", function()
      local called = false
      _G.GearScoreCalc = {
        OnPlayerEquipmentChanged = function()
          called = true
          _G.GEAR_SCORE_CACHE = { ["PlayerGUID-1"] = { 1234, 115 } }
        end,
      }
      _G.GEAR_SCORE_CACHE = {}
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      assert.are.equal(1234, GS.ReadLivePlayerScoreTBCClassic())
      assert.is_true(called)
    end)

    it("ReadLivePlayerScoreTBCClassic returns nil when addon globals are absent", function()
      _G.GearScoreCalc = nil
      _G.GEAR_SCORE_CACHE = nil
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      assert.is_nil(GS.ReadLivePlayerScoreTBCClassic())
    end)

    it("CaptureCurrentCharacterScore persists live value into current character", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      _G.GearScoreCalc = {
        OnPlayerEquipmentChanged = function()
          _G.GEAR_SCORE_CACHE = { ["PlayerGUID-1"] = { 5678, 120 } }
        end,
      }
      _G.GEAR_SCORE_CACHE = {}
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      GS.CaptureCurrentCharacterScore()
      local char = DS:GetCharacter("TestChar", "TestRealm")
      assert.are.equal(5678, char.gearScores.GearScoreTBCClassic)
      assert.are.equal(1, char.dataVersions.gearScores)
    end)

    it("CaptureCurrentCharacterScore does not overwrite existing value with 0", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      _G.GearScoreCalc = {
        OnPlayerEquipmentChanged = function()
          _G.GEAR_SCORE_CACHE = { ["PlayerGUID-1"] = { 0, 0 } }
        end,
      }
      _G.GEAR_SCORE_CACHE = {}
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      local char = DS:GetCharacter("TestChar", "TestRealm")
      char.gearScores = { GearScoreTBCClassic = 9999 }
      char.dataVersions = { gearScores = 1 }

      GS.CaptureCurrentCharacterScore()
      assert.are.equal(9999, char.gearScores.GearScoreTBCClassic)
    end)

    it("CaptureCurrentCharacterScore persists a legitimate zero score", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      _G.GearScoreCalc = {
        OnPlayerEquipmentChanged = function()
          _G.GEAR_SCORE_CACHE = { ["PlayerGUID-1"] = { 0, 0 } }
        end,
      }
      _G.GEAR_SCORE_CACHE = {}
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      GS.CaptureCurrentCharacterScore()
      local char = DS:GetCharacter("TestChar", "TestRealm")
      assert.are.equal(0, char.gearScores.GearScoreTBCClassic)
      assert.are.equal(1, char.dataVersions.gearScores)
    end)

    it("ScoreCharacter returns persisted gearScores value", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      local char = {
        gearScores = { GearScoreTBCClassic = 4321 },
        dataVersions = { gearScores = 1 },
      }
      assert.are.equal(4321, GS.ScoreCharacter("gs:GearScoreTBCClassic", char))
      assert.are.equal(0, GS.ScoreCharacter("gs:GearScoreTBCClassic", {}))
    end)
  end)

  describe("IsGearScoreTBCClassicAvailable", function()
    it("reflects addon-loaded state", function()
      assert.is_false(GS.IsGearScoreTBCClassicAvailable())
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      GS.RefreshProviders()
      assert.is_true(GS.IsGearScoreTBCClassicAvailable())
    end)
  end)

  describe("IsScoreMissing", function()
    it("returns true for GSTBC provider when no value recorded and addon available", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      GS.RefreshProviders()
      assert.is_true(GS.IsScoreMissing({}, "gs:GearScoreTBCClassic"))
    end)

    it("returns false when value exists", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      GS.RefreshProviders()
      local char = { gearScores = { GearScoreTBCClassic = 100 } }
      assert.is_false(GS.IsScoreMissing(char, "gs:GearScoreTBCClassic"))
    end)

    it("returns false when persisted value is zero", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      GS.RefreshProviders()
      local char = { gearScores = { GearScoreTBCClassic = 0 }, dataVersions = { gearScores = 1 } }
      assert.is_false(GS.IsScoreMissing(char, "gs:GearScoreTBCClassic"))
      assert.are.equal(0, GS.ScoreCharacter("gs:GearScoreTBCClassic", char))
    end)

    it("returns false for ilvl provider", function()
      assert.is_false(GS.IsScoreMissing({}, "ilvl"))
    end)
  end)

  describe("ScoreCharacter TacoTip aggregation", function()
    it("sums per-item scores and skips shirt slot 4", function()
      _G.TT_GS = {
        GetItemScore = function(link)
          local id = tonumber(tostring(link):match("item:(%d+)")) or link
          if id == 102 then return 999, 0 end
          return 10, 0
        end,
      }
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      local char = {
        classFile = "WARRIOR",
        Inventory = {
          [1] = 100,
          [4] = 102,
        },
      }
      assert.are.equal(10, GS.ScoreCharacter("gs_tacotip", char))
    end)

    it("applies hunter ranged weighting on slot 18", function()
      _G.TT_GS = {
        GetItemScore = function()
          return 10, 115, 0, 1, 0, "INVTYPE_RANGED"
        end,
      }
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      local char = {
        classFile = "HUNTER",
        Inventory = {
          [18] = 103,
        },
      }
      assert.are.equal(math.floor(10 * 5.3224), GS.ScoreCharacter("gs_tacotip", char))
    end)
  end)

  describe("GetProviderShortLabel", function()
    it("returns Gear Score for gear score providers", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      _G.TT_GS = {
        GetItemScore = function()
          return 50, 0
        end,
      }
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      assert.are.equal("Gear Score", GS.GetProviderShortLabel("gs_tacotip"))
      assert.are.equal("Gear Score", GS.GetProviderShortLabel("gs:GearScoreTBCClassic"))
      assert.are.equal("Item Level", GS.GetProviderShortLabel("ilvl"))
      assert.are.equal("Level", GS.GetProviderShortLabel("level"))
    end)
  end)

  describe("GetDisplayScoreColor", function()
    it("returns nil for level and ilvl providers", function()
      assert.is_nil(GS.GetDisplayScoreColor("level", 70))
      assert.is_nil(GS.GetDisplayScoreColor("ilvl", 120))
    end)

    it("uses TacoTip GetQuality for gs_tacotip scores", function()
      _G.TT_GS = {
        GetItemScore = function()
          return 50, 0
        end,
        GetQuality = function()
          return 0.69, 0.28, 0.97
        end,
      }
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      local r, g, b = GS.GetDisplayScoreColor("gs_tacotip", 1200)
      assert.are.equal(0.69, r)
      assert.are.equal(0.28, g)
      assert.are.equal(0.97, b)
    end)

    it("returns trash gray for zero GearScoreTBCClassic scores", function()
      local r, g, b = GS.GetDisplayScoreColor("gs:GearScoreTBCClassic", 0)
      assert.are.equal(0.55, r)
      assert.are.equal(0.55, g)
      assert.are.equal(0.55, b)
    end)

    it("interpolates GearScoreTBCClassic epic-band colors", function()
      local r, g, b = GS.GetDisplayScoreColor("gs:GearScoreTBCClassic", 1800)
      assert.is_true(r > 0.7 and r < 0.8)
      assert.is_true(g > 0.25 and g < 0.4)
      assert.is_true(b > 0.7)
    end)
  end)

  describe("DecorateEntry", function()
    it("populates entry.scores keyed by provider label", function()
      _G._mockLoadedAddons["GearScoreTBCClassic"] = true
      _G.TT_GS = {
        GetItemScore = function()
          return 25, 0
        end,
      }
      package.loaded["GearScore"] = nil
      require("GearScore")
      GS = AltArmy.GearScore

      local char = {
        classFile = "WARRIOR",
        Inventory = { [1] = 100 },
        gearScores = { GearScoreTBCClassic = 1500 },
        dataVersions = { gearScores = 1 },
      }
      local entry = { name = "Bob" }
      GS.DecorateEntry(entry, char)
      assert.is_number(entry.scores["Avg Item Level"])
      assert.are.equal(1500, entry.scores["Gear Score (GearScoreTBCClassic Title)"])
      assert.are.equal(25, entry.scores["Gear Score (TacoTip)"])
    end)
  end)
end)
