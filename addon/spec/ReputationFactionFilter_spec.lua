--[[
  Unit tests for ReputationFactionFilter.lua (faction name substring filter).
]]

describe("ReputationFactionFilter", function()
  local F

  setup(function()
    _G.AltArmy = {}
    assert(loadfile("AltArmy_TBC/ReputationFactionFilter.lua"))()
    F = AltArmy.ReputationFactionFilter
  end)

  describe("filterRows", function()
    it("returns the same table when filter is empty or only whitespace", function()
      local rows = { { name = "A", factionID = 1 }, { name = "B", factionID = 2 } }
      assert.are.equal(rows, F.filterRows(rows, ""))
      assert.are.equal(rows, F.filterRows(rows, "   "))
    end)

    it("matches case-insensitive substring", function()
      local rows = {
        { name = "Honor Hold", factionID = 1 },
        { name = "Cenarion Expedition", factionID = 2 },
      }
      local r = F.filterRows(rows, "hon")
      assert.are.equal(1, #r)
      assert.are.equal("Honor Hold", r[1].name)
    end)

    it("matches in the middle of the name", function()
      local rows = { { name = "Lower City", factionID = 1 } }
      assert.are.equal(1, #F.filterRows(rows, "er ci"))
    end)

    it("treats filter as plain text (no pattern magic)", function()
      local rows = { { name = "Foo (test)", factionID = 1 }, { name = "Other", factionID = 2 } }
      local r = F.filterRows(rows, "(test)")
      assert.are.equal(1, #r)
      assert.are.equal("Foo (test)", r[1].name)
    end)

    it("returns empty when nothing matches", function()
      local rows = { { name = "A", factionID = 1 } }
      local r = F.filterRows(rows, "zzz")
      assert.are.equal(0, #r)
    end)
  end)
end)
