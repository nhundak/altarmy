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

  describe("ResolvePresenceMainAndDisplay", function()
    local function charEntry(name, level)
      return { name = name, realm = "R", char = { name = name, level = level or 0 } }
    end

    before_each(function()
      AltArmy.GuildShareOnboarding = {
        PickDefaultMain = function(candidates)
          local best
          for _, c in ipairs(candidates or {}) do
            if not best or (c.char.level or 0) > (best.char.level or 0) then
              best = c
            end
          end
          return best and best.name or nil
        end,
      }
    end)

    it("returns saved main and display name when both are set", function()
      GSS.SetMain("R", "SavedMain")
      GSS.SetDisplayName("R", "Chief")
      local main, display = GSS.ResolvePresenceMainAndDisplay({
        charEntry("Alt", 40), charEntry("SavedMain", 70),
      }, "R")
      assert.are.equal("SavedMain", main)
      assert.are.equal("Chief", display)
    end)

    it("guesses main and uses the main name as display when both are unknown", function()
      local main, display = GSS.ResolvePresenceMainAndDisplay({
        charEntry("Alt", 40), charEntry("Topchar", 70),
      }, "R")
      assert.are.equal("Topchar", main)
      assert.are.equal("Topchar", display)
    end)

    it("uses the main name as display when main is saved but display is not", function()
      GSS.SetMain("R", "SavedMain")
      local main, display = GSS.ResolvePresenceMainAndDisplay({ charEntry("SavedMain", 70) }, "R")
      assert.are.equal("SavedMain", main)
      assert.are.equal("SavedMain", display)
    end)
  end)
end)
