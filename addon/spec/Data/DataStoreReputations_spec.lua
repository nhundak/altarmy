--[[
  Unit tests for DataStoreReputations.lua (GetReputationLimits, GetReputationInfo).
  Run from project root: npm test
]]

describe("DataStoreReputations", function()
  local DS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME or { AddMessage = function() end }
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreReputations")
    DS = AltArmy.DataStore
  end)

  describe("_GetReputationLimits", function()
    it("returns 0, 36000 for earned 0", function()
      local bottom, top = DS._GetReputationLimits(0)
      assert.are.equal(bottom, 0)
      assert.are.equal(top, 36000)
    end)
    it("returns 36000, 78000 for earned in Friendly range", function()
      local bottom, top = DS._GetReputationLimits(50000)
      assert.are.equal(bottom, 36000)
      assert.are.equal(top, 78000)
    end)
    it("returns 192000, 42000 for exalted (top cap)", function()
      local bottom, top = DS._GetReputationLimits(200000)
      assert.are.equal(bottom, 192000)
      assert.are.equal(top, 42000)
    end)
  end)

  describe("GetReputationInfo", function()
    it("returns nil, 0, 0, 0 when char or faction missing", function()
      local s, re = DS:GetReputationInfo(nil, 1)
      assert.is_nil(s)
      assert.are.equal(0, re)
      s, re = DS:GetReputationInfo({ Reputations = {} }, nil)
      assert.is_nil(s)
      assert.are.equal(0, re)
    end)
    it("returns nil, 0, 0, 0 when faction not in char", function()
      local s, re = DS:GetReputationInfo({ Reputations = {} }, 123)
      assert.is_nil(s)
      assert.are.equal(0, re)
    end)
    it("returns standing, repEarned, nextLevel, rate for known faction", function()
      local char = { Reputations = { [123] = 50000 } }
      local standing, repEarned, nextLevel, rate = DS:GetReputationInfo(char, 123)
      assert.are.equal("Friendly", standing)
      assert.are.equal(50000 - 36000, repEarned)
      assert.are.equal(78000 - 36000, nextLevel)
      assert.truthy(rate > 0 and rate <= 100)
    end)
    it("uses v2 API snapshot table (standingID + bounds) for label and progress", function()
      local char = { Reputations = { [123] = { s = 5, e = 7500, b = 3000, t = 9000 } } }
      local standing, repEarned, nextLevel, rate = DS:GetReputationInfo(char, 123)
      assert.are.equal("Friendly", standing)
      assert.are.equal(4500, repEarned)
      assert.are.equal(6000, nextLevel)
      assert.truthy(rate > 0 and rate <= 100)
    end)
  end)

  describe("FormatReputationProgressText", function()
    it("returns current over next for in-progress standing", function()
      assert.are.equal("14000/42000", DS.FormatReputationProgressText("Friendly", 14000, 42000))
    end)
    it("returns current over span for Exalted like other tiers", function()
      assert.are.equal("842/1000", DS.FormatReputationProgressText("Exalted", 842, 1000))
    end)
    it("returns cur/1000 for Exalted when span is zero (capped / API)", function()
      assert.are.equal("999/1000", DS.FormatReputationProgressText("Exalted", 999, 0))
    end)
    it("returns Max when nextLevel is zero or negative", function()
      assert.are.equal("Max", DS.FormatReputationProgressText("Honored", 100, 0))
      assert.are.equal("Max", DS.FormatReputationProgressText("Honored", 100, -1))
    end)
  end)

  describe("GetReputationBarColorsForStanding", function()
    it("returns three numbers in 0..1 range for Hated", function()
      local r, g, b = DS.GetReputationBarColorsForStanding("Hated")
      assert.are.equal("number", type(r))
      assert.are.equal("number", type(g))
      assert.are.equal("number", type(b))
      assert.truthy(r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1)
    end)
    it("returns different hue for Friendly vs Hated", function()
      local rh, gh, bh = DS.GetReputationBarColorsForStanding("Hated")
      local rf, gf, bf = DS.GetReputationBarColorsForStanding("Friendly")
      assert.is_false(rh == rf and gh == gf and bh == bf)
    end)
  end)

  describe("GetCurrentReputationFactionRows", function()
    local oldNum, oldInfo, oldGetFactionInfoByID

    before_each(function()
      oldNum = _G.GetNumFactions
      oldInfo = _G.GetFactionInfo
      oldGetFactionInfoByID = _G.GetFactionInfoByID
      _G.AltArmyTBC_Data.Characters = {}
      _G.AltArmyTBC_Data.ReputationFactionNames = nil
    end)

    after_each(function()
      _G.GetNumFactions = oldNum
      _G.GetFactionInfo = oldInfo
      _G.GetFactionInfoByID = oldGetFactionInfoByID
    end)

    it("returns empty list when GetNumFactions missing and no saved reps", function()
      _G.GetNumFactions = nil
      _G.GetFactionInfo = function() end
      assert.are.same({}, DS:GetCurrentReputationFactionRows())
    end)

    it("excludes legacy v1 scalar reputations from union", function()
      _G.GetNumFactions = function()
        return 0
      end
      _G.GetFactionInfo = function() end
      _G.AltArmyTBC_Data.Characters = {
        R = {
          P = { Reputations = { [47] = 50000 } },
        },
      }
      assert.are.same({}, DS:GetCurrentReputationFactionRows())
    end)

    it("excludes v2 Neutral at zero progress from union (default city rows in saved data)", function()
      _G.GetNumFactions = function()
        return 0
      end
      _G.GetFactionInfo = function() end
      _G.AltArmyTBC_Data.Characters = {
        R = {
          P = {
            Reputations = {
              [47] = { s = 4, e = 3000, b = 3000, t = 9000 },
            },
          },
        },
      }
      assert.are.same({}, DS:GetCurrentReputationFactionRows())
    end)

    it("includes v2 Neutral when there is progress within the tier (e > b)", function()
      _G.GetNumFactions = function()
        return 0
      end
      _G.GetFactionInfo = function() end
      _G.AltArmyTBC_Data.Characters = {
        R = {
          P = {
            Reputations = {
              [47] = { s = 4, e = 5000, b = 3000, t = 9000 },
            },
          },
        },
      }
      _G.AltArmyTBC_Data.ReputationFactionNames = { [47] = "Ironforge" }
      local rows = DS:GetCurrentReputationFactionRows()
      assert.are.equal(1, #rows)
      assert.are.equal(47, rows[1].factionID)
      assert.are.equal("Ironforge", rows[1].name)
    end)

    it("does not list factions that only exist on the client rep UI with no saved character data", function()
      _G.AltArmyTBC_Data.Characters = {}
      _G.GetNumFactions = function()
        return 2
      end
      _G.GetFactionInfo = function(i)
        if i == 1 then
          return "Ironforge", nil, nil, nil, nil, nil, nil, nil, false, false, nil, nil, nil, 47
        end
        return "Stormwind", nil, nil, nil, nil, nil, nil, nil, false, false, nil, nil, nil, 72
      end
      assert.are.same({}, DS:GetCurrentReputationFactionRows())
    end)

    it("returns alphabetical order by display name (not client list order)", function()
      _G.AltArmyTBC_Data.Characters = {
        R = {
          P = {
            Reputations = {
              [100] = { s = 5, e = 0, b = 0, t = 1 },
              [200] = { s = 5, e = 0, b = 0, t = 1 },
              [300] = { s = 5, e = 0, b = 0, t = 1 },
            },
          },
        },
      }
      _G.GetNumFactions = function()
        return 4
      end
      _G.GetFactionInfo = function(i)
        if i == 1 then
          return "Header", nil, nil, nil, nil, nil, nil, nil, true, false, nil, nil, nil, 0
        elseif i == 2 then
          return "Zeta", nil, nil, nil, nil, nil, nil, nil, false, false, nil, nil, nil, 300
        elseif i == 3 then
          return "Alpha", nil, nil, nil, nil, nil, nil, nil, false, false, nil, nil, nil, 100
        elseif i == 4 then
          return "Beta", nil, nil, nil, nil, nil, nil, nil, false, false, nil, nil, nil, 200
        end
      end
      local rows = DS:GetCurrentReputationFactionRows()
      assert.are.equal(3, #rows)
      assert.are.equal("Alpha", rows[1].name)
      assert.are.equal(100, rows[1].factionID)
      assert.are.equal("Beta", rows[2].name)
      assert.are.equal(200, rows[2].factionID)
      assert.are.equal("Zeta", rows[3].name)
      assert.are.equal(300, rows[3].factionID)
    end)

    it("includes union of faction IDs from all saved characters", function()
      _G.GetNumFactions = function()
        return 1
      end
      _G.GetFactionInfo = function()
        return "X", nil, nil, nil, nil, nil, nil, nil, true, false, nil, nil, nil, 0
      end
      _G.AltArmyTBC_Data.Characters = {
        R1 = {
          A = { Reputations = { [10] = { s = 5, e = 0, b = 0, t = 1 } } },
          B = { Reputations = { [20] = { s = 5, e = 0, b = 0, t = 1 } } },
        },
      }
      _G.AltArmyTBC_Data.ReputationFactionNames = { [10] = "Faction Ten", [20] = "Faction Twenty" }
      local rows = DS:GetCurrentReputationFactionRows()
      assert.are.equal(2, #rows)
      assert.are.equal(10, rows[1].factionID)
      assert.are.equal("Faction Ten", rows[1].name)
      assert.are.equal(20, rows[2].factionID)
      assert.are.equal("Faction Twenty", rows[2].name)
    end)

    it("resolves display name via GetFactionInfoByID when missing from saved map", function()
      _G.GetNumFactions = function()
        return 0
      end
      _G.GetFactionInfo = function() end
      _G.GetFactionInfoByID = function(id)
        if id == 989 then
          return "Sporeggar"
        end
      end
      _G.AltArmyTBC_Data.Characters = {
        R1 = {
          P = { Reputations = { [989] = { s = 5, e = 0, b = 0, t = 1 } } },
        },
      }
      _G.AltArmyTBC_Data.ReputationFactionNames = {}
      local rows = DS:GetCurrentReputationFactionRows()
      assert.are.equal(1, #rows)
      assert.are.equal(989, rows[1].factionID)
      assert.are.equal("Sporeggar", rows[1].name)
      assert.are.equal("Sporeggar", _G.AltArmyTBC_Data.ReputationFactionNames[989])
    end)
  end)
end)
