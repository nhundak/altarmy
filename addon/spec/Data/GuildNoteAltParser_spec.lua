--[[
  Unit tests for GuildNoteAltParser.lua (guild note → main suggestions).
  Run from project root: npm test
]]

describe("GuildNoteAltParser", function()
  local GNP, GTD

  local function rosterSet(names)
    local set = {}
    for _, n in ipairs(names) do
      set[n:lower()] = n
    end
    return set
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("GuildTabData")
    require("GuildNoteAltParser")
    GNP = AltArmy.GuildNoteAltParser
    GTD = AltArmy.GuildTabData
    assert.truthy(GNP)
  end)

  describe("ParseNote", function()
    local roster

    before_each(function()
      roster = rosterSet({ "Bob", "Alice", "Carol" })
    end)

    it("matches 'alt of Bob'", function()
      local r = GNP.ParseNote("alt of Bob", roster)
      assert.truthy(r)
      assert.are.equal("Bob", r.main)
      assert.are.equal("alt_of", r.pattern)
    end)

    it("matches \"Bob's alt\"", function()
      local r = GNP.ParseNote("Bob's alt", roster)
      assert.are.equal("Bob", r.main)
      assert.are.equal("possessive_alt", r.pattern)
    end)

    it("matches Bob alt", function()
      local r = GNP.ParseNote("Bob alt", roster)
      assert.are.equal("Bob", r.main)
      assert.are.equal("name_alt", r.pattern)
    end)

    it("matches X not Y alt as an alt of X", function()
      local names = rosterSet({ "Serint", "Berint", "Bob", "Alice" })
      local r = GNP.ParseNote("serint not berint alt", names)
      assert.truthy(r)
      assert.are.equal("Serint", r.main)
      assert.are.equal("not_other_alt", r.pattern)
      -- Plain name_alt cases still resolve to the name before alt.
      assert.are.equal("Berint", GNP.ParseNote("berint alt", names).main)
      assert.are.equal("Bob", GNP.ParseNote("Bob alt", names).main)
    end)

    it("matches main is CharacterName", function()
      local r = GNP.ParseNote("main is Bob", roster)
      assert.are.equal("Bob", r.main)
      assert.are.equal("main_is", r.pattern)
      assert.are.equal("Alice", GNP.ParseNote("Main Is alice", roster).main)
    end)

    it("matches main: Bob and alt: Bob", function()
      assert.are.equal("Bob", GNP.ParseNote("main: Bob", roster).main)
      assert.are.equal("Alice", GNP.ParseNote("alt: Alice", roster).main)
      assert.are.equal("label", GNP.ParseNote("main: Bob", roster).pattern)
    end)

    it("matches '= Bob' and '(Bob)'", function()
      assert.are.equal("Bob", GNP.ParseNote("= Bob", roster).main)
      assert.are.equal("Bob", GNP.ParseNote("(Bob)", roster).main)
    end)

    it("matches a bare exact roster name", function()
      local r = GNP.ParseNote("Bob", roster)
      assert.are.equal("Bob", r.main)
      assert.are.equal("bare", r.pattern)
    end)

    it("matches Name dash professions notes", function()
      local names = rosterSet({ "Celewi", "Serint", "Bob" })
      local r1 = GNP.ParseNote("Celewi - Spellfire Specialty", names)
      assert.are.equal("Celewi", r1.main)
      assert.are.equal("name_dash", r1.pattern)

      local r2 = GNP.ParseNote("Serint - lw/ski", names)
      assert.are.equal("Serint", r2.main)
      assert.are.equal("name_dash", r2.pattern)

      local r3 = GNP.ParseNote("Serint - eng/min", names)
      assert.are.equal("Serint", r3.main)
      assert.are.equal("name_dash", r3.pattern)

      local r4 = GNP.ParseNote("bob - mining", names)
      assert.are.equal("Bob", r4.main)
    end)

    it("rejects Name dash relationship notes that are not profession-like", function()
      local names = rosterSet({ "Unburdened", "Jemmandi", "Bob" })
      assert.is_nil(GNP.ParseNote("Unburdened - Wife", names))
      assert.is_nil(GNP.ParseNote("Bob - husband", names))
      assert.is_nil(GNP.ParseNote("Bob - tank", names))
    end)

    it("IsProfessionLikeSuffix accepts profession text and rejects relationship labels", function()
      assert.is_true(GNP.IsProfessionLikeSuffix("lw/ski"))
      assert.is_true(GNP.IsProfessionLikeSuffix("eng/min"))
      assert.is_true(GNP.IsProfessionLikeSuffix("Spellfire Specialty"))
      assert.is_true(GNP.IsProfessionLikeSuffix("mining"))
      assert.is_true(GNP.IsProfessionLikeSuffix("Tailoring"))
      assert.is_false(GNP.IsProfessionLikeSuffix("Wife"))
      assert.is_false(GNP.IsProfessionLikeSuffix("husband"))
      assert.is_false(GNP.IsProfessionLikeSuffix("tank"))
      assert.is_false(GNP.IsProfessionLikeSuffix(""))
      assert.is_false(GNP.IsProfessionLikeSuffix(nil))
    end)

    it("rejects Name dash with no trailing text and unknown dash names", function()
      assert.is_nil(GNP.ParseNote("Bob -", roster))
      assert.is_nil(GNP.ParseNote("Bob -   ", roster))
      assert.is_nil(GNP.ParseNote("Nobody - eng/min", roster))
    end)

    it("rejects candidates that are not on the roster", function()
      assert.is_nil(GNP.ParseNote("alt of Nobody", roster))
      assert.is_nil(GNP.ParseNote("Nobody's alt", roster))
      assert.is_nil(GNP.ParseNote("Nobody", roster))
    end)

    it("is case-insensitive for matching but returns roster casing", function()
      local r = GNP.ParseNote("ALT OF bob", roster)
      assert.are.equal("Bob", r.main)
    end)

    it("returns nil for empty or nil notes", function()
      assert.is_nil(GNP.ParseNote(nil, roster))
      assert.is_nil(GNP.ParseNote("", roster))
      assert.is_nil(GNP.ParseNote("   ", roster))
    end)

    it("ignores notes that do not match any pattern", function()
      assert.is_nil(GNP.ParseNote("rank officer since 2020", roster))
      assert.is_nil(GNP.ParseNote("likes pie", roster))
    end)

    it("falls through to a later pattern when an earlier candidate is off-roster", function()
      -- "alt of Zed" matches first but Zed is not on the roster; "(Bob)" should win.
      local r = GNP.ParseNote("alt of Zed (Bob)", roster)
      assert.truthy(r)
      assert.are.equal("Bob", r.main)
      assert.are.equal("parens", r.pattern)
    end)

    it("does not error or invent candidates from notes with pipe escape sequences", function()
      assert.is_nil(GNP.ParseNote("|cff00ff00Hacked|r", roster))
      assert.is_nil(GNP.ParseNote("|TInterface\\Icons\\INV_Misc_QuestionMark:16|t", roster))
      -- A real roster match still works even when the note also contains escapes.
      local r = GNP.ParseNote("alt of Bob |cff00ff00wow|r", roster)
      assert.truthy(r)
      assert.are.equal("Bob", r.main)
    end)
  end)

  describe("HashNote", function()
    it("returns a stable number for the same text", function()
      local a = GNP.HashNote("bob alt")
      local b = GNP.HashNote("bob alt")
      assert.are.equal(a, b)
      assert.is_true(type(a) == "number")
    end)

    it("differs when the note changes", function()
      assert.is_true(GNP.HashNote("bob alt") ~= GNP.HashNote("alice alt"))
    end)
  end)

  describe("ScanRoster", function()
    it("suggests mappings from public and officer notes", function()
      local rosterEntries = {
        { name = "Bobsalt", publicNote = "bob alt", officerNote = "" },
        { name = "Alicealt", publicNote = "", officerNote = "alt of Alice" },
        { name = "Bob", publicNote = "", officerNote = "" },
        { name = "Alice", publicNote = "", officerNote = "" },
      }
      local suggestions = GNP.ScanRoster(rosterEntries, {}, {})
      assert.are.equal(2, #suggestions)
      local byName = {}
      for _, s in ipairs(suggestions) do byName[s.name] = s end
      assert.are.equal("Bob", byName.Bobsalt.main)
      assert.are.equal("bob alt", byName.Bobsalt.noteText)
      assert.truthy(byName.Bobsalt.noteHash)
      assert.are.equal("Alice", byName.Alicealt.main)
    end)

    it("skips characters already covered by stored addon chars", function()
      local rosterEntries = {
        { name = "Bobsalt", publicNote = "bob alt" },
        { name = "Bob", publicNote = "" },
      }
      local storedChars = { Bobsalt = { name = "Bobsalt", main = "Other" } }
      local suggestions = GNP.ScanRoster(rosterEntries, {}, storedChars)
      assert.are.equal(0, #suggestions)
    end)

    it("skips characters when storedChars keys differ only by case", function()
      local rosterEntries = {
        { name = "Bobsalt", publicNote = "bob alt" },
        { name = "Bob", publicNote = "" },
      }
      local storedChars = { bobsalt = { name = "Bobsalt", main = "Other" } }
      assert.are.equal(0, #GNP.ScanRoster(rosterEntries, {}, storedChars))
    end)

    it("skips characters when existingMappings keys differ only by case", function()
      local note = "bob alt"
      local hash = GNP.HashNote(note)
      local rosterEntries = {
        { name = "Bobsalt", publicNote = note },
        { name = "Bob", publicNote = "" },
      }
      local existing = {
        bobsalt = { main = "Bob", origin = "note", noteHash = hash },
      }
      assert.are.equal(0, #GNP.ScanRoster(rosterEntries, existing, {}))
    end)

    it("skips characters with an accepted unchanged note mapping", function()
      local note = "bob alt"
      local hash = GNP.HashNote(note)
      local rosterEntries = {
        { name = "Bobsalt", publicNote = note },
        { name = "Bob", publicNote = "" },
      }
      local existing = {
        Bobsalt = { main = "Bob", origin = "note", noteHash = hash },
      }
      assert.are.equal(0, #GNP.ScanRoster(rosterEntries, existing, {}))
    end)

    it("re-suggests when an accepted note has changed", function()
      local rosterEntries = {
        { name = "Bobsalt", publicNote = "bob alt NOW" },
        { name = "Bob", publicNote = "" },
      }
      local existing = {
        Bobsalt = { main = "Bob", origin = "note", noteHash = GNP.HashNote("bob alt") },
      }
      local suggestions = GNP.ScanRoster(rosterEntries, existing, {})
      assert.are.equal(1, #suggestions)
      assert.are.equal("Bob", suggestions[1].main)
    end)

    it("does not suggest a character as an alt of itself", function()
      local rosterEntries = {
        { name = "Bob", publicNote = "Bob" },
      }
      assert.are.equal(0, #GNP.ScanRoster(rosterEntries, {}, {}))
    end)

    it("never re-suggests origin user mappings even when the note changed", function()
      local rosterEntries = {
        { name = "Bobsalt", publicNote = "alice alt NOW" },
        { name = "Bob", publicNote = "" },
        { name = "Alice", publicNote = "" },
      }
      local existing = {
        Bobsalt = { main = "Bob", origin = "user", noteHash = GNP.HashNote("bob alt") },
      }
      assert.are.equal(0, #GNP.ScanRoster(rosterEntries, existing, {}))
    end)

    it("re-suggests under a new main when an accepted note points elsewhere", function()
      local rosterEntries = {
        { name = "Bobsalt", publicNote = "alice alt" },
        { name = "Bob", publicNote = "" },
        { name = "Alice", publicNote = "" },
      }
      local existing = {
        Bobsalt = { main = "Bob", origin = "note", noteHash = GNP.HashNote("bob alt") },
      }
      local suggestions = GNP.ScanRoster(rosterEntries, existing, {})
      assert.are.equal(1, #suggestions)
      assert.are.equal("Bobsalt", suggestions[1].name)
      assert.are.equal("Alice", suggestions[1].main)
    end)

    it("prefers the public note over a disagreeing officer note", function()
      local rosterEntries = {
        { name = "Bobsalt", publicNote = "bob alt", officerNote = "alice alt" },
        { name = "Bob", publicNote = "" },
        { name = "Alice", publicNote = "" },
      }
      local suggestions = GNP.ScanRoster(rosterEntries, {}, {})
      assert.are.equal(1, #suggestions)
      assert.are.equal("Bob", suggestions[1].main)
      assert.are.equal("bob alt", suggestions[1].noteText)
    end)

    it("produces no suggestion when a previously accepted note is cleared", function()
      local rosterEntries = {
        { name = "Bobsalt", publicNote = "", officerNote = "" },
        { name = "Bob", publicNote = "" },
      }
      local existing = {
        Bobsalt = { main = "Bob", origin = "note", noteHash = GNP.HashNote("bob alt") },
      }
      assert.are.equal(0, #GNP.ScanRoster(rosterEntries, existing, {}))
    end)

    it("does not match non-ASCII names with %a patterns (documented limitation)", function()
      local names = rosterSet({ "Ångela", "Bob" })
      -- Accented candidate names are not matched by the current [%a%d]+ patterns.
      assert.is_nil(GNP.ParseNote("alt of Ångela", names))
      assert.is_nil(GNP.ParseNote("Ångela", names))
      -- ASCII patterns still work alongside roster entries that happen to be non-ASCII.
      assert.are.equal("Bob", GNP.ParseNote("alt of Bob", names).main)
    end)

    it("lists stale manual mappings whose character left the roster", function()
      local rosterEntries = {
        { name = "Bob", publicNote = "" },
      }
      local existing = {
        GoneAlt = { main = "Bob", origin = "user" },
        Bobsalt = { main = "Bob", origin = "note" },
      }
      -- Bobsalt not on roster either
      local stale = GNP.FindStaleMappings(existing, rosterEntries)
      assert.are.equal(2, #stale)
      local names = {}
      for _, s in ipairs(stale) do names[s.name] = s.main end
      assert.are.equal("Bob", names.GoneAlt)
      assert.are.equal("Bob", names.Bobsalt)
    end)

    it("does not report mappings whose main left the roster while the alt remains (documented)", function()
      -- Current behavior: only the mapped character's roster presence is checked.
      -- A mapping Alt→GoneMain with Alt still on roster is not considered stale.
      local rosterEntries = {
        { name = "StillHere", publicNote = "" },
        { name = "Bob", publicNote = "" },
      }
      local existing = {
        StillHere = { main = "GoneMain", origin = "user" },
      }
      local stale = GNP.FindStaleMappings(existing, rosterEntries)
      assert.are.equal(0, #stale)
    end)
  end)

  describe("CollapseSuggestionChains", function()
    it("rewrites alt-of-alt suggestions onto the root main", function()
      -- CharacterB → CharacterA, CharacterC → CharacterB  ⇒  both under CharacterA
      local collapsed = GNP.CollapseSuggestionChains({
        { name = "CharacterB", main = "CharacterA", noteText = "CharacterA's alt", noteHash = 1 },
        { name = "CharacterC", main = "CharacterB", noteText = "CharacterB's alt", noteHash = 2 },
      })
      assert.are.equal(2, #collapsed)
      local byName = {}
      for _, s in ipairs(collapsed) do byName[s.name] = s end
      assert.are.equal("CharacterA", byName.CharacterB.main)
      assert.are.equal("CharacterA", byName.CharacterC.main)
      assert.are.equal("CharacterB's alt", byName.CharacterC.noteText)
    end)

    it("follows longer chains to the root", function()
      local collapsed = GNP.CollapseSuggestionChains({
        { name = "B", main = "A", noteText = "A alt", noteHash = 1 },
        { name = "C", main = "B", noteText = "B alt", noteHash = 2 },
        { name = "D", main = "C", noteText = "C alt", noteHash = 3 },
      })
      for _, s in ipairs(collapsed) do
        assert.are.equal("A", s.main)
      end
    end)

    it("follows existing mappings when the intermediate main is already grouped", function()
      -- B already mapped to A; C's note points at B ⇒ collapse C under A
      local collapsed = GNP.CollapseSuggestionChains({
        { name = "CharacterC", main = "CharacterB", noteText = "CharacterB's alt", noteHash = 2 },
      }, {
        CharacterB = { main = "CharacterA", origin = "note" },
      })
      assert.are.equal(1, #collapsed)
      assert.are.equal("CharacterA", collapsed[1].main)
      assert.are.equal("CharacterC", collapsed[1].name)
    end)

    it("leaves suggestions unchanged when there is no chain", function()
      local collapsed = GNP.CollapseSuggestionChains({
        { name = "Bobsalt", main = "Bob", noteText = "bob alt", noteHash = 1 },
      })
      assert.are.equal(1, #collapsed)
      assert.are.equal("Bob", collapsed[1].main)
      assert.are.equal("Bobsalt", collapsed[1].name)
    end)

    it("keeps original mains when a cycle is detected", function()
      local collapsed = GNP.CollapseSuggestionChains({
        { name = "Alice", main = "Bob", noteText = "Bob's alt", noteHash = 1 },
        { name = "Bob", main = "Alice", noteText = "Alice's alt", noteHash = 2 },
      })
      local byName = {}
      for _, s in ipairs(collapsed) do byName[s.name] = s end
      assert.are.equal("Bob", byName.Alice.main)
      assert.are.equal("Alice", byName.Bob.main)
    end)

    it("does not mutate the input list", function()
      local suggestions = {
        { name = "C", main = "B", noteText = "B alt", noteHash = 1 },
        { name = "B", main = "A", noteText = "A alt", noteHash = 2 },
      }
      GNP.CollapseSuggestionChains(suggestions)
      assert.are.equal("B", suggestions[1].main)
      assert.are.equal("A", suggestions[2].main)
    end)

    it("returns empty for nil or empty input", function()
      assert.are.equal(0, #GNP.CollapseSuggestionChains(nil))
      assert.are.equal(0, #GNP.CollapseSuggestionChains({}))
    end)

    it("follows Alt Army shared data when a note points at a known alt", function()
      -- Shared: CharacterB → CharacterA. Note: CharacterC → CharacterB ⇒ collapse onto CharacterA.
      local collapsed = GNP.CollapseSuggestionChains({
        { name = "CharacterC", main = "CharacterB", noteText = "Alt of CharacterB", noteHash = 1 },
      }, nil, {
        { name = "CharacterA", main = "CharacterA" },
        { name = "CharacterB", main = "CharacterA" },
      })
      assert.are.equal(1, #collapsed)
      assert.are.equal("CharacterC", collapsed[1].name)
      assert.are.equal("CharacterA", collapsed[1].main)
      assert.are.equal("Alt of CharacterB", collapsed[1].noteText)
    end)

    it("ignores self-main shared rows so they do not create cycles", function()
      local collapsed = GNP.CollapseSuggestionChains({
        { name = "Alt", main = "Bob", noteText = "bob alt", noteHash = 1 },
      }, nil, {
        { name = "Bob", main = "Bob" },
      })
      assert.are.equal(1, #collapsed)
      assert.are.equal("Bob", collapsed[1].main)
    end)
  end)

  describe("GroupSuggestionsByMain", function()
    it("groups flat suggestions under each proposed main", function()
      local proposals = GNP.GroupSuggestionsByMain({
        { name = "Bobsalt", main = "Bob", noteText = "bob alt", noteHash = 1, pattern = "name_alt" },
        { name = "Bobtwo", main = "Bob", noteText = "alt of Bob", noteHash = 2, pattern = "alt_of" },
        { name = "Alicealt", main = "Alice", noteText = "Alice's alt", noteHash = 3, pattern = "possessive_alt" },
      })
      assert.are.equal(2, #proposals)
      -- Sorted by main name
      assert.are.equal("Alice", proposals[1].main)
      assert.are.equal("Alice", proposals[1].displayName)
      assert.are.equal(1, #proposals[1].members)
      assert.are.equal("Alicealt", proposals[1].members[1].name)
      assert.are.equal("Alice's alt", proposals[1].members[1].noteText)

      assert.are.equal("Bob", proposals[2].main)
      assert.are.equal(2, #proposals[2].members)
      assert.are.equal("Bobsalt", proposals[2].members[1].name)
      assert.are.equal("Bobtwo", proposals[2].members[2].name)
    end)

    it("collapses chains into a single root group before grouping", function()
      local proposals = GNP.GroupSuggestionsByMain({
        { name = "CharacterB", main = "CharacterA", noteText = "CharacterA's alt", noteHash = 1 },
        { name = "CharacterC", main = "CharacterB", noteText = "CharacterB's alt", noteHash = 2 },
      })
      assert.are.equal(1, #proposals)
      assert.are.equal("CharacterA", proposals[1].main)
      assert.are.equal(2, #proposals[1].members)
      assert.are.equal("CharacterB", proposals[1].members[1].name)
      assert.are.equal("CharacterC", proposals[1].members[2].name)
      assert.are.equal("CharacterB's alt", proposals[1].members[2].noteText)
    end)

    it("includes existingMappings already under a proposed main", function()
      -- New note match creates the Nosgotho proposal; a previously accepted
      -- "Nosgotho alt" mapping should still appear in the member list.
      local proposals = GNP.GroupSuggestionsByMain({
        { name = "NewAlt", main = "Nosgotho", noteText = "Main is Nosgotho", noteHash = 1 },
      }, {
        Nosgotho = { main = "Nosgotho", origin = "note", guild = "G" },
        OldAlt = {
          main = "Nosgotho",
          origin = "note",
          noteText = "Nosgotho alt",
          noteHash = 99,
          guild = "G",
        },
        OtherGuildAlt = { main = "SomeoneElse", origin = "user", guild = "G" },
      })
      assert.are.equal(1, #proposals)
      assert.are.equal("Nosgotho", proposals[1].main)
      assert.are.equal(2, #proposals[1].members)
      assert.are.equal("NewAlt", proposals[1].members[1].name)
      assert.are.equal("OldAlt", proposals[1].members[2].name)
      assert.are.equal("Nosgotho alt", proposals[1].members[2].noteText)
      assert.is_true(proposals[1].members[2].alreadyMapped)
      assert.is_nil(proposals[1].members[1].alreadyMapped)
    end)

    it("collapses through existingMappings when grouping", function()
      local proposals = GNP.GroupSuggestionsByMain({
        { name = "CharacterC", main = "CharacterB", noteText = "CharacterB's alt", noteHash = 2 },
      }, {
        CharacterB = { main = "CharacterA", origin = "user" },
      })
      assert.are.equal(1, #proposals)
      assert.are.equal("CharacterA", proposals[1].main)
      -- CharacterB is already mapped under CharacterA; include them too.
      assert.are.equal(2, #proposals[1].members)
      assert.are.equal("CharacterB", proposals[1].members[1].name)
      assert.is_true(proposals[1].members[1].alreadyMapped)
      assert.are.equal("CharacterC", proposals[1].members[2].name)
    end)

    it("collapses through Alt Army shared data when grouping", function()
      local proposals = GNP.GroupSuggestionsByMain({
        { name = "CharacterC", main = "CharacterB", noteText = "Alt of CharacterB", noteHash = 1 },
      }, nil, {
        { name = "CharacterA", main = "CharacterA" },
        { name = "CharacterB", main = "CharacterA" },
      })
      assert.are.equal(1, #proposals)
      assert.are.equal("CharacterA", proposals[1].main)
      assert.are.equal(1, #proposals[1].members)
      assert.are.equal("CharacterC", proposals[1].members[1].name)
    end)

    it("returns empty for nil or empty suggestions", function()
      assert.are.equal(0, #GNP.GroupSuggestionsByMain(nil))
      assert.are.equal(0, #GNP.GroupSuggestionsByMain({}))
    end)

    it("copies proposals so callers can edit members without mutating input", function()
      local suggestions = {
        { name = "Bobsalt", main = "Bob", noteText = "bob alt", noteHash = 1 },
      }
      local proposals = GNP.GroupSuggestionsByMain(suggestions)
      proposals[1].displayName = "Bobby"
      table.remove(proposals[1].members, 1)
      assert.are.equal("Bob", suggestions[1].main)
      assert.are.equal("Bobsalt", suggestions[1].name)
    end)

    it("merges suggestions whose resolved mains differ only by case", function()
      local proposals = GNP.GroupSuggestionsByMain({
        { name = "Bobsalt", main = "Bob", noteText = "bob alt", noteHash = 1 },
        { name = "Bobtwo", main = "bob", noteText = "alt of bob", noteHash = 2 },
      })
      assert.are.equal(1, #proposals)
      assert.are.equal("Bob", proposals[1].main)
      assert.are.equal(2, #proposals[1].members)
      local memberNames = {}
      for _, m in ipairs(proposals[1].members) do
        memberNames[#memberNames + 1] = m.name
      end
      table.sort(memberNames)
      assert.are.same({ "Bobsalt", "Bobtwo" }, memberNames)
    end)

    it("scan-level mutual-alt notes produce two proposals that ApplyProposal resolves without a cycle", function()
      local rosterEntries = {
        { name = "Alice", publicNote = "Bob's alt" },
        { name = "Bob", publicNote = "Alice's alt" },
      }
      local suggestions = GNP.ScanRoster(rosterEntries, {}, {})
      local proposals = GNP.GroupSuggestionsByMain(suggestions)
      -- Cycle keeps original mains → two proposals (Alice under Bob, Bob under Alice).
      assert.are.equal(2, #proposals)
      local byMain = {}
      for _, p in ipairs(proposals) do byMain[p.main] = p end
      assert.truthy(byMain.Bob)
      assert.truthy(byMain.Alice)
      assert.are.equal(1, #byMain.Bob.members)
      assert.are.equal("Alice", byMain.Bob.members[1].name)
      assert.are.equal(1, #byMain.Alice.members)
      assert.are.equal("Bob", byMain.Alice.members[1].name)

      -- Accepting both halves uses AssignToGroup cycle-break; no stored cycle remains.
      require("GuildManualGroups")
      local GMG = AltArmy.GuildManualGroups
      assert.truthy(GMG)
      _G.AltArmyTBC_GuildData = { manual = {} }
      GMG.ApplyProposal(byMain.Bob, "R", "G")
      GMG.ApplyProposal(byMain.Alice, "R", "G")
      assert.are.equal("Alice", GMG.GetMapping("Bob", "R").main)
      local alice = GMG.GetMapping("Alice", "R")
      assert.truthy(alice)
      assert.are.equal("Alice", alice.main)
    end)
  end)

  describe("EnrichProposalsWithSharedData", function()
    it("marks mains known from Alt Army data and appends other shared group members", function()
      local proposals = {
        {
          main = "Alice",
          displayName = "Alice",
          members = {
            { name = "NoteAlt", noteText = "Alice's alt", noteHash = 1 },
          },
        },
      }
      local shared = {
        { name = "Alice", main = "Alice" },
        { name = "SharedAlt", main = "Alice" },
        { name = "SharedTwo", main = "Alice" },
        { name = "OtherMain", main = "OtherMain" },
      }
      local out = GNP.EnrichProposalsWithSharedData(proposals, shared)
      assert.are.equal(1, #out)
      assert.is_true(out[1].mainFromShared)
      assert.are.equal(2, #out[1].knownMembers)
      assert.are.equal("SharedAlt", out[1].knownMembers[1].name)
      assert.are.equal("SharedTwo", out[1].knownMembers[2].name)
      -- Note-deduced member is not duplicated into knownMembers.
      assert.are.equal(1, #out[1].members)
      assert.are.equal("NoteAlt", out[1].members[1].name)
    end)

    it("fills displayName from the shared preferred name when it differs from the main", function()
      local proposals = {
        {
          main = "Alice",
          displayName = "Alice",
          members = { { name = "NoteAlt", noteText = "Alice's alt", noteHash = 1 } },
        },
      }
      local out = GNP.EnrichProposalsWithSharedData(proposals, {
        { name = "Alice", main = "Alice", displayName = "Allie" },
        { name = "SharedAlt", main = "Alice", displayName = "Allie" },
      })
      assert.is_true(out[1].mainFromShared)
      assert.are.equal("Allie", out[1].displayName)
    end)

    it("prefers the main character's shared displayName over an alt's", function()
      local proposals = {
        {
          main = "Alice",
          displayName = "Alice",
          members = { { name = "NoteAlt", noteText = "Alice's alt", noteHash = 1 } },
        },
      }
      local out = GNP.EnrichProposalsWithSharedData(proposals, {
        { name = "SharedAlt", main = "Alice", displayName = "Wrong" },
        { name = "Alice", main = "Alice", displayName = "Allie" },
      })
      assert.are.equal("Allie", out[1].displayName)
    end)

    it("keeps character-name displayName when shared data has no preferred name", function()
      local proposals = {
        {
          main = "Alice",
          displayName = "Alice",
          members = { { name = "NoteAlt", noteText = "Alice's alt", noteHash = 1 } },
        },
      }
      local out = GNP.EnrichProposalsWithSharedData(proposals, {
        { name = "Alice", main = "Alice" },
      })
      assert.are.equal("Alice", out[1].displayName)
    end)

    it("leaves mainFromShared false when the main has no shared data", function()
      local proposals = {
        {
          main = "Nobody",
          displayName = "Nobody",
          members = { { name = "Alt", noteText = "Nobody alt", noteHash = 1 } },
        },
      }
      local out = GNP.EnrichProposalsWithSharedData(proposals, {
        { name = "Alice", main = "Alice" },
      })
      assert.is_false(out[1].mainFromShared)
      assert.are.equal(0, #out[1].knownMembers)
    end)

    it("treats a shared alt's main as known even when the main row is only implied", function()
      -- Shared data has SharedAlt → Alice, but no Alice character entry.
      local proposals = {
        {
          main = "Alice",
          displayName = "Alice",
          members = { { name = "NoteAlt", noteText = "Alice's alt", noteHash = 1 } },
        },
      }
      local out = GNP.EnrichProposalsWithSharedData(proposals, {
        { name = "SharedAlt", main = "Alice" },
      })
      assert.is_true(out[1].mainFromShared)
      assert.are.equal(1, #out[1].knownMembers)
      assert.are.equal("SharedAlt", out[1].knownMembers[1].name)
    end)

    it("returns empty for nil proposals", function()
      assert.are.equal(0, #GNP.EnrichProposalsWithSharedData(nil, {}))
    end)
  end)

  describe("CollectProposalOccupiedNames", function()
    it("collects mains, members, and knownMembers across all proposals", function()
      local occupied = GNP.CollectProposalOccupiedNames({
        {
          main = "Alice",
          members = {
            { name = "NoteAlt" },
            { name = "NoteTwo" },
          },
          knownMembers = {
            { name = "SharedAlt" },
          },
        },
        {
          main = "Bob",
          members = {
            { name = "Bobsalt" },
          },
        },
      })
      assert.is_true(occupied.alice)
      assert.is_true(occupied.notealt)
      assert.is_true(occupied.notetwo)
      assert.is_true(occupied.sharedalt)
      assert.is_true(occupied.bob)
      assert.is_true(occupied.bobsalt)
      assert.is_nil(occupied.carol)
    end)

    it("returns empty for nil or empty proposals", function()
      local empty = GNP.CollectProposalOccupiedNames(nil)
      assert.are.equal(0, (function()
        local n = 0
        for _ in pairs(empty) do n = n + 1 end
        return n
      end)())
      assert.are.equal(0, (function()
        local set = GNP.CollectProposalOccupiedNames({})
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        return n
      end)())
    end)

    it("dedupes names that appear in multiple proposals", function()
      local occupied = GNP.CollectProposalOccupiedNames({
        { main = "Alice", members = { { name = "Shared" } } },
        { main = "Bob", members = { { name = "Shared" } }, knownMembers = { { name = "Alice" } } },
      })
      assert.is_true(occupied.alice)
      assert.is_true(occupied.shared)
      assert.is_true(occupied.bob)
    end)
  end)

  describe("FilterProposalsExcludingNames", function()
    it("drops proposals whose main is in the excluded set", function()
      local out = GNP.FilterProposalsExcludingNames({
        {
          main = "MyMain",
          members = { { name = "GuildAlt" } },
        },
        {
          main = "Other",
          members = { { name = "OtherAlt" } },
        },
      }, { mymain = true })
      assert.are.equal(1, #out)
      assert.are.equal("Other", out[1].main)
    end)

    it("strips excluded members and knownMembers from kept proposals", function()
      local out = GNP.FilterProposalsExcludingNames({
        {
          main = "Alice",
          members = {
            { name = "NoteAlt" },
            { name = "MyAlt" },
          },
          knownMembers = {
            { name = "SharedAlt" },
            { name = "MyMain" },
          },
        },
      }, { myalt = true, mymain = true })
      assert.are.equal(1, #out)
      assert.are.equal(1, #out[1].members)
      assert.are.equal("NoteAlt", out[1].members[1].name)
      assert.are.equal(1, #out[1].knownMembers)
      assert.are.equal("SharedAlt", out[1].knownMembers[1].name)
    end)

    it("drops a proposal that has no members left after stripping excluded names", function()
      local out = GNP.FilterProposalsExcludingNames({
        {
          main = "Alice",
          members = { { name = "MyAlt" } },
          knownMembers = { { name = "SharedAlt" } },
        },
      }, { myalt = true })
      assert.are.equal(0, #out)
    end)

    it("returns empty for nil proposals or nil excluded set", function()
      assert.are.equal(0, #GNP.FilterProposalsExcludingNames(nil, { a = true }))
      local kept = GNP.FilterProposalsExcludingNames({
        { main = "Alice", members = { { name = "Alt" } } },
      }, nil)
      assert.are.equal(1, #kept)
    end)

    it("matches excluded names case-insensitively", function()
      local out = GNP.FilterProposalsExcludingNames({
        { main = "MyMain", members = { { name = "GuildAlt" } } },
      }, { MYMAIN = true })
      assert.are.equal(0, #out)
    end)
  end)
end)
