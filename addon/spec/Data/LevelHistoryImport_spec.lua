--[[
  Unit tests for level history import adapters.
  Run from project root: npm test
]]

describe("LevelHistoryImport", function()
  local DS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = { Characters = {} }
    _G.AltArmyTBC_Options = {}
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.time = _G.time or function() return 1700000000 end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("Debug")
    require("DataStore")
    require("DataStoreLevelHistory")
    DS = AltArmy.DataStore
    DS._ResetLevelHistoryTestState()
  end)

  before_each(function()
    _G.AltArmyTBC_Options = {}
    AltArmy.Debug.Ensure()
    DS._ResetLevelHistoryTestState()
  end)

  local function enableLevelHistoryDebug()
    AltArmy.Debug.SetEnabled(true)
    AltArmy.Debug.SetLevelHistoryEnabled(true)
  end

  describe("ImportLevelHistoryFromQuestie", function()
    it("imports only reachedAt from Level journey events", function()
      local char = { name = "Bob", realm = "Faerlina" }
      local questieData = {
        journey = {
          { Event = "Quest", SubType = "Complete", Quest = 1, Level = 5, Timestamp = 100 },
          { Event = "Level", NewLevel = 6, Timestamp = 200 },
          { Event = "Level", NewLevel = 7, Timestamp = 300 },
        },
      }
      DS:ImportLevelHistoryFromQuestie(char, questieData)
      assert.are.equal(200, char.levelHistory.milestones[6].reachedAt)
      assert.are.equal(300, char.levelHistory.milestones[7].reachedAt)
      assert.is_nil(char.levelHistory.milestones[6].playedTotal)
    end)

    it("does not overwrite existing milestones", function()
      local char = {
        levelHistory = { milestones = { [6] = { reachedAt = 999 } }, meta = {}, deaths = {} },
      }
      DS:ImportLevelHistoryFromQuestie(char, {
        journey = { { Event = "Level", NewLevel = 6, Timestamp = 200 } },
      })
      assert.are.equal(999, char.levelHistory.milestones[6].reachedAt)
    end)
  end)

  describe("_ResolveRxpTrackingProfile", function()
    local oldUnitName, oldGetRealmName

    before_each(function()
      oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit)
        return unit == "player" and "Bob" or nil
      end
      _G.GetRealmName = function()
        return "Faerlina"
      end
    end)

    after_each(function()
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      _G.RXPCTrackingData = nil
    end)

    it("reads AceDB character profile from RXPCTrackingData.profiles", function()
      local profile = { levels = { [1] = { timestamp = { finished = 100 } } } }
      _G.RXPCTrackingData = {
        profileKeys = { ["Bob - Faerlina"] = "Bob - Faerlina" },
        profiles = { ["Bob - Faerlina"] = profile },
      }
      local resolved, source = DS._ResolveRxpTrackingProfile()
      assert.are.same(profile, resolved)
      assert.matches("profiles%[Bob %- Faerlina%]", source)
    end)

    it("falls back to RXPCTrackingData.profile for legacy saves", function()
      local profile = { levels = { [1] = { timestamp = { finished = 100 } } } }
      _G.RXPCTrackingData = { profile = profile }
      local resolved = DS._ResolveRxpTrackingProfile()
      assert.are.same(profile, resolved)
    end)
  end)

  describe("ImportLevelHistoryFromRXP", function()
    it("imports native milestone fields only", function()
      local char = { name = "Bob", realm = "Faerlina" }
      local profile = {
        levels = {
          [5] = {
            timestamp = {
              started = 1000,
              finished = 2500,
              dateFinished = { year = 2024, month = 6, monthDay = 15, hour = 14, minute = 30 },
            },
            deaths = 2,
            quests = { ["Zone"] = { [123] = 500 } },
            mobs = { ["Zone"] = { xp = 800, count = 10 } },
            groupExperience = 200,
          },
        },
      }
      DS:ImportLevelHistoryFromRXP(char, profile)
      local m = char.levelHistory.milestones[6]
      assert.are.equal(2500, m.playedTotal)
      assert.are.equal(1500, m.playedLevel)
      assert.are.equal(2, m.deaths)
      assert.is_not_nil(m.reachedAt)
      assert.is_nil(m.questXp)
      assert.is_nil(m.mobXp)
      assert.is_nil(m.groupXp)
    end)

    it("does not overwrite existing milestone fields", function()
      local char = {
        levelHistory = {
          milestones = { [6] = { playedTotal = 999, deaths = 1 } },
          meta = {},
          deaths = {},
        },
      }
      DS:ImportLevelHistoryFromRXP(char, {
        levels = {
          [5] = {
            timestamp = { started = 1000, finished = 2500 },
            deaths = 5,
          },
        },
      })
      assert.are.equal(999, char.levelHistory.milestones[6].playedTotal)
      assert.are.equal(1, char.levelHistory.milestones[6].deaths)
    end)
  end)

  describe("_CalendarToUnix", function()
    it("converts calendar table to unix time", function()
      local unix = DS._CalendarToUnix({
        year = 2024,
        month = 1,
        monthDay = 1,
        hour = 12,
        minute = 0,
      })
      assert.is_number(unix)
      assert.is_true(unix > 0)
    end)

    it("returns nil for invalid calendar", function()
      assert.is_nil(DS._CalendarToUnix(nil))
      assert.is_nil(DS._CalendarToUnix({ month = 1 }))
    end)
  end)

  describe("RunLevelHistoryBackfill", function()
    it("runs Questie import once account-wide", function()
      _G.AltArmyTBC_Data.levelHistoryImport = nil
      _G.QuestieConfig = {
        char = {
          ["Bob - Faerlina"] = {
            journey = { { Event = "Level", NewLevel = 5, Timestamp = 500 } },
          },
        },
      }
      AltArmyTBC_Data.Characters = {
        Faerlina = { Bob = { name = "Bob", realm = "Faerlina" } },
      }
      DS._SetLevelHistoryTestChar(AltArmyTBC_Data.Characters.Faerlina.Bob)
      DS:RunLevelHistoryBackfill()
      assert.is_not_nil(AltArmyTBC_Data.levelHistoryImport.questieAt)
      assert.are.equal(500, AltArmyTBC_Data.Characters.Faerlina.Bob.levelHistory.milestones[5].reachedAt)

      _G.QuestieConfig.char["Bob - Faerlina"].journey = {
        { Event = "Level", NewLevel = 6, Timestamp = 600 },
      }
      DS:RunLevelHistoryBackfill()
      assert.is_nil(AltArmyTBC_Data.Characters.Faerlina.Bob.levelHistory.milestones[6])
    end)

    it("runs RXP import once per character", function()
      _G.AltArmyTBC_Data.levelHistoryImport = { questieAt = 1 }
      local char = { name = "Bob", realm = "Faerlina" }
      DS._SetLevelHistoryTestChar(char)
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Faerlina" end
      _G.RXPCTrackingData = {
        profileKeys = { ["Bob - Faerlina"] = "Bob - Faerlina" },
        profiles = {
          ["Bob - Faerlina"] = {
            levels = {
              [4] = { timestamp = { started = 100, finished = 500 }, deaths = 1 },
            },
          },
        },
      }
      DS:RunLevelHistoryBackfill()
      assert.is_not_nil(char.levelHistory.meta.importedRxpAt)
      assert.are.equal(500, char.levelHistory.milestones[5].playedTotal)

      _G.RXPCTrackingData.profiles["Bob - Faerlina"].levels[5] = {
        timestamp = { started = 500, finished = 900 },
      }
      DS:RunLevelHistoryBackfill()
      assert.is_nil(char.levelHistory.milestones[6])
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
    end)

    it("posts chat when Questie backfill imports milestones", function()
      _G.AltArmyTBC_Data.levelHistoryImport = nil
      _G.RXPCTrackingData = nil
      _G.QuestieConfig = {
        char = {
          ["Bob - Faerlina"] = {
            journey = {
              { Event = "Level", NewLevel = 5, Timestamp = 500 },
              { Event = "Level", NewLevel = 6, Timestamp = 600 },
            },
          },
        },
      }
      AltArmyTBC_Data.Characters = {
        Faerlina = { Bob = { name = "Bob", realm = "Faerlina" } },
      }
      DS._SetLevelHistoryTestChar(AltArmyTBC_Data.Characters.Faerlina.Bob)
      DS._BeginLevelHistoryChatCapture()
      DS:RunLevelHistoryBackfill()
      local messages = DS._GetLevelHistoryChatMessages()
      assert.are.equal(1, #messages)
      assert.matches("Questie", messages[1])
      assert.matches("2 level milestone", messages[1])
    end)

    it("posts chat when RestedXP backfill imports milestones", function()
      _G.AltArmyTBC_Data.levelHistoryImport = { questieAt = 1 }
      local char = { name = "Bob", realm = "Faerlina" }
      DS._SetLevelHistoryTestChar(char)
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Faerlina" end
      _G.RXPCTrackingData = {
        profileKeys = { ["Bob - Faerlina"] = "Bob - Faerlina" },
        profiles = {
          ["Bob - Faerlina"] = {
            levels = {
              [4] = { timestamp = { started = 100, finished = 500 }, deaths = 1 },
              [5] = { timestamp = { started = 500, finished = 900 }, deaths = 0 },
            },
          },
        },
      }
      DS._BeginLevelHistoryChatCapture()
      DS:RunLevelHistoryBackfill()
      local messages = DS._GetLevelHistoryChatMessages()
      assert.are.equal(1, #messages)
      assert.matches("RestedXP", messages[1])
      assert.matches("Bob", messages[1])
      assert.matches("2 level milestone", messages[1])
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
    end)

    it("does not post chat when no import data is available", function()
      _G.AltArmyTBC_Data.levelHistoryImport = nil
      _G.QuestieConfig = nil
      local char = { name = "Bob", realm = "Faerlina" }
      DS._SetLevelHistoryTestChar(char)
      _G.RXPCTrackingData = nil
      DS._BeginLevelHistoryChatCapture()
      DS:RunLevelHistoryBackfill()
      assert.are.equal(0, #DS._GetLevelHistoryChatMessages())
      assert.is_nil(AltArmyTBC_Data.levelHistoryImport)
      assert.is_nil(char.levelHistory)
    end)

    it("does not set import gates when source addons are absent", function()
      _G.AltArmyTBC_Data.levelHistoryImport = nil
      _G.QuestieConfig = nil
      _G.RXPCTrackingData = nil
      _G.RXPGuides = nil
      local char = { name = "Bob", realm = "Faerlina" }
      DS._SetLevelHistoryTestChar(char)
      DS:RunLevelHistoryBackfill()
      assert.is_nil(AltArmyTBC_Data.levelHistoryImport)
      assert.is_nil(char.levelHistory)
      DS:RunLevelHistoryBackfill()
      assert.is_nil(AltArmyTBC_Data.levelHistoryImport)
    end)

    it("imports RXP data after deferred retry once AceDB profile appears", function()
      _G.AltArmyTBC_Data.levelHistoryImport = { questieAt = 1 }
      local char = { name = "Bob", realm = "Faerlina" }
      DS._SetLevelHistoryTestChar(char)
      _G.RXPCTrackingData = nil
      local oldUnitName, oldGetRealmName = _G.UnitName, _G.GetRealmName
      _G.UnitName = function(unit) return unit == "player" and "Bob" or nil end
      _G.GetRealmName = function() return "Faerlina" end
      local scheduled = {}
      _G.C_Timer = {
        After = function(_, fn)
          scheduled[#scheduled + 1] = fn
        end,
      }
      DS._SetLevelHistoryTestRxpAddonEnabled(true)
      enableLevelHistoryDebug()
      DS._BeginLevelHistoryDebugCapture()
      DS:RunLevelHistoryBackfill()
      assert.is_nil(char.levelHistory)
      assert.are.equal(1, #scheduled)
      local messagesBeforeRetry = DS._GetLevelHistoryDebugMessages()
      local foundDeferred = false
      for _, line in ipairs(messagesBeforeRetry) do
        if line:match("not ready yet") then
          foundDeferred = true
          break
        end
      end
      assert.is_true(foundDeferred)
      _G.RXPCTrackingData = {
        profileKeys = { ["Bob - Faerlina"] = "Bob - Faerlina" },
        profiles = {
          ["Bob - Faerlina"] = {
            levels = {
              [4] = { timestamp = { started = 100, finished = 500 }, deaths = 1 },
            },
          },
        },
      }
      scheduled[1]()
      assert.is_not_nil(char.levelHistory.meta.importedRxpAt)
      assert.are.equal(500, char.levelHistory.milestones[5].playedTotal)
      _G.C_Timer = nil
      _G.UnitName, _G.GetRealmName = oldUnitName, oldGetRealmName
      DS._SetLevelHistoryTestRxpAddonEnabled(nil)
    end)

    it("logs import decisions and stored summary when debug enabled", function()
      enableLevelHistoryDebug()
      _G.AltArmyTBC_Data.levelHistoryImport = { questieAt = 1 }
      local char = {
        name = "Bob",
        realm = "Faerlina",
        levelHistory = {
          milestones = { [5] = { reachedAt = 100 }, [6] = { reachedAt = 200 } },
          deaths = { { at = 1 }, { at = 2 } },
          meta = { importedRxpAt = 1 },
        },
      }
      DS._SetLevelHistoryTestChar(char)
      DS._BeginLevelHistoryDebugCapture()
      DS:RunLevelHistoryBackfill()
      local messages = DS._GetLevelHistoryDebugMessages()
      assert.is_true(#messages >= 3)
      assert.matches("Checking level history import status", messages[1])
      assert.matches("Questie: skip import", messages[2])
      assert.matches("RXP: skip import", messages[3])
      assert.matches("Stored: Bob: 2 level milestone%(s%), 2 death event%(s%)", messages[#messages])
    end)

    it("does not log debug messages when level history debug is disabled", function()
      AltArmy.Debug.SetEnabled(false)
      AltArmy.Debug.SetLevelHistoryEnabled(false)
      _G.AltArmyTBC_Data.levelHistoryImport = { questieAt = 1 }
      local char = {
        name = "Bob",
        realm = "Faerlina",
        levelHistory = { milestones = {}, deaths = {}, meta = { importedRxpAt = 1 } },
      }
      DS._SetLevelHistoryTestChar(char)
      DS._BeginLevelHistoryDebugCapture()
      DS:RunLevelHistoryBackfill()
      assert.are.equal(0, #DS._GetLevelHistoryDebugMessages())
    end)
  end)
end)
