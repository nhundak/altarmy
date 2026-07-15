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

  it("uses getLabel for the bracket text when provided", function()
    local out = GCM.Transform(
      "Alt",
      "hello",
      mains({ Alt = "Mainman" }),
      nil,
      function() return "Buddy" end)
    assert.is_true(out:find("Buddy", 1, true) ~= nil, out)
    assert.is_false(out:find("Mainman", 1, true) ~= nil, out)
  end)

  it("still skips annotation when sender is the main even if getLabel differs", function()
    local out = GCM.Transform(
      "Mainman",
      "hello",
      mains({ Mainman = "Mainman" }),
      nil,
      function() return "Buddy" end)
    assert.are.equal("hello", out)
  end)

  describe("FilterMessage display label", function()
    local savedDebug
    local savedGSS
    local savedGSD

    setup(function()
      savedDebug = AltArmy.Debug
      savedGSS = AltArmy.GuildShareSettings
      savedGSD = AltArmy.GuildShareData
      AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
      AltArmy.GuildShareSettings = {
        IsChatInsertionEnabled = function() return true end,
        IsChatInsertionChannelEnabled = function() return true end,
        GetGroupOverrideName = function(main, realm)
          if main == "Mainman" and realm == "R" then return "Buddy" end
          return nil
        end,
      }
      AltArmy.GuildShareData = {
        GetMainOf = function() return "Mainman" end,
        FindCharacter = function(name)
          if name == "Alt" then
            return { realm = "R", classFile = "WARRIOR", main = "Mainman", displayName = "Chief" }
          end
          if name == "Mainman" then
            return { realm = "R", classFile = "MAGE", main = "Mainman", displayName = "Chief" }
          end
          return nil
        end,
      }
    end)

    teardown(function()
      AltArmy.Debug = savedDebug
      AltArmy.GuildShareSettings = savedGSS
      AltArmy.GuildShareData = savedGSD
    end)

    it("prefers override name in the chat bracket", function()
      local out = GCM.FilterMessage("hello", "Alt", "guild")
      assert.is_true(out and out:find("Buddy", 1, true) ~= nil, out)
      assert.is_false(out:find("Mainman", 1, true) ~= nil, out)
      assert.is_false(out:find("Chief", 1, true) ~= nil, out)
    end)

    it("falls back to displayName when no override", function()
      AltArmy.GuildShareSettings.GetGroupOverrideName = function() return nil end
      local out = GCM.FilterMessage("hello", "Alt", "guild")
      assert.is_true(out and out:find("Chief", 1, true) ~= nil, out)
    end)
  end)

  describe("online/offline system messages", function()
    local ONLINE = "|Hplayer:Allystie|h[Allystie]|h has come online."
    local OFFLINE = "Allystie has gone offline."

    setup(function()
      _G.ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online."
      _G.ERR_FRIEND_OFFLINE_S = "%s has gone offline."
    end)

    it("ParseOnlineOffline extracts the name from an online message", function()
      local name, kind = GCM.ParseOnlineOffline(ONLINE)
      assert.are.equal("Allystie", name)
      assert.are.equal("online", kind)
    end)

    it("ParseOnlineOffline extracts the name from an offline message", function()
      local name, kind = GCM.ParseOnlineOffline(OFFLINE)
      assert.are.equal("Allystie", name)
      assert.are.equal("offline", kind)
    end)

    it("ParseOnlineOffline returns nil for unrelated system text", function()
      assert.is_nil(GCM.ParseOnlineOffline("You receive loot: [Foo]."))
    end)

    it("inserts the main after the character name on online", function()
      local out = GCM.TransformOnlineOffline(ONLINE, mains({ Allystie = "Treebus" }))
      assert.is_true(out:find("|Hplayer:Allystie|h%[Allystie%]|h %[.-Treebus.-] has come online%.$", 1) ~= nil, out)
    end)

    it("inserts the main after the character name on offline", function()
      local out = GCM.TransformOnlineOffline(OFFLINE, mains({ Allystie = "Treebus" }))
      assert.is_true(out:find("^Allystie %[.-Treebus.-] has gone offline%.$", 1) ~= nil, out)
    end)

    it("colors the main name with the main character class", function()
      local out = GCM.TransformOnlineOffline(
        ONLINE,
        mains({ Allystie = "Treebus" }),
        mainClasses({ Treebus = "MAGE" })
      )
      assert.is_true(out:find("|cff", 1, true) ~= nil, out)
      assert.is_true(out:find("Treebus", 1, true) ~= nil)
      assert.is_false(out:find("808080", 1, true) ~= nil, "should not use gray")
    end)

    it("leaves online/offline unchanged when the character is their own main", function()
      assert.are.equal(ONLINE, GCM.TransformOnlineOffline(ONLINE, mains({ Allystie = "Allystie" })))
      assert.are.equal(OFFLINE, GCM.TransformOnlineOffline(OFFLINE, mains({ Allystie = "Allystie" })))
    end)

    it("leaves online/offline unchanged when the character is unknown", function()
      assert.are.equal(ONLINE, GCM.TransformOnlineOffline(ONLINE, mains({})))
    end)

    it("uses getLabel for the bracket text when provided", function()
      local out = GCM.TransformOnlineOffline(
        OFFLINE,
        mains({ Allystie = "Treebus" }),
        nil,
        function() return "Buddy" end)
      assert.is_true(out:find("Buddy", 1, true) ~= nil, out)
      assert.is_false(out:find("Treebus", 1, true) ~= nil, out)
    end)

    describe("FilterSystemMessage gating", function()
      local savedDebug
      local savedGSS

      setup(function()
        savedDebug = AltArmy.Debug
        savedGSS = AltArmy.GuildShareSettings
        AltArmy.Debug = { IsGuildShareEnabled = function() return true end }
        AltArmy.GuildShareSettings = {
          IsChatInsertionEnabled = function() return true end,
        }
        AltArmy.GuildShareData = {
          GetMainOf = function() return "Treebus" end,
          FindCharacter = function(name)
            if name == "Allystie" then
              return { realm = "R", classFile = "WARRIOR", main = "Treebus" }
            end
            if name == "Treebus" then
              return { realm = "R", classFile = "MAGE", main = "Treebus", displayName = "Treebus" }
            end
            return nil
          end,
        }
      end)

      teardown(function()
        AltArmy.Debug = savedDebug
        AltArmy.GuildShareSettings = savedGSS
        AltArmy.GuildShareData = nil
      end)

      it("annotates when chat insertion is enabled", function()
        local out = GCM.FilterSystemMessage(ONLINE)
        assert.is_true(out and out:find("Treebus", 1, true) ~= nil, out)
      end)

      it("returns nil when chat insertion is disabled", function()
        AltArmy.GuildShareSettings.IsChatInsertionEnabled = function() return false end
        assert.is_nil(GCM.FilterSystemMessage(ONLINE))
      end)

      it("returns nil for non online/offline system text", function()
        assert.is_nil(GCM.FilterSystemMessage("You receive loot: [Foo]."))
      end)
    end)
  end)
end)
