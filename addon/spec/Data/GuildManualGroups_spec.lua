--[[
  Unit tests for GuildManualGroups.lua (local-only name→main mappings).
  Run from project root: npm test
]]

describe("GuildManualGroups", function()
  local GMG, GSD
  local NOW = 1700000000

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.time = function() return NOW end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("GuildShareProtocol")
    require("GuildShareData")
    require("GuildManualGroups")
    GMG = AltArmy.GuildManualGroups
    GSD = AltArmy.GuildShareData
    assert.truthy(GMG)
  end)

  before_each(function()
    _G.AltArmyTBC_GuildData = nil
    if GSD and GSD._Ensure then GSD._Ensure() end
    if GMG and GMG._Ensure then GMG._Ensure() end
  end)

  describe("SetMapping / GetMapping / RemoveMapping", function()
    it("stores a mapping under realm keyed by character name", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G", origin = "user" })
      local m = GMG.GetMapping("Bobsalt", "R")
      assert.truthy(m)
      assert.are.equal("Bob", m.main)
      assert.are.equal("G", m.guild)
      assert.are.equal("user", m.origin)
      assert.are.equal(NOW, m.createdAt)
      assert.are.equal(NOW, m.updatedAt)
    end)

    it("stores note provenance when origin is note", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", {
        guild = "G",
        origin = "note",
        noteText = "bob alt",
        noteHash = 42,
      })
      local m = GMG.GetMapping("Bobsalt", "R")
      assert.are.equal("note", m.origin)
      assert.are.equal("bob alt", m.noteText)
      assert.are.equal(42, m.noteHash)
    end)

    it("defaults origin to user when omitted", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      assert.are.equal("user", GMG.GetMapping("Alt", "R").origin)
    end)

    it("updates an existing mapping and preserves createdAt", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G", origin = "user" })
      local created = GMG.GetMapping("Alt", "R").createdAt
      NOW = 1700001000
      GMG.SetMapping("Alt", "R", "OtherMain", { guild = "G", origin = "note", noteText = "x" })
      local m = GMG.GetMapping("Alt", "R")
      assert.are.equal("OtherMain", m.main)
      assert.are.equal(created, m.createdAt)
      assert.are.equal(1700001000, m.updatedAt)
      NOW = 1700000000
    end)

    it("returns nil for unknown mappings", function()
      assert.is_nil(GMG.GetMapping("Nobody", "R"))
    end)

    it("RemoveMapping clears a single entry", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      GMG.RemoveMapping("Alt", "R")
      assert.is_nil(GMG.GetMapping("Alt", "R"))
    end)

    it("no-ops SetMapping when name or main is empty", function()
      GMG.SetMapping("", "R", "Main", { guild = "G" })
      GMG.SetMapping("Alt", "R", "", { guild = "G" })
      GMG.SetMapping(nil, "R", "Main", { guild = "G" })
      assert.is_nil(GMG.GetMapping("Alt", "R"))
    end)
  end)

  describe("GetMainOf", function()
    it("returns the mapped main for an alt", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      assert.are.equal("Bob", GMG.GetMainOf("Bobsalt", "R"))
    end)

    it("returns the name itself when it is a main of some mapping", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      assert.are.equal("Bob", GMG.GetMainOf("Bob", "R"))
    end)

    it("returns nil when unknown", function()
      assert.is_nil(GMG.GetMainOf("Nobody", "R"))
    end)

    it("searches all realms when realm is omitted", function()
      GMG.SetMapping("Bobsalt", "OtherRealm", "Bob", { guild = "G" })
      assert.are.equal("Bob", GMG.GetMainOf("Bobsalt"))
    end)
  end)

  describe("GetMappingsForGuild", function()
    it("returns flat list of mappings for a guild", function()
      GMG.SetMapping("A1", "R", "A", { guild = "G" })
      GMG.SetMapping("A2", "R", "A", { guild = "G" })
      GMG.SetMapping("B1", "R", "B", { guild = "Other" })
      local list = GMG.GetMappingsForGuild("G")
      assert.are.equal(2, #list)
      local names = {}
      for _, e in ipairs(list) do
        names[e.name] = e.main
        assert.are.equal("R", e.realm)
        assert.are.equal("G", e.guild)
      end
      assert.are.equal("A", names.A1)
      assert.are.equal("A", names.A2)
    end)

    it("returns empty list when none match", function()
      assert.are.equal(0, #GMG.GetMappingsForGuild("G"))
    end)
  end)

  describe("IsShadowed", function()
    it("is false when no addon data exists for the character", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      assert.is_false(GMG.IsShadowed("Alt", "R"))
    end)

    it("is true when GuildShareData has a stored character", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      GSD.SaveReceived("Peer", {
        main = "Other",
        chars = {
          { name = "Alt", classFile = "MAGE", level = 70, profs = {} },
        },
      }, "G", "R")
      assert.is_true(GMG.IsShadowed("Alt", "R"))
    end)
  end)

  describe("RemoveGroup", function()
    it("removes all mappings whose main matches", function()
      GMG.SetMapping("A1", "R", "Main", { guild = "G" })
      GMG.SetMapping("A2", "R", "Main", { guild = "G" })
      GMG.SetMapping("B1", "R", "Other", { guild = "G" })
      local n = GMG.RemoveGroup("Main", "R")
      assert.are.equal(2, n)
      assert.is_nil(GMG.GetMapping("A1", "R"))
      assert.is_nil(GMG.GetMapping("A2", "R"))
      assert.truthy(GMG.GetMapping("B1", "R"))
    end)

    it("searches all realms when realm is omitted", function()
      GMG.SetMapping("A1", "R1", "Main", { guild = "G" })
      GMG.SetMapping("A2", "R2", "Main", { guild = "G" })
      assert.are.equal(2, GMG.RemoveGroup("Main"))
    end)
  end)

  describe("RetireIfAgrees", function()
    it("removes mapping when effectiveMain matches the mapped main", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      assert.is_true(GMG.RetireIfAgrees("Alt", "R", "Main"))
      assert.is_nil(GMG.GetMapping("Alt", "R"))
    end)

    it("keeps mapping when effectiveMain disagrees", function()
      GMG.SetMapping("Alt", "R", "Main", { guild = "G" })
      assert.is_false(GMG.RetireIfAgrees("Alt", "R", "Other"))
      assert.truthy(GMG.GetMapping("Alt", "R"))
    end)

    it("returns false when no mapping exists", function()
      assert.is_false(GMG.RetireIfAgrees("Nobody", "R", "Main"))
    end)
  end)

  describe("ClearGuild / ClearAll", function()
    it("ClearGuild removes mappings for one guild only", function()
      GMG.SetMapping("A1", "R", "A", { guild = "G" })
      GMG.SetMapping("B1", "R", "B", { guild = "Other" })
      GMG.ClearGuild("G")
      assert.is_nil(GMG.GetMapping("A1", "R"))
      assert.truthy(GMG.GetMapping("B1", "R"))
    end)

    it("ClearAll removes every mapping", function()
      GMG.SetMapping("A1", "R", "A", { guild = "G" })
      GMG.SetMapping("B1", "R2", "B", { guild = "Other" })
      GMG.ClearAll()
      assert.is_nil(GMG.GetMapping("A1", "R"))
      assert.is_nil(GMG.GetMapping("B1", "R2"))
    end)
  end)
end)
