--[[
  Unit tests for GuildShareProtocol.lua (guild data sharing payload build/parse).
  Run from project root: npm test
]]

describe("GuildShareProtocol", function()
  local P

  local function makeChar(overrides)
    local c = {
      name = "Bob", realm = "R", classFile = "MAGE", faction = "Alliance", level = 70,
      Professions = {
        Tailoring = {
          rank = 375,
          Recipes = {
            [100] = { primaryRecipeID = 100, color = 1 },
            [200] = { primaryRecipeID = 200, color = 2 },
            -- alias row: points at 200, must be excluded
            [999] = { primaryRecipeID = 200, color = 2 },
          },
        },
      },
    }
    for k, v in pairs(overrides or {}) do c[k] = v end
    return c
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("GuildShareProtocol")
    P = AltArmy.GuildShareProtocol
    assert.truthy(P)
    -- Locale-safe profession key resolver stub.
    AltArmy.SearchSettings = AltArmy.SearchSettings or {}
    AltArmy.SearchSettings.ResolveProfessionKey = function(name)
      if name == "Tailoring" then return "tailoring" end
      return nil
    end
  end)

  describe("GetPrimaryRecipeIDs", function()
    it("returns sorted primary ids, excluding aliases", function()
      local prof = makeChar().Professions.Tailoring
      local ids = P.GetPrimaryRecipeIDs(prof)
      assert.are.same({ 100, 200 }, ids)
    end)
  end)

  describe("HashRecipeIDs", function()
    it("is deterministic and order-independent", function()
      assert.are.equal(P.HashRecipeIDs({ 1, 2, 3 }), P.HashRecipeIDs({ 3, 2, 1 }))
    end)
    it("changes when the set changes", function()
      assert.are_not.equal(P.HashRecipeIDs({ 1, 2 }), P.HashRecipeIDs({ 1, 2, 3 }))
    end)
  end)

  describe("BuildPresence", function()
    it("builds a slim v2 presence with main, display name, and per-char checksum (no profs)", function()
      local chars = { { name = "Bob", realm = "R", char = makeChar() } }
      local msg = P.BuildPresence(chars, "Bob", "Bobby")
      assert.are.equal(P.PRESENCE_V2, msg.v)
      assert.are.equal("Bob", msg.main)
      assert.are.equal("Bobby", msg.displayName)
      assert.are.equal(1, #msg.chars)
      local c = msg.chars[1]
      assert.are.equal("Bob", c.name)
      assert.are.equal("MAGE", c.classFile)
      assert.are.equal(70, c.level)
      assert.truthy(c.ch)
      assert.is_nil(c.profs)
    end)

    it("includes each character's average item level (rounded)", function()
      AltArmy.DataStore = {
        GetAverageItemLevel = function(_, char) return (char and char.ilvlStub) or 0 end,
      }
      local chars = { { name = "Bob", realm = "R", char = makeChar({ ilvlStub = 105.6 }) } }
      local msg = P.BuildPresence(chars, "Bob", "Bobby")
      assert.are.equal(106, msg.chars[1].itemLevel)
      AltArmy.DataStore = nil
    end)

    it("defaults item level to 0 when no data store is available", function()
      AltArmy.DataStore = nil
      local chars = { { name = "Bob", realm = "R", char = makeChar() } }
      local msg = P.BuildPresence(chars, "Bob", "Bobby")
      assert.are.equal(0, msg.chars[1].itemLevel)
    end)

    it("changes ch when profession specialization changes", function()
      local base = makeChar({ Professions = {
        Tailoring = { rank = 375, specialization = "Spellfire", Recipes = {} },
      } })
      local other = makeChar({ Professions = {
        Tailoring = { rank = 375, specialization = "Shadoweave", Recipes = {} },
      } })
      local a = P.BuildPresence({ { name = "Bob", realm = "R", char = base } }, "Bob")
      local b = P.BuildPresence({ { name = "Bob", realm = "R", char = other } }, "Bob")
      assert.are_not.equal(a.chars[1].ch, b.chars[1].ch)
    end)
  end)

  describe("HashCharacterCard", function()
    it("is stable for the same identity and profession summaries", function()
      local char = makeChar()
      local a = P.HashCharacterCard({
        classFile = char.classFile, faction = char.faction, level = 70, itemLevel = 100,
        profs = P.BuildProfessionSummaries(char),
      })
      local b = P.HashCharacterCard({
        classFile = char.classFile, faction = char.faction, level = 70, itemLevel = 100,
        profs = P.BuildProfessionSummaries(char),
      })
      assert.are.equal(a, b)
    end)

    it("changes when level or item level changes", function()
      local char = makeChar()
      local profs = P.BuildProfessionSummaries(char)
      local base = P.HashCharacterCard({
        classFile = "MAGE", faction = "Alliance", level = 70, itemLevel = 100, profs = profs,
      })
      local lvl = P.HashCharacterCard({
        classFile = "MAGE", faction = "Alliance", level = 71, itemLevel = 100, profs = profs,
      })
      local ilvl = P.HashCharacterCard({
        classFile = "MAGE", faction = "Alliance", level = 70, itemLevel = 101, profs = profs,
      })
      assert.are_not.equal(base, lvl)
      assert.are_not.equal(base, ilvl)
    end)
  end)

  describe("BuildCharCard / ParseCharCard", function()
    it("builds and parses a profession card with checksum", function()
      local char = makeChar({ Professions = {
        Tailoring = { rank = 375, specialization = "Spellfire", Recipes = {
          [100] = { primaryRecipeID = 100 },
        } },
      } })
      local card = P.BuildCharCard("Bob", "R", char)
      assert.are.equal(P.PRESENCE_V2, card.v)
      assert.are.equal("Bob", card.name)
      assert.are.equal("Spellfire", card.profs[1].spec)
      assert.truthy(card.ch)
      local parsed = P.ParseCharCard(card)
      assert.are.equal("Bob", parsed.name)
      assert.are.equal(card.ch, parsed.ch)
      assert.are.equal("Spellfire", parsed.profs[1].spec)
    end)

    it("rejects malformed char cards", function()
      assert.is_nil(P.ParseCharCard(nil))
      assert.is_nil(P.ParseCharCard({ v = 1, name = "Bob", profs = {} }))
      assert.is_nil(P.ParseCharCard({ v = 2, profs = {} }))
    end)
  end)

  describe("BuildCharCardRequest / ParseCharCardRequest", function()
    it("builds and parses a char-card request", function()
      local req = P.BuildCharCardRequest("Bob", "R")
      assert.are.equal(P.PRESENCE_V2, req.v)
      assert.are.equal("Bob", req.name)
      assert.are.equal("R", req.realm)
      local parsed = P.ParseCharCardRequest(req)
      assert.are.equal("Bob", parsed.name)
      assert.are.equal("R", parsed.realm)
    end)

    it("rejects malformed requests", function()
      assert.is_nil(P.ParseCharCardRequest(nil))
      assert.is_nil(P.ParseCharCardRequest({ v = 1, name = "Bob" }))
      assert.is_nil(P.ParseCharCardRequest({ v = 2 }))
    end)
  end)

  describe("BuildRecipes", function()
    it("builds a per-character recipe payload keyed by profession (recipes stay v1)", function()
      local msg = P.BuildRecipes("Bob", "R", makeChar())
      assert.are.equal(P.RECIPES_VERSION, msg.v)
      assert.are.equal("Bob", msg.name)
      assert.are.equal("R", msg.realm)
      assert.are.equal(1, #msg.profs)
      assert.are.equal("tailoring", msg.profs[1].key)
      assert.are.same({ 100, 200 }, msg.profs[1].ids)
    end)
  end)

  describe("ParsePresence", function()
    it("accepts a well-formed slim v2 presence", function()
      local chars = { { name = "Bob", realm = "R", char = makeChar() } }
      local ok = P.ParsePresence(P.BuildPresence(chars, "Bob", "Bobby"))
      assert.truthy(ok)
      assert.are.equal(P.PRESENCE_V2, ok.v)
      assert.are.equal("Bob", ok.main)
      assert.truthy(ok.chars[1].ch)
      assert.are.equal(0, #(ok.chars[1].profs or {}))
    end)

    it("still accepts legacy fat v1 presence with profession summaries", function()
      local parsed = P.ParsePresence({
        v = 1, main = "Bob", chars = {
          { name = "Bob", classFile = "MAGE", level = 70, profs = {
            { key = "tailoring", name = "Tailoring", rank = 375, spec = "Spellfire" },
            { key = "alchemy", name = "Alchemy", rank = 300 },
          } },
        },
      })
      assert.are.equal(P.PRESENCE_V1, parsed.v)
      assert.are.equal("Spellfire", parsed.chars[1].profs[1].spec)
      assert.is_nil(parsed.chars[1].profs[2].spec)
      assert.is_nil(parsed.chars[1].ch)
    end)

    it("carries item level through, defaulting to 0 when absent", function()
      local parsed = P.ParsePresence({
        v = 2, main = "Bob", chars = {
          { name = "Bob", classFile = "MAGE", level = 70, itemLevel = 128, ch = 1 },
          { name = "Alt", classFile = "WARRIOR", level = 60, ch = 2 },
        },
      })
      assert.are.equal(128, parsed.chars[1].itemLevel)
      assert.are.equal(0, parsed.chars[2].itemLevel)
    end)

    it("carries the login announce flag when true, omits it otherwise", function()
      local withLogin = P.ParsePresence({
        v = 2, login = true, main = "Bob",
        chars = { { name = "Bob", classFile = "MAGE", level = 70, ch = 1 } },
      })
      assert.is_true(withLogin.login)
      local without = P.ParsePresence({
        v = 2, main = "Bob",
        chars = { { name = "Bob", classFile = "MAGE", level = 70, ch = 1 } },
      })
      assert.is_nil(without.login)
    end)

    it("rejects non-tables and unsupported versions", function()
      assert.is_nil(P.ParsePresence(nil))
      assert.is_nil(P.ParsePresence("nope"))
      assert.is_nil(P.ParsePresence({ v = 999, chars = {} }))
      assert.is_nil(P.ParsePresence({ v = 2 })) -- missing chars
    end)

    it("truncates inbound displayName to DISPLAY_NAME_MAX_LENGTH", function()
      package.loaded["GuildShareSettings"] = nil
      _G.CreateFrame = _G.CreateFrame or function() return { SetScript = function() end } end
      require("GuildShareSettings")
      local longName = string.rep("z", 25)
      local parsed = P.ParsePresence({
        v = 2, main = "Bob", displayName = longName,
        chars = { { name = "Bob", classFile = "MAGE", level = 70, ch = 1 } },
      })
      assert.are.equal(20, #parsed.displayName)
    end)

    it("drops malformed char entries but keeps valid ones", function()
      local msg = {
        v = 2, main = "Bob", chars = {
          { name = "Bob", classFile = "MAGE", level = 70, ch = 1 },
          { name = 12345 }, -- invalid name type
          { level = 10 }, -- missing name
        },
      }
      local parsed = P.ParsePresence(msg)
      assert.are.equal(1, #parsed.chars)
      assert.are.equal("Bob", parsed.chars[1].name)
    end)
  end)

  describe("ParseRecipes", function()
    it("accepts a well-formed recipe payload", function()
      local msg = P.BuildRecipes("Bob", "R", makeChar())
      local parsed = P.ParseRecipes(msg)
      assert.are.equal("Bob", parsed.name)
      assert.are.same({ 100, 200 }, parsed.profs[1].ids)
    end)
    it("rejects malformed payloads", function()
      assert.is_nil(P.ParseRecipes(nil))
      assert.is_nil(P.ParseRecipes({ v = 1 }))
      assert.is_nil(P.ParseRecipes({ v = 2, name = "Bob", profs = {} }))
    end)
  end)
end)
