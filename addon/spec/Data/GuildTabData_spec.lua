--[[
  Unit tests for GuildTabData.lua (pure grouping / sorting / filtering / formatting for
  the Guild tab). No frames; the TabGuild UI wiring is exercised in-game.
  Run from project root: npm test
]]

describe("GuildTabData", function()
  local GTD

  -- Class-color-free formatter so format tests don't depend on RAID_CLASS_COLORS.
  local function plainFormatName(name)
    return name or "?"
  end

  local function profMap(list)
    local out = {}
    for _, p in ipairs(list or {}) do
      out[p.key] = { key = p.key, name = p.name or p.key, rank = p.rank or 0, spec = p.spec }
    end
    return out
  end

  local EM_DASH = "\226\128\148"

  local function member(opts)
    return {
      name = opts.name,
      realm = opts.realm or "R",
      classFile = opts.classFile,
      level = opts.level or 0,
      main = opts.main,
      displayName = opts.displayName,
      isMain = opts.isMain or false,
      source = opts.source,
      Professions = profMap(opts.profs),
    }
  end

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("GuildTabData")
    GTD = AltArmy.GuildTabData
    assert.truthy(GTD)
  end)

  describe("GetPrimaryProfessions", function()
    it("returns only crafting professions with rank, highest skill first", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 375 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
        { key = "cooking", name = "Cooking", rank = 300 },
        { key = "firstAid", name = "First Aid", rank = 300 },
        { key = "mining", name = "Mining", rank = 300 },
      } })
      assert.are.same(
        {
          { key = "tailoring", name = "Tailoring", rank = 375 },
          { key = "alchemy", name = "Alchemy", rank = 300 },
        },
        GTD.GetPrimaryProfessions(m))
    end)

    it("breaks skill-rank ties alphabetically by name", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 300 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
        { key = "engineering", name = "Engineering", rank = 375 },
      } })
      assert.are.same({
        { key = "engineering", name = "Engineering", rank = 375 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
        { key = "tailoring", name = "Tailoring", rank = 300 },
      }, GTD.GetPrimaryProfessions(m))
    end)

    it("excludes professions with zero rank", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 0 },
        { key = "alchemy", name = "Alchemy", rank = 1 },
      } })
      assert.are.same({ { key = "alchemy", name = "Alchemy", rank = 1 } }, GTD.GetPrimaryProfessions(m))
    end)

    it("excludes poisons", function()
      local m = member({ name = "A", profs = {
        { key = "poisons", name = "Poisons", rank = 300 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
      } })
      assert.are.same({ { key = "alchemy", name = "Alchemy", rank = 300 } }, GTD.GetPrimaryProfessions(m))
    end)

    it("includes the specialization label when present", function()
      local m = member({ name = "A", profs = {
        { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" },
      } })
      assert.are.same({ { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" } },
        GTD.GetPrimaryProfessions(m))
    end)

    it("returns empty when there are no professions", function()
      assert.are.same({}, GTD.GetPrimaryProfessions(member({ name = "A" })))
    end)
  end)

  describe("FormatProfessions", function()
    it("lists each profession with its skill level in gray parentheses", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 375 },
        { key = "alchemy", name = "Alchemy", rank = 300 },
      } })
      assert.are.equal(
        "Tailoring |cff808080(375)|r, Alchemy |cff808080(300)|r",
        GTD.FormatProfessions(m))
    end)

    it("returns an empty string when there are no primary professions", function()
      assert.are.equal("", GTD.FormatProfessions(member({ name = "A" })))
    end)

    it("shows the specialization after an em dash (white) before the gray skill level", function()
      local m = member({ name = "A", profs = {
        { key = "tailoring", name = "Tailoring", rank = 375, spec = "Spellfire" },
        { key = "alchemy", name = "Alchemy", rank = 300 },
      } })
      assert.are.equal(
        "Tailoring " .. EM_DASH .. " Spellfire |cff808080(375)|r, Alchemy |cff808080(300)|r",
        GTD.FormatProfessions(m))
    end)

    it("highlights matching substrings in profession names and specializations", function()
      local m = member({ name = "A", profs = {
        { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" },
      } })
      assert.are.equal(
        "|cff00ff00Alch|r" .. "emy " .. EM_DASH .. " Transmute |cff808080(375)|r",
        GTD.FormatProfessions(m, "alch"))
    end)
  end)

  describe("GroupMembersByMain", function()
    it("groups alts under their main with preferred name and character count", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Mainman", main = "Mainman", isMain = true, displayName = "Bossman",
          classFile = "MAGE", level = 70 }),
        member({ name = "Altchar", main = "Mainman", level = 40, classFile = "WARRIOR" }),
      })
      assert.are.equal(1, #groups)
      assert.are.equal("Bossman", groups[1].preferredName)
      assert.are.equal("Mainman", groups[1].main)
      assert.are.equal(2, groups[1].characterCount)
      assert.are.equal("MAGE", groups[1].classFile)
    end)

    it("falls back to the main character name when no display name is set", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Solo", main = "Solo", isMain = true }),
      })
      assert.are.equal("Solo", groups[1].preferredName)
    end)

    it("uses the character's own name as the group key when no main is set", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Loner", level = 12 }),
      })
      assert.are.equal(1, #groups)
      assert.are.equal("Loner", groups[1].preferredName)
    end)

    it("sorts groups alphabetically by preferred name, case-insensitively", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "zed", main = "zed", isMain = true, displayName = "zed" }),
        member({ name = "Alice", main = "Alice", isMain = true, displayName = "alice" }),
        member({ name = "Bob", main = "Bob", isMain = true, displayName = "Bob" }),
      })
      assert.are.equal("alice", groups[1].preferredName)
      assert.are.equal("Bob", groups[2].preferredName)
      assert.are.equal("zed", groups[3].preferredName)
    end)

    it("sorts members within a group by level descending, then name ascending", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Mid", main = "Main", level = 40 }),
        member({ name = "Main", main = "Main", isMain = true, level = 70 }),
        member({ name = "Aaa", main = "Main", level = 40 }),
        member({ name = "Low", main = "Main", level = 10 }),
      })
      local names = {}
      for _, m in ipairs(groups[1].members) do names[#names + 1] = m.name end
      assert.are.same({ "Main", "Aaa", "Mid", "Low" }, names)
    end)
  end)

  describe("FilterGroups", function()
    local groups

    before_each(function()
      groups = GTD.GroupMembersByMain({
        member({ name = "Bossman", main = "Bossman", isMain = true, displayName = "TopDog" }),
        member({ name = "Sidekick", main = "Bossman" }),
        member({ name = "Loner", main = "Loner", isMain = true, displayName = "Loner" }),
      })
    end)

    it("returns all groups when the query is empty", function()
      assert.are.equal(2, #GTD.FilterGroups(groups, ""))
      assert.are.equal(2, #GTD.FilterGroups(groups, nil))
      assert.are.equal(2, #GTD.FilterGroups(groups, "  "))
    end)

    it("matches on the preferred name and includes all characters in the group", function()
      local out = GTD.FilterGroups(groups, "topdog")
      assert.are.equal(1, #out)
      assert.are.equal("TopDog", out[1].preferredName)
      assert.are.equal(2, #out[1].members)
      assert.are.equal(2, out[1].characterCount)
    end)

    it("matches on the main character name and includes all characters in the group", function()
      local out = GTD.FilterGroups(groups, "bossman")
      assert.are.equal(1, #out)
      assert.are.equal("TopDog", out[1].preferredName)
      assert.are.equal(2, #out[1].members)
      assert.are.equal(2, out[1].characterCount)
    end)

    it("matches on an alt character name and omits non-matching characters", function()
      local out = GTD.FilterGroups(groups, "sidekick")
      assert.are.equal(1, #out)
      assert.are.equal("TopDog", out[1].preferredName)
      assert.are.equal(1, #out[1].members)
      assert.are.equal("Sidekick", out[1].members[1].name)
    end)

    it("returns nothing when no group matches", function()
      assert.are.equal(0, #GTD.FilterGroups(groups, "nobody"))
    end)

    it("updates characterCount to the number of visible members", function()
      local out = GTD.FilterGroups(groups, "sidekick")
      assert.are.equal(1, out[1].characterCount)
    end)

    it("matches on a character profession name and omits non-matching characters", function()
      local profGroups = GTD.GroupMembersByMain({
        member({ name = "Bossman", main = "Bossman", isMain = true, displayName = "TopDog", profs = {
          { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" },
        } }),
        member({ name = "Sidekick", main = "Bossman" }),
      })
      local out = GTD.FilterGroups(profGroups, "alch")
      assert.are.equal(1, #out)
      assert.are.equal(1, #out[1].members)
      assert.are.equal("Bossman", out[1].members[1].name)
    end)

    it("matches on a profession specialization", function()
      local profGroups = GTD.GroupMembersByMain({
        member({ name = "Crafter", main = "Crafter", isMain = true, profs = {
          { key = "alchemy", name = "Alchemy", rank = 375, spec = "Transmute" },
        } }),
      })
      local out = GTD.FilterGroups(profGroups, "trans")
      assert.are.equal(1, #out)
      assert.are.equal("Crafter", out[1].members[1].name)
    end)
  end)

  describe("FormatTextWithSearchHighlight", function()
    local GREEN = "|cff00ff00"

    it("returns plain text when the query is empty", function()
      assert.are.equal("Mindfrell", GTD.FormatTextWithSearchHighlight("Mindfrell", "MAGE", ""))
    end)

    it("highlights the matching substring in bright green with class-colored prefix", function()
      local function fakeFormat(text)
        return "<MAGE>" .. text
      end
      local out = GTD.FormatTextWithSearchHighlight("Mindfrell", "MAGE", "frell", fakeFormat)
      assert.are.equal("<MAGE>Mind" .. GREEN .. "frell|r", out)
    end)

    it("is case-insensitive while preserving original casing", function()
      local out = GTD.FormatTextWithSearchHighlight("Mindfrell", nil, "FRELL")
      assert.are.equal("Mind" .. GREEN .. "frell|r", out)
    end)

    it("highlights every non-overlapping match", function()
      local out = GTD.FormatTextWithSearchHighlight("banana", nil, "an")
      assert.are.equal("b" .. GREEN .. "an|r" .. GREEN .. "an|r" .. "a", out)
    end)
  end)

  describe("FormatMainRowName", function()
    it("returns the preferred name", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
      })
      assert.are.equal("Chief", GTD.FormatMainRowName(groups[1]))
    end)

    it("highlights the matching portion of the preferred name", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Mindfrell", classFile = "MAGE" }),
      })
      assert.are.equal(
        "Mind|cff00ff00frell|r",
        GTD.FormatMainRowName(groups[1], plainFormatName, "frell"))
    end)
  end)

  describe("FormatMainRowCount", function()
    it("pluralizes the character count", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
        member({ name = "Alt", main = "Main" }),
      })
      assert.are.equal("2 characters", GTD.FormatMainRowCount(groups[1]))
    end)

    it("uses the singular form for a single character", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Solo", main = "Solo", isMain = true, displayName = "Solo" }),
      })
      assert.are.equal("1 character", GTD.FormatMainRowCount(groups[1]))
    end)
  end)

  describe("FormatMainRowLabel", function()
    it("shows the preferred name and pluralized character count", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
        member({ name = "Alt", main = "Main" }),
      })
      assert.are.equal("Chief 2 characters", GTD.FormatMainRowLabel(groups[1]))
    end)

    it("uses the singular form for a single character", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Solo", main = "Solo", isMain = true, displayName = "Solo" }),
      })
      assert.are.equal("Solo 1 character", GTD.FormatMainRowLabel(groups[1]))
    end)

    it("colors the preferred name via formatName while leaving the count plain", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief", classFile = "MAGE" }),
        member({ name = "Alt", main = "Main" }),
      })
      local seen = {}
      local function fakeFormat(name, classFile)
        seen.name, seen.classFile = name, classFile
        return "<" .. classFile .. ">" .. name
      end
      assert.are.equal("<MAGE>Chief 2 characters",
        GTD.FormatMainRowLabel(groups[1], fakeFormat))
      assert.are.equal("Chief", seen.name)
      assert.are.equal("MAGE", seen.classFile)
    end)

    it("highlights the matching portion of the preferred name", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Mindfrell", classFile = "MAGE" }),
      })
      assert.are.equal(
        "Mind|cff00ff00frell|r 1 character",
        GTD.FormatMainRowLabel(groups[1], plainFormatName, "frell"))
    end)
  end)

  describe("GetStoredCharacter", function()
    it("reads from DataStore for local entries", function()
      local savedDS = AltArmy.DataStore
      local charData = { name = "Local", Professions = { tailoring = { rank = 300 } } }
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm == "R" then return { Local = charData } end
          return {}
        end,
      }
      local entry = member({ name = "Local", realm = "R", source = "local" })
      assert.are.same(charData, GTD.GetStoredCharacter(entry))
      AltArmy.DataStore = savedDS
    end)

    it("reads from GuildShareData for remote entries", function()
      local savedGSD = AltArmy.GuildShareData
      local stored = { name = "Remote", Professions = {} }
      AltArmy.GuildShareData = {
        GetCharacter = function(name, realm)
          if name == "Remote" and realm == "R" then return stored end
          return nil
        end,
      }
      local entry = member({ name = "Remote", realm = "R", source = "Peer" })
      assert.are.same(stored, GTD.GetStoredCharacter(entry))
      AltArmy.GuildShareData = savedGSD
    end)
  end)

  describe("GetProfessionRecipes", function()
    before_each(function()
      package.loaded["GuildShareProtocol"] = nil
      require("GuildShareProtocol")
    end)

    it("returns primary recipe ids sorted, excluding aliases", function()
      local entry = member({
        name = "A",
        profs = {
          { key = "alchemy", name = "Alchemy", rank = 300 },
        },
      })
      entry.Professions.alchemy.Recipes = {
        [11449] = { primaryRecipeID = 11449, resultItemID = 9187 },
        [11334] = { primaryRecipeID = 11449 },
      }
      assert.are.same({
        { recipeID = 11449, resultItemID = 9187 },
      }, GTD.GetProfessionRecipes(entry, "alchemy"))
    end)

    it("returns empty when profession is missing", function()
      assert.are.same({}, GTD.GetProfessionRecipes(member({ name = "A" }), "alchemy"))
    end)

    it("reads recipes from DataStore for local entries", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm == "R" then
            return {
              Local = {
                Professions = {
                  tailoring = {
                    Recipes = {
                      [12045] = { primaryRecipeID = 12045 },
                      [12046] = { primaryRecipeID = 12046 },
                    },
                  },
                },
              },
            }
          end
          return {}
        end,
      }
      local entry = member({ name = "Local", realm = "R", source = "local" })
      assert.are.same({
        { recipeID = 12045 },
        { recipeID = 12046 },
      }, GTD.GetProfessionRecipes(entry, "tailoring"))
      AltArmy.DataStore = savedDS
    end)
  end)

  describe("FormatCharacterTitle", function()
    it("returns class-colored name via formatName", function()
      local m = member({ name = "Mage", classFile = "MAGE" })
      assert.are.equal("Mage", GTD.FormatCharacterTitle(m, plainFormatName))
    end)
  end)

  describe("FormatNoProfessionsMessage", function()
    it("embeds the class-colored character name", function()
      local m = member({ name = "Newbie", classFile = "WARRIOR" })
      assert.are.equal("Newbie has not picked professions yet",
        GTD.FormatNoProfessionsMessage(m, plainFormatName))
    end)
  end)

  describe("CollectAccountGuilds", function()
    it("returns sorted unique guild names from account characters", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        ForEachCharacter = function(_, fn)
          fn("R1", "A", { guildName = "Zeta Guild" })
          fn("R1", "B", { guildName = "Alpha Guild" })
          fn("R2", "C", { guildName = "Alpha Guild" })
          fn("R2", "D", { guildName = nil })
        end,
      }
      assert.are.same({ "Alpha Guild", "Zeta Guild" }, GTD.CollectAccountGuilds())
      AltArmy.DataStore = savedDS
    end)

    it("returns empty when DataStore is unavailable", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = nil
      assert.are.same({}, GTD.CollectAccountGuilds())
      AltArmy.DataStore = savedDS
    end)
  end)

  describe("GetAutoBrowseGuild", function()
    it("returns the sole guild when there is exactly one", function()
      assert.are.equal("Only Guild", GTD.GetAutoBrowseGuild({ "Only Guild" }))
    end)

    it("returns nil when there are zero or multiple guilds", function()
      assert.is_nil(GTD.GetAutoBrowseGuild({}))
      assert.is_nil(GTD.GetAutoBrowseGuild({ "A", "B" }))
      assert.is_nil(GTD.GetAutoBrowseGuild(nil))
    end)
  end)

  describe("FormatRecipeSearchPlaceholder", function()
    it("uses the character name in plain text", function()
      assert.are.equal("Search for recipes on Mindfrell", GTD.FormatRecipeSearchPlaceholder("Mindfrell"))
    end)

    it("falls back when the name is missing", function()
      assert.are.equal("Search for recipes on this character", GTD.FormatRecipeSearchPlaceholder(nil))
    end)
  end)

  describe("FilterRecipesBySearch", function()
    local recipes = {
      { recipeID = 1, name = "Bolt of Silk Cloth" },
      { recipeID = 2, name = "Mooncloth" },
    }

    it("returns all recipes when the query is empty", function()
      assert.are.same(recipes, GTD.FilterRecipesBySearch(recipes, "", function(r) return r.name end))
    end)

    it("filters by case-insensitive substring on the resolved name", function()
      local out = GTD.FilterRecipesBySearch(recipes, "moon", function(r) return r.name end)
      assert.are.same({ { recipeID = 2, name = "Mooncloth" } }, out)
    end)
  end)

  describe("FormatRecipeSkillCell", function()
    local savedRCL

    before_each(function()
      savedRCL = AltArmy.RecipeCraftLib
    end)

    after_each(function()
      AltArmy.RecipeCraftLib = savedRCL
    end)

    it("delegates to RecipeCraftLib when available", function()
      AltArmy.RecipeCraftLib = {
        EnrichEntry = function(entry)
          entry.recipeSkillRequired = 180
          entry.difficulty = "yellow"
        end,
        FormatSkillCell = function(req, rank, difficulty)
          return string.format("%d/%d/%s", req, rank, difficulty)
        end,
      }
      local text = GTD.FormatRecipeSkillCell(
        { recipeID = 26751, resultItemID = 21842 },
        "Tailoring",
        375
      )
      assert.are.equal("180/375/yellow", text)
    end)

    it("falls back to skill rank when RecipeCraftLib is unavailable", function()
      AltArmy.RecipeCraftLib = nil
      assert.are.equal("300", GTD.FormatRecipeSkillCell({ recipeID = 1 }, "Alchemy", 300))
    end)

    it("shows em dash when skill rank is zero and CraftLib is unavailable", function()
      AltArmy.RecipeCraftLib = {
        EnrichEntry = function() end,
        FormatSkillCell = function()
          return "—"
        end,
      }
      assert.are.equal("—", GTD.FormatRecipeSkillCell({ recipeID = 1 }, "Alchemy", 0))
    end)
  end)

  describe("SortRecipes", function()
    local savedRCL
    local recipes = {
      { recipeID = 1, name = "Zebra Cloth" },
      { recipeID = 2, name = "Alpha Bolt" },
      { recipeID = 3, name = "Mooncloth" },
    }
    local function nameOf(r)
      return r.name
    end

    before_each(function()
      savedRCL = AltArmy.RecipeCraftLib
    end)

    after_each(function()
      AltArmy.RecipeCraftLib = savedRCL
    end)

    it("sorts by recipe name ascending", function()
      local out = GTD.SortRecipes(recipes, "recipe", true, { getRecipeName = nameOf })
      assert.are.equal(2, out[1].recipeID)
      assert.are.equal(3, out[2].recipeID)
      assert.are.equal(1, out[3].recipeID)
    end)

    it("sorts by recipe name descending", function()
      local out = GTD.SortRecipes(recipes, "recipe", false, { getRecipeName = nameOf })
      assert.are.equal(1, out[1].recipeID)
      assert.are.equal(3, out[2].recipeID)
      assert.are.equal(2, out[3].recipeID)
    end)

    it("sorts by required skill ascending with name tiebreaker", function()
      AltArmy.RecipeCraftLib = {
        EnrichEntry = function(entry)
          if entry.recipeID == 1 then
            entry.recipeSkillRequired = 300
            entry.difficulty = "orange"
          elseif entry.recipeID == 2 then
            entry.recipeSkillRequired = 150
            entry.difficulty = "yellow"
          elseif entry.recipeID == 3 then
            entry.recipeSkillRequired = 300
            entry.difficulty = "green"
          end
        end,
      }
      local out = GTD.SortRecipes(recipes, "skill", true, {
        professionName = "Tailoring",
        skillRank = 375,
        getRecipeName = nameOf,
      })
      assert.are.equal(2, out[1].recipeID)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal(3, out[3].recipeID)
    end)

    it("places recipes without required skill last when ascending", function()
      AltArmy.RecipeCraftLib = {
        EnrichEntry = function(entry)
          if entry.recipeID == 1 then
            entry.recipeSkillRequired = nil
          elseif entry.recipeID == 2 then
            entry.recipeSkillRequired = 100
          end
        end,
      }
      local two = {
        { recipeID = 1, name = "Unknown" },
        { recipeID = 2, name = "Known" },
      }
      local out = GTD.SortRecipes(two, "skill", true, {
        professionName = "Alchemy",
        skillRank = 300,
        getRecipeName = nameOf,
      })
      assert.are.equal(2, out[1].recipeID)
      assert.are.equal(1, out[2].recipeID)
    end)
  end)

  describe("FormatCharacterName", function()
    it("includes the class-colored name and gray level", function()
      local m = member({ name = "Mage", classFile = "MAGE", level = 70 })
      assert.are.equal("Mage |cff808080(level 70)|r",
        GTD.FormatCharacterName(m, plainFormatName))
    end)

    it("highlights the matching portion of the character name", function()
      local m = member({ name = "Mindfrell", classFile = "MAGE", level = 70 })
      local out = GTD.FormatCharacterName(m, plainFormatName, "frell")
      assert.are.equal("Mind|cff00ff00frell|r |cff808080(level 70)|r", out)
    end)

    it("floors fractional levels", function()
      local m = member({ name = "Odd", level = 42.9 })
      local text = GTD.FormatCharacterName(m, plainFormatName)
      assert.truthy(text:find("(level 42)", 1, true))
    end)
  end)
end)
