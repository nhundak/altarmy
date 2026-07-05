--[[
  Unit tests for GuildShareData.lua (received guildmate data store).
  Run from project root: npm test
]]

describe("GuildShareData", function()
  local GSD, P
  local NOW = 1700000000

  local function presence(main, chars)
    return { v = 1, main = main, displayName = main and (main .. "!"), chars = chars }
  end

  local function charEntry(name, profs)
    return { name = name, realm = "R", classFile = "MAGE", faction = "Alliance", level = 70, profs = profs or {} }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.time = function() return NOW end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("GuildShareProtocol")
    require("GuildShareData")
    GSD = AltArmy.GuildShareData
    P = AltArmy.GuildShareProtocol
    assert.truthy(GSD)
  end)

  before_each(function()
    _G.AltArmyTBC_GuildData = nil
    GSD._Ensure()
  end)

  describe("SaveReceived / getters", function()
    it("stores each character under realm keyed by name with guild + main + source", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 375, count = 2, rv = 42 } }),
        charEntry("Alt", {}),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")

      local members = GSD.GetGuildMembers("G")
      assert.are.equal(2, #members)

      local main = GSD.GetCharacter("Main", "R")
      assert.are.equal("G", main.guildName)
      assert.are.equal("Main", main.main)
      assert.is_true(main.isMain)
      assert.are.equal("Main", main.source)
      assert.are.equal(NOW, main.receivedAt)

      local alt = GSD.GetCharacter("Alt", "R")
      assert.are.equal("Main", alt.main)
      assert.is_false(alt.isMain)
    end)

    it("guesses a main for received data when the sender declares none (level, then item level)", function()
      -- Sender hasn't picked a main (presence.main nil). Same level, differing item level:
      -- the higher-item-level character becomes the implicit main for the whole group.
      local msg = {
        v = 1, main = nil, chars = {
          { name = "Lowgear", classFile = "MAGE", level = 70, itemLevel = 100, profs = {} },
          { name = "Topgear", classFile = "MAGE", level = 70, itemLevel = 145, profs = {} },
          { name = "Leveler", classFile = "WARRIOR", level = 40, itemLevel = 200, profs = {} },
        },
      }
      GSD.SaveReceived("Peer", P.ParsePresence(msg), "G", "R")
      local top = GSD.GetCharacter("Topgear", "R")
      local low = GSD.GetCharacter("Lowgear", "R")
      assert.are.equal("Topgear", top.main)
      assert.is_true(top.isMain)
      assert.are.equal("Topgear", low.main)
      assert.is_false(low.isMain)
      assert.are.equal("Topgear", GSD.GetCharacter("Leveler", "R").main)
    end)

    it("stores received item level and keeps a sender-declared main untouched", function()
      local msg = {
        v = 1, main = "Declared", chars = {
          { name = "Declared", classFile = "MAGE", level = 70, itemLevel = 90, profs = {} },
          { name = "Beefy", classFile = "WARRIOR", level = 70, itemLevel = 150, profs = {} },
        },
      }
      GSD.SaveReceived("Peer", P.ParsePresence(msg), "G", "R")
      local declared = GSD.GetCharacter("Declared", "R")
      assert.are.equal("Declared", declared.main)
      assert.is_true(declared.isMain)
      assert.are.equal(150, GSD.GetCharacter("Beefy", "R").itemLevel)
      assert.is_false(GSD.GetCharacter("Beefy", "R").isMain)
    end)

    it("stores a received profession specialization", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 375, spec = "Spellfire" } }),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      assert.are.equal("Spellfire", GSD.GetCharacter("Main", "R").Professions.tailoring.spec)
    end)

    it("GetMainOf resolves an alt to its main, and a main to itself", function()
      local msg = presence("Main", { charEntry("Main"), charEntry("Alt") })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      assert.are.equal("Main", GSD.GetMainOf("Alt", "R"))
      assert.are.equal("Main", GSD.GetMainOf("Main", "R"))
      assert.is_nil(GSD.GetMainOf("Stranger", "R"))
    end)
  end)

  describe("PresenceMatchesStored", function()
    local function parsed(main, chars)
      return P.ParsePresence(presence(main, chars))
    end

    it("returns false when no prior data exists", function()
      assert.is_false(GSD.PresenceMatchesStored("Peer", parsed("Main", { charEntry("Main") }), "R"))
    end)

    it("returns true when presence matches stored data", function()
      local msg = parsed("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 375, count = 2, rv = 42 } }),
        charEntry("Alt", {}),
      })
      GSD.SaveReceived("Peer", msg, "G", "R")
      assert.is_true(GSD.PresenceMatchesStored("Peer", msg, "R"))
    end)

    it("returns false when level changes", function()
      local msg = parsed("Main", { charEntry("Main") })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = P.ParsePresence(presence("Main", {
        { name = "Main", realm = "R", classFile = "MAGE", faction = "Alliance", level = 71, profs = {} },
      }))
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when rv changes", function()
      local rv1 = P.HashRecipeIDs({ 100, 200 })
      local rv2 = P.HashRecipeIDs({ 100, 200, 300 })
      local msg = parsed("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = rv1 } }),
      })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 3, rv = rv2 } }),
      }))
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when main changes", function()
      local msg = parsed("Main", { charEntry("Main"), charEntry("Alt") })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = parsed("Alt", { charEntry("Main"), charEntry("Alt") })
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when displayName changes", function()
      local msg = P.ParsePresence({ v = 1, main = "Main", displayName = "OldName", chars = { charEntry("Main") } })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = P.ParsePresence({ v = 1, main = "Main", displayName = "NewName", chars = { charEntry("Main") } })
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when spec changes", function()
      local msg = parsed("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, spec = "Spellfire" } }),
      })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = parsed("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, spec = "Shadoweave" } }),
      })
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)

    it("returns false when a new char appears in presence", function()
      local msg = parsed("Main", { charEntry("Main") })
      GSD.SaveReceived("Peer", msg, "G", "R")
      local changed = parsed("Main", { charEntry("Main"), charEntry("NewAlt") })
      assert.is_false(GSD.PresenceMatchesStored("Peer", changed, "R"))
    end)
  end)

  describe("recipe pull tracking", function()
    it("flags professions as needing recipes until SaveRecipes fills them", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 375, count = 2,
          rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Main", "R"))

      GSD.SaveRecipes("R", { v = 1, name = "Main", profs = { { key = "tailoring", ids = { 100, 200 } } } })
      assert.are.same({}, GSD.GetProfessionsNeedingRecipes("Main", "R"))

      local profs = GSD.GetRecipesFor("Main", "R")
      assert.truthy(profs.tailoring.Recipes[100])
      assert.are.equal(100, profs.tailoring.Recipes[100].primaryRecipeID)
    end)

    it("re-flags a profession for pull when the advertised version changes", function()
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })), "G", "R")
      GSD.SaveRecipes("R", { v = 1, name = "Main", profs = { { key = "tailoring", ids = { 100, 200 } } } })
      assert.are.same({}, GSD.GetProfessionsNeedingRecipes("Main", "R"))

      -- New presence advertises a different recipe set version -> needs re-pull, old recipes dropped.
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 3, rv = P.HashRecipeIDs({ 100, 200, 300 }) } }),
      })), "G", "R")
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Main", "R"))
    end)

    it("returns empty within backoff after MarkRecipesRequested", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2,
          rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      assert.are.same({}, GSD.GetProfessionsNeedingRecipes("Main", "R", NOW + 100))
    end)

    it("returns prof again after backoff expires", function()
      local msg = presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2,
          rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })
      GSD.SaveReceived("Main", P.ParsePresence(msg), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Main", "R", NOW + 3601))
    end)

    it("ignores backoff when rv changes", function()
      local rv1 = P.HashRecipeIDs({ 100, 200 })
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = rv1 } }),
      })), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 3,
          rv = P.HashRecipeIDs({ 100, 200, 300 }) } }),
      })), "G", "R")
      assert.are.same({ "tailoring" }, GSD.GetProfessionsNeedingRecipes("Main", "R", NOW + 100))
    end)

    it("preserves recipesRequestedAt when rv is unchanged on SaveReceived", function()
      local rv = P.HashRecipeIDs({ 100, 200 })
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = rv } }),
      })), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2, rv = rv } }),
      })), "G", "R")
      assert.are.equal(NOW, GSD.GetCharacter("Main", "R").Professions.tailoring.recipesRequestedAt)
    end)

    it("clears recipesRequestedAt when rv changes on SaveReceived", function()
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 2,
          rv = P.HashRecipeIDs({ 100, 200 }) } }),
      })), "G", "R")
      GSD.MarkRecipesRequested("Main", "R", { "tailoring" }, NOW)
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", rank = 375, count = 3,
          rv = P.HashRecipeIDs({ 100, 200, 300 }) } }),
      })), "G", "R")
      assert.is_nil(GSD.GetCharacter("Main", "R").Professions.tailoring.recipesRequestedAt)
    end)
  end)

  describe("local guild members for display", function()
    before_each(function()
      AltArmy.GuildShareSettings = {
        _CurrentRealm = function() return "R" end,
        GetMain = function() return "Main" end,
        GetDisplayName = function() return "MainDisplay" end,
        GetAllGuildedCharacters = function(guild, realm)
          if guild ~= "G" or realm ~= "R" then return {} end
          return {
            { name = "Main", realm = "R", char = {
              name = "Main", classFile = "MAGE", level = 70,
              Professions = { Tailoring = { rank = 375, Recipes = { [1] = { primaryRecipeID = 1 } } } },
            } },
            { name = "Alt", realm = "R", char = { name = "Alt", classFile = "WARRIOR", level = 42 } },
          }
        end,
      }
    end)

    it("GetLocalGuildMembers builds entries from account data", function()
      local members = GSD.GetLocalGuildMembers("G", "R")
      assert.are.equal(2, #members)
      local main, alt
      for _, m in ipairs(members) do
        if m.name == "Main" then main = m elseif m.name == "Alt" then alt = m end
      end
      assert.are.equal("local", main.source)
      assert.is_true(main.isMain)
      assert.are.equal("MainDisplay", main.displayName)
      assert.truthy(main.Professions.Tailoring)
      assert.are.equal(375, main.Professions.Tailoring.rank)
      assert.is_false(alt.isMain)
    end)

    it("GetGuildMembersForDisplay merges received data with local account characters", function()
      GSD.SaveReceived("Peer", P.ParsePresence(presence("Peer", { charEntry("Peer") })), "G", "R")
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      assert.are.equal(3, #members)
      local names = {}
      for _, m in ipairs(members) do names[m.name] = m.source end
      assert.are.equal("Peer", names.Peer)
      assert.is_true(names.Main ~= nil)
      assert.are.equal("local", names.Main)
      assert.are.equal("local", names.Alt)
    end)

    it("groups all local characters under a default main when none is configured", function()
      -- Sharing enabled but no main picked yet: every character must still collapse under
      -- one group instead of each becoming its own top-level row.
      AltArmy.GuildShareSettings.GetMain = function() return nil end
      local members = GSD.GetLocalGuildMembers("G", "R")
      assert.are.equal(2, #members)
      local mains, isMainCount = {}, 0
      for _, m in ipairs(members) do
        local key = m.main or "<nil>"
        mains[key] = (mains[key] or 0) + 1
        if m.isMain then isMainCount = isMainCount + 1 end
      end
      -- Highest-level character (Main, 70) becomes the implicit main for the whole group.
      assert.are.equal(2, mains["Main"])
      assert.is_nil(mains["<nil>"])
      assert.are.equal(1, isMainCount)
    end)

    it("local account data overrides received entries for the same character", function()
      GSD.SaveReceived("Main", P.ParsePresence(presence("Main", {
        charEntry("Main", { { key = "tailoring", name = "Tailoring", rank = 1, count = 0, rv = 0 } }),
      })), "G", "R")
      local members = GSD.GetGuildMembersForDisplay("G", "R")
      local main
      for _, m in ipairs(members) do
        if m.name == "Main" then main = m break end
      end
      assert.are.equal("local", main.source)
      assert.are.equal(375, main.Professions.Tailoring.rank)
    end)
  end)

  describe("purging", function()
    it("PurgeGuild removes all characters in a guild", function()
      GSD.SaveReceived("A", P.ParsePresence(presence("A", { charEntry("A") })), "G", "R")
      GSD.SaveReceived("B", P.ParsePresence(presence("B", { charEntry("B") })), "OtherGuild", "R")
      GSD.PurgeGuild("G")
      assert.are.equal(0, #GSD.GetGuildMembers("G"))
      assert.are.equal(1, #GSD.GetGuildMembers("OtherGuild"))
    end)

    it("PurgeStale removes entries older than maxAge", function()
      GSD.SaveReceived("A", P.ParsePresence(presence("A", { charEntry("A") })), "G", "R")
      local removed = GSD.PurgeStale(100, NOW + 1000)
      assert.are.equal(1, removed)
      assert.are.equal(0, #GSD.GetGuildMembers("G"))
    end)

    it("PurgeStale keeps fresh entries", function()
      GSD.SaveReceived("A", P.ParsePresence(presence("A", { charEntry("A") })), "G", "R")
      local removed = GSD.PurgeStale(100, NOW + 50)
      assert.are.equal(0, removed)
      assert.are.equal(1, #GSD.GetGuildMembers("G"))
    end)
  end)
end)
