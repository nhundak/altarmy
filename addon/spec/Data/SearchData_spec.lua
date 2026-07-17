--[[
  Unit tests for SearchData.lua (location, match score, search/aggregation).
  Run from project root: npm test
]]

describe("SearchData", function()
  local SD

  setup(function()
    _G.AltArmy = _G.AltArmy or {}
    _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
    _G.CreateFrame = _G.CreateFrame or function()
      return { SetScript = function() end, RegisterEvent = function() end }
    end
    _G.UIParent = _G.UIParent or {}
    package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
    require("DataStore")
    require("DataStoreProfessions")
    require("RecipeCraftLib")
    require("SearchSettings")
    require("SearchData")
    SD = AltArmy.SearchData
  end)

  before_each(function()
    _G.AltArmyTBC_Data.recipePrimaryIdsMigrated = nil
    if AltArmy.DataStore then
      AltArmy.DataStore.accountData = _G.AltArmyTBC_Data
    end
    if SD and SD.ClearSearchCaches then
      SD.ClearSearchCaches()
    elseif SD and SD.ClearSearchableTextCache then
      SD.ClearSearchableTextCache()
    end
  end)

  describe("GetAllContainerSlots (mail)", function()
    it("includes mail attachment items as location=mail", function()
      local DS = AltArmy.DataStore
      assert.truthy(DS)
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        ScanCurrentCharacterBags = DS.ScanCurrentCharacterBags,
      }

      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return {
          Alice = {
            name = "Alice",
            Mails = { { itemID = 111, count = 2, link = "item:111" } },
            MailCache = { { itemID = 222, count = 3, link = "item:222" } },
          },
        }
      end
      DS.IterateContainerSlots = function(_self, _char, cb)
        -- One bag item so we can verify mail + bag both exist
        cb(0, 1, 999, 1, "item:999")
      end
      DS.GetCharacterName = function(_self, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARRIOR" end
      DS.ScanCurrentCharacterBags = function() end

      local list = SD.GetAllContainerSlots()

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.IterateContainerSlots = old.IterateContainerSlots
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass
      DS.ScanCurrentCharacterBags = old.ScanCurrentCharacterBags

      local seenBag, seenMail111, seenMail222 = false, false, false
      for _, e in ipairs(list) do
        if e.itemID == 999 and e.location == "bag" then seenBag = true end
        if e.itemID == 111 and e.location == "mail" and e.count == 2 then seenMail111 = true end
        if e.itemID == 222 and e.location == "mail" and e.count == 3 then seenMail222 = true end
      end
      assert.is_true(seenBag)
      assert.is_true(seenMail111)
      assert.is_true(seenMail222)
    end)

    it("includes equipped items as location=equipped", function()
      local DS = AltArmy.DataStore
      assert.truthy(DS)
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        IterateInventory = DS.IterateInventory,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
      }

      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return { Alice = { name = "Alice" } }
      end
      DS.IterateContainerSlots = function(_self, _char, _cb) end
      DS.IterateInventory = function(_self, _char, cb)
        cb(1, 333)
        cb(2, "item:444:0:0:0:0:0:0:0:0:0:0:0:0")
      end
      DS.GetCharacterName = function(_self, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARRIOR" end

      local list = SD.GetAllContainerSlots()

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.IterateContainerSlots = old.IterateContainerSlots
      DS.IterateInventory = old.IterateInventory
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass

      local seenNumeric, seenEnchanted = false, false
      for _, e in ipairs(list) do
        if e.itemID == 333 and e.location == "equipped" and e.count == 1 and e.slot == 1 then
          seenNumeric = true
        end
        if e.itemID == 444 and e.location == "equipped" and e.count == 1 and e.slot == 2
            and e.itemLink == "item:444:0:0:0:0:0:0:0:0:0:0:0:0" then
          seenEnchanted = true
        end
      end
      assert.is_true(seenNumeric)
      assert.is_true(seenEnchanted)
    end)
  end)

  describe("search caches", function()
    it("caches container slot list until invalidated", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
      }

      local iterateCalls = 0
      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return { Alice = { name = "Alice" } }
      end
      DS.IterateContainerSlots = function(_self, _char, cb)
        iterateCalls = iterateCalls + 1
        cb(0, 1, 999, 1, "item:999")
      end
      DS.GetCharacterName = function(_self, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARRIOR" end

      local first = SD.GetAllContainerSlots()
      local second = SD.GetAllContainerSlots()
      assert.are.equal(1, iterateCalls)
      assert.are.equal(#first, #second)

      SD.InvalidateContainerSlotsCache()
      local third = SD.GetAllContainerSlots()
      assert.are.equal(2, iterateCalls)
      assert.are.equal(#first, #third)

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.IterateContainerSlots = old.IterateContainerSlots
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass
    end)

    it("does not scan current character bags while building container cache", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        ScanCurrentCharacterBags = DS.ScanCurrentCharacterBags,
      }

      local scanned = false
      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return { Alice = { name = "Alice" } }
      end
      DS.IterateContainerSlots = function(_self, _char, cb)
        cb(0, 1, 999, 1, "item:999")
      end
      DS.GetCharacterName = function(_self, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARRIOR" end
      DS.ScanCurrentCharacterBags = function()
        scanned = true
      end

      SD.InvalidateContainerSlotsCache()
      SD.GetAllContainerSlots()
      assert.is_false(scanned)

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.IterateContainerSlots = old.IterateContainerSlots
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass
      DS.ScanCurrentCharacterBags = old.ScanCurrentCharacterBags
    end)

    it("caches recipe list until invalidated", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        GetProfessions = DS.GetProfessions,
      }

      local getProfessionsCalls = 0
      DS.GetRealms = function() return { Realm1 = true } end
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = { rank = 300, Recipes = { [12345] = 1 } },
            },
          },
        }
      end
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "WARLOCK" end
      DS.GetProfessions = function(_, char)
        getProfessionsCalls = getProfessionsCalls + 1
        return char and char.Professions or {}
      end

      local first = SD.GetAllRecipes()
      local second = SD.GetAllRecipes()
      assert.are.equal(1, getProfessionsCalls)
      assert.are.equal(#first, #second)

      SD.InvalidateRecipesCache()
      local third = SD.GetAllRecipes()
      assert.are.equal(2, getProfessionsCalls)
      assert.are.equal(#first, #third)

      DS.GetRealms = old.GetRealms
      DS.GetCharacters = old.GetCharacters
      DS.GetCharacterName = old.GetCharacterName
      DS.GetCharacterClass = old.GetCharacterClass
      DS.GetProfessions = old.GetProfessions
    end)

    it("does not re-fetch recipe names during sort comparator", function()
      local oldGetAll = SD.GetAllRecipes
      local oldGetSpellInfo = _G.GetSpellInfo
      local oldGetItemInfo = _G.GetItemInfo

      SD.GetAllRecipes = function()
        return {
          { characterName = "B", realm = "R", professionName = "Alchemy", skillRank = 300, recipeID = 111 },
          { characterName = "A", realm = "R", professionName = "Alchemy", skillRank = 280, recipeID = 111 },
          { characterName = "C", realm = "R", professionName = "Alchemy", skillRank = 260, recipeID = 222 },
        }
      end

      local spellCalls = 0
      _G.GetSpellInfo = function(id)
        spellCalls = spellCalls + 1
        if id == 111 then return "Minor Potion" end
        if id == 222 then return "Major Potion" end
        return nil
      end
      _G.GetItemInfo = function() return nil end

      local results = SD.SearchRecipes("potion")
      assert.are.equal(3, #results)
      assert.are.equal(2, spellCalls)

      local resultsAgain = SD.SearchRecipes("potion")
      assert.are.equal(3, #resultsAgain)
      assert.are.equal(2, spellCalls)

      SD.GetAllRecipes = oldGetAll
      _G.GetSpellInfo = oldGetSpellInfo
      _G.GetItemInfo = oldGetItemInfo
    end)
  end)

  describe("_LocationSortKey", function()
    it("orders bag before keyring before bank before equipped before mail", function()
      assert.is_true(SD._LocationSortKey("bag") < SD._LocationSortKey("keyring"))
      assert.is_true(SD._LocationSortKey("keyring") < SD._LocationSortKey("bank"))
      assert.is_true(SD._LocationSortKey("bank") < SD._LocationSortKey("equipped"))
      assert.is_true(SD._LocationSortKey("equipped") < SD._LocationSortKey("mail"))
    end)
  end)

  describe("_LocationFromBagID", function()
    it("returns bag for 0-4", function()
      assert.are.equal(SD._LocationFromBagID(0), "bag")
      assert.are.equal(SD._LocationFromBagID(1), "bag")
      assert.are.equal(SD._LocationFromBagID(4), "bag")
    end)
    it("returns bank for -1", function()
      assert.are.equal(SD._LocationFromBagID(-1), "bank")
    end)
    it("returns bank for 5-11", function()
      assert.are.equal(SD._LocationFromBagID(5), "bank")
      assert.are.equal(SD._LocationFromBagID(11), "bank")
    end)
    it("returns keyring for -2", function()
      assert.are.equal(SD._LocationFromBagID(-2), "keyring")
    end)
  end)

  describe("_GetNameMatchScore", function()
    it("returns 0 for nil or empty", function()
      assert.are.equal(SD._GetNameMatchScore(nil, "x"), 0)
      assert.are.equal(SD._GetNameMatchScore("Foo", ""), 0)
      assert.are.equal(SD._GetNameMatchScore("Foo", nil), 0)
    end)
    it("returns 3 for exact match", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "foo bar"), 3)
    end)
    it("returns 2 for prefix match", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "foo"), 2)
    end)
    it("returns 1 for contains", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "bar"), 1)
    end)
    it("returns 0 when no match", function()
      assert.are.equal(SD._GetNameMatchScore("Foo Bar", "baz"), 0)
    end)
  end)

  describe("Search", function()
    it("returns empty for nil query", function()
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return {} end
      assert.are.same(SD.Search(nil), {})
      SD.GetAllContainerSlots = old
    end)
    it("returns empty for whitespace-only query", function()
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return {} end
      assert.are.same(SD.Search("   "), {})
      SD.GetAllContainerSlots = old
    end)
    it("matches by itemID when query is number", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 12345, itemLink = nil, count = 1, location = "bag" },
        { characterName = "B", realm = "R", itemID = 99999, itemLink = nil, count = 1, location = "bag" },
      }
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return list end
      local results = SD.Search(12345)
      SD.GetAllContainerSlots = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].itemID, 12345)
    end)
    it("matches by itemID when query is string digits", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 12345, itemLink = nil, count = 1, location = "bag" },
      }
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return list end
      local results = SD.Search("12345")
      SD.GetAllContainerSlots = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].itemID, 12345)
    end)
    it("returns non-nil second value (tooltipOnly list)", function()
      local old = SD.GetAllContainerSlots
      SD.GetAllContainerSlots = function() return {} end
      local _, tooltipOnly = SD.Search("anything")
      SD.GetAllContainerSlots = old
      assert.is_not_nil(tooltipOnly)
    end)
    it("puts tooltip-only matches into second result, not first", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 11111, itemLink = nil, count = 1, location = "bag" },
      }
      local oldSlots = SD.GetAllContainerSlots
      local oldGetSearchable = SD._GetSearchableTextForItem
      SD.GetAllContainerSlots = function() return list end
      SD._GetSearchableTextForItem = function(itemID, _)
        if itemID == 11111 then return "mote of fire primal fire" end
        return nil
      end
      local main, tooltipOnly = SD.Search("primal")
      SD.GetAllContainerSlots = oldSlots
      SD._GetSearchableTextForItem = oldGetSearchable
      assert.are.equal(#main, 0)
      assert.are.equal(#tooltipOnly, 1)
      assert.are.equal(tooltipOnly[1].itemID, 11111)
    end)
    it("keeps name-matched entries in main result only", function()
      local list = {
        { characterName = "A", realm = "R", itemID = 22222, itemLink = nil, count = 1, location = "bag" },
      }
      local oldSlots = SD.GetAllContainerSlots
      local oldGetItemInfo = _G.GetItemInfo
      SD.GetAllContainerSlots = function() return list end
      _G.GetItemInfo = function(id)
        if id == 22222 then return "Primal Fire" end
        return nil
      end
      local main, tooltipOnly = SD.Search("primal")
      SD.GetAllContainerSlots = oldSlots
      _G.GetItemInfo = oldGetItemInfo
      assert.are.equal(#main, 1)
      assert.are.equal(#tooltipOnly, 0)
      assert.are.equal(main[1].itemID, 22222)
    end)
  end)

  describe("ClearSearchableTextCache", function()
    it("exists and does not error", function()
      assert.is_function(SD.ClearSearchableTextCache)
      assert.has_no.errors(function()
        SD.ClearSearchableTextCache()
      end)
    end)
  end)

  describe("SearchGroupedByCharacter", function()
    it("aggregates count by character", function()
      local old = SD.Search
      SD.Search = function()
        return {
          { characterName = "A", realm = "R", itemID = 100, count = 2 },
          { characterName = "A", realm = "R", itemID = 100, count = 3 },
        }, {}
      end
      local results = SD.SearchGroupedByCharacter("x")
      SD.Search = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].count, 5)
    end)
  end)

  describe("SearchWithLocationGroups", function()
    it("returns empty tables for nil query", function()
      local main, tooltipOnly = SD.SearchWithLocationGroups(nil)
      assert.are.same(main, {})
      assert.are.same(tooltipOnly, {})
    end)
    it("returns two non-nil values", function()
      local old = SD.Search
      SD.Search = function() return {}, {} end
      local main, tooltipOnly = SD.SearchWithLocationGroups("foo")
      SD.Search = old
      assert.is_not_nil(main)
      assert.is_not_nil(tooltipOnly)
    end)
    it("aggregates by itemID, character, realm, location", function()
      local old = SD.Search
      SD.Search = function()
        return {
          { itemID = 100, itemLink = "x", itemName = "Foo", characterName = "A", realm = "R",
            location = "bag", count = 2, classFile = "" },
          { itemID = 100, itemLink = "x", itemName = "Foo", characterName = "A", realm = "R",
            location = "bag", count = 3, classFile = "" },
        }, {}
      end
      local results, _ = SD.SearchWithLocationGroups("foo")
      SD.Search = old
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].count, 5)
    end)
    it("routes tooltip-only entries into second return", function()
      local old = SD.Search
      SD.Search = function()
        return {}, {
          { itemID = 300, itemLink = "link", itemName = "Mote of Fire", characterName = "A", realm = "R",
            location = "bag", count = 1, classFile = "" },
        }
      end
      local _, tooltipOnly = SD.SearchWithLocationGroups("primal")
      SD.Search = old
      assert.are.equal(#tooltipOnly, 1)
      assert.are.equal(tooltipOnly[1].itemID, 300)
    end)
  end)

  describe("GetAllRecipes", function()
    it("returns empty when DS or GetProfessions missing", function()
      local DS = AltArmy.DataStore
      local oldGetProfessions = DS and DS.GetProfessions
      if DS then DS.GetProfessions = nil end
      local oldGetRealms = DS and DS.GetRealms
      if DS then DS.GetRealms = function() return {} end end
      assert.are.same(SD.GetAllRecipes(), {})
      if DS and oldGetProfessions then DS.GetProfessions = oldGetProfessions end
      if DS and oldGetRealms then DS.GetRealms = oldGetRealms end
    end)
    it("returns flat list of recipe entries per character profession", function()
      local DS = AltArmy.DataStore
      local oldGetRealms = DS.GetRealms
      local oldGetCharacters = DS.GetCharacters
      local oldGetCharacterName = DS.GetCharacterName
      local oldGetCharacterClass = DS.GetCharacterClass
      local oldGetProfessions = DS.GetProfessions
      DS.GetRealms = function() return { Realm1 = true } end
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = { rank = 300, maxRank = 375, Recipes = { [12345] = 1, [67890] = 2 } },
            },
          },
        }
      end
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function(_, char)
        return char and char.class or "", char and char.classFile or "WARLOCK"
      end
      DS.GetProfessions = function(_, char) return char and char.Professions or {} end
      local results = SD.GetAllRecipes()
      DS.GetRealms = oldGetRealms
      DS.GetCharacters = oldGetCharacters
      DS.GetCharacterName = oldGetCharacterName
      DS.GetCharacterClass = oldGetCharacterClass
      DS.GetProfessions = oldGetProfessions
      assert.are.equal(#results, 2)
      table.sort(results, function(a, b) return (a.recipeID or 0) < (b.recipeID or 0) end)
      assert.are.equal(results[1].characterName, "Char1")
      assert.are.equal(results[1].realm, "Realm1")
      assert.are.equal(results[1].professionName, "Alchemy")
      assert.are.equal(results[1].skillRank, 300)
      assert.are.equal(results[1].recipeID, 12345)
      assert.are.equal(results[2].recipeID, 67890)
    end)
    it("excludes alias recipe ids (e.g. crafted item use spell)", function()
      local DS = AltArmy.DataStore
      local oldGetRealms = DS.GetRealms
      local oldGetCharacters = DS.GetCharacters
      local oldGetCharacterName = DS.GetCharacterName
      local oldGetCharacterClass = DS.GetCharacterClass
      local oldGetProfessions = DS.GetProfessions
      local oldGetItemSpell = _G.GetItemSpell
      local row = { color = 1, resultItemID = 9187, primaryRecipeID = 11449 }
      DS.GetRealms = function() return { Realm1 = true } end
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = {
                rank = 300,
                Recipes = {
                  [11449] = row,
                  [11334] = row, -- Agility buff spell alias
                },
              },
            },
          },
        }
      end
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function(_, char)
        return char and char.class or "", char and char.classFile or "MAGE"
      end
      DS.GetProfessions = function(_, char) return char and char.Professions or {} end
      _G.GetItemSpell = function(itemID)
        if itemID == 9187 then return "Agility", 11334 end
        return nil
      end
      AltArmy.DataStore:MigrateRecipePrimaryIds()
      local results = SD.GetAllRecipes()
      DS.GetRealms = oldGetRealms
      DS.GetCharacters = oldGetCharacters
      DS.GetCharacterName = oldGetCharacterName
      DS.GetCharacterClass = oldGetCharacterClass
      DS.GetProfessions = oldGetProfessions
      _G.GetItemSpell = oldGetItemSpell
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].recipeID, 11449)
    end)
  end)

  describe("GetAllGuildRecipes", function()
    local DS, restore

    before_each(function()
      DS = AltArmy.DataStore
      require("Debug")
      require("GuildShareProtocol")
      require("GuildShareData")
      restore = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        GetProfessions = DS.GetProfessions,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        ForEachCharacter = DS.ForEachCharacter,
        GetCurrentPlayerRealm = DS.GetCurrentPlayerRealm,
      }
      -- No local profession data; guild-toggle eligibility still needs a guilded char on realm.
      DS.GetRealms = function() return { R = true } end
      DS.GetCharacters = function(_, realm)
        if realm == "R" then
          return { Local = { guildName = "G" } }
        end
        return {}
      end
      DS.GetProfessions = function() return {} end
      DS.GetCharacterName = function(_, c) return c and c.name or "" end
      DS.GetCharacterClass = function() return "", "MAGE" end
      DS.GetCurrentPlayerRealm = function() return "R" end
      _G.AltArmyTBC_GuildData = {
        chars = {
          R = {
            Bob = {
              name = "Bob", realm = "R", classFile = "MAGE", guildName = "G", displayName = "Bobby",
              Professions = {
                tailoring = {
                  key = "tailoring", name = "Tailoring", rank = 375,
                  Recipes = { [100] = { primaryRecipeID = 100 }, [200] = { primaryRecipeID = 200 } },
                },
              },
            },
          },
        },
      }
      AltArmy.SearchSettings.SetIncludeGuildmatesEnabled(true)
      package.loaded["GuildShareSettings"] = nil
      package.loaded["GuildTabData"] = nil
      require("GuildShareSettings")
      require("GuildTabData")
      AltArmy.GuildShareSettings.SetSharingEnabled(true)
      AltArmy.DataStore.ForEachCharacter = function(_, fn)
        fn("R", "Local", { guildName = "G" })
      end
      SD.NotifyRecipesChanged()
    end)

    after_each(function()
      for k, v in pairs(restore) do
        if v ~= nil then DS[k] = v end
      end
      if AltArmy.GuildShareSettings and AltArmy.GuildShareSettings.SetSharingEnabled then
        AltArmy.GuildShareSettings.SetSharingEnabled(false)
      end
      _G.AltArmyTBC_GuildData = nil
      SD.NotifyRecipesChanged()
    end)

    it("keeps GetAllRecipes local-only (no guild rows)", function()
      assert.are.equal(0, #SD.GetAllRecipes())
      local guild = SD.GetAllGuildRecipes()
      assert.are.equal(2, #guild)
      for _, r in ipairs(guild) do
        assert.is_true(r.isGuild)
        assert.are.equal("Bob", r.characterName)
        assert.are.equal("tailoring", r.professionKey)
      end
    end)

    it("excludes guild recipes when the feature flag is off", function()
      local saved = AltArmy.Debug.IsGuildShareEnabled
      AltArmy.Debug.IsGuildShareEnabled = function() return false end
      SD.NotifyRecipesChanged()
      assert.are.equal(0, #SD.GetAllGuildRecipes())
      AltArmy.Debug.IsGuildShareEnabled = saved
    end)

    it("excludes guild recipes when the include-guildmates toggle is off", function()
      assert.are.equal(2, #SD.GetAllGuildRecipes())
      AltArmy.SearchSettings.SetIncludeGuildmatesEnabled(false)
      assert.are.equal(0, #SD.GetAllGuildRecipes())
      AltArmy.SearchSettings.SetIncludeGuildmatesEnabled(true)
      assert.are.equal(2, #SD.GetAllGuildRecipes())
    end)

    it("excludes guild recipes when guild sharing is disabled", function()
      AltArmy.GuildShareSettings.SetSharingEnabled(false)
      SD.NotifyRecipesChanged()
      assert.are.equal(0, #SD.GetAllGuildRecipes())
    end)
  end)

  describe("SearchRecipes", function()
    it("returns empty for nil or whitespace query", function()
      local old = SD.GetAllRecipes
      SD.GetAllRecipes = function() return {} end
      assert.are.same(SD.SearchRecipes(nil), {})
      assert.are.same(SD.SearchRecipes("   "), {})
      SD.GetAllRecipes = old
    end)
    it("filters by recipe name (item or spell)", function()
      local oldGetAll = SD.GetAllRecipes
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      SD.GetAllRecipes = function()
        return {
          { characterName = "A", realm = "R", professionName = "Alchemy", skillRank = 300, recipeID = 111 },
          { characterName = "B", realm = "R", professionName = "Alchemy", skillRank = 250, recipeID = 222 },
        }
      end
      _G.GetItemInfo = function(id)
        if id == 111 then return "Minor Healing Potion", nil, nil, nil, nil, nil, nil, nil, nil, "icon1" end
        if id == 222 then return "Super Mana Potion", nil, nil, nil, nil, nil, nil, nil, nil, "icon2" end
        return nil
      end
      _G.GetSpellInfo = function() return nil end
      local results = SD.SearchRecipes("mana")
      SD.GetAllRecipes = oldGetAll
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].recipeID, 222)
      assert.are.equal(results[1].characterName, "B")
    end)

    it("lists own characters before guildmates when FilterAndSortRecipes merges both", function()
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetItemInfo = function(id)
        if id == 111 then return "Minor Healing Potion", nil, nil, nil, nil, nil, nil, nil, nil, "icon1" end
        if id == 222 then return "Super Mana Potion", nil, nil, nil, nil, nil, nil, nil, nil, "icon2" end
        return nil
      end
      _G.GetSpellInfo = function() return nil end
      local results = SD._FilterAndSortRecipes({
        {
          characterName = "Zebra",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 300,
          recipeID = 111,
          isGuild = true,
        },
        {
          characterName = "Alice",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 250,
          recipeID = 111,
          isGuild = true,
        },
        {
          characterName = "MageAlt",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 375,
          recipeID = 111,
        },
        {
          characterName = "PriestAlt",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 200,
          recipeID = 111,
        },
        {
          characterName = "OtherRecipeOwner",
          realm = "R",
          professionName = "Alchemy",
          skillRank = 100,
          recipeID = 222,
          isGuild = true,
        },
      }, "potion")
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      assert.are.equal(5, #results)
      -- Same recipe: own chars (alpha by name), then guildmates (alpha by name).
      assert.are.equal("MageAlt", results[1].characterName)
      assert.is_nil(results[1].isGuild)
      assert.are.equal("PriestAlt", results[2].characterName)
      assert.is_nil(results[2].isGuild)
      assert.are.equal("Alice", results[3].characterName)
      assert.is_true(results[3].isGuild)
      assert.are.equal("Zebra", results[4].characterName)
      assert.is_true(results[4].isGuild)
      -- Different recipe name still sorts after (mana after healing).
      assert.are.equal(222, results[5].recipeID)
      assert.are.equal("OtherRecipeOwner", results[5].characterName)
    end)

    it("SearchRecipes returns only local rows; SearchGuildRecipes returns guild rows", function()
      local oldGetAll = SD.GetAllRecipes
      local oldGetGuild = SD.GetAllGuildRecipes
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      SD.GetAllRecipes = function()
        return {
          { characterName = "Local", realm = "R", professionName = "Alchemy", skillRank = 300, recipeID = 111 },
        }
      end
      SD.GetAllGuildRecipes = function()
        return {
          {
            characterName = "Bob",
            realm = "R",
            professionName = "Alchemy",
            skillRank = 200,
            recipeID = 111,
            isGuild = true,
          },
        }
      end
      _G.GetItemInfo = function(id)
        if id == 111 then return "Minor Healing Potion" end
        return nil
      end
      _G.GetSpellInfo = function() return nil end
      local localResults = SD.SearchRecipes("potion")
      local guildResults = SD.SearchGuildRecipes("potion")
      SD.GetAllRecipes = oldGetAll
      SD.GetAllGuildRecipes = oldGetGuild
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      assert.are.equal(1, #localResults)
      assert.is_nil(localResults[1].isGuild)
      assert.are.equal(1, #guildResults)
      assert.is_true(guildResults[1].isGuild)
    end)

    it("does not return alias effect spells when both match query", function()
      local DS = AltArmy.DataStore
      local oldGetRealms = DS.GetRealms
      local oldGetCharacters = DS.GetCharacters
      local oldGetCharacterName = DS.GetCharacterName
      local oldGetCharacterClass = DS.GetCharacterClass
      local oldGetProfessions = DS.GetProfessions
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      local oldGetItemSpell = _G.GetItemSpell
      local row = { color = 1, resultItemID = 9187, primaryRecipeID = 11449 }
      DS.GetRealms = function() return { Realm1 = true } end
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = {
                rank = 300,
                Recipes = {
                  [11449] = row,
                  [11334] = row,
                },
              },
            },
          },
        }
      end
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function(_, char)
        return char and char.class or "", char and char.classFile or "MAGE"
      end
      DS.GetProfessions = function(_, char) return char and char.Professions or {} end
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11334 then return "Agility" end
        return nil
      end
      _G.GetItemInfo = function() return nil end
      _G.GetItemSpell = function(itemID)
        if itemID == 9187 then return "Agility", 11334 end
        return nil
      end
      AltArmy.DataStore:MigrateRecipePrimaryIds()
      local results = SD.SearchRecipes("agility")
      DS.GetRealms = oldGetRealms
      DS.GetCharacters = oldGetCharacters
      DS.GetCharacterName = oldGetCharacterName
      DS.GetCharacterClass = oldGetCharacterClass
      DS.GetProfessions = oldGetProfessions
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      _G.GetItemSpell = oldGetItemSpell
      assert.are.equal(#results, 1)
      assert.are.equal(results[1].recipeID, 11449)
    end)
    it("excludes split alias rows after remigrate debug", function()
      local DS = AltArmy.DataStore
      local oldGetCharacterName = DS.GetCharacterName
      local oldGetCharacterClass = DS.GetCharacterClass
      local oldGetProfessions = DS.GetProfessions
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      local oldGetItemSpell = _G.GetItemSpell
      DS.accountData = _G.AltArmyTBC_Data
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function(_, char)
        return char and char.class or "", char and char.classFile or "MAGE"
      end
      DS.GetProfessions = function(_, char) return char and char.Professions or {} end
      _G.AltArmyTBC_Data.recipePrimaryIdsMigrated = true
      _G.AltArmyTBC_Data.Characters = {
        Dreamscythe = {
          felfrell = {
            name = "felfrell",
            Professions = {
              Alchemy = {
                rank = 373,
                Recipes = {
                  [11449] = { color = 1, primaryRecipeID = 11449, resultItemID = 8949 },
                  [11328] = { color = 1, primaryRecipeID = 11328, resultItemID = 8949 },
                },
              },
            },
          },
        },
      }
      _G.GetSpellInfo = function(id)
        if id == 11449 then return "Elixir of Agility" end
        if id == 11328 then return "Agility" end
        return nil
      end
      _G.GetItemInfo = function() return nil end
      _G.GetItemSpell = function(itemID)
        if itemID == 8949 then return "Agility", 11328 end
        return nil
      end
      SD.ClearSearchCaches()
      local updated = DS:RemigrateRecipePrimaryIdsDebug()
      assert.is_true(updated > 0)
      local all = SD.GetAllRecipes()
      assert.are.equal(1, #all)
      local results = SD.SearchRecipes("agility")
      DS.GetCharacterName = oldGetCharacterName
      DS.GetCharacterClass = oldGetCharacterClass
      DS.GetProfessions = oldGetProfessions
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      _G.GetItemSpell = oldGetItemSpell
      assert.are.equal(1, #results)
      assert.are.equal(11449, results[1].recipeID)
    end)
  end)

  describe("_FilterRecipesByLevel", function()
    it("keeps rows in range and rows with nil recipeSkillRequired", function()
      _G.CraftLib = { IsReady = function() return true end }
      local rows = {
        { recipeID = 1, recipeSkillRequired = 200 },
        { recipeID = 2, recipeSkillRequired = 260 },
        { recipeID = 3, recipeSkillRequired = nil },
      }
      local filtered = SD._FilterRecipesByLevel(rows, { min = 200, max = 250 })
      _G.CraftLib = nil
      assert.are.equal(2, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
      assert.are.equal(3, filtered[2].recipeID)
    end)

    it("returns all rows when filter is full range 0-375", function()
      local rows = { { recipeID = 1, recipeSkillRequired = 999 } }
      local filtered = SD._FilterRecipesByLevel(rows, { min = 0, max = 375 })
      assert.are.equal(1, #filtered)
    end)
  end)

  describe("_EnrichRecipeEntry", function()
    before_each(function()
      _G.CraftLib = nil
      if AltArmy.RecipeCraftLib and AltArmy.RecipeCraftLib.ClearCaches then
        AltArmy.RecipeCraftLib.ClearCaches()
      end
    end)

    it("adds recipeSkillRequired and difficulty when CraftLib resolves recipe", function()
      _G.GetSpellInfo = function() return "Alchemy" end
      _G.CraftLib = {
        IsReady = function() return true end,
        GetProfessions = function()
          return { alchemy = { id = 1, name = "Alchemy", recipes = {} } }
        end,
        GetRecipeBySpellId = function(_, profKey, spellId)
          if profKey == "alchemy" and spellId == 111 then
            return {
              id = 111,
              skillRequired = 180,
              skillRange = { yellow = 195, green = 210, gray = 225 },
            }
          end
          return nil
        end,
        GetRecipeDifficulty = function(_, recipe, skill)
          if skill < recipe.skillRange.yellow then return "orange" end
          return "gray"
        end,
      }
      local entry = {
        professionName = "Alchemy",
        recipeID = 111,
        skillRank = 300,
      }
      SD._EnrichRecipeEntry(entry)
      assert.are.equal(180, entry.recipeSkillRequired)
      assert.are.equal("gray", entry.difficulty)
    end)
  end)

  describe("_FilterRecipesByDifficulty", function()
    before_each(function()
      _G.CraftLib = { IsReady = function() return true end }
    end)
    after_each(function()
      _G.CraftLib = nil
    end)

    it("keeps rows with enabled difficulty and unknown difficulty", function()
      local rows = {
        { recipeID = 1, difficulty = "orange" },
        { recipeID = 2, difficulty = "gray" },
        { recipeID = 3, difficulty = nil },
      }
      local filtered = SD._FilterRecipesByDifficulty(rows, {
        orange = true, yellow = true, green = true, gray = false,
      })
      assert.are.equal(2, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
      assert.are.equal(3, filtered[2].recipeID)
    end)
  end)

  describe("_FilterRecipesBySource", function()
    before_each(function()
      _G.CraftLib = { IsReady = function() return true end }
    end)
    after_each(function()
      _G.CraftLib = nil
    end)

    it("keeps rows with enabled source and unknown source", function()
      local rows = {
        { recipeID = 1, recipeSource = "trainer" },
        { recipeID = 2, recipeSource = "drop" },
        { recipeID = 3, recipeSource = nil },
      }
      local filtered = SD._FilterRecipesBySource(rows, {
        trainer = true, vendor = true, quest = true,
        drop = false, reputation = true, starter = true,
      })
      assert.are.equal(2, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
      assert.are.equal(3, filtered[2].recipeID)
    end)
  end)

  describe("_FilterRecipesByProfession", function()
    before_each(function()
      _G.AltArmy = _G.AltArmy or {}
      package.loaded["SearchSettings"] = nil
      require("SearchSettings")
      AltArmy.SearchSettings._ClearProfessionKeyCache()
      _G.GetSpellInfo = function(spellId)
        if spellId == 2259 then return "Alchemy" end
        if spellId == 3908 then return "Tailoring" end
        return nil
      end
    end)
    after_each(function()
      _G.GetSpellInfo = nil
    end)

    it("keeps rows with enabled professions and unknown professions", function()
      local rows = {
        { recipeID = 1, professionName = "Alchemy" },
        { recipeID = 2, professionName = "Tailoring" },
        { recipeID = 3, professionName = "Unknown" },
      }
      local filtered = SD._FilterRecipesByProfession(rows, {
        alchemy = true,
        blacksmithing = true,
        cooking = true,
        enchanting = true,
        engineering = true,
        firstAid = true,
        jewelcrafting = true,
        leatherworking = true,
        mining = true,
        poisons = true,
        tailoring = false,
      })
      assert.are.equal(2, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
      assert.are.equal(3, filtered[2].recipeID)
    end)
  end)

  describe("_ApplyRecipeSearchFilters", function()
    before_each(function()
      _G.CraftLib = { IsReady = function() return true end }
    end)
    after_each(function()
      _G.CraftLib = nil
    end)

    it("applies difficulty and source filters together", function()
      local rows = {
        { recipeID = 1, difficulty = "orange", recipeSource = "trainer" },
        { recipeID = 2, difficulty = "gray", recipeSource = "trainer" },
        { recipeID = 3, difficulty = "orange", recipeSource = "drop" },
      }
      local filtered = SD._ApplyRecipeSearchFilters(rows, {
        recipeLevelFilter = { min = 0, max = 375 },
        professionFilter = {
          alchemy = true, blacksmithing = true, cooking = true, enchanting = true,
          engineering = true, firstAid = true, jewelcrafting = true, leatherworking = true,
          mining = true, poisons = true, tailoring = true,
        },
        difficultyFilter = { orange = true, yellow = true, green = true, gray = false },
        sourceFilter = {
          trainer = true, vendor = true, quest = true,
          drop = false, reputation = true, starter = true,
        },
      })
      assert.are.equal(1, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
    end)

    it("applies profession filter without CraftLib", function()
      _G.CraftLib = nil
      local rows = {
        { recipeID = 1, professionName = "Alchemy" },
        { recipeID = 2, professionName = "Tailoring" },
      }
      local filtered = SD._ApplyRecipeSearchFilters(rows, {
        professionFilter = {
          alchemy = true,
          blacksmithing = true,
          cooking = true,
          enchanting = true,
          engineering = true,
          firstAid = true,
          jewelcrafting = true,
          leatherworking = true,
          mining = true,
          tailoring = false,
        },
      })
      assert.are.equal(1, #filtered)
      assert.are.equal(1, filtered[1].recipeID)
    end)
  end)

  describe("SortItemResults", function()
    local rows = {
      { itemID = 1, itemName = "Zebra Cloth", characterName = "Bob", realm = "R", location = "bag", count = 2 },
      { itemID = 2, itemName = "Alpha Bolt", characterName = "Alice", realm = "R", location = "bank", count = 5 },
      { itemID = 1, itemName = "Zebra Cloth", characterName = "Alice", realm = "R", location = "bank", count = 3 },
    }

    it("returns the list unchanged when sortKey is nil", function()
      assert.are.same(rows, SD.SortItemResults(rows, nil, true))
    end)

    it("sorts by item name ascending", function()
      local out = SD.SortItemResults(rows, "Item", true)
      assert.are.equal(2, out[1].itemID)
      assert.are.equal(1, out[2].itemID)
      assert.are.equal("bank", out[2].location)
      assert.are.equal(1, out[3].itemID)
      assert.are.equal("bag", out[3].location)
    end)

    it("sorts by character name ascending", function()
      local out = SD.SortItemResults(rows, "Character", true)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Alice", out[2].characterName)
      assert.are.equal("Bob", out[3].characterName)
    end)

    it("sorts by grouped item total descending", function()
      local out = SD.SortItemResults(rows, "Total", false)
      assert.are.equal(1, out[1].itemID)
      assert.are.equal(1, out[2].itemID)
      assert.are.equal(2, out[3].itemID)
    end)
  end)

  describe("SortRecipeResults", function()
    local rows = {
      {
        characterName = "Zebra",
        recipeID = 1,
        recipeNameLower = "zebra cloth",
        professionName = "Tailoring",
        skillRank = 300,
        isGuild = true,
      },
      {
        characterName = "Alice",
        recipeID = 2,
        recipeNameLower = "alpha bolt",
        professionName = "Tailoring",
        skillRank = 375,
        recipeSkillRequired = 250,
        difficulty = "yellow",
      },
      {
        characterName = "Bob",
        recipeID = 3,
        recipeNameLower = "mooncloth",
        professionName = "Tailoring",
        skillRank = 200,
        recipeSkillRequired = 300,
        difficulty = "orange",
      },
    }

    it("sorts by recipe name ascending", function()
      local out = SD.SortRecipeResults(rows, "Recipe", true, true)
      assert.are.equal(2, out[1].recipeID)
      assert.are.equal(3, out[2].recipeID)
      assert.are.equal(1, out[3].recipeID)
    end)

    it("sorts by character name ascending", function()
      local out = SD.SortRecipeResults(rows, "Character", true, true)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Bob", out[2].characterName)
      assert.are.equal("Zebra", out[3].characterName)
    end)

    it("sorts by required skill descending when CraftLib is available", function()
      local out = SD.SortRecipeResults(rows, "Skill", false, true)
      assert.are.equal(3, out[1].recipeID)
      assert.are.equal(2, out[2].recipeID)
      assert.are.equal(1, out[3].recipeID)
    end)

    it("sorts by character skill rank when CraftLib is unavailable", function()
      local out = SD.SortRecipeResults(rows, "Skill", false, false)
      assert.are.equal(2, out[1].recipeID)
      assert.are.equal(1, out[2].recipeID)
      assert.are.equal(3, out[3].recipeID)
    end)

    it("lists own characters before guildmates when recipe names tie", function()
      local tied = {
        {
          characterName = "Zebra",
          recipeID = 1,
          recipeNameLower = "bolt",
          professionName = "Tailoring",
          isGuild = true,
        },
        {
          characterName = "Alice",
          recipeID = 1,
          recipeNameLower = "bolt",
          professionName = "Tailoring",
        },
        {
          characterName = "Bob",
          recipeID = 1,
          recipeNameLower = "bolt",
          professionName = "Tailoring",
        },
      }
      local out = SD.SortRecipeResults(tied, "Recipe", true, true)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Bob", out[2].characterName)
      assert.are.equal("Zebra", out[3].characterName)
    end)

    it("lists own characters before guildmates when required skill ties", function()
      local tied = {
        {
          characterName = "Zebra",
          recipeID = 1,
          recipeNameLower = "alpha",
          professionName = "Tailoring",
          recipeSkillRequired = 300,
          isGuild = true,
        },
        {
          characterName = "Alice",
          recipeID = 2,
          recipeNameLower = "beta",
          professionName = "Tailoring",
          recipeSkillRequired = 300,
        },
        {
          characterName = "Bob",
          recipeID = 3,
          recipeNameLower = "gamma",
          professionName = "Tailoring",
          recipeSkillRequired = 300,
        },
      }
      local out = SD.SortRecipeResults(tied, "Skill", false, true)
      assert.are.equal("Alice", out[1].characterName)
      assert.are.equal("Bob", out[2].characterName)
      assert.are.equal("Zebra", out[3].characterName)
    end)
  end)

  describe("_IsRecipeAliasId", function()
    it("returns true when recipeID differs from primaryRecipeID", function()
      assert.is_true(SD._IsRecipeAliasId(11334, { primaryRecipeID = 11449 }))
      assert.is_false(SD._IsRecipeAliasId(11449, { primaryRecipeID = 11449 }))
    end)
    it("returns false when primaryRecipeID is missing", function()
      assert.is_false(SD._IsRecipeAliasId(11334, { resultItemID = 9187 }))
    end)
  end)

  describe("GetSearchTailDebounceSecs", function()
    it("returns 0 for empty query", function()
      assert.are.equal(0, SD.GetSearchTailDebounceSecs(nil))
      assert.are.equal(0, SD.GetSearchTailDebounceSecs(""))
    end)
    it("uses 0.4s debounce for 1-character queries", function()
      assert.are.equal(0.4, SD.GetSearchTailDebounceSecs("a"))
    end)
    it("uses 0.1s debounce for 2-character queries", function()
      assert.are.equal(0.1, SD.GetSearchTailDebounceSecs("ab"))
    end)
    it("runs synchronously (0 delay) for 3+ character queries", function()
      assert.are.equal(0, SD.GetSearchTailDebounceSecs("abc"))
      assert.are.equal(0, SD.GetSearchTailDebounceSecs("abcd"))
      assert.are.equal(0, SD.GetSearchTailDebounceSecs("healing potion"))
    end)
  end)

  describe("search indexes and suffix array", function()
    local function stubTwoCharsSameItem()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        IterateInventory = DS.IterateInventory,
      }
      DS.GetRealms = function() return { R1 = true } end
      DS.GetCharacters = function()
        return {
          Alice = { name = "Alice" },
          Bob = { name = "Bob" },
        }
      end
      DS.IterateContainerSlots = function(_, char, cb)
        if char.name == "Alice" then
          cb(0, 1, 111, 2, "item:111")
        elseif char.name == "Bob" then
          cb(0, 1, 111, 5, "item:111")
          cb(0, 2, 222, 1, "item:222")
        end
      end
      DS.GetCharacterName = function(_, char) return char and char.name or "" end
      DS.GetCharacterClass = function() return "", "MAGE" end
      DS.IterateInventory = function() end
      return old
    end

    local function restoreDS(old)
      local DS = AltArmy.DataStore
      for k, v in pairs(old) do
        DS[k] = v
      end
    end

    it("BuildSlotsByItemID groups duplicate itemIDs", function()
      local byID = SD._BuildSlotsByItemID({
        { itemID = 1, characterName = "A" },
        { itemID = 1, characterName = "B" },
        { itemID = 2, characterName = "C" },
      })
      assert.are.equal(2, #byID[1])
      assert.are.equal(1, #byID[2])
    end)

    it("suffix array binary search finds mid-string and prefix ranges", function()
      local arr = SD._BuildSuffixArray({
        [10] = "minor healing potion",
        [20] = "super mana potion",
      })
      local potionIds = SD._LookupSuffixArrayIds(arr, "otion")
      assert.is_true(potionIds[10])
      assert.is_true(potionIds[20])
      local minorIds = SD._LookupSuffixArrayIds(arr, "minor")
      assert.is_true(minorIds[10])
      assert.is_nil(minorIds[20])
      local none = SD._LookupSuffixArrayIds(arr, "zzzz")
      assert.is_nil(next(none))
    end)

    it("chunked suffix sort finishes across multiple steps and matches full sort", function()
      assert.is_truthy(SD._BeginChunkedSuffixSort)
      assert.is_truthy(SD._ChunkedSuffixSortStep)
      assert.are.equal(200, SD._PREWARM_SORT_RUN)

      local arr = {}
      for i = 500, 1, -1 do
        arr[#arr + 1] = { suffix = string.format("name%04d", i), id = i }
        arr[#arr + 1] = { suffix = string.format("ame%04d", i), id = i }
        arr[#arr + 1] = { suffix = string.format("me%04d", i), id = i }
      end
      local expected = {}
      for i = 1, #arr do
        expected[i] = { suffix = arr[i].suffix, id = arr[i].id }
      end
      SD._SortSuffixArray(expected)

      local state = SD._BeginChunkedSuffixSort(arr)
      local steps = 0
      local done = false
      while not done and steps < 5000 do
        done = SD._ChunkedSuffixSortStep(state)
        steps = steps + 1
      end
      assert.is_true(done, "chunked sort did not finish")
      assert.is_true(steps > 1, "expected multi-step sort for large array, got " .. tostring(steps))
      assert.are.equal(#expected, #arr)
      for i = 1, #expected do
        assert.are.equal(expected[i].suffix, arr[i].suffix)
        assert.are.equal(expected[i].id, arr[i].id)
      end
    end)

    it("chunked suffix sort handles empty and tiny arrays in one step", function()
      local emptyState = SD._BeginChunkedSuffixSort({})
      assert.is_true(SD._ChunkedSuffixSortStep(emptyState))

      local tiny = {
        { suffix = "b", id = 2 },
        { suffix = "a", id = 1 },
      }
      local tinyState = SD._BeginChunkedSuffixSort(tiny)
      assert.is_true(SD._ChunkedSuffixSortStep(tinyState))
      assert.are.equal("a", tiny[1].suffix)
      assert.are.equal("b", tiny[2].suffix)
    end)

    it("Search by item ID returns all characters with that item", function()
      local old = stubTwoCharsSameItem()
      local oldGetItemInfo = _G.GetItemInfo
      _G.GetItemInfo = function(id)
        if id == 111 or id == "item:111" then return "Netherweave Cloth" end
        if id == 222 or id == "item:222" then return "Runecloth" end
        return nil
      end
      SD.NotifyContainerDataChanged()
      local results = SD.Search(111, true)
      restoreDS(old)
      _G.GetItemInfo = oldGetItemInfo
      assert.are.equal(2, #results)
      local names = {}
      for _, r in ipairs(results) do
        names[r.characterName] = true
        assert.are.equal(111, r.itemID)
      end
      assert.is_true(names.Alice)
      assert.is_true(names.Bob)
    end)

    it("Search by mid-string name expands to all stacks of matching itemIDs", function()
      local old = stubTwoCharsSameItem()
      local oldGetItemInfo = _G.GetItemInfo
      _G.GetItemInfo = function(id)
        if id == 111 or id == "item:111" then return "Minor Healing Potion" end
        if id == 222 or id == "item:222" then return "Runecloth" end
        return nil
      end
      SD.NotifyContainerDataChanged()
      local results = SD.Search("otion", true)
      restoreDS(old)
      _G.GetItemInfo = oldGetItemInfo
      assert.are.equal(2, #results)
      for _, r in ipairs(results) do
        assert.are.equal(111, r.itemID)
      end
    end)

    it("Search by prefix name still matches", function()
      local old = stubTwoCharsSameItem()
      local oldGetItemInfo = _G.GetItemInfo
      _G.GetItemInfo = function(id)
        if id == 111 or id == "item:111" then return "Minor Healing Potion" end
        if id == 222 or id == "item:222" then return "Runecloth" end
        return nil
      end
      SD.NotifyContainerDataChanged()
      local results = SD.Search("minor", true)
      restoreDS(old)
      _G.GetItemInfo = oldGetItemInfo
      assert.are.equal(2, #results)
    end)

    it("invalidates item index after NotifyContainerDataChanged", function()
      local old = stubTwoCharsSameItem()
      local oldGetItemInfo = _G.GetItemInfo
      _G.GetItemInfo = function(id)
        if id == 111 or id == "item:111" then return "Cloth" end
        if id == 222 or id == "item:222" then return "Runecloth" end
        return nil
      end
      SD.NotifyContainerDataChanged()
      assert.are.equal(2, #SD.Search(111, true))
      local DS = AltArmy.DataStore
      DS.IterateContainerSlots = function(_, char, cb)
        if char.name == "Alice" then
          cb(0, 1, 111, 1, "item:111")
        end
      end
      SD.NotifyContainerDataChanged()
      local results = SD.Search(111, true)
      restoreDS(old)
      _G.GetItemInfo = oldGetItemInfo
      assert.are.equal(1, #results)
      assert.are.equal("Alice", results[1].characterName)
    end)

    it("SearchRecipes expands one recipeID to multiple characters via index", function()
      local oldGetAll = SD.GetAllRecipes
      local oldGetSpellInfo = _G.GetSpellInfo
      local oldGetItemInfo = _G.GetItemInfo
      -- Use real index path: stub Build via GetAllRecipes replacement that still sets indexes
      -- by calling through a temporary list + _FilterAndSortRecipes with byID.
      local list = {
        { characterName = "A", realm = "R", professionName = "Alchemy", skillRank = 1, recipeID = 50 },
        { characterName = "B", realm = "R", professionName = "Alchemy", skillRank = 1, recipeID = 50 },
        { characterName = "C", realm = "R", professionName = "Alchemy", skillRank = 1, recipeID = 99 },
      }
      _G.GetSpellInfo = function(id)
        if id == 50 then return "Elixir of Healing" end
        if id == 99 then return "Transmute" end
        return nil
      end
      _G.GetItemInfo = function() return nil end
      local byID = SD._BuildRecipesByID(list)
      local names = { [50] = "elixir of healing", [99] = "transmute" }
      local arr = SD._BuildSuffixArray(names)
      local results = SD._FilterAndSortRecipes(list, "elixir", byID, function() return arr end)
      SD.GetAllRecipes = oldGetAll
      _G.GetSpellInfo = oldGetSpellInfo
      _G.GetItemInfo = oldGetItemInfo
      assert.are.equal(2, #results)
      assert.are.equal(50, results[1].recipeID)
      assert.are.equal(50, results[2].recipeID)
    end)

    it("invalidates recipe suffix path after NotifyRecipesChanged", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        GetProfessions = DS.GetProfessions,
        ForEachCharacter = DS.ForEachCharacter,
      }
      DS.GetRealms = function() return { R = true } end
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = { rank = 300, Recipes = { [50] = 1 } },
            },
          },
        }
      end
      DS.GetCharacterName = function(_, c) return c and c.name or "" end
      DS.GetCharacterClass = function() return "", "MAGE" end
      DS.GetProfessions = function(_, c) return c and c.Professions or {} end
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetSpellInfo = function(id)
        if id == 50 then return "Test Potion" end
        if id == 60 then return "Other Spell" end
        return nil
      end
      SD.NotifyRecipesChanged()
      assert.are.equal(1, #SD.SearchRecipes("potion"))
      DS.GetCharacters = function()
        return {
          Char1 = {
            name = "Char1",
            Professions = {
              Alchemy = { rank = 300, Recipes = { [60] = 1 } },
            },
          },
        }
      end
      SD.NotifyRecipesChanged()
      local results = SD.SearchRecipes("potion")
      for k, v in pairs(old) do DS[k] = v end
      _G.GetSpellInfo = oldGetSpellInfo
      assert.are.equal(0, #results)
      assert.are.equal(1, #SD.SearchRecipes("other"))
    end)
  end)

  describe("index prewarm", function()
    local function stubSlotsAndRecipes()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        IterateInventory = DS.IterateInventory,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        GetProfessions = DS.GetProfessions,
        ForEachCharacter = DS.ForEachCharacter,
      }
      DS.GetRealms = function() return { R = true } end
      DS.GetCharacters = function()
        return {
          Alice = {
            name = "Alice",
            Professions = {
              Alchemy = { rank = 300, Recipes = { [50] = 1, [60] = 1 } },
            },
          },
        }
      end
      DS.IterateContainerSlots = function(_, _char, cb)
        cb(0, 1, 111, 1, "item:111")
        cb(0, 2, 222, 1, "item:222")
      end
      DS.IterateInventory = function() end
      DS.GetCharacterName = function(_, c) return c and c.name or "" end
      DS.GetCharacterClass = function() return "", "MAGE" end
      DS.GetProfessions = function(_, c) return c and c.Professions or {} end
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetItemInfo = function(id)
        if id == 111 or id == "item:111" then return "Minor Healing Potion" end
        if id == 222 or id == "item:222" then return "Runecloth" end
        return nil
      end
      _G.GetSpellInfo = function(id)
        if id == 50 then return "Elixir of Giants" end
        if id == 60 then return "Transmute Iron to Gold" end
        return nil
      end
      return old, oldGetItemInfo, oldGetSpellInfo
    end

    local function restoreAll(old, oldGetItemInfo, oldGetSpellInfo)
      local DS = AltArmy.DataStore
      for k, v in pairs(old) do DS[k] = v end
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      SD.StopIndexPrewarm()
      SD.ClearSearchCaches()
    end

    local function drivePrewarmToIdle()
      local guard = 0
      while SD.IsIndexPrewarmRunning() and guard < 5000 do
        SD._PrewarmStep()
        guard = guard + 1
      end
      assert.is_true(guard < 5000, "prewarm did not finish")
    end

    it("completes item and local recipe suffix arrays via chunked steps", function()
      local old, oldGetItemInfo, oldGetSpellInfo = stubSlotsAndRecipes()
      SD.NotifyContainerDataChanged()
      SD.NotifyRecipesChanged()
      AltArmy.MainFrame = { IsShown = function() return true end }
      SD.StartIndexPrewarm()
      assert.is_true(SD.IsIndexPrewarmRunning())
      drivePrewarmToIdle()
      local itemArr = SD._GetItemSuffixArrayForTests()
      local recipeArr = SD._GetLocalRecipeSuffixArrayForTests()
      assert.is_truthy(itemArr)
      assert.is_true(#itemArr > 0)
      assert.is_truthy(recipeArr)
      assert.is_true(#recipeArr > 0)
      local potionIds = SD._LookupSuffixArrayIds(itemArr, "otion")
      assert.is_true(potionIds[111])
      local elixirIds = SD._LookupSuffixArrayIds(recipeArr, "elixir")
      assert.is_true(elixirIds[50])
      restoreAll(old, oldGetItemInfo, oldGetSpellInfo)
      AltArmy.MainFrame = nil
    end)

    it("stops and clears on invalidate mid-prewarm", function()
      local old, oldGetItemInfo, oldGetSpellInfo = stubSlotsAndRecipes()
      SD.NotifyContainerDataChanged()
      AltArmy.MainFrame = { IsShown = function() return false end }
      SD.StartIndexPrewarm()
      assert.is_true(SD.IsIndexPrewarmRunning())
      SD._PrewarmStep()
      SD.NotifyContainerDataChanged()
      assert.is_false(SD.IsIndexPrewarmRunning())
      assert.is_nil(SD._GetItemSuffixArrayForTests())
      restoreAll(old, oldGetItemInfo, oldGetSpellInfo)
      AltArmy.MainFrame = nil
    end)

    it("Ensure sync-finish during incomplete prewarm matches full BuildSuffixArray", function()
      local old, oldGetItemInfo, oldGetSpellInfo = stubSlotsAndRecipes()
      SD.NotifyContainerDataChanged()
      AltArmy.MainFrame = { IsShown = function() return false end }
      SD.StartIndexPrewarm()
      -- One step: slots only; item suffix not ready yet.
      SD._PrewarmStep()
      assert.is_nil(SD._GetItemSuffixArrayForTests())
      local results = SD.Search("otion", true)
      assert.are.equal(1, #results)
      assert.are.equal(111, results[1].itemID)
      local arr = SD._GetItemSuffixArrayForTests()
      assert.is_truthy(arr)
      local expected = SD._BuildSuffixArray({
        [111] = "minor healing potion",
        [222] = "runecloth",
      })
      assert.are.equal(#expected, #arr)
      restoreAll(old, oldGetItemInfo, oldGetSpellInfo)
      AltArmy.MainFrame = nil
    end)
  end)

  describe("index build debug logging", function()
    it("logs suffix array build timing when search debug is on", function()
      local logs = {}
      local prevDebug = AltArmy.Debug
      AltArmy.Debug = {
        IsSearchEnabled = function() return true end,
        LogSearch = function(msg) logs[#logs + 1] = msg end,
      }
      local oldStart, oldStop = _G.debugprofilestart, _G.debugprofilestop
      _G.debugprofilestart = function() end
      _G.debugprofilestop = function() return 2.25 end

      SD._BuildSuffixArray({ [1] = "foo", [2] = "barbaz" })

      _G.debugprofilestart = oldStart
      _G.debugprofilestop = oldStop
      AltArmy.Debug = prevDebug

      local found = false
      for _, msg in ipairs(logs) do
        if type(msg) == "string" and msg:find("index suffixArray", 1, true)
            and msg:find("ms=", 1, true) then
          found = true
          break
        end
      end
      assert.is_true(found, "expected index suffixArray timing log")
    end)

    it("logs prewarm start/done and sort phases when search debug is on", function()
      local DS = AltArmy.DataStore
      local old = {
        GetRealms = DS.GetRealms,
        GetCharacters = DS.GetCharacters,
        IterateContainerSlots = DS.IterateContainerSlots,
        IterateInventory = DS.IterateInventory,
        GetCharacterName = DS.GetCharacterName,
        GetCharacterClass = DS.GetCharacterClass,
        GetProfessions = DS.GetProfessions,
      }
      DS.GetRealms = function() return { R = true } end
      DS.GetCharacters = function()
        return {
          Alice = {
            name = "Alice",
            Professions = { Alchemy = { rank = 300, Recipes = { [50] = 1 } } },
          },
        }
      end
      DS.IterateContainerSlots = function(_, _char, cb)
        cb(0, 1, 111, 1, "item:111")
      end
      DS.IterateInventory = function() end
      DS.GetCharacterName = function(_, c) return c and c.name or "" end
      DS.GetCharacterClass = function() return "", "MAGE" end
      DS.GetProfessions = function(_, c) return c and c.Professions or {} end
      local oldGetItemInfo = _G.GetItemInfo
      local oldGetSpellInfo = _G.GetSpellInfo
      _G.GetItemInfo = function(id)
        if id == 111 or id == "item:111" then return "Minor Healing Potion" end
        return nil
      end
      _G.GetSpellInfo = function(id)
        if id == 50 then return "Elixir of Giants" end
        return nil
      end
      local oldGetTime = _G.GetTime
      _G.GetTime = function() return 10 end

      local logs = {}
      local prevDebug = AltArmy.Debug
      AltArmy.Debug = {
        IsSearchEnabled = function() return true end,
        LogSearch = function(msg) logs[#logs + 1] = msg end,
      }
      local oldStart, oldStop = _G.debugprofilestart, _G.debugprofilestop
      _G.debugprofilestart = function() end
      _G.debugprofilestop = function() return 1 end

      SD.ClearSearchCaches()
      AltArmy.MainFrame = { IsShown = function() return true end }
      SD.StartIndexPrewarm()
      local guard = 0
      while SD.IsIndexPrewarmRunning() and guard < 5000 do
        SD._PrewarmStep()
        guard = guard + 1
      end

      _G.debugprofilestart = oldStart
      _G.debugprofilestop = oldStop
      _G.GetItemInfo = oldGetItemInfo
      _G.GetSpellInfo = oldGetSpellInfo
      _G.GetTime = oldGetTime
      for k, v in pairs(old) do DS[k] = v end
      AltArmy.Debug = prevDebug
      SD.StopIndexPrewarm()
      SD.ClearSearchCaches()
      AltArmy.MainFrame = nil

      local joined = table.concat(logs, "\n")
      assert.is_truthy(joined:find("index prewarm start", 1, true))
      assert.is_truthy(joined:find("prewarm itemSuffix", 1, true))
      assert.is_truthy(joined:find("prewarm localRecipeSuffix", 1, true))
      assert.is_truthy(joined:find("index prewarm done", 1, true))
    end)
  end)
end)
