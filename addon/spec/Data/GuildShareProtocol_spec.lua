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
    it("builds a versioned presence with main, display name, and per-char prof summaries", function()
      local chars = { { name = "Bob", realm = "R", char = makeChar() } }
      local msg = P.BuildPresence(chars, "Bob", "Bobby")
      assert.are.equal(1, msg.v)
      assert.are.equal("Bob", msg.main)
      assert.are.equal("Bobby", msg.displayName)
      assert.are.equal(1, #msg.chars)
      local c = msg.chars[1]
      assert.are.equal("Bob", c.name)
      assert.are.equal("MAGE", c.classFile)
      assert.are.equal(70, c.level)
      assert.are.equal(1, #c.profs)
      assert.are.equal("tailoring", c.profs[1].key)
      assert.are.equal(375, c.profs[1].rank)
      assert.are.equal(2, c.profs[1].count)
      assert.truthy(c.profs[1].rv)
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

    it("includes each profession's specialization label", function()
      local char = makeChar({ Professions = {
        Tailoring = { rank = 375, specialization = "Spellfire", Recipes = {} },
      } })
      local msg = P.BuildPresence({ { name = "Bob", realm = "R", char = char } }, "Bob")
      assert.are.equal("Spellfire", msg.chars[1].profs[1].spec)
    end)
  end)

  describe("BuildRecipes", function()
    it("builds a per-character recipe payload keyed by profession", function()
      local msg = P.BuildRecipes("Bob", "R", makeChar())
      assert.are.equal(1, msg.v)
      assert.are.equal("Bob", msg.name)
      assert.are.equal("R", msg.realm)
      assert.are.equal(1, #msg.profs)
      assert.are.equal("tailoring", msg.profs[1].key)
      assert.are.same({ 100, 200 }, msg.profs[1].ids)
    end)
  end)

  describe("ParsePresence", function()
    it("accepts a well-formed presence", function()
      local chars = { { name = "Bob", realm = "R", char = makeChar() } }
      local ok = P.ParsePresence(P.BuildPresence(chars, "Bob", "Bobby"))
      assert.truthy(ok)
      assert.are.equal("Bob", ok.main)
    end)
    it("carries a profession specialization through, nil when absent", function()
      local parsed = P.ParsePresence({
        v = 1, main = "Bob", chars = {
          { name = "Bob", classFile = "MAGE", level = 70, profs = {
            { key = "tailoring", name = "Tailoring", rank = 375, spec = "Spellfire" },
            { key = "alchemy", name = "Alchemy", rank = 300 },
          } },
        },
      })
      assert.are.equal("Spellfire", parsed.chars[1].profs[1].spec)
      assert.is_nil(parsed.chars[1].profs[2].spec)
    end)
    it("carries item level through, defaulting to 0 when absent", function()
      local parsed = P.ParsePresence({
        v = 1, main = "Bob", chars = {
          { name = "Bob", classFile = "MAGE", level = 70, itemLevel = 128, profs = {} },
          { name = "Alt", classFile = "WARRIOR", level = 60, profs = {} },
        },
      })
      assert.are.equal(128, parsed.chars[1].itemLevel)
      assert.are.equal(0, parsed.chars[2].itemLevel)
    end)
    it("rejects non-tables and wrong versions", function()
      assert.is_nil(P.ParsePresence(nil))
      assert.is_nil(P.ParsePresence("nope"))
      assert.is_nil(P.ParsePresence({ v = 999, chars = {} }))
      assert.is_nil(P.ParsePresence({ v = 1 })) -- missing chars
    end)
    it("truncates inbound displayName to DISPLAY_NAME_MAX_LENGTH", function()
      package.loaded["GuildShareSettings"] = nil
      _G.CreateFrame = _G.CreateFrame or function() return { SetScript = function() end } end
      require("GuildShareSettings")
      local longName = string.rep("z", 25)
      local parsed = P.ParsePresence({
        v = 1, main = "Bob", displayName = longName,
        chars = { { name = "Bob", classFile = "MAGE", level = 70, profs = {} } },
      })
      assert.are.equal(20, #parsed.displayName)
    end)
    it("drops malformed char entries but keeps valid ones", function()
      local msg = {
        v = 1, main = "Bob", chars = {
          { name = "Bob", classFile = "MAGE", level = 70, profs = {} },
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
