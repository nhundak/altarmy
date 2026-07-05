--[[
  Unit tests for the pure helpers in GuildShareComm.lua (flag-branched send-set + sender
  normalization). The AceComm wiring itself is exercised in-game, not here.
  Run from project root: npm test
]]

describe("GuildShareComm helpers", function()
  local Comm

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.CreateFrame = _G.CreateFrame or function()
      return { RegisterEvent = function() end, SetScript = function() end }
    end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("GuildShareComm")
    Comm = AltArmy.GuildShareComm
    assert.truthy(Comm)
  end)

  before_each(function()
    AltArmy.GuildShareSettings = {
      GetShareableCharacters = function() return { { name = "OptedIn" } } end,
      GetAllGuildedCharacters = function() return { { name = "AllGuilded" } } end,
    }
  end)

  describe("_SelectShareChars", function()
    it("uses the opt-in set when the flag is ON", function()
      local list = Comm._SelectShareChars(true, "G", "R")
      assert.are.equal(1, #list)
      assert.are.equal("OptedIn", list[1].name)
    end)
    it("uses the all-guilded set (ignoring settings) when the flag is OFF", function()
      local list = Comm._SelectShareChars(false, "G", "R")
      assert.are.equal(1, #list)
      assert.are.equal("AllGuilded", list[1].name)
    end)
  end)

  describe("_BroadcastSkippedLogMessage", function()
    it("returns a message only when the feature flag is on and sharing is disabled", function()
      assert.is_nil(Comm._BroadcastSkippedLogMessage(false, false))
      assert.is_nil(Comm._BroadcastSkippedLogMessage(false, true))
      assert.is_nil(Comm._BroadcastSkippedLogMessage(true, true))
      local msg = Comm._BroadcastSkippedLogMessage(true, false)
      assert.truthy(msg)
      assert.matches("sharing disabled", msg)
    end)
  end)

  describe("_HasNewlyOnlineGuildmate", function()
    it("returns true when someone newly appears online", function()
      assert.is_true(Comm._HasNewlyOnlineGuildmate({ Alice = true }, { Alice = true, Bob = true }))
    end)

    it("returns false when someone goes offline", function()
      assert.is_false(Comm._HasNewlyOnlineGuildmate({ Alice = true, Bob = true }, { Alice = true }))
    end)

    it("returns false when the online set is unchanged", function()
      assert.is_false(Comm._HasNewlyOnlineGuildmate({ Alice = true }, { Alice = true }))
    end)
  end)

  describe("_ShouldBroadcastOnRosterUpdate", function()
    it("does not broadcast while establishing the first roster baseline", function()
      assert.is_false(Comm._ShouldBroadcastOnRosterUpdate({}, { Alice = true }, true))
    end)

    it("broadcasts when a guildmate comes online after the baseline", function()
      assert.is_true(Comm._ShouldBroadcastOnRosterUpdate({ Alice = true }, { Alice = true, Bob = true }, false))
    end)

    it("does not broadcast when a guildmate goes offline", function()
      assert.is_false(Comm._ShouldBroadcastOnRosterUpdate({ Alice = true, Bob = true }, { Alice = true }, false))
    end)
  end)

  describe("_GuildMembershipChanged", function()
    it("is true when joining or leaving a guild", function()
      assert.is_true(Comm._GuildMembershipChanged(nil, "G"))
      assert.is_true(Comm._GuildMembershipChanged("G", nil))
      assert.is_true(Comm._GuildMembershipChanged("A", "B"))
    end)

    it("is false when the guild is unchanged", function()
      assert.is_false(Comm._GuildMembershipChanged(nil, nil))
      assert.is_false(Comm._GuildMembershipChanged("G", "G"))
    end)
  end)

  describe("_HandlePlayerGuildUpdate", function()
    local broadcastCount, purged

    before_each(function()
      broadcastCount = 0
      purged = nil
      _G.IsInGuild = function() return true end
      _G.GetGuildInfo = function() return "NewGuild" end
      AltArmy.GuildShareData = {
        PurgeGuild = function(g) purged = g end,
      }
      Comm.Broadcast = function() broadcastCount = broadcastCount + 1 end
      Comm.NotifyDataChanged = function() end
    end)

    it("broadcasts once when guild membership changes", function()
      Comm._HandlePlayerGuildUpdate()
      assert.are.equal(1, broadcastCount)
      Comm._HandlePlayerGuildUpdate()
      assert.are.equal(1, broadcastCount, "duplicate PLAYER_GUILD_UPDATE should not rebroadcast")
    end)
  end)

  describe("_NormalizeSender", function()
    it("strips a realm suffix", function()
      assert.are.equal("Bob", Comm._NormalizeSender("Bob-Faerlina"))
      assert.are.equal("Bob", Comm._NormalizeSender("Bob"))
    end)
  end)

  describe("_IsLocalSender", function()
    it("matches the player name with or without a realm suffix", function()
      _G.UnitName = function() return "Bob-Faerlina" end
      assert.is_true(Comm._IsLocalSender("Bob"))
      assert.is_true(Comm._IsLocalSender("Bob-Faerlina"))
      assert.is_false(Comm._IsLocalSender("Alice"))
    end)

    it("returns false when the player name is unavailable", function()
      _G.UnitName = function() return "" end
      assert.is_false(Comm._IsLocalSender("Bob"))
    end)
  end)

  describe("_DispatchReceivedMessage", function()
    local saved

    before_each(function()
      saved = {}
      _G.UnitName = function() return "Bob" end
      AltArmy.Debug = {
        IsGuildShareEnabled = function() return true end,
        LogGuildShare = function() end,
      }
      AltArmy.GuildShareProtocol = {
        ParsePresence = function(msg) return msg end,
        ParseRecipes = function(msg) return msg end,
      }
      AltArmy.GuildShareData = {
        SaveReceived = function(sender, presence)
          saved.received = { sender = sender, presence = presence }
        end,
        SaveRecipes = function(_, payload)
          saved.recipes = payload
        end,
        GetProfessionsNeedingRecipes = function() return {} end,
      }
      AltArmy.GuildShareSettings = {
        GetShareableCharacters = function() return {} end,
        GetAllGuildedCharacters = function() return {} end,
      }
      _G.GetGuildInfo = function() return "G" end
      _G.GetRealmName = function() return "R" end
    end)

    it("ignores presence messages from the local player", function()
      Comm._DispatchReceivedMessage("P", { chars = { { name = "Bob" } } }, "Bob")
      assert.is_nil(saved.received)
    end)

    it("stores presence from other players", function()
      Comm._DispatchReceivedMessage("P", { chars = { { name = "Alice" } } }, "Alice")
      assert.truthy(saved.received)
      assert.are.equal("Alice", saved.received.sender)
    end)
  end)

  describe("_PickSampleProfChar", function()
    it("returns nil when there is no DataStore", function()
      AltArmy.DataStore = nil
      assert.is_nil(Comm._PickSampleProfChar("R"))
    end)

    it("picks the character with the most professions", function()
      AltArmy.DataStore = {
        GetCharacters = function()
          return {
            NoProf = { Professions = {} },
            One = { Professions = { Tailoring = {} } },
            Two = { name = "Two", Professions = { Alchemy = {}, Herbalism = {} } },
          }
        end,
      }
      local char = Comm._PickSampleProfChar("R")
      assert.truthy(char)
      assert.are.equal("Two", char.name)
    end)
  end)

  describe("InjectTestPresence", function()
    local flagOn, saved

    before_each(function()
      flagOn = true
      saved = {}
      _G.GetRealmName = function() return "TestRealm" end
      _G.GetGuildInfo = function() return nil end
      AltArmy.Debug = {
        IsGuildShareEnabled = function() return flagOn end,
        LogGuildShare = function() end,
      }
      AltArmy.GuildShareProtocol = {
        VERSION = 1,
        BuildProfessionSummaries = function() return {} end,
        BuildRecipes = function(name, realm) return { v = 1, name = name, realm = realm, profs = {} } end,
        ParsePresence = function(msg) return msg end,
      }
      AltArmy.GuildShareData = {
        SaveReceived = function(sender, presence, guild, realm)
          saved.received = { sender = sender, presence = presence, guild = guild, realm = realm }
        end,
        SaveRecipes = function(realm, payload)
          saved.recipes = { realm = realm, payload = payload }
        end,
      }
      AltArmy.DataStore = nil
      AltArmy.SearchData = nil
      AltArmy.RefreshGuildTab = nil
    end)

    it("does nothing and reports flag-off when the feature flag is OFF", function()
      flagOn = false
      local ok, reason = Comm.InjectTestPresence()
      assert.is_false(ok)
      assert.are.equal("flag-off", reason)
      assert.is_nil(saved.received)
    end)

    it("stores a synthetic main + alt through the receive/store path when the flag is ON", function()
      local ok = Comm.InjectTestPresence()
      assert.is_true(ok)
      assert.truthy(saved.received)
      assert.are.equal("AltArmy Test Guild", saved.received.guild)
      assert.are.equal("TestRealm", saved.received.realm)
      assert.are.equal(2, #saved.received.presence.chars)
      -- No local characters to sample -> no recipe payload.
      assert.is_nil(saved.recipes)
    end)

    it("seeds recipes from a local character when one with professions exists", function()
      AltArmy.DataStore = {
        GetCharacters = function()
          return { Me = { name = "Me", Professions = { Tailoring = {} } } }
        end,
      }
      local ok = Comm.InjectTestPresence()
      assert.is_true(ok)
      assert.truthy(saved.recipes)
      assert.are.equal("AAtestmain", saved.recipes.payload.name)
    end)
  end)
end)
