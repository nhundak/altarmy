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
    require("DataStoreContainers")
    require("SearchData")
    SD = AltArmy.SearchData
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
  end)
end)
