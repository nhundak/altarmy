--[[ Unit tests for SearchQuery.lua — v2 match/expand/filter. ]]

describe("SearchQuery", function()
    local SQ
    local SI

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["SearchIndex"] = nil
        package.loaded["SearchQuery"] = nil
        require("SearchIndex")
        require("SearchQuery")
        SI = AltArmy.SearchIndex
        SQ = AltArmy.SearchQuery
        assert.truthy(SQ)
    end)

    local function makeItemIndex()
        local entries = {
            {
                itemID = 2589, itemName = "Linen Cloth", itemNameLower = "linen cloth",
                itemLink = "|Hitem:2589|h", characterName = "Alice", realm = "R",
                location = "bag", count = 20, classFile = "MAGE",
            },
            {
                itemID = 2589, itemName = "Linen Cloth", itemNameLower = "linen cloth",
                itemLink = "|Hitem:2589|h", characterName = "Bob", realm = "R",
                location = "bank", count = 5, classFile = "WARRIOR",
            },
            {
                itemID = 2592, itemName = "Wool Cloth", itemNameLower = "wool cloth",
                itemLink = "|Hitem:2592|h", characterName = "Alice", realm = "R",
                location = "bag", count = 3, classFile = "MAGE",
            },
        }
        return SI.BuildIndex(entries, {
            getId = function(e) return e.itemID end,
            getNameLower = function(e) return e.itemNameLower end,
        })
    end

    it("ParseQuery returns lowercase and numeric id", function()
        local lower, id = SQ.ParseQuery("Linen")
        assert.are.equal("linen", lower)
        assert.is_nil(id)
        local _, id2 = SQ.ParseQuery("2589")
        assert.are.equal(2589, id2)
    end)

    it("MatchAndExpandItems finds by name substring", function()
        local index = makeItemIndex()
        local memo = {}
        local rows = SQ.MatchAndExpandItems(index, "linen", nil, memo)
        assert.are.equal(2, #rows)
        assert.are.equal(2589, rows[1].itemID)
    end)

    it("MatchAndExpandItems finds by item id", function()
        local index = makeItemIndex()
        local rows = SQ.MatchAndExpandItems(index, nil, 2592, {})
        assert.are.equal(1, #rows)
        assert.are.equal(2592, rows[1].itemID)
    end)

    it("MatchAndExpandItems narrows when query extends previous", function()
        local index = makeItemIndex()
        local memo = {}
        SQ.MatchAndExpandItems(index, "cloth", nil, memo)
        assert.is_true(memo.prevIds[2589])
        assert.is_true(memo.prevIds[2592])
        local rows = SQ.MatchAndExpandItems(index, "linen cloth", nil, memo)
        assert.are.equal(2, #rows)
        assert.is_true(memo.prevIds[2589])
        assert.is_nil(memo.prevIds[2592])
    end)

    it("MatchAndExpandRecipes expands character rows for matched recipe ids", function()
        local entries = {
            {
                recipeID = 100, recipeNameLower = "bolt of linen cloth",
                characterName = "Alice", realm = "R", isGuild = false,
            },
            {
                recipeID = 100, recipeNameLower = "bolt of linen cloth",
                characterName = "Bob", realm = "R", isGuild = true,
            },
            {
                recipeID = 200, recipeNameLower = "woolen cape",
                characterName = "Alice", realm = "R", isGuild = false,
            },
        }
        local index = SI.BuildIndex(entries, {
            getId = function(e) return e.recipeID end,
            getNameLower = function(e) return e.recipeNameLower end,
            compareWithinId = function(a, b)
                local aGuild = a.isGuild and true or false
                local bGuild = b.isGuild and true or false
                if aGuild ~= bGuild then return not aGuild end
                return (a.characterName or "") < (b.characterName or "")
            end,
        })
        local rows = SQ.MatchAndExpandRecipes(index, "linen", {})
        assert.are.equal(2, #rows)
        assert.are.equal(100, rows[1].recipeID)
        assert.is_false(rows[1].isGuild and true or false)
    end)
end)
