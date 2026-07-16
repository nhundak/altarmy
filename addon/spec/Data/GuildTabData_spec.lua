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
      mainDeclared = opts.mainDeclared,
      source = opts.source,
      receivedAt = opts.receivedAt,
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

  describe("old received data", function()
    local DAY = 60 * 60 * 24
    local NOW = 1700000000

    it("exposes a 14-day UI warning age", function()
      assert.are.equal(14 * DAY, GTD.OLD_DATA_AGE_SEC)
    end)

    it("IsMemberDataOld is false for local account members", function()
      local m = member({ name = "Me", source = "local", receivedAt = NOW - 30 * DAY })
      assert.is_false(GTD.IsMemberDataOld(m, NOW))
    end)

    it("IsMemberDataOld is false when receivedAt is missing", function()
      local m = member({ name = "Peer", source = "Peer" })
      assert.is_false(GTD.IsMemberDataOld(m, NOW))
    end)

    it("IsMemberDataOld is false when data is fresher than the warning age", function()
      local m = member({
        name = "Peer", source = "Peer", receivedAt = NOW - (GTD.OLD_DATA_AGE_SEC - DAY),
      })
      assert.is_false(GTD.IsMemberDataOld(m, NOW))
    end)

    it("IsMemberDataOld is true when data is at or past the warning age", function()
      local m = member({
        name = "Peer", source = "Peer", receivedAt = NOW - GTD.OLD_DATA_AGE_SEC,
      })
      assert.is_true(GTD.IsMemberDataOld(m, NOW))
      assert.is_true(GTD.IsMemberDataOld(
        member({ name = "Peer", source = "Peer", receivedAt = NOW - (20 * DAY) }),
        NOW))
    end)

    it("GroupHasOldData is true when any received member is old", function()
      local groups = GTD.GroupMembersByMain({
        member({
          name = "Main", main = "Main", isMain = true, source = "Main",
          receivedAt = NOW - (20 * DAY),
        }),
        member({
          name = "Alt", main = "Main", source = "Main",
          receivedAt = NOW - (20 * DAY),
        }),
      })
      assert.is_true(GTD.GroupHasOldData(groups[1], NOW))
    end)

    it("GroupHasOldData is false for fresh received groups and local-only groups", function()
      local fresh = GTD.GroupMembersByMain({
        member({
          name = "Fresh", main = "Fresh", isMain = true, source = "Fresh",
          receivedAt = NOW - DAY,
        }),
      })
      assert.is_false(GTD.GroupHasOldData(fresh[1], NOW))

      local localOnly = GTD.GroupMembersByMain({
        member({ name = "Me", main = "Me", isMain = true, source = "local" }),
      })
      assert.is_false(GTD.GroupHasOldData(localOnly[1], NOW))
    end)

    it("GetOldDataTooltipText explains that shared data is outdated", function()
      local text = GTD.GetOldDataTooltipText()
      assert.is_true(type(text) == "string" and #text > 0)
      assert.truthy(text:find("14", 1, true))
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

    it("matches on overrideName and includes all characters in the group", function()
      local target
      for _, g in ipairs(groups) do
        if g.main == "Bossman" then
          target = g
          break
        end
      end
      assert.truthy(target)
      target.overrideName = "Nickname"
      local out = GTD.FilterGroups(groups, "nick")
      assert.are.equal(1, #out)
      assert.are.equal("Bossman", out[1].main)
      assert.are.equal(2, #out[1].members)
      assert.are.equal("Nickname", out[1].overrideName)
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

    it("prefers overrideName over preferredName", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
      })
      groups[1].overrideName = "Buddy"
      assert.are.equal("Buddy", GTD.FormatMainRowName(groups[1]))
    end)

    it("appends gray (you) when the group is the player's own", function()
      local groups = GTD.GroupMembersByMain({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief", classFile = "MAGE" }),
      })
      assert.are.equal(
        "Chief |cff808080(you)|r",
        GTD.FormatMainRowName(groups[1], plainFormatName, nil, true))
      assert.are.equal("Chief", GTD.FormatMainRowName(groups[1], plainFormatName, nil, false))
    end)
  end)

  describe("ResolveGroupDisplayName", function()
    it("prefers override, then preferredName, then main", function()
      assert.are.equal("Buddy", GTD.ResolveGroupDisplayName({
        main = "Main", preferredName = "Chief", overrideName = "Buddy",
      }))
      assert.are.equal("Chief", GTD.ResolveGroupDisplayName({
        main = "Main", preferredName = "Chief",
      }))
      assert.are.equal("Main", GTD.ResolveGroupDisplayName({ main = "Main" }))
      assert.are.equal("?", GTD.ResolveGroupDisplayName({}))
    end)

    it("accepts an optional getOverride callback", function()
      local name = GTD.ResolveGroupDisplayName(
        { main = "Main", preferredName = "Chief" },
        function(group) return group.main == "Main" and "FromCb" or nil end)
      assert.are.equal("FromCb", name)
    end)
  end)

  describe("IsOwnGroup", function()
    it("is true when group main matches the player's main", function()
      assert.is_true(GTD.IsOwnGroup({ main = "Me" }, "Me"))
      assert.is_false(GTD.IsOwnGroup({ main = "Me" }, "Other"))
      assert.is_false(GTD.IsOwnGroup({ main = "Me" }, nil))
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

  describe("roster last online", function()
    describe("NormalizeRosterName", function()
      it("strips a realm suffix and lowercases", function()
        assert.are.equal("alice", GTD.NormalizeRosterName("Alice-EmeraldDream"))
      end)

      it("returns the short name lowercased", function()
        assert.are.equal("bob", GTD.NormalizeRosterName("Bob"))
      end)

      it("returns nil for non-strings", function()
        assert.is_nil(GTD.NormalizeRosterName(nil))
        assert.is_nil(GTD.NormalizeRosterName(12))
      end)
    end)

    describe("RosterOfflineHours", function()
      it("returns 0 for online or missing status", function()
        assert.are.equal(0, GTD.RosterOfflineHours({ online = true }))
        assert.are.equal(0, GTD.RosterOfflineHours(nil))
      end)

      it("converts years/months/days/hours into comparable hours", function()
        local hours = GTD.RosterOfflineHours({
          online = false, years = 0, months = 1, days = 2, hours = 3,
        })
        assert.are.equal(((1 * 30.5) + 2) * 24 + 3, hours)
      end)
    end)

    describe("FormatRosterLastOnline", function()
      it("returns empty string when status is missing", function()
        assert.are.equal("", GTD.FormatRosterLastOnline(nil))
      end)

      it("returns gray Unknown when status is missing and showUnknownWhenMissing", function()
        assert.are.equal("|cff808080Unknown|r", GTD.FormatRosterLastOnline(nil, {
          showUnknownWhenMissing = true,
        }))
      end)

      it("returns Online when the character is online", function()
        assert.are.equal("Online", GTD.FormatRosterLastOnline({ online = true }))
      end)

      it("formats the largest non-zero unit", function()
        assert.are.equal("2y ago", GTD.FormatRosterLastOnline({
          online = false, years = 2, months = 3, days = 4, hours = 5,
        }))
        assert.are.equal("3mo ago", GTD.FormatRosterLastOnline({
          online = false, years = 0, months = 3, days = 4, hours = 5,
        }))
        assert.are.equal("4d ago", GTD.FormatRosterLastOnline({
          online = false, years = 0, months = 0, days = 4, hours = 5,
        }))
        assert.are.equal("5h ago", GTD.FormatRosterLastOnline({
          online = false, years = 0, months = 0, days = 0, hours = 5,
        }))
      end)

      it("returns < 1h ago when offline duration is under an hour", function()
        assert.are.equal("< 1h ago", GTD.FormatRosterLastOnline({
          online = false, years = 0, months = 0, days = 0, hours = 0,
        }))
      end)
    end)

    describe("PickMostRecentRosterStatus", function()
      it("returns Online when any status is online", function()
        local status = GTD.PickMostRecentRosterStatus({
          { online = false, years = 0, months = 0, days = 5, hours = 0 },
          { online = true },
          { online = false, years = 0, months = 0, days = 1, hours = 0 },
        })
        assert.are.same({ online = true }, status)
      end)

      it("picks the shortest offline duration", function()
        local status = GTD.PickMostRecentRosterStatus({
          { online = false, years = 0, months = 0, days = 5, hours = 0 },
          { online = false, years = 0, months = 0, days = 1, hours = 2 },
          { online = false, years = 0, months = 0, days = 3, hours = 0 },
        })
        assert.are.same({
          online = false, years = 0, months = 0, days = 1, hours = 2,
        }, status)
      end)

      it("ignores nil statuses and returns nil when none remain", function()
        assert.is_nil(GTD.PickMostRecentRosterStatus({ nil, nil }))
        assert.is_nil(GTD.PickMostRecentRosterStatus(nil))
      end)
    end)

    describe("GetGroupLastOnlineStatus", function()
      it("aggregates the most recent status across group members", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
          member({ name = "Alt", main = "Main" }),
        })
        local roster = {
          main = { online = false, years = 0, months = 0, days = 4, hours = 0 },
          alt = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        }
        assert.are.same(roster.alt, GTD.GetGroupLastOnlineStatus(groups[1], roster))
      end)

      it("matches roster names that include a realm suffix", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Alice", main = "Alice", isMain = true, displayName = "Alice" }),
        })
        local roster = {
          alice = { online = true },
        }
        assert.are.same({ online = true }, GTD.GetGroupLastOnlineStatus(groups[1], roster))
      end)

      it("returns nil when no group members appear in the roster", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Ghost", main = "Ghost", isMain = true, displayName = "Ghost" }),
        })
        assert.is_nil(GTD.GetGroupLastOnlineStatus(groups[1], {}))
      end)
    end)

    describe("GetGroupMostRecentOnlineDetail", function()
      it("returns which member is the most recent and their status", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
          member({ name = "Alt", main = "Main" }),
        })
        local roster = {
          main = { online = false, years = 0, months = 0, days = 4, hours = 0 },
          alt = { online = true },
        }
        local detail = GTD.GetGroupMostRecentOnlineDetail(groups[1], roster)
        assert.are.equal("Alt", detail.memberName)
        assert.is_true(detail.status.online)
      end)

      it("returns nil when nothing is in the roster", function()
        local groups = GTD.GroupMembersByMain({
          member({ name = "Ghost", main = "Ghost", isMain = true, displayName = "Ghost" }),
        })
        assert.is_nil(GTD.GetGroupMostRecentOnlineDetail(groups[1], {}))
      end)
    end)

    describe("FormatGroupPresenceTooltipLine", function()
      it("returns nil when detail is missing", function()
        assert.is_nil(GTD.FormatGroupPresenceTooltipLine("Bob", nil))
      end)

      it("returns Online when the hovered character is online", function()
        assert.are.equal(
          "Online",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Bob",
            status = { online = true },
          })
        )
      end)

      it("notes when another character is the online presence", function()
        assert.are.equal(
          "Online (as Alice)",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Alice",
            classFile = "WARRIOR",
            status = { online = true },
          }, plainFormatName)
        )
      end)

      it("class-colors the other character name in the as-clause", function()
        assert.are.equal(
          "Online (as [Alice])",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Alice",
            classFile = "WARRIOR",
            status = { online = true },
          }, function(name) return "[" .. name .. "]" end)
        )
      end)

      it("formats last seen and notes a different character when applicable", function()
        assert.are.equal(
          "Last seen 5h ago",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Bob",
            status = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          }, plainFormatName)
        )
        assert.are.equal(
          "Last seen 2d ago (as Alice)",
          GTD.FormatGroupPresenceTooltipLine("Bob", {
            memberName = "Alice",
            status = { online = false, years = 0, months = 0, days = 2, hours = 0 },
          }, plainFormatName)
        )
      end)
    end)

    describe("BuildGuildCharacterHoverTooltipLines", function()
      it("builds title and level lines with class-colored name", function()
        local lines = GTD.BuildGuildCharacterHoverTooltipLines({
          name = "Bob",
          preferredName = "Chief",
          classFile = "MAGE",
          level = 70,
          formatName = function(name) return "[" .. name .. "]" end,
          classDisplayName = "Mage",
        })
        assert.are.equal("[Bob] (Chief)", lines[1])
        assert.are.equal("Level 70 Mage", lines[2])
        assert.is_nil(lines[3])
      end)

      it("omits preferred name when it matches the character name", function()
        local lines = GTD.BuildGuildCharacterHoverTooltipLines({
          name = "Bob",
          preferredName = "bob",
          classFile = "MAGE",
          level = 70,
          formatName = plainFormatName,
          classDisplayName = "Mage",
        })
        assert.are.equal("Bob", lines[1])
        assert.are.equal("Level 70 Mage", lines[2])
      end)

      it("appends a presence line when roster detail is available", function()
        local lines = GTD.BuildGuildCharacterHoverTooltipLines({
          name = "Bob",
          preferredName = "Chief",
          classFile = "MAGE",
          level = 70,
          formatName = plainFormatName,
          classDisplayName = "Mage",
          presenceDetail = {
            memberName = "Alice",
            status = { online = true },
          },
        })
        assert.are.equal("Bob (Chief)", lines[1])
        assert.are.equal("Level 70 Mage", lines[2])
        assert.are.equal("Online (as Alice)", lines[3])
        assert.is_true(lines.presenceOnline)
      end)

      it("marks presenceOnline false when last seen", function()
        local lines = GTD.BuildGuildCharacterHoverTooltipLines({
          name = "Bob",
          preferredName = "Bob",
          classFile = "MAGE",
          level = 70,
          formatName = plainFormatName,
          classDisplayName = "Mage",
          presenceDetail = {
            memberName = "Bob",
            status = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          },
        })
        assert.are.equal("Last seen 5h ago", lines[3])
        assert.is_false(lines.presenceOnline)
      end)
    end)

    describe("ResolveOnlineWhisperTarget", function()
      it("returns nil when nobody in the group is online", function()
        local entry = member({ name = "Bob", main = "Main", displayName = "Chief" })
        local members = {
          member({ name = "Main", main = "Main", isMain = true, displayName = "Chief" }),
          entry,
        }
        local roster = {
          bob = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          main = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        }
        assert.is_nil(GTD.ResolveOnlineWhisperTarget(entry, roster, members))
      end)

      it("returns the online character even when viewing a different alt", function()
        local entry = member({ name = "Bob", main = "Main", displayName = "Chief" })
        local members = {
          member({ name = "Alice", main = "Main", isMain = true, displayName = "Chief" }),
          entry,
        }
        local roster = {
          bob = { online = false, years = 0, months = 0, days = 0, hours = 5 },
          alice = { online = true },
        }
        assert.are.equal("Alice", GTD.ResolveOnlineWhisperTarget(entry, roster, members))
      end)

      it("returns the viewed character when they are the online one", function()
        local entry = member({ name = "Bob", main = "Main", displayName = "Chief" })
        local members = {
          member({ name = "Alice", main = "Main", isMain = true, displayName = "Chief" }),
          entry,
        }
        local roster = {
          bob = { online = true },
          alice = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        }
        assert.are.equal("Bob", GTD.ResolveOnlineWhisperTarget(entry, roster, members))
      end)

      it("returns nil for the player's own (local) characters", function()
        local entry = member({ name = "MyAlt", main = "MyMain", source = "local" })
        local members = {
          member({ name = "MyMain", main = "MyMain", isMain = true, source = "local" }),
          entry,
        }
        local roster = {
          myalt = { online = true },
          mymain = { online = true },
        }
        assert.is_nil(GTD.ResolveOnlineWhisperTarget(entry, roster, members))
      end)
    end)

    describe("character recipe title level suffix", function()
      it("formats full and short level suffixes", function()
        assert.are.equal(" (level 70)", GTD.FormatCharacterLevelSuffix(70, "full"))
        assert.are.equal(" (70)", GTD.FormatCharacterLevelSuffix(70, "short"))
        assert.are.equal(
          " |cff808080(level 70)|r",
          GTD.FormatCharacterLevelSuffix(70, "full", "|cff808080")
        )
      end)

      it("chooses full, short, or ellipsis mode from fit flags", function()
        assert.are.equal("full", GTD.ChooseCharacterTitleLevelMode(true, true))
        assert.are.equal("short", GTD.ChooseCharacterTitleLevelMode(false, true))
        assert.are.equal("ellipsis", GTD.ChooseCharacterTitleLevelMode(false, false))
      end)
    end)

    describe("BuildRosterLastOnlineMap", function()
      it("returns an empty map when not in a guild", function()
        local map = GTD.BuildRosterLastOnlineMap({
          isInGuild = function() return false end,
          getNumGuildMembers = function() return 3 end,
        })
        assert.are.same({}, map)
      end)

      it("maps online and offline members by short name", function()
        local roster = {
          [1] = { name = "Alice-Realm", online = true },
          [2] = { name = "Bob", online = false, years = 0, months = 0, days = 2, hours = 4 },
        }
        local map = GTD.BuildRosterLastOnlineMap({
          isInGuild = function() return true end,
          getNumGuildMembers = function() return 2 end,
          getGuildRosterInfo = function(i)
            local e = roster[i]
            return e.name, nil, nil, nil, nil, nil, nil, nil, e.online
          end,
          getGuildRosterLastOnline = function(i)
            local e = roster[i]
            return e.years, e.months, e.days, e.hours
          end,
        })
        assert.are.same({
          alice = { online = true },
          bob = { online = false, years = 0, months = 0, days = 2, hours = 4 },
        }, map)
      end)
    end)
  end)

  describe("SortGroups", function()
    local function grouped(members)
      return GTD.GroupMembersByMain(members)
    end

    it("sorts by preferred name ascending by default", function()
      local groups = grouped({
        member({ name = "Zed", main = "Zed", isMain = true, displayName = "Zed" }),
        member({ name = "Amy", main = "Amy", isMain = true, displayName = "Amy" }),
        member({ name = "Bob", main = "Bob", isMain = true, displayName = "Bob" }),
      })
      local sorted = GTD.SortGroups(groups, "name", true)
      assert.are.equal("Amy", sorted[1].preferredName)
      assert.are.equal("Bob", sorted[2].preferredName)
      assert.are.equal("Zed", sorted[3].preferredName)
    end)

    it("sorts by preferred name descending", function()
      local groups = grouped({
        member({ name = "Zed", main = "Zed", isMain = true, displayName = "Zed" }),
        member({ name = "Amy", main = "Amy", isMain = true, displayName = "Amy" }),
      })
      local sorted = GTD.SortGroups(groups, "name", false)
      assert.are.equal("Zed", sorted[1].preferredName)
      assert.are.equal("Amy", sorted[2].preferredName)
    end)

    it("sorts by character count", function()
      local groups = grouped({
        member({ name = "Solo", main = "Solo", isMain = true, displayName = "Solo" }),
        member({ name = "Main", main = "Main", isMain = true, displayName = "Duo" }),
        member({ name = "Alt", main = "Main" }),
      })
      local asc = GTD.SortGroups(groups, "characterCount", true)
      assert.are.equal("Solo", asc[1].preferredName)
      assert.are.equal("Duo", asc[2].preferredName)
      local desc = GTD.SortGroups(groups, "characterCount", false)
      assert.are.equal("Duo", desc[1].preferredName)
      assert.are.equal("Solo", desc[2].preferredName)
    end)

    it("sorts online as least time, then hours, days, months, years", function()
      local groups = grouped({
        member({ name = "Old", main = "Old", isMain = true, displayName = "Old" }),
        member({ name = "Live", main = "Live", isMain = true, displayName = "Live" }),
        member({ name = "Recent", main = "Recent", isMain = true, displayName = "Recent" }),
        member({ name = "DayOld", main = "DayOld", isMain = true, displayName = "DayOld" }),
        member({ name = "Gone", main = "Gone", isMain = true, displayName = "Gone" }),
      })
      local roster = {
        live = { online = true },
        recent = { online = false, years = 0, months = 0, days = 0, hours = 2 },
        dayold = { online = false, years = 0, months = 0, days = 1, hours = 0 },
        old = { online = false, years = 0, months = 0, days = 10, hours = 0 },
      }
      local sorted = GTD.SortGroups(groups, "online", true, roster)
      assert.are.equal("Live", sorted[1].preferredName)
      assert.are.equal("Recent", sorted[2].preferredName)
      assert.are.equal("DayOld", sorted[3].preferredName)
      assert.are.equal("Old", sorted[4].preferredName)
      assert.are.equal("Gone", sorted[5].preferredName)
    end)

    it("sorts online descending from most time to least, with online last", function()
      local groups = grouped({
        member({ name = "Old", main = "Old", isMain = true, displayName = "Old" }),
        member({ name = "Live", main = "Live", isMain = true, displayName = "Live" }),
        member({ name = "Recent", main = "Recent", isMain = true, displayName = "Recent" }),
        member({ name = "Gone", main = "Gone", isMain = true, displayName = "Gone" }),
      })
      local roster = {
        live = { online = true },
        recent = { online = false, years = 0, months = 0, days = 0, hours = 2 },
        old = { online = false, years = 0, months = 0, days = 10, hours = 0 },
      }
      local sorted = GTD.SortGroups(groups, "online", false, roster)
      assert.are.equal("Gone", sorted[1].preferredName)
      assert.are.equal("Old", sorted[2].preferredName)
      assert.are.equal("Recent", sorted[3].preferredName)
      assert.are.equal("Live", sorted[4].preferredName)
    end)

    it("matches roster names case-insensitively when sorting by online", function()
      local groups = grouped({
        member({ name = "Live", main = "Live", isMain = true, displayName = "Live" }),
        member({ name = "Old", main = "Old", isMain = true, displayName = "Old" }),
      })
      local roster = {
        live = { online = true },
        old = { online = false, years = 0, months = 0, days = 3, hours = 0 },
      }
      local sorted = GTD.SortGroups(groups, "online", true, roster)
      assert.are.equal("Live", sorted[1].preferredName)
      assert.are.equal("Old", sorted[2].preferredName)
    end)

    it("sorts members within a group by online when sorting by online", function()
      local groups = grouped({
        member({ name = "Main", main = "Main", isMain = true, displayName = "Chief", level = 70 }),
        member({ name = "Alt", main = "Main", level = 60 }),
      })
      local roster = {
        main = { online = false, years = 0, months = 0, days = 5, hours = 0 },
        alt = { online = true },
      }
      local sorted = GTD.SortGroups(groups, "online", true, roster)
      assert.are.equal("Alt", sorted[1].members[1].name)
      assert.are.equal("Main", sorted[1].members[2].name)
    end)

    it("ties break by preferred name ascending even when online sort is descending", function()
      local groups = grouped({
        member({ name = "B", main = "B", isMain = true, displayName = "B" }),
        member({ name = "A", main = "A", isMain = true, displayName = "A" }),
      })
      local roster = {
        a = { online = true },
        b = { online = true },
      }
      local sorted = GTD.SortGroups(groups, "online", false, roster)
      assert.are.equal("A", sorted[1].preferredName)
      assert.are.equal("B", sorted[2].preferredName)
    end)

    it("does not mutate the input list", function()
      local groups = grouped({
        member({ name = "Zed", main = "Zed", isMain = true, displayName = "Zed" }),
        member({ name = "Amy", main = "Amy", isMain = true, displayName = "Amy" }),
      })
      local first = groups[1].preferredName
      GTD.SortGroups(groups, "name", true)
      assert.are.equal(first, groups[1].preferredName)
    end)

    it("sorts pinned groups before unpinned while preserving name order within each bucket", function()
      local groups = grouped({
        member({ name = "Zed", main = "Zed", isMain = true, displayName = "Zed" }),
        member({ name = "Amy", main = "Amy", isMain = true, displayName = "Amy" }),
        member({ name = "Bob", main = "Bob", isMain = true, displayName = "Bob" }),
      })
      -- GroupMembersByMain orders Amy, Bob, Zed; pin Bob and Zed.
      groups[2].pinned = true
      groups[3].pinned = true
      local sorted = GTD.SortGroups(groups, "name", true)
      assert.are.equal("Bob", sorted[1].preferredName)
      assert.are.equal("Zed", sorted[2].preferredName)
      assert.are.equal("Amy", sorted[3].preferredName)
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

  describe("FormatNoProfessionRecipesMessage", function()
    it("embeds the class-colored character name", function()
      local m = member({ name = "Bob", classFile = "MAGE" })
      assert.are.equal(
        "No recipes known for Bob",
        GTD.FormatNoProfessionRecipesMessage(m, plainFormatName))
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

  describe("CollectGuildsOnRealm", function()
    it("returns sorted unique guild names for characters on that realm only", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm == "R1" then
            return {
              A = { guildName = "Zeta Guild" },
              B = { guildName = "Alpha Guild" },
            }
          end
          if realm == "R2" then
            return {
              C = { guildName = "Other Realm Guild" },
              D = { guildName = nil },
            }
          end
          return {}
        end,
      }
      assert.are.same({ "Alpha Guild", "Zeta Guild" }, GTD.CollectGuildsOnRealm("R1"))
      assert.are.same({ "Other Realm Guild" }, GTD.CollectGuildsOnRealm("R2"))
      assert.are.same({}, GTD.CollectGuildsOnRealm("Missing"))
      assert.are.same({}, GTD.CollectGuildsOnRealm(nil))
      AltArmy.DataStore = savedDS
    end)
  end)

  describe("ShouldShowGuildTab", function()
    it("requires the guildShare feature flag and at least one guilded character", function()
      assert.is_false(GTD.ShouldShowGuildTab(false, true))
      assert.is_false(GTD.ShouldShowGuildTab(true, false))
      assert.is_false(GTD.ShouldShowGuildTab(false, false))
      assert.is_true(GTD.ShouldShowGuildTab(true, true))
    end)
  end)

  describe("HasGuildedCharactersOnRealm", function()
    it("is true only when a character on that realm has a guild", function()
      local savedDS = AltArmy.DataStore
      AltArmy.DataStore = {
        GetCharacters = function(_, realm)
          if realm == "Current" then
            return { Unguilded = { guildName = nil } }
          end
          if realm == "Other" then
            return { Guilded = { guildName = "Other Guild" } }
          end
          return {}
        end,
      }
      assert.is_false(GTD.HasGuildedCharactersOnRealm("Current"))
      assert.is_true(GTD.HasGuildedCharactersOnRealm("Other"))
      assert.is_false(GTD.HasGuildedCharactersOnRealm(nil))
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

  describe("AreRecipeListsEqual", function()
    it("returns true for the same table reference", function()
      local recipes = { { recipeID = 1 } }
      assert.is_true(GTD.AreRecipeListsEqual(recipes, recipes))
    end)

    it("returns true when ordered recipeIDs match despite different table references", function()
      local a = { { recipeID = 10, resultItemID = 1 }, { recipeID = 20 } }
      local b = { { recipeID = 10, resultItemID = 99 }, { recipeID = 20, name = "x" } }
      assert.is_true(GTD.AreRecipeListsEqual(a, b))
    end)

    it("treats numeric-string recipeIDs as equal to numbers", function()
      assert.is_true(GTD.AreRecipeListsEqual(
        { { recipeID = 42 } },
        { { recipeID = "42" } }
      ))
    end)

    it("returns false when lengths differ", function()
      assert.is_false(GTD.AreRecipeListsEqual(
        { { recipeID = 1 } },
        { { recipeID = 1 }, { recipeID = 2 } }
      ))
    end)

    it("returns false when order differs", function()
      assert.is_false(GTD.AreRecipeListsEqual(
        { { recipeID = 1 }, { recipeID = 2 } },
        { { recipeID = 2 }, { recipeID = 1 } }
      ))
    end)

    it("returns false when a recipeID differs", function()
      assert.is_false(GTD.AreRecipeListsEqual(
        { { recipeID = 1 } },
        { { recipeID = 2 } }
      ))
    end)

    it("returns false for nil or non-table inputs", function()
      assert.is_false(GTD.AreRecipeListsEqual(nil, {}))
      assert.is_false(GTD.AreRecipeListsEqual({}, nil))
      assert.is_false(GTD.AreRecipeListsEqual("x", {}))
    end)

    it("returns true for two empty lists", function()
      assert.is_true(GTD.AreRecipeListsEqual({}, {}))
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

  describe("EnrichRecipeEntry", function()
    local savedRCL

    before_each(function()
      savedRCL = AltArmy.RecipeCraftLib
    end)

    after_each(function()
      AltArmy.RecipeCraftLib = savedRCL
    end)

    it("surfaces CraftLib-backfilled resultItemID for guild recipe rows", function()
      AltArmy.RecipeCraftLib = {
        EnrichEntry = function(entry)
          if not entry.resultItemID then
            entry.resultItemID = 6370
          end
        end,
      }
      local enriched = GTD.EnrichRecipeEntry({ recipeID = 7837 }, "Alchemy", 300)
      assert.are.equal(7837, enriched.recipeID)
      assert.are.equal(6370, enriched.resultItemID)
      assert.are.equal("Alchemy", enriched.professionName)
      assert.are.equal(300, enriched.skillRank)
    end)

    it("preserves an existing resultItemID", function()
      AltArmy.RecipeCraftLib = {
        EnrichEntry = function(entry)
          if not entry.resultItemID then
            entry.resultItemID = 6370
          end
        end,
      }
      local enriched = GTD.EnrichRecipeEntry(
        { recipeID = 7837, resultItemID = 9999 },
        "Alchemy",
        300
      )
      assert.are.equal(9999, enriched.resultItemID)
    end)
  end)

  describe("ResolveRecipeDisplay", function()
    local savedGetItemInfo
    local savedGetItemIcon
    local savedGetItemInfoInstant
    local savedGetSpellInfo

    before_each(function()
      savedGetItemInfo = _G.GetItemInfo
      savedGetItemIcon = _G.GetItemIcon
      savedGetItemInfoInstant = _G.GetItemInfoInstant
      savedGetSpellInfo = _G.GetSpellInfo
      _G.GetItemInfo = nil
      _G.GetItemIcon = nil
      _G.GetItemInfoInstant = nil
      _G.GetSpellInfo = nil
    end)

    after_each(function()
      _G.GetItemInfo = savedGetItemInfo
      _G.GetItemIcon = savedGetItemIcon
      _G.GetItemInfoInstant = savedGetItemInfoInstant
      _G.GetSpellInfo = savedGetSpellInfo
    end)

    it("uses GetItemIcon for result item when GetItemInfo has not cached yet", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemInfo = function()
        return nil
      end
      _G.GetItemIcon = function(id)
        if id == 4306 then return 132905 end
      end
      local name, icon = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal(132905, icon)
    end)

    it("falls back to GetItemInfoInstant icon when GetItemIcon is absent", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemInfo = function() return nil end
      _G.GetItemInfoInstant = function(id)
        if id == 4306 then
          return 4306, "Tradeskill", "Cloth", "", 132905, 7, 5
        end
      end
      local name, icon = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal(132905, icon)
    end)

    it("uses GetItemInfo icon when the item is already cached", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemInfo = function(id)
        if id == 4306 then
          return "Silk Cloth", nil, nil, nil, nil, nil, nil, nil, nil, "Interface\\Icons\\INV_Fabric_Silk_01"
        end
      end
      local name, icon = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal("Interface\\Icons\\INV_Fabric_Silk_01", icon)
    end)

    it("falls back to spell icon when no result item is known", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk", nil, "Interface\\Icons\\Spell_Nature_Dryad" end
      end
      local name, icon = GTD.ResolveRecipeDisplay(100, nil)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal("Interface\\Icons\\Spell_Nature_Dryad", icon)
    end)

    it("returns question-mark icon when nothing resolves", function()
      local name, icon = GTD.ResolveRecipeDisplay(999, 888)
      assert.are.equal("Recipe 999", name)
      assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", icon)
    end)

    it("reports whether an unresolved item id should be watched for cache arrival", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemInfo = function() return nil end
      local name, icon, pendingItemID = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal("Bolt of Silk", name)
      assert.are.equal("Interface\\Icons\\INV_Misc_QuestionMark", icon)
      assert.are.equal(4306, pendingItemID)
    end)

    it("does not mark pending when an instant icon is already available", function()
      _G.GetSpellInfo = function(id)
        if id == 100 then return "Bolt of Silk" end
      end
      _G.GetItemIcon = function(id)
        if id == 4306 then return 132905 end
      end
      local _, icon, pendingItemID = GTD.ResolveRecipeDisplay(100, 4306)
      assert.are.equal(132905, icon)
      assert.is_nil(pendingItemID)
    end)
  end)

  describe("GetDefaultRecipeSort", function()
    it("defaults to name ascending when CraftLib is unavailable", function()
      local sortKey, ascending = GTD.GetDefaultRecipeSort(false)
      assert.are.equal("recipe", sortKey)
      assert.is_true(ascending)
    end)

    it("defaults to required skill descending when CraftLib is available", function()
      local sortKey, ascending = GTD.GetDefaultRecipeSort(true)
      assert.are.equal("skill", sortKey)
      assert.is_false(ascending)
    end)
  end)

  describe("GetDefaultListSort", function()
    it("defaults to online ascending when roster last-online can be looked up", function()
      local sortKey, ascending = GTD.GetDefaultListSort(true)
      assert.are.equal("online", sortKey)
      assert.is_true(ascending)
    end)

    it("defaults to name ascending when roster last-online cannot be looked up", function()
      local sortKey, ascending = GTD.GetDefaultListSort(false)
      assert.are.equal("name", sortKey)
      assert.is_true(ascending)
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

    it("sorts by required skill descending with name tiebreaker", function()
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
      local out = GTD.SortRecipes(recipes, "skill", false, {
        professionName = "Tailoring",
        skillRank = 375,
        getRecipeName = nameOf,
      })
      assert.are.equal(3, out[1].recipeID)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal(2, out[3].recipeID)
    end)

    it("treats missing required skill as 0 when sorting by skill", function()
      AltArmy.RecipeCraftLib = {
        EnrichEntry = function(entry)
          if entry.recipeID == 1 then
            entry.recipeSkillRequired = nil
          elseif entry.recipeID == 2 then
            entry.recipeSkillRequired = 100
          elseif entry.recipeID == 3 then
            entry.recipeSkillRequired = 50
          end
        end,
      }
      local three = {
        { recipeID = 1, name = "Unknown" },
        { recipeID = 2, name = "High" },
        { recipeID = 3, name = "Low" },
      }
      local ascending = GTD.SortRecipes(three, "skill", true, {
        professionName = "Alchemy",
        skillRank = 300,
        getRecipeName = nameOf,
      })
      assert.are.equal(1, ascending[1].recipeID)
      assert.are.equal(3, ascending[2].recipeID)
      assert.are.equal(2, ascending[3].recipeID)

      local descending = GTD.SortRecipes(three, "skill", false, {
        professionName = "Alchemy",
        skillRank = 300,
        getRecipeName = nameOf,
      })
      assert.are.equal(2, descending[1].recipeID)
      assert.are.equal(3, descending[2].recipeID)
      assert.are.equal(1, descending[3].recipeID)
    end)
  end)

  describe("explicit main star", function()
    setup(function()
      _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
        MAGE = { r = 0.41, g = 0.8, b = 0.94 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
      }
      package.loaded["ClassColor"] = nil
      package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
      require("ClassColor")
    end)

    it("IsExplicitMain is true only for declared mains", function()
      assert.is_true(GTD.IsExplicitMain(member({ name = "Main", isMain = true, mainDeclared = true })))
      assert.is_false(GTD.IsExplicitMain(member({ name = "Main", isMain = true, mainDeclared = false })))
      assert.is_false(GTD.IsExplicitMain(member({ name = "Alt", isMain = false, mainDeclared = true })))
      assert.is_false(GTD.IsExplicitMain(nil))
    end)

    it("FormatMainStarTooltip uses your for own characters", function()
      local text = GTD.FormatMainStarTooltip("Alice", "MAGE", true)
      assert.truthy(text:find("|cff"))
      assert.truthy(text:find("Alice"))
      assert.truthy(text:find(" is your main character$"))
    end)

    it("FormatMainStarTooltip uses their for other players' characters", function()
      local text = GTD.FormatMainStarTooltip("Bob", "WARRIOR", false)
      assert.truthy(text:find("Bob"))
      assert.truthy(text:find(" is their main character$"))
    end)

    it("PresentMainStarTooltip shows title and gray Click to configure hint", function()
      local lines = {}
      local owner = {}
      _G.GameTooltip = {
        SetOwner = function() end,
        ClearLines = function() end,
        AddLine = function(_, text, r, g, b)
          lines[#lines + 1] = { text = text, r = r, g = g, b = b }
        end,
        Show = function() end,
      }
      assert.is_true(GTD.PresentMainStarTooltip(owner, "ANCHOR_BOTTOMLEFT", {
        name = "Alice",
        classFile = "MAGE",
        isOwn = true,
        showConfigureHint = true,
      }))
      assert.truthy(lines[1].text:find("Alice"))
      assert.truthy(lines[1].text:find(" is your main character"))
      assert.are.equal(1, lines[1].r)
      assert.are.equal("Click to configure", lines[2].text)
      assert.are.equal(0.5, lines[2].r)
      assert.are.equal(0.5, lines[2].g)
      assert.are.equal(0.5, lines[2].b)
    end)

    it("PresentMainStarTooltip omits configure hint when not requested", function()
      local lines = {}
      _G.GameTooltip = {
        SetOwner = function() end,
        ClearLines = function() end,
        AddLine = function(_, text)
          lines[#lines + 1] = text
        end,
        Show = function() end,
      }
      assert.is_true(GTD.PresentMainStarTooltip({}, "ANCHOR_BOTTOMLEFT", {
        name = "Bob",
        classFile = "WARRIOR",
        isOwn = false,
      }))
      assert.are.equal(1, #lines)
      assert.truthy(lines[1]:find(" is their main character"))
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
