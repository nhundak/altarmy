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
    it("stores classFile and level when provided", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", {
        guild = "G",
        classFile = "WARRIOR",
        level = 60,
      })
      local m = GMG.GetMapping("Bobsalt", "R")
      assert.are.equal("WARRIOR", m.classFile)
      assert.are.equal(60, m.level)
    end)

    it("preserves classFile and level when omitted on update", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", {
        guild = "G", classFile = "WARRIOR", level = 60,
      })
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G", origin = "note" })
      local m = GMG.GetMapping("Bobsalt", "R")
      assert.are.equal("WARRIOR", m.classFile)
      assert.are.equal(60, m.level)
    end)
  end)

  describe("RefreshFromRosterInfo", function()
    it("updates classFile and level from a roster info map", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      GMG.SetMapping("Bob", "R", "Bob", { guild = "G", classFile = "MAGE", level = 68 })
      local updated = GMG.RefreshFromRosterInfo({
        bobsalt = { classFile = "WARRIOR", level = 60, name = "Bobsalt" },
        bob = { classFile = "MAGE", level = 70, name = "Bob" },
      }, "R")
      assert.are.equal(2, updated)
      assert.are.equal("WARRIOR", GMG.GetMapping("Bobsalt", "R").classFile)
      assert.are.equal(60, GMG.GetMapping("Bobsalt", "R").level)
      assert.are.equal(70, GMG.GetMapping("Bob", "R").level)
    end)

    it("returns 0 when roster info is empty or nil", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      assert.are.equal(0, GMG.RefreshFromRosterInfo(nil, "R"))
      assert.are.equal(0, GMG.RefreshFromRosterInfo({}, "R"))
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

    it("resolves an alt lookup case-insensitively", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      assert.are.equal("Bob", GMG.GetMainOf("bobsalt", "R"))
    end)

    it("resolves a main-of lookup case-insensitively", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      assert.are.equal("Bob", GMG.GetMainOf("bob", "R"))
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

    it("removes mappings whose main matches case-insensitively", function()
      GMG.SetMapping("A1", "R", "Bob", { guild = "G" })
      GMG.SetMapping("A2", "R", "Bob", { guild = "G" })
      GMG.SetMapping("B1", "R", "Other", { guild = "G" })
      local n = GMG.RemoveGroup("BOB", "R")
      assert.are.equal(2, n)
      assert.is_nil(GMG.GetMapping("A1", "R"))
      assert.is_nil(GMG.GetMapping("A2", "R"))
      assert.truthy(GMG.GetMapping("B1", "R"))
    end)
  end)

  describe("GetUltimateMain", function()
    it("returns the name itself when unmapped", function()
      assert.are.equal("Bob", GMG.GetUltimateMain("Bob", "R"))
    end)

    it("returns the mapped main for a single hop", function()
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      assert.are.equal("Bob", GMG.GetUltimateMain("Bobsalt", "R"))
    end)

    it("walks a chain to the root", function()
      GMG.SetMapping("C", "R", "B", { guild = "G" })
      GMG.SetMapping("B", "R", "A", { guild = "G" })
      assert.are.equal("A", GMG.GetUltimateMain("C", "R"))
    end)

    it("returns the starting name on a cycle", function()
      GMG.SetMapping("Alice", "R", "Bob", { guild = "G" })
      GMG.SetMapping("Bob", "R", "Alice", { guild = "G" })
      assert.are.equal("Alice", GMG.GetUltimateMain("Alice", "R"))
      assert.are.equal("Bob", GMG.GetUltimateMain("Bob", "R"))
    end)

    it("treats a self-main anchor as the root", function()
      GMG.SetMapping("Bob", "R", "Bob", { guild = "G" })
      GMG.SetMapping("Bobsalt", "R", "Bob", { guild = "G" })
      assert.are.equal("Bob", GMG.GetUltimateMain("Bobsalt", "R"))
      assert.are.equal("Bob", GMG.GetUltimateMain("Bob", "R"))
    end)
  end)

  describe("AssignToGroup", function()
    it("maps a character under the given main", function()
      GMG.AssignToGroup("Bobsalt", "R", "Bob", { guild = "G", origin = "user" })
      local m = GMG.GetMapping("Bobsalt", "R")
      assert.truthy(m)
      assert.are.equal("Bob", m.main)
      assert.are.equal("user", m.origin)
    end)

    it("overwrites an existing mapping to move between groups", function()
      GMG.SetMapping("Alt", "R", "Alice", { guild = "G" })
      GMG.AssignToGroup("Alt", "R", "Bob", { guild = "G", origin = "user" })
      assert.are.equal("Bob", GMG.GetMapping("Alt", "R").main)
    end)

    it("resolves the target main to its root when the main is already an alt", function()
      GMG.SetMapping("Alice", "R", "Bob", { guild = "G" })
      GMG.AssignToGroup("Carol", "R", "Alice", { guild = "G", origin = "user" })
      assert.are.equal("Bob", GMG.GetMapping("Carol", "R").main)
    end)

    it("reparents existing alts when a main is moved under another main", function()
      GMG.SetMapping("A", "R", "A", { guild = "G" })
      GMG.SetMapping("A1", "R", "A", { guild = "G" })
      GMG.SetMapping("A2", "R", "A", { guild = "G" })
      GMG.AssignToGroup("A", "R", "B", { guild = "G", origin = "user" })
      assert.are.equal("B", GMG.GetMapping("A", "R").main)
      assert.are.equal("B", GMG.GetMapping("A1", "R").main)
      assert.are.equal("B", GMG.GetMapping("A2", "R").main)
    end)

    it("self-assignment writes an anchor without stranding alts", function()
      GMG.SetMapping("A1", "R", "A", { guild = "G" })
      GMG.AssignToGroup("A", "R", "A", { guild = "G", origin = "note" })
      assert.are.equal("A", GMG.GetMapping("A", "R").main)
      assert.are.equal("A", GMG.GetMapping("A1", "R").main)
    end)

    it("accepting both halves of a note cycle produces no stored cycle", function()
      -- Alice's note → Bob, then Bob's note → Alice: second assign reparents onto Alice.
      GMG.AssignToGroup("Alice", "R", "Bob", { guild = "G", origin = "note" })
      GMG.AssignToGroup("Bob", "R", "Alice", { guild = "G", origin = "note" })
      assert.are.equal("Alice", GMG.GetMapping("Bob", "R").main)
      -- Alice was reparented onto Alice (root after Bob→Alice); no Alice→Bob edge left.
      local alice = GMG.GetMapping("Alice", "R")
      if alice then
        assert.are.equal("Alice", alice.main)
      end
      assert.are.equal("Alice", GMG.GetUltimateMain("Bob", "R"))
      assert.are.equal("Alice", GMG.GetUltimateMain("Alice", "R"))
    end)

    it("no-ops when name or main is empty", function()
      GMG.AssignToGroup("", "R", "Bob", { guild = "G" })
      GMG.AssignToGroup("Alt", "R", "", { guild = "G" })
      assert.is_nil(GMG.GetMapping("Alt", "R"))
    end)

    it("updates an existing entry when AssignToGroup uses a case-variant name", function()
      GMG.SetMapping("Bobsalt", "R", "Alice", { guild = "G", origin = "user", classFile = "WARRIOR", level = 60 })
      GMG.AssignToGroup("bobsalt", "R", "Bob", { guild = "G", origin = "note" })
      local underExact = GMG.GetMapping("Bobsalt", "R")
      assert.truthy(underExact)
      assert.are.equal("Bob", underExact.main)
      assert.are.equal("note", underExact.origin)
      -- Must update the existing key, not create a duplicate case-variant entry.
      local all = GMG.GetMappingsForGuild("G")
      local count = 0
      local storedName
      for _, e in ipairs(all) do
        if (e.name or ""):lower() == "bobsalt" then
          count = count + 1
          storedName = e.name
        end
      end
      assert.are.equal(1, count)
      assert.are.equal("Bobsalt", storedName)
    end)
  end)

  describe("ApplyProposal", function()
    it("writes the main anchor and non-alreadyMapped members", function()
      local proposal = {
        main = "Bob",
        members = {
          { name = "Bobsalt", noteText = "bob alt", noteHash = 1 },
          { name = "OldAlt", alreadyMapped = true, noteText = "old", noteHash = 2 },
        },
      }
      GMG.SetMapping("OldAlt", "R", "Bob", { guild = "G", origin = "note" })
      GMG.ApplyProposal(proposal, "R", "G", function(name)
        if name == "Bob" then return "MAGE", 70 end
        if name == "Bobsalt" then return "WARRIOR", 60 end
        return nil, nil
      end)
      assert.are.equal("Bob", GMG.GetMapping("Bob", "R").main)
      assert.are.equal("MAGE", GMG.GetMapping("Bob", "R").classFile)
      assert.are.equal(70, GMG.GetMapping("Bob", "R").level)
      assert.are.equal("Bob", GMG.GetMapping("Bobsalt", "R").main)
      assert.are.equal("note", GMG.GetMapping("Bobsalt", "R").origin)
      assert.are.equal("bob alt", GMG.GetMapping("Bobsalt", "R").noteText)
      assert.are.equal(1, GMG.GetMapping("Bobsalt", "R").noteHash)
      assert.are.equal("WARRIOR", GMG.GetMapping("Bobsalt", "R").classFile)
      -- alreadyMapped member left untouched (still mapped).
      assert.are.equal("Bob", GMG.GetMapping("OldAlt", "R").main)
    end)

    it("unmaps names listed in removedMappedNames", function()
      GMG.SetMapping("Bob", "R", "Bob", { guild = "G", origin = "note" })
      GMG.SetMapping("OldAlt", "R", "Bob", { guild = "G", origin = "note" })
      GMG.SetMapping("KeepAlt", "R", "Bob", { guild = "G", origin = "note" })
      local proposal = {
        main = "Bob",
        members = {
          { name = "KeepAlt", alreadyMapped = true },
        },
        removedMappedNames = { "OldAlt" },
      }
      GMG.ApplyProposal(proposal, "R", "G")
      assert.is_nil(GMG.GetMapping("OldAlt", "R"))
      assert.are.equal("Bob", GMG.GetMapping("KeepAlt", "R").main)
      assert.are.equal("Bob", GMG.GetMapping("Bob", "R").main)
    end)

    it("accept with all members removed writes only the anchor", function()
      local proposal = {
        main = "Bob",
        members = {},
        removedMappedNames = { "OldAlt" },
      }
      GMG.SetMapping("OldAlt", "R", "Bob", { guild = "G" })
      GMG.ApplyProposal(proposal, "R", "G")
      assert.are.equal("Bob", GMG.GetMapping("Bob", "R").main)
      assert.is_nil(GMG.GetMapping("OldAlt", "R"))
      -- No other members written.
      assert.are.equal(1, #GMG.GetMappingsForGuild("G"))
    end)

    it("merges under the root when the proposal main is already grouped elsewhere", function()
      GMG.SetMapping("Alice", "R", "Bob", { guild = "G", origin = "user" })
      local proposal = {
        main = "Alice",
        members = {
          { name = "Carol", noteText = "Alice alt", noteHash = 3 },
        },
      }
      GMG.ApplyProposal(proposal, "R", "G")
      -- Alice was already under Bob; Carol collapses under Bob, Alice stays under Bob.
      assert.are.equal("Bob", GMG.GetMapping("Carol", "R").main)
      assert.are.equal("Bob", GMG.GetMapping("Alice", "R").main)
      local alice = GMG.GetMapping("Alice", "R")
      assert.are.equal("Bob", alice.main)
    end)

    it("no-ops when proposal or main is missing", function()
      GMG.ApplyProposal(nil, "R", "G")
      GMG.ApplyProposal({ members = {} }, "R", "G")
      assert.are.equal(0, #GMG.GetMappingsForGuild("G"))
    end)

    it("defaults origin to note when opts is omitted", function()
      local proposal = {
        main = "Bob",
        members = { { name = "Bobsalt" } },
      }
      GMG.ApplyProposal(proposal, "R", "G")
      assert.are.equal("note", GMG.GetMapping("Bob", "R").origin)
      assert.are.equal("note", GMG.GetMapping("Bobsalt", "R").origin)
    end)

    it("uses opts.origin when provided (manual wizard)", function()
      local proposal = {
        main = "Bob",
        members = { { name = "Bobsalt" } },
      }
      GMG.ApplyProposal(proposal, "R", "G", nil, { origin = "user" })
      assert.are.equal("user", GMG.GetMapping("Bob", "R").origin)
      assert.are.equal("user", GMG.GetMapping("Bobsalt", "R").origin)
    end)

    it("keeps a remove-then-re-added member mapped (removedMappedNames vs members)", function()
      -- Notes wizard: remove alreadyMapped OldAlt (adds to removedMappedNames), then
      -- re-add via the add box. Accept must leave OldAlt mapped under Bob.
      GMG.SetMapping("Bob", "R", "Bob", { guild = "G", origin = "note" })
      GMG.SetMapping("OldAlt", "R", "Bob", { guild = "G", origin = "note" })
      GMG.SetMapping("KeepAlt", "R", "Bob", { guild = "G", origin = "note" })
      local proposal = {
        main = "Bob",
        members = {
          { name = "OldAlt", noteText = nil, noteHash = nil, addedManually = true },
          { name = "KeepAlt", alreadyMapped = true },
        },
        removedMappedNames = { "OldAlt" },
      }
      GMG.ApplyProposal(proposal, "R", "G")
      assert.are.equal("Bob", GMG.GetMapping("OldAlt", "R").main)
      assert.are.equal("Bob", GMG.GetMapping("KeepAlt", "R").main)
      assert.are.equal("Bob", GMG.GetMapping("Bob", "R").main)
    end)

    it("skips a member that equals the main differing only by case", function()
      local proposal = {
        main = "Bob",
        members = {
          { name = "bob" },
          { name = "Bobsalt" },
        },
      }
      GMG.ApplyProposal(proposal, "R", "G")
      assert.are.equal("Bob", GMG.GetMapping("Bob", "R").main)
      assert.are.equal("Bob", GMG.GetMapping("Bobsalt", "R").main)
      -- Case-variant of main must not create a second mapping entry.
      local all = GMG.GetMappingsForGuild("G")
      local bobCount = 0
      local storedName
      for _, e in ipairs(all) do
        if (e.name or ""):lower() == "bob" then
          bobCount = bobCount + 1
          storedName = e.name
        end
      end
      assert.are.equal(1, bobCount)
      assert.are.equal("Bob", storedName)
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

    it("retires when mains match case-insensitively", function()
      GMG.SetMapping("Alt", "R", "bobsalt", { guild = "G" })
      assert.is_true(GMG.RetireIfAgrees("Alt", "R", "Bobsalt"))
      assert.is_nil(GMG.GetMapping("Alt", "R"))
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
