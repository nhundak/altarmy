--[[
  Unit tests for SearchGuildNav.lua — drill-in from search results to a guild
  character recipe view, with return-to-search semantics.
  Run from project root: npm test
]]

describe("SearchGuildNav", function()
  local Nav

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("SearchGuildNav")
    Nav = AltArmy.SearchGuildNav
  end)

  before_each(function()
    Nav.End()
  end)

  it("is inactive until Begin", function()
    assert.is_false(Nav.IsActive())
    Nav.Begin()
    assert.is_true(Nav.IsActive())
  end)

  it("End clears the active drill-in", function()
    Nav.Begin()
    Nav.End()
    assert.is_false(Nav.IsActive())
  end)

  it("header search change while inactive is ignored", function()
    assert.are.equal("ignore", Nav.OnHeaderSearchTextChanged("iron"))
    assert.are.equal("ignore", Nav.OnHeaderSearchTextChanged(""))
  end)

  it("header search change while active ends drill-in and requests search results", function()
    Nav.Begin()
    assert.are.equal("show_search", Nav.OnHeaderSearchTextChanged("iron ore"))
    assert.is_false(Nav.IsActive())
  end)

  it("clearing header search while active ends drill-in and exits search", function()
    Nav.Begin()
    assert.are.equal("exit_search", Nav.OnHeaderSearchTextChanged(""))
    assert.is_false(Nav.IsActive())
  end)

  it("Back should return to search only while drill-in is active", function()
    assert.is_false(Nav.ShouldBackReturnToSearch())
    Nav.Begin()
    assert.is_true(Nav.ShouldBackReturnToSearch())
    Nav.End()
    assert.is_false(Nav.ShouldBackReturnToSearch())
  end)

  it("ResolveGuildMember uses GuildShareData.GetCharacter", function()
    local called
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        called = { name = name, realm = realm }
        return { name = name, realm = realm, source = "OtherPlayer" }
      end,
    }
    local entry = Nav.ResolveGuildMember("Bob", "Area 52")
    assert.are.same({ name = "Bob", realm = "Area 52" }, called)
    assert.are.equal("Bob", entry.name)
    assert.are.equal("OtherPlayer", entry.source)
  end)

  it("ResolveGuildMember returns nil when character is missing", function()
    AltArmy.GuildShareData = {
      GetCharacter = function() return nil end,
    }
    assert.is_nil(Nav.ResolveGuildMember("Missing", "Realm"))
  end)

  it("guildmate recipe entry is clickable only when online", function()
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        return { name = name, realm = realm, main = name, guildName = "G" }
      end,
      GetGuildMembersForDisplay = function()
        return { { name = "Bob", realm = "R", main = "Bob", isMain = true } }
      end,
    }
    assert.is_false(Nav.IsGuildRecipeCharacterClickable(nil))
    assert.is_false(Nav.IsGuildRecipeCharacterClickable({}))
    assert.is_false(Nav.IsGuildRecipeCharacterClickable({ isGuild = false, characterName = "Bob" }))
    assert.is_true(Nav.IsGuildRecipeCharacterClickable({
      isGuild = true, characterName = "Bob", realm = "R",
    }, { rosterByName = { bob = { online = true } } }))
    assert.is_false(Nav.IsGuildRecipeCharacterClickable({
      isGuild = true, characterName = "Bob", realm = "R",
    }, {
      rosterByName = {
        bob = { online = false, years = 0, months = 0, days = 1, hours = 0 },
      },
    }))
  end)

  it("own-character recipe entries are never Character-column clickable", function()
    AltArmy.GuildShareData = {
      GetCharacter = function() return nil end,
      BuildLocalMemberEntry = function(name, realm, char, guild, mainName, displayName, mainDeclared)
        return {
          name = name,
          realm = realm,
          classFile = char.classFile,
          level = char.level,
          guildName = guild,
          main = mainName,
          displayName = displayName,
          mainDeclared = mainDeclared and true or false,
          source = "local",
          Professions = {},
        }
      end,
    }
    AltArmy.DataStore = {
      GetCharacter = function(_, name, realm)
        if name == "MyAlt" and realm == "Area 52" then
          return { name = "MyAlt", classFile = "MAGE", level = 70, guildName = "MyGuild" }
        end
        return nil
      end,
    }
    assert.is_false(Nav.IsGuildRecipeCharacterClickable({
      characterName = "MyAlt",
      realm = "Area 52",
    }))
    assert.is_false(Nav.IsGuildRecipeCharacterClickable({
      isGuild = false,
      characterName = "MyAlt",
      realm = "Area 52",
    }))
  end)

  it("ResolveGuildMember falls back to a local DataStore character", function()
    local built
    AltArmy.GuildShareData = {
      GetCharacter = function() return nil end,
      BuildLocalMemberEntry = function(name, realm, char, guild, mainName, displayName, mainDeclared)
        built = {
          name = name,
          realm = realm,
          classFile = char.classFile,
          level = char.level,
          guildName = guild,
          main = mainName,
          displayName = displayName,
          mainDeclared = mainDeclared and true or false,
          source = "local",
        }
        return built
      end,
    }
    AltArmy.GuildShareSettings = {
      GetDisplayName = function() return "Chief" end,
      GetMain = function() return "MyMain" end,
    }
    AltArmy.DataStore = {
      GetCharacter = function(_, name, realm)
        return {
          name = name,
          realm = realm,
          classFile = "WARRIOR",
          level = 68,
          guildName = "LocalGuild",
        }
      end,
    }
    local entry = Nav.ResolveGuildMember("MyAlt", "Area 52")
    assert.are.equal("local", entry.source)
    assert.are.equal("MyAlt", entry.name)
    assert.are.equal("Area 52", entry.realm)
    assert.are.equal("LocalGuild", entry.guildName)
    assert.are.equal("MyMain", entry.main)
    assert.are.equal("Chief", entry.displayName)
    assert.is_true(entry.mainDeclared)
    assert.are.equal(built, entry)
  end)

  it("ResolveGuildMember prefers stored guildmate over local fallback", function()
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        return { name = name, realm = realm, source = "OtherPlayer" }
      end,
      BuildLocalMemberEntry = function()
        error("should not build local entry when guildmate exists")
      end,
    }
    AltArmy.DataStore = {
      GetCharacter = function()
        return { name = "Bob", classFile = "MAGE", level = 70 }
      end,
    }
    local entry = Nav.ResolveGuildMember("Bob", "R")
    assert.are.equal("OtherPlayer", entry.source)
  end)

  it("FindProfessionIndex prefers matching professionKey", function()
    local profs = {
      { key = "alchemy", name = "Alchemy" },
      { key = "tailoring", name = "Tailoring" },
    }
    assert.are.equal(2, Nav.FindProfessionIndex(profs, "tailoring", nil))
    assert.are.equal(1, Nav.FindProfessionIndex(profs, "alchemy", "Tailoring"))
  end)

  it("FindProfessionIndex falls back to professionName", function()
    local profs = {
      { key = "alchemy", name = "Alchemy" },
      { key = "tailoring", name = "Tailoring" },
    }
    assert.are.equal(2, Nav.FindProfessionIndex(profs, nil, "Tailoring"))
    assert.are.equal(2, Nav.FindProfessionIndex(profs, "unknown", "tailoring"))
  end)

  it("FindProfessionIndex defaults to 1 when no match", function()
    assert.are.equal(1, Nav.FindProfessionIndex(nil, "alchemy", nil))
    assert.are.equal(1, Nav.FindProfessionIndex({}, "alchemy", nil))
    assert.are.equal(1, Nav.FindProfessionIndex(
      { { key = "alchemy", name = "Alchemy" } }, "enchanting", "Enchanting"))
  end)

  it("FindRecipeRowIndex returns 1-based index or nil", function()
    local recipes = {
      { recipeID = 10 },
      { recipeID = 20 },
      { recipeID = 30 },
    }
    assert.are.equal(2, Nav.FindRecipeRowIndex(recipes, 20))
    assert.is_nil(Nav.FindRecipeRowIndex(recipes, 99))
    assert.is_nil(Nav.FindRecipeRowIndex(nil, 20))
  end)

  it("ScrollOffsetToRevealRow returns nil when row is already visible", function()
    -- view 100px, row at y=20 height 18, offset 0 → fully visible
    assert.is_nil(Nav.ScrollOffsetToRevealRow(20, 18, 100, 0, 400))
  end)

  it("ScrollOffsetToRevealRow scrolls down when row is below the viewport", function()
    -- view 100px, row at y=200 → need offset so row is visible; centers when possible
    local target = Nav.ScrollOffsetToRevealRow(200, 18, 100, 0, 400)
    assert.is_true(target ~= nil)
    assert.is_true(target > 0)
    -- centered: 200 - (100-18)/2 = 200 - 41 = 159
    assert.are.equal(159, target)
  end)

  it("ScrollOffsetToRevealRow scrolls up when row is above the viewport", function()
    local target = Nav.ScrollOffsetToRevealRow(10, 18, 100, 200, 400)
    assert.is_true(target ~= nil)
    assert.is_true(target < 200)
  end)

  it("ScrollOffsetToRevealRow clamps to max scroll", function()
    -- content barely taller than view; row near bottom
    local target = Nav.ScrollOffsetToRevealRow(90, 18, 100, 0, 110)
    assert.are.equal(10, target) -- maxScroll = 110-100 = 10
  end)

  it("GetGuildCharacterHoverTooltipLines builds lines from guild member + roster", function()
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        return {
          name = name,
          realm = realm,
          classFile = "MAGE",
          level = 70,
          displayName = "Chief",
          main = "ChiefMain",
          guildName = "G",
        }
      end,
      GetGuildMembersForDisplay = function()
        return {
          {
            name = "Bob",
            realm = "R",
            classFile = "MAGE",
            level = 70,
            displayName = "Chief",
            main = "ChiefMain",
            isMain = false,
          },
          {
            name = "Alice",
            realm = "R",
            classFile = "WARRIOR",
            level = 70,
            displayName = "Chief",
            main = "ChiefMain",
            isMain = true,
          },
        }
      end,
    }
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    local lines = Nav.GetGuildCharacterHoverTooltipLines("Bob", "R", {
      rosterByName = {
        bob = { online = false, years = 0, months = 0, days = 0, hours = 5 },
        alice = { online = true },
      },
    })
    assert.is_truthy(lines)
    assert.is_truthy(lines[1]:find("Bob", 1, true))
    assert.is_truthy(lines[1]:find("Chief", 1, true))
    -- Main/display name is class-colored; parentheses stay white.
    assert.is_truthy(lines[1]:find("|cffffffff(|r", 1, true))
    assert.is_truthy(lines[1]:find("|cffffffff)|r", 1, true))
    assert.are.equal("Level 70 Mage", lines[2])
    assert.are.equal("|cffffffffOnline (as |rAlice|cffffffff)|r", lines[3])
    assert.are.equal("|cff808080Click to whisper|r", lines[4])
  end)

  it("GetGuildCharacterHoverTooltipLines omits whisper hint when offline", function()
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        return {
          name = name,
          realm = realm,
          classFile = "MAGE",
          level = 70,
          displayName = "Bob",
          main = "Bob",
          guildName = "G",
        }
      end,
      GetGuildMembersForDisplay = function()
        return {
          { name = "Bob", realm = "R", classFile = "MAGE", level = 70, main = "Bob", isMain = true },
        }
      end,
    }
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    local lines = Nav.GetGuildCharacterHoverTooltipLines("Bob", "R", {
      rosterByName = {
        bob = { online = false, years = 0, months = 0, days = 0, hours = 5 },
      },
    })
    assert.is_truthy(lines)
    assert.are.equal("|cff808080Last seen 5h ago|r", lines[3])
    assert.is_nil(lines[4])
  end)

  it("GetGuildCharacterHoverTooltipLines uses own-character tooltip for local source", function()
    AltArmy.GuildShareData = {
      GetCharacter = function() return nil end,
      BuildLocalMemberEntry = function(name, realm, char)
        return {
          name = name,
          realm = realm,
          classFile = char.classFile,
          level = char.level,
          displayName = "Chief",
          main = "MyMain",
          source = "local",
        }
      end,
      GetGuildMembersForDisplay = function()
        return {
          {
            name = "MyAlt",
            realm = "Area 52",
            classFile = "MAGE",
            level = 68,
            displayName = "Chief",
            main = "MyMain",
            source = "local",
          },
          {
            name = "MyMain",
            realm = "Area 52",
            classFile = "WARRIOR",
            level = 70,
            displayName = "Chief",
            main = "MyMain",
            isMain = true,
            source = "local",
          },
        }
      end,
    }
    AltArmy.DataStore = {
      GetCharacter = function(_, name, realm)
        return {
          name = name,
          realm = realm,
          classFile = "MAGE",
          level = 68,
          guildName = "G",
        }
      end,
    }
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    local lines = Nav.GetGuildCharacterHoverTooltipLines("MyAlt", "Area 52", {
      rosterByName = {
        myalt = { online = true },
      },
    })
    assert.is_truthy(lines)
    assert.is_truthy(lines[1]:find("MyAlt", 1, true))
    -- Own tooltip: no preferred/main suffix and no presence line.
    assert.is_nil(lines[1]:find("Chief", 1, true))
    assert.is_nil(lines[1]:find("(", 1, true))
    assert.are.equal("Level 68 Mage", lines[2])
    assert.is_nil(lines[3])
  end)

  it("IsGuildRecipePlayerOnline is true when any character in the main group is online", function()
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        return {
          name = name,
          realm = realm,
          main = "ChiefMain",
          guildName = "G",
        }
      end,
      GetGuildMembersForDisplay = function()
        return {
          { name = "Bob", realm = "R", main = "ChiefMain" },
          { name = "Alice", realm = "R", main = "ChiefMain", isMain = true },
        }
      end,
    }
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    assert.is_true(Nav.IsGuildRecipePlayerOnline("Bob", "R", {
      rosterByName = {
        bob = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        alice = { online = true },
      },
    }))
    assert.is_false(Nav.IsGuildRecipePlayerOnline("Bob", "R", {
      rosterByName = {
        bob = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        alice = { online = false, years = 0, months = 0, days = 2, hours = 0 },
      },
    }))
  end)

  it("FormatGuildRecipeCharacterSuffix colors Online white and Offline gray", function()
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        return { name = name, realm = realm, main = name, guildName = "G" }
      end,
      GetGuildMembersForDisplay = function()
        return { { name = "Bob", realm = "R", main = "Bob", isMain = true } }
      end,
    }
    assert.are.equal(
      "|cff8ab4f8 (Guild |r|cffffffffOnline|r|cff8ab4f8)|r",
      Nav.FormatGuildRecipeCharacterSuffix("Bob", "R", {
        rosterByName = { bob = { online = true } },
      }))
    assert.are.equal(
      "|cff8ab4f8 (Guild |r|cff808080Offline|r|cff8ab4f8)|r",
      Nav.FormatGuildRecipeCharacterSuffix("Bob", "R", {
        rosterByName = {
          bob = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        },
      }))
  end)

  it("GetCollapsedGuildRecipeTooltipLines resolves mains and caches on the entry", function()
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        if name == "Bob" then
          return {
            name = "Bob",
            realm = realm,
            classFile = "MAGE",
            main = "Chief",
            displayName = "Chief",
            guildName = "G",
          }
        end
        if name == "Alice" then
          return {
            name = "Alice",
            realm = realm,
            classFile = "WARRIOR",
            main = "Alice",
            displayName = "Alice",
            guildName = "G",
            isMain = true,
          }
        end
        if name == "Chief" then
          return {
            name = "Chief",
            realm = realm,
            classFile = "WARRIOR",
            main = "Chief",
            displayName = "Chief",
            guildName = "G",
            isMain = true,
          }
        end
        return nil
      end,
    }
    local entry = {
      isGuildCollapsed = true,
      recipeID = 42,
      guildChars = {
        { characterName = "Bob", realm = "R", classFile = "MAGE" },
        { characterName = "Alice", realm = "R", classFile = "WARRIOR" },
      },
    }
    local roster = {
      bob = { online = false, years = 0, months = 0, days = 0, hours = 5 },
      alice = { online = true },
    }
    local lines = Nav.GetCollapsedGuildRecipeTooltipLines(entry, { rosterByName = roster })
    assert.is_truthy(lines)
    assert.are.equal(3, #lines)
    -- Online Alice first (main omitted), then offline Bob with main Chief, then expand hint.
    assert.is_truthy(lines[1].left:find("Alice", 1, true))
    assert.are.equal("|cffffffffOnline|r", lines[1].right)
    assert.is_nil(lines[1].left:find("(", 1, true))
    assert.is_truthy(lines[2].left:find("Bob", 1, true))
    assert.is_truthy(lines[2].left:find("Chief", 1, true))
    assert.are.equal("|cff8080805h ago|r", lines[2].right)
    assert.are.equal("|cff808080Click to expand|r", lines[3])
    -- Cached on the entry for subsequent hovers.
    assert.are.equal(lines, entry._aaCollapsedTooltipLines)
    local again = Nav.GetCollapsedGuildRecipeTooltipLines(entry, { rosterByName = roster })
    assert.are.equal(lines, again)
  end)

  it("GetCollapsedGuildRecipeTooltipLines returns nil for non-collapsed entries", function()
    assert.is_nil(Nav.GetCollapsedGuildRecipeTooltipLines(nil))
    assert.is_nil(Nav.GetCollapsedGuildRecipeTooltipLines({
      characterName = "Bob",
      isGuild = true,
    }))
  end)

  it("GetCollapsedGuildRecipeTooltipLines treats player online via any alt in the main group", function()
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        if name == "Bob" or name == "Alice" then
          return {
            name = name,
            realm = realm,
            classFile = name == "Bob" and "MAGE" or "WARRIOR",
            main = "ChiefMain",
            displayName = "Chief",
            guildName = "G",
            isMain = name == "Alice",
          }
        end
        return nil
      end,
      GetGuildMembersForDisplay = function()
        return {
          {
            name = "Bob",
            realm = "R",
            classFile = "MAGE",
            main = "ChiefMain",
            displayName = "Chief",
            guildName = "G",
          },
          {
            name = "Alice",
            realm = "R",
            classFile = "WARRIOR",
            main = "ChiefMain",
            displayName = "Chief",
            guildName = "G",
            isMain = true,
          },
          {
            name = "Zebra",
            realm = "R",
            classFile = "HUNTER",
            main = "Zebra",
            displayName = "Zebra",
            guildName = "G",
            isMain = true,
          },
        }
      end,
    }
    local entry = {
      isGuildCollapsed = true,
      recipeID = 99,
      guildChars = {
        -- Bob has the recipe but is offline; Alice (same player) is online.
        { characterName = "Bob", realm = "R", classFile = "MAGE" },
        { characterName = "Zebra", realm = "R", classFile = "HUNTER" },
      },
    }
    local lines = Nav.GetCollapsedGuildRecipeTooltipLines(entry, {
      rosterByName = {
        bob = { online = false, years = 0, months = 0, days = 5, hours = 0 },
        alice = { online = true },
        zebra = { online = false, years = 0, months = 0, days = 1, hours = 0 },
      },
    })
    assert.is_truthy(lines)
    -- Bob counts as online (Alice is playing), so sorts before Zebra.
    assert.is_truthy(lines[1].left:find("Bob", 1, true))
    assert.are.equal("|cffffffffOnline|r", lines[1].right)
    assert.is_truthy(lines[2].left:find("Zebra", 1, true))
    assert.are.equal("|cff8080801d ago|r", lines[2].right)
  end)

  it("ResolveGuildRecipeWhisperTarget returns the online character in the main group", function()
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        return {
          name = name,
          realm = realm,
          main = "ChiefMain",
          guildName = "G",
        }
      end,
      GetGuildMembersForDisplay = function()
        return {
          { name = "Bob", realm = "R", main = "ChiefMain" },
          { name = "Alice", realm = "R", main = "ChiefMain", isMain = true },
        }
      end,
    }
    assert.are.equal("Alice", Nav.ResolveGuildRecipeWhisperTarget("Bob", "R", {
      rosterByName = {
        bob = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        alice = { online = true },
      },
    }))
    assert.is_nil(Nav.ResolveGuildRecipeWhisperTarget("Bob", "R", {
      rosterByName = {
        bob = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        alice = { online = false, years = 0, months = 0, days = 2, hours = 0 },
      },
    }))
  end)

  it("OpenGuildRecipeWhisper sends tell to the online target", function()
    package.loaded["GuildTabData"] = nil
    require("GuildTabData")
    local told
    _G.ChatFrame_SendTell = function(name) told = name end
    AltArmy.GuildShareData = {
      GetCharacter = function(name, realm)
        return { name = name, realm = realm, main = name, guildName = "G" }
      end,
      GetGuildMembersForDisplay = function()
        return { { name = "Bob", realm = "R", main = "Bob", isMain = true } }
      end,
    }
    assert.is_true(Nav.OpenGuildRecipeWhisper("Bob", "R", {
      rosterByName = { bob = { online = true } },
    }))
    assert.are.equal("Bob", told)
    told = nil
    assert.is_false(Nav.OpenGuildRecipeWhisper("Bob", "R", {
      rosterByName = {
        bob = { online = false, years = 0, months = 0, days = 1, hours = 0 },
      },
    }))
    assert.is_nil(told)
  end)
end)
