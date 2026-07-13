--[[
  Unit tests for GuildShareSettings.lua (guild data sharing: send-side privacy).
  Run from project root: npm test
]]

describe("GuildShareSettings", function()
  local GSS

  local function setChars(realm, chars)
    AltArmyTBC_Data.Characters[realm] = chars
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    _G.time = _G.time or function() return 1700000000 end
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    _G.AltArmyTBC_Data = { Characters = {} }
    require("DataStore")
    require("DataStoreCharacter")
    require("GuildShareSettings")
    GSS = AltArmy.GuildShareSettings
    assert.truthy(GSS)
  end)

  before_each(function()
    _G.AltArmyTBC_SharingSettings = nil
    _G.AltArmyTBC_Data = { Characters = {} }
    AltArmy.DataStore.accountData = _G.AltArmyTBC_Data
    AltArmy.DB = _G.AltArmyTBC_Data
  end)

  describe("defaults", function()
    it("sharing is disabled by default (opt-in)", function()
      assert.is_false(GSS.IsSharingEnabled())
    end)
    it("chat insertion defaults to enabled", function()
      assert.is_true(GSS.IsChatInsertionEnabled())
    end)
    it("chat insertion channels default to all enabled", function()
      local channels = GSS.GetChatInsertionChannels()
      assert.is_true(channels.guild)
      assert.is_true(channels.party)
      assert.is_true(channels.raid)
      assert.is_true(channels.whisper)
    end)
    it("main, display name, opt-out, onboarding default to empty/false", function()
      assert.is_nil(GSS.GetMain("R"))
      assert.is_nil(GSS.GetDisplayName("R"))
      assert.is_false(GSS.IsCharacterOptedOut("Bob", "R"))
      assert.is_false(GSS.IsOnboardingCompleted("R"))
      assert.is_false(GSS.IsNonGuildedOptedIn("Bob", "R"))
    end)
  end)

  describe("setters persist", function()
    it("SetSharingEnabled", function()
      GSS.SetSharingEnabled(true)
      assert.is_true(GSS.IsSharingEnabled())
      assert.is_true(AltArmyTBC_SharingSettings.enabled)
    end)
    it("SetMain / SetDisplayName per realm", function()
      GSS.SetMain("R", "Bob")
      GSS.SetDisplayName("R", "Bobby")
      assert.are.equal("Bob", GSS.GetMain("R"))
      assert.are.equal("Bobby", GSS.GetDisplayName("R"))
    end)
    it("SetDisplayName truncates to DISPLAY_NAME_MAX_LENGTH", function()
      local longName = string.rep("x", GSS.DISPLAY_NAME_MAX_LENGTH + 5)
      GSS.SetDisplayName("R", longName)
      assert.are.equal(GSS.DISPLAY_NAME_MAX_LENGTH, #GSS.GetDisplayName("R"))
      assert.are.equal(string.rep("x", GSS.DISPLAY_NAME_MAX_LENGTH), GSS.GetDisplayName("R"))
    end)
    it("NormalizeDisplayName returns nil for empty input", function()
      assert.is_nil(GSS.NormalizeDisplayName(nil))
      assert.is_nil(GSS.NormalizeDisplayName(""))
    end)
    it("ShouldSyncDisplayNameWithMain when preferred still matches main (case-insensitive)", function()
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob", "Bob"))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob", "bob"))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("BOB", "Bob"))
    end)
    it("ShouldSyncDisplayNameWithMain when preferred is empty (nothing custom to keep)", function()
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob", nil))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain("Bob", ""))
      assert.is_true(GSS.ShouldSyncDisplayNameWithMain(nil, nil))
    end)
    it("ShouldSyncDisplayNameWithMain is false when preferred differs from main", function()
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain("Bob", "Chief"))
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain("Bob", "Bobby"))
      assert.is_false(GSS.ShouldSyncDisplayNameWithMain(nil, "Chief"))
    end)
    it("SetCharacterOptedOut", function()
      GSS.SetCharacterOptedOut("Bob", "R", true)
      assert.is_true(GSS.IsCharacterOptedOut("Bob", "R"))
      GSS.SetCharacterOptedOut("Bob", "R", false)
      assert.is_false(GSS.IsCharacterOptedOut("Bob", "R"))
    end)
    it("SetNonGuildedOptIn stores a guild, cleared with nil", function()
      GSS.SetNonGuildedOptIn("Alt", "R", "The Guild")
      assert.is_true(GSS.IsNonGuildedOptedIn("Alt", "R"))
      assert.are.equal("The Guild", GSS.GetNonGuildedOptInGuild("Alt", "R"))
      GSS.SetNonGuildedOptIn("Alt", "R", nil)
      assert.is_false(GSS.IsNonGuildedOptedIn("Alt", "R"))
    end)
    it("SetChatInsertionEnabled / SetOnboardingCompleted", function()
      GSS.SetChatInsertionEnabled(false)
      assert.is_false(GSS.IsChatInsertionEnabled())
      GSS.SetOnboardingCompleted("R", true)
      assert.is_true(GSS.IsOnboardingCompleted("R"))
    end)
  end)

  describe("GetAllGuildedCharacters (flag OFF default set)", function()
    it("returns every character in the guild, ignoring settings", function()
      setChars("R", {
        Main = { name = "Main", realm = "R", guildName = "G" },
        Alt = { name = "Alt", realm = "R", guildName = "G" },
        Other = { name = "Other", realm = "R", guildName = "Different" },
        NoGuild = { name = "NoGuild", realm = "R" },
      })
      -- Even when sharing is off and a char is opted out, all guilded are returned.
      GSS.SetSharingEnabled(false)
      GSS.SetCharacterOptedOut("Alt", "R", true)
      local list = GSS.GetAllGuildedCharacters("G", "R")
      local names = {}
      for _, e in ipairs(list) do names[e.name] = true end
      assert.is_true(names.Main)
      assert.is_true(names.Alt)
      assert.is_nil(names.Other)
      assert.is_nil(names.NoGuild)
    end)
    it("returns empty when guild is nil", function()
      setChars("R", { Main = { name = "Main", realm = "R", guildName = "G" } })
      assert.are.equal(0, #GSS.GetAllGuildedCharacters(nil, "R"))
    end)
  end)

  describe("GetShareableCharacters (flag ON opt-in set)", function()
    it("is empty when sharing is disabled", function()
      setChars("R", { Main = { name = "Main", realm = "R", guildName = "G" } })
      GSS.SetSharingEnabled(false)
      assert.are.equal(0, #GSS.GetShareableCharacters("G", "R"))
    end)
    it("returns guilded chars not opted out when enabled", function()
      setChars("R", {
        Main = { name = "Main", realm = "R", guildName = "G" },
        Alt = { name = "Alt", realm = "R", guildName = "G" },
        Other = { name = "Other", realm = "R", guildName = "Different" },
      })
      GSS.SetSharingEnabled(true)
      GSS.SetCharacterOptedOut("Alt", "R", true)
      local list = GSS.GetShareableCharacters("G", "R")
      local names = {}
      for _, e in ipairs(list) do names[e.name] = true end
      assert.is_true(names.Main)
      assert.is_nil(names.Alt)
      assert.is_nil(names.Other)
    end)
    it("includes non-guilded characters opted in to this guild", function()
      setChars("R", {
        Main = { name = "Main", realm = "R", guildName = "G" },
        Bank = { name = "Bank", realm = "R" },
        Bank2 = { name = "Bank2", realm = "R" },
      })
      GSS.SetSharingEnabled(true)
      GSS.SetNonGuildedOptIn("Bank", "R", "G")
      GSS.SetNonGuildedOptIn("Bank2", "R", "OtherGuild")
      local list = GSS.GetShareableCharacters("G", "R")
      local names = {}
      for _, e in ipairs(list) do names[e.name] = true end
      assert.is_true(names.Main)
      assert.is_true(names.Bank)
      assert.is_nil(names.Bank2)
    end)
  end)

  describe("chat insertion channels", function()
    it("SetChatInsertionChannelEnabled toggles individual channels", function()
      GSS.SetChatInsertionChannelEnabled("party", false)
      assert.is_false(GSS.IsChatInsertionChannelEnabled("party"))
      assert.is_true(GSS.IsChatInsertionChannelEnabled("guild"))
    end)

    it("FormatChatInsertionChannelSummary lists every enabled channel", function()
      local summary = GSS.FormatChatInsertionChannelSummary(
        GSS.CHAT_INSERTION_CHANNEL_ORDER,
        GSS.CHAT_INSERTION_CHANNEL_LABELS,
        GSS.GetChatInsertionChannels()
      )
      assert.is_true(summary:find("Guild", 1, true) ~= nil, summary)
      assert.is_true(summary:find("Party", 1, true) ~= nil, summary)
      assert.is_true(summary:find("Raid", 1, true) ~= nil, summary)
      assert.is_true(summary:find("Whisper", 1, true) ~= nil, summary)
    end)

    it("FormatChatInsertionChannelSummary lists enabled channel labels", function()
      GSS.SetChatInsertionChannelEnabled("guild", true)
      GSS.SetChatInsertionChannelEnabled("party", false)
      GSS.SetChatInsertionChannelEnabled("raid", false)
      GSS.SetChatInsertionChannelEnabled("whisper", true)
      local summary = GSS.FormatChatInsertionChannelSummary(
        GSS.CHAT_INSERTION_CHANNEL_ORDER,
        GSS.CHAT_INSERTION_CHANNEL_LABELS,
        GSS.GetChatInsertionChannels()
      )
      assert.is_true(summary:find("Guild", 1, true) ~= nil, summary)
      assert.is_true(summary:find("Whisper", 1, true) ~= nil, summary)
      assert.is_nil(summary:find("Party", 1, true))
    end)
  end)

  describe("EnsureDefaultMainIfMissing", function()
    it("sets the top-ranked character when no main is saved", function()
      setChars("R", {
        Alt = { name = "Alt", realm = "R", level = 40, classFile = "MAGE" },
        Main = { name = "Main", realm = "R", level = 70, classFile = "WARRIOR" },
      })
      AltArmy.GuildShareOnboarding = AltArmy.GuildShareOnboarding or {}
      local GSO = AltArmy.GuildShareOnboarding
      local origBuild = GSO.BuildRealmCharEntries
      GSO.BuildRealmCharEntries = function(chars)
        return {
          { id = "Main", label = "Main" },
          { id = "Alt", label = "Alt" },
        }
      end
      local picked = GSS.EnsureDefaultMainIfMissing("R")
      GSO.BuildRealmCharEntries = origBuild
      assert.are.equal("Main", picked)
      assert.are.equal("Main", GSS.GetMain("R"))
    end)
  end)

  describe("character share mode", function()
    before_each(function()
      _G.GetGuildInfo = function() return "G" end
    end)

    it("defaults to default when no overrides are set", function()
      assert.are.equal("default", GSS.GetCharacterShareMode("Bob", "R"))
    end)

    it("returns dont_share when opted out", function()
      GSS.SetCharacterOptedOut("Bob", "R", true)
      assert.are.equal("dont_share", GSS.GetCharacterShareMode("Bob", "R"))
    end)

    it("returns share when a non-guilded character is opted in", function()
      setChars("R", { Bank = { name = "Bank", realm = "R" } })
      GSS.SetNonGuildedOptIn("Bank", "R", "G")
      assert.are.equal("share", GSS.GetCharacterShareMode("Bank", "R"))
    end)

    it("SetCharacterShareMode default clears overrides", function()
      GSS.SetCharacterOptedOut("Bob", "R", true)
      GSS.SetCharacterShareMode("Bob", "R", "default")
      assert.are.equal("default", GSS.GetCharacterShareMode("Bob", "R"))
    end)

    it("SetCharacterShareMode dont_share opts out guilded characters", function()
      setChars("R", { Alt = { name = "Alt", realm = "R", guildName = "G" } })
      GSS.SetCharacterShareMode("Alt", "R", "dont_share")
      assert.is_true(GSS.IsCharacterOptedOut("Alt", "R"))
    end)

    it("SetCharacterShareMode share opts in non-guilded characters to current guild", function()
      setChars("R", { Bank = { name = "Bank", realm = "R" } })
      GSS.SetCharacterShareMode("Bank", "R", "share")
      assert.are.equal("G", GSS.GetNonGuildedOptInGuild("Bank", "R"))
    end)

    it("GetCharacterShareModeDefaultLabel reflects global sharing", function()
      GSS.SetSharingEnabled(true)
      assert.are.equal("Use global setting (share)", GSS.GetCharacterShareModeDefaultLabel())
      GSS.SetSharingEnabled(false)
      assert.are.equal("Use global setting (don't share)", GSS.GetCharacterShareModeDefaultLabel())
    end)

    it("GetCharacterShareModeEntries includes dynamic default label", function()
      GSS.SetSharingEnabled(true)
      local entries = GSS.GetCharacterShareModeEntries()
      assert.are.equal(3, #entries)
      assert.are.equal("default", entries[1].id)
      assert.are.equal("Use global setting (share)", entries[1].label)
      assert.are.equal("Always share", entries[2].label)
      assert.are.equal("Never share", entries[3].label)
    end)
  end)

  describe("ResolvePresenceMainAndDisplay", function()
    local function charEntry(name, level)
      return { name = name, realm = "R", char = { name = name, level = level or 0 } }
    end

    it("returns saved main and display name when both are set", function()
      GSS.SetMain("R", "SavedMain")
      GSS.SetDisplayName("R", "Chief")
      local main, display = GSS.ResolvePresenceMainAndDisplay({
        charEntry("Alt", 40), charEntry("SavedMain", 70),
      }, "R")
      assert.are.equal("SavedMain", main)
      assert.are.equal("Chief", display)
    end)

    it("leaves main and display nil when neither is saved (receivers guess the main)", function()
      local main, display = GSS.ResolvePresenceMainAndDisplay({
        charEntry("Alt", 40), charEntry("Topchar", 70),
      }, "R")
      assert.is_nil(main)
      assert.is_nil(display)
    end)

    it("sends a saved display name even when main is unset", function()
      GSS.SetDisplayName("R", "Chief")
      local main, display = GSS.ResolvePresenceMainAndDisplay({
        charEntry("Alt", 40), charEntry("Topchar", 70),
      }, "R")
      assert.is_nil(main)
      assert.are.equal("Chief", display)
    end)

    it("uses the main name as display when main is saved but display is not", function()
      GSS.SetMain("R", "SavedMain")
      local main, display = GSS.ResolvePresenceMainAndDisplay({ charEntry("SavedMain", 70) }, "R")
      assert.are.equal("SavedMain", main)
      assert.are.equal("SavedMain", display)
    end)
  end)

  describe("group UI prefs", function()
    it("pin defaults to false", function()
      assert.is_false(GSS.IsGroupPinned("Mainman", "R"))
    end)

    it("SetGroupPinned persists per realm and main", function()
      GSS.SetGroupPinned("Mainman", "R", true)
      assert.is_true(GSS.IsGroupPinned("Mainman", "R"))
      assert.is_false(GSS.IsGroupPinned("Other", "R"))
      assert.is_false(GSS.IsGroupPinned("Mainman", "OtherRealm"))
      GSS.SetGroupPinned("Mainman", "R", false)
      assert.is_false(GSS.IsGroupPinned("Mainman", "R"))
    end)

    it("override name defaults to nil", function()
      assert.is_nil(GSS.GetGroupOverrideName("Mainman", "R"))
    end)

    it("SetGroupOverrideName persists and truncates like display names", function()
      GSS.SetGroupOverrideName("Mainman", "R", "Buddy")
      assert.are.equal("Buddy", GSS.GetGroupOverrideName("Mainman", "R"))
      local longName = string.rep("y", GSS.DISPLAY_NAME_MAX_LENGTH + 5)
      GSS.SetGroupOverrideName("Mainman", "R", longName)
      assert.are.equal(string.rep("y", GSS.DISPLAY_NAME_MAX_LENGTH), GSS.GetGroupOverrideName("Mainman", "R"))
    end)

    it("SetGroupOverrideName clears when empty", function()
      GSS.SetGroupOverrideName("Mainman", "R", "Buddy")
      GSS.SetGroupOverrideName("Mainman", "R", "")
      assert.is_nil(GSS.GetGroupOverrideName("Mainman", "R"))
    end)

    it("ClearGroupUiPrefs removes pin and override for that group", function()
      GSS.SetGroupPinned("Mainman", "R", true)
      GSS.SetGroupOverrideName("Mainman", "R", "Buddy")
      GSS.SetGroupPinned("Other", "R", true)
      GSS.ClearGroupUiPrefs("Mainman", "R")
      assert.is_false(GSS.IsGroupPinned("Mainman", "R"))
      assert.is_nil(GSS.GetGroupOverrideName("Mainman", "R"))
      assert.is_true(GSS.IsGroupPinned("Other", "R"))
    end)
  end)
end)
