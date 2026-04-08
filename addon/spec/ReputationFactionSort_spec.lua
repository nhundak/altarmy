--[[
  Ordering when sorting by faction: undiscovered rep sorts after any discovered value,
  including ascending (low-first) mode.
]]

describe("ReputationFactionSort", function()
  local DS
  local RepSort
  local FID = 47

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME or { AddMessage = function() end }
    package.path = package.path .. ";AltArmy_TBC/?.lua;AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreReputations")
    assert(loadfile("AltArmy_TBC/ReputationFactionSort.lua"))()
    DS = AltArmy.DataStore
    RepSort = AltArmy.ReputationFactionSort
  end)

  local function putChar(name, realm, char)
    AltArmyTBC_Data.Characters[realm] = AltArmyTBC_Data.Characters[realm] or {}
    AltArmyTBC_Data.Characters[realm][name] = char
  end

  local function entry(name, realm, played)
    return { name = name, realm = realm, played = played or 0 }
  end

  it("ascending: discovered lower rep sorts before discovered higher rep", function()
    putChar("A", "R", {
      dataVersions = { reputations = 2 },
      Reputations = { [FID] = { s = 5, e = 1000, b = 0, t = 1 } },
    })
    putChar("B", "R", {
      dataVersions = { reputations = 2 },
      Reputations = { [FID] = { s = 5, e = 5000, b = 0, t = 1 } },
    })
    local a, b = entry("A", "R"), entry("B", "R")
    assert.is_true(
      RepSort.CompareByFactionRep(DS, a, b, FID, false, "Time Played", "Name"),
      "A should come before B (lower rep first)"
    )
    assert.is_false(
      RepSort.CompareByFactionRep(DS, b, a, FID, false, "Time Played", "Name"),
      "B should not come before A"
    )
  end)

  it("ascending: undiscovered sorts after discovered even when earned sentinel is lowest", function()
    putChar("Has", "R", {
      dataVersions = { reputations = 2 },
      Reputations = { [FID] = { s = 5, e = 100, b = 0, t = 1 } },
    })
    putChar("None", "R", {
      dataVersions = { reputations = 2 },
      Reputations = {},
    })
    local has, none = entry("Has", "R"), entry("None", "R")
    assert.is_true(
      RepSort.CompareByFactionRep(DS, has, none, FID, false, "Time Played", "Name"),
      "discovered should sort before undiscovered in ascending mode"
    )
    assert.is_false(
      RepSort.CompareByFactionRep(DS, none, has, FID, false, "Time Played", "Name"),
      "undiscovered should not sort before discovered"
    )
  end)

  it("column sort: ascending puts undiscovered faction rows after discovered for the same character", function()
    putChar("Col", "R", {
      dataVersions = { reputations = 2 },
      Reputations = {
        [10] = { s = 5, e = 5000, b = 0, t = 1 },
        [20] = { s = 5, e = 100, b = 0, t = 1 },
      },
    })
    local charEntry = entry("Col", "R")
    local rowHigh = { factionID = 10, name = "High Rep" }
    local rowLow = { factionID = 20, name = "Low Rep" }
    local rowNone = { factionID = 99, name = "Zebra No Rep" }
    assert.is_true(
      RepSort.CompareFactionRowsForCharacter(DS, charEntry, rowLow, rowHigh, false),
      "lower earned should be before higher when both discovered"
    )
    assert.is_true(
      RepSort.CompareFactionRowsForCharacter(DS, charEntry, rowHigh, rowNone, false),
      "discovered should be before undiscovered row in ascending"
    )
    assert.is_false(
      RepSort.CompareFactionRowsForCharacter(DS, charEntry, rowNone, rowHigh, false),
      "undiscovered should not precede discovered"
    )
  end)
end)
