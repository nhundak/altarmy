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
    it("orders bag before bank before equipped before mail", function()
      assert.is_true(SD._LocationSortKey("bag") < SD._LocationSortKey("bank"))
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

  describe("_IsRecipeAliasId", function()
    it("returns true when recipeID differs from primaryRecipeID", function()
      assert.is_true(SD._IsRecipeAliasId(11334, { primaryRecipeID = 11449 }))
      assert.is_false(SD._IsRecipeAliasId(11449, { primaryRecipeID = 11449 }))
    end)
    it("returns false when primaryRecipeID is missing", function()
      assert.is_false(SD._IsRecipeAliasId(11334, { resultItemID = 9187 }))
    end)
  end)
end)
