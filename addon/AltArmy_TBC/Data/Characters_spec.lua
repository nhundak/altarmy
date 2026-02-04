--[[
  Unit tests for Characters.lua (Sort).
  Run from project root: npm test
]]

describe("Characters", function()
  local ns

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    if not _G.wipe then
      _G.wipe = function(t)
        for k in pairs(t) do t[k] = nil end
      end
    end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("SummaryData")
    AltArmy.SummaryData.GetCharacterList = function()
      return {
        { name = "Bob", realm = "R1", level = 2, restXp = 0, money = 100, played = 0,
          lastOnline = 10, bagSlots = 0, bagFree = 0, equipmentCount = 0 },
        { name = "Alice", realm = "R1", level = 1, restXp = 0, money = 50, played = 0,
          lastOnline = 5, bagSlots = 0, bagFree = 0, equipmentCount = 0 },
      }
    end
    require("Characters")
    ns = AltArmy.Characters
  end)

  describe("Sort", function()
    it("sorts by name ascending", function()
      ns:InvalidateView()
      ns:GetList()
      ns:Sort(true, "name")
      local list = ns:GetList()
      assert.are.equal(#list, 2)
      assert.are.equal(list[1].name, "Alice")
      assert.are.equal(list[2].name, "Bob")
    end)
    it("sorts by name descending", function()
      ns:InvalidateView()
      ns:GetList()
      ns:Sort(false, "name")
      local list = ns:GetList()
      assert.are.equal(list[1].name, "Bob")
      assert.are.equal(list[2].name, "Alice")
    end)
    it("sorts by level ascending", function()
      ns:InvalidateView()
      ns:GetList()
      ns:Sort(true, "level")
      local list = ns:GetList()
      assert.are.equal(list[1].level, 1)
      assert.are.equal(list[2].level, 2)
    end)
    it("sorts by level descending", function()
      ns:InvalidateView()
      ns:GetList()
      ns:Sort(false, "level")
      local list = ns:GetList()
      assert.are.equal(list[1].level, 2)
      assert.are.equal(list[2].level, 1)
    end)
    it("treats lastOnline nil as 0 for sort", function()
      AltArmy.SummaryData.GetCharacterList = function()
        return {
          { name = "A", realm = "R", level = 1, lastOnline = 100 },
          { name = "B", realm = "R", level = 1, lastOnline = nil },
        }
      end
      ns:InvalidateView()
      ns:GetList()
      ns:Sort(true, "lastOnline")
      local list = ns:GetList()
      assert.are.equal(list[1].name, "B")
      assert.are.equal(list[2].name, "A")
    end)
    it("does nothing when list empty", function()
      AltArmy.SummaryData.GetCharacterList = function() return {} end
      ns:InvalidateView()
      assert.has_no.errors(function()
        ns:Sort(true, "name")
      end)
    end)
  end)
end)
