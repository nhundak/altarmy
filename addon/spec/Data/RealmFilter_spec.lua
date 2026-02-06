--[[
  Unit tests for RealmFilter.lua (realm filter and display name helpers).
  Run from project root: npm test
]]

describe("RealmFilter", function()
  local RF

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("RealmFilter")
    RF = AltArmy.RealmFilter
  end)

  describe("filterListByRealm", function()
    it("returns full list when realmFilter is 'all'", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R2" },
      }
      local out = RF.filterListByRealm(list, "all", "R1")
      assert.are.equal(#out, 2)
      assert.are.equal(out[1].name, "A")
      assert.are.equal(out[2].name, "B")
    end)

    it("returns only current-realm entries when realmFilter is 'currentRealm'", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R2" },
        { name = "C", realm = "R1" },
      }
      local out = RF.filterListByRealm(list, "currentRealm", "R1")
      assert.are.equal(#out, 2)
      assert.are.equal(out[1].name, "A")
      assert.are.equal(out[2].name, "C")
    end)

    it("returns empty list when currentRealm has no matches", function()
      local list = {
        { name = "A", realm = "R1" },
      }
      local out = RF.filterListByRealm(list, "currentRealm", "R2")
      assert.are.equal(#out, 0)
    end)

    it("returns new table (does not mutate input)", function()
      local list = {
        { name = "A", realm = "R1" },
      }
      local out = RF.filterListByRealm(list, "currentRealm", "R2")
      assert.are.equal(#list, 1)
      assert.are.equal(#out, 0)
    end)
  end)

  describe("hasMultipleRealms", function()
    it("returns false for empty list", function()
      assert.is_false(RF.hasMultipleRealms({}))
    end)

    it("returns false for single entry", function()
      assert.is_false(RF.hasMultipleRealms({ { name = "A", realm = "R1" } }))
    end)

    it("returns false when all entries same realm", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R1" },
      }
      assert.is_false(RF.hasMultipleRealms(list))
    end)

    it("returns true when entries have different realms", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R2" },
      }
      assert.is_true(RF.hasMultipleRealms(list))
    end)

    it("returns true when more than two realms", function()
      local list = {
        { name = "A", realm = "R1" },
        { name = "B", realm = "R2" },
        { name = "C", realm = "R3" },
      }
      assert.is_true(RF.hasMultipleRealms(list))
    end)
  end)

  describe("formatCharacterDisplayName", function()
    it("returns name only when showRealmSuffix is false", function()
      assert.are.equal(RF.formatCharacterDisplayName("Frell", "Dreamscythe", false), "Frell")
    end)

    it("returns name-realm when showRealmSuffix is true", function()
      assert.are.equal(RF.formatCharacterDisplayName("Frell", "Dreamscythe", true), "Frell-Dreamscythe")
    end)

    it("handles nil realm as empty string when showRealmSuffix true", function()
      assert.are.equal(RF.formatCharacterDisplayName("Frell", nil, true), "Frell-")
    end)
  end)

  describe("formatCharacterDisplayNameColored", function()
    it("returns name with color code when showRealmSuffix false", function()
      local s = RF.formatCharacterDisplayNameColored("Frell", "Dreamscythe", false, 1, 0.5, 0)
      assert.truthy(s:find("|cFF"))
      assert.truthy(s:find("Frell"))
      assert.truthy(s:find("|r"))
      assert.is_nil(s:find("Dreamscythe"))
    end)

    it("returns name (colored) and -realm (after |r) when showRealmSuffix true", function()
      local s = RF.formatCharacterDisplayNameColored("Frell", "Dreamscythe", true, 1, 0.5, 0)
      assert.truthy(s:find("|cFF"))
      assert.truthy(s:find("Frell"))
      assert.truthy(s:find("|r"))
      assert.truthy(s:find("-Dreamscythe"))
    end)
  end)
end)
