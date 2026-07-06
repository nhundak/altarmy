--[[
  Unit tests for GuildChatMainName.lua (pure guild-chat main-name annotation).
  Run from project root: npm test
]]

describe("GuildChatMainName", function()
  local GCM

  local function mains(map)
    return function(sender) return map[sender] end
  end

  local function mainClasses(map)
    return function(_sender, main) return map[main] end
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
      WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
      MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    }
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("ClassColor")
    require("GuildChatMainName")
    GCM = AltArmy.GuildChatMainName
    assert.truthy(GCM)
  end)

  it("prefixes the main name in square brackets when the sender is a known alt", function()
    local out = GCM.Transform("Alt", "hello", mains({ Alt = "Mainman" }))
    assert.is_true(out:find("^%[.-Mainman.-] hello$") ~= nil, out)
    assert.is_true(out:find("hello", 1, true) ~= nil)
  end)

  it("colors the main name with the main character class", function()
    local out = GCM.Transform(
      "Alt",
      "hello",
      mains({ Alt = "Mainman" }),
      mainClasses({ Mainman = "MAGE" })
    )
    assert.is_true(out:find("|cff", 1, true) ~= nil, out)
    assert.is_true(out:find("Mainman", 1, true) ~= nil)
    assert.is_false(out:find("808080", 1, true) ~= nil, "should not use gray")
  end)

  it("leaves the message unchanged when the sender is their own main", function()
    assert.are.equal("hello", GCM.Transform("Mainman", "hello", mains({ Mainman = "Mainman" })))
  end)

  it("leaves the message unchanged when the sender main matches without realm suffix", function()
    assert.are.equal(
      "hello",
      GCM.Transform("Mainman-Realm", "hello", mains({ ["Mainman-Realm"] = "Mainman" }))
    )
  end)

  describe("FilterMessage channel gating", function()
    local savedDebug
    local savedGSS

    setup(function()
      savedDebug = AltArmy.Debug
      savedGSS = AltArmy.GuildShareSettings
      AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
      AltArmy.GuildShareSettings = {
        IsChatInsertionEnabled = function() return true end,
        IsChatInsertionChannelEnabled = function(key) return key == "guild" end,
      }
      AltArmy.GuildShareData = {
        GetMainOf = function() return "Mainman" end,
        FindCharacter = function() return { realm = "R", classFile = "MAGE" } end,
      }
    end)

    teardown(function()
      AltArmy.Debug = savedDebug
      AltArmy.GuildShareSettings = savedGSS
      AltArmy.GuildShareData = nil
    end)

    it("returns nil when the channel is disabled", function()
      assert.is_nil(GCM.FilterMessage("hello", "Alt", "party"))
    end)

    it("annotates when the channel is enabled", function()
      local out = GCM.FilterMessage("hello", "Alt", "guild")
      assert.is_true(out and out:find("Mainman", 1, true) ~= nil, out)
    end)
  end)

  it("leaves the message unchanged when the sender is unknown", function()
    assert.are.equal("hi", GCM.Transform("Stranger", "hi", mains({})))
  end)

  it("leaves the message unchanged with no resolver", function()
    assert.are.equal("hi", GCM.Transform("Alt", "hi", nil))
  end)

  it("does not annotate twice if the main equals the sender name case-sensitively only", function()
    local out = GCM.Transform("Alt", "yo", mains({ Alt = "Boss" }))
    local _, count = out:gsub("Boss", "Boss")
    assert.are.equal(1, count)
  end)
end)
