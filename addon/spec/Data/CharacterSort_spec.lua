--[[
  Unit tests for CharacterSort.lua.
  Run from project root: npm test
]]

describe("CharacterSort", function()
  local CS

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("CharacterSort")
    CS = AltArmy.CharacterSort
  end)

  local function entry(name, level, played, avgItemLevel)
    return {
      name = name,
      level = level,
      played = played,
      avgItemLevel = avgItemLevel,
    }
  end

  it("sorts Name A-Z as primary", function()
    local a = entry("Alice", 60, 100, 50)
    local b = entry("Bob", 60, 100, 50)
    assert.is_true(CS.CompareBySort(a, b, "Name", "Level"))
    assert.is_false(CS.CompareBySort(b, a, "Name", "Level"))
  end)

  it("sorts numeric keys high-first", function()
    local a = entry("A", 70, 200, 60)
    local b = entry("B", 60, 100, 50)
    assert.is_true(CS.CompareBySort(a, b, "Level", "Name"))
    assert.is_true(CS.CompareBySort(a, b, "Time Played", "Name"))
    assert.is_true(CS.CompareBySort(a, b, "Avg Item Level", "Name"))
  end)

  it("uses secondary sort when primary ties", function()
    local a = entry("Alice", 60, 100, 50)
    local b = entry("Bob", 60, 100, 50)
    assert.is_true(CS.CompareBySort(a, b, "Level", "Name"))
  end)

  it("GetSortValue returns defaults for missing fields", function()
    assert.are.equal("", CS.GetSortValue({}, "Name"))
    assert.are.equal(0, CS.GetSortValue({}, "Level"))
  end)

  it("sorts by gear score provider label from entry.scores", function()
    local a = entry("Alice", 60, 100, 50)
    local b = entry("Bob", 60, 100, 50)
    a.scores = { ["Gear Score (TacoTip)"] = 1200 }
    b.scores = { ["Gear Score (TacoTip)"] = 800 }
    assert.is_true(CS.CompareBySort(a, b, "Gear Score (TacoTip)", "Name"))
    assert.is_false(CS.CompareBySort(b, a, "Gear Score (TacoTip)", "Name"))
  end)
end)
