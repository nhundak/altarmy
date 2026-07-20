--[[ Unit tests for SearchEngine.lua — facade over SearchData. ]]

describe("SearchEngine", function()
    local SE
    local calls

    local function stubSearchData()
        calls = {}
        AltArmy.SearchData = {
            SearchItems = function(q, skip)
                calls[#calls + 1] = { "SearchItems", q, skip }
                return { { itemID = 1 } }, {}
            end,
            SearchWithLocationGroups = function(q, skip)
                calls[#calls + 1] = { "SearchWithLocationGroups", q, skip }
                return { { itemID = 1 } }, {}
            end,
            SearchRecipes = function(q)
                calls[#calls + 1] = { "SearchRecipes", q }
                return { { recipeID = 2 } }
            end,
            SearchGuildRecipes = function(q)
                calls[#calls + 1] = { "SearchGuildRecipes", q }
                return { { recipeID = 3, isGuild = true } }
            end,
            MergeRecipeSearchResults = function(a, b)
                calls[#calls + 1] = { "MergeRecipeSearchResults", a, b }
                return { a[1], b[1] }
            end,
            SortItemResults = function(list, key, asc)
                calls[#calls + 1] = { "SortItemResults", list, key, asc }
                return list
            end,
            SortRecipeResults = function(list, key, asc, craft)
                calls[#calls + 1] = { "SortRecipeResults", list, key, asc, craft }
                return list
            end,
            CollapseGuildRecipeRows = function(list, expanded)
                calls[#calls + 1] = { "CollapseGuildRecipeRows", list, expanded }
                return list
            end,
            EnsureRecipeDisplayCache = function(entry)
                calls[#calls + 1] = { "EnsureRecipeDisplayCache", entry }
                return entry
            end,
            _EnrichRecipeEntry = function(entry)
                calls[#calls + 1] = { "EnrichRecipeEntry", entry }
                return entry
            end,
            GetSearchTailDebounceSecs = function(q)
                calls[#calls + 1] = { "GetSearchTailDebounceSecs", q }
                return 0.1
            end,
            GetAllContainerSlots = function()
                calls[#calls + 1] = { "GetAllContainerSlots" }
                return {}
            end,
            StartRecipeResultPrewarm = function(list)
                calls[#calls + 1] = { "StartRecipeResultPrewarm", list }
            end,
            NotifyContainerDataChanged = function()
                calls[#calls + 1] = { "NotifyContainerDataChanged" }
            end,
            NotifyRecipesChanged = function()
                calls[#calls + 1] = { "NotifyRecipesChanged" }
            end,
        }
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        stubSearchData()
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["SearchEngine"] = nil
        require("SearchEngine")
        SE = AltArmy.SearchEngine
        assert.truthy(SE)
    end)

    before_each(function()
        stubSearchData()
        calls = {}
    end)

    it("routes SearchItems to SearchData.SearchItems", function()
        local main, tip = SE.SearchItems("linen", true)
        assert.are.equal(1, #main)
        assert.are.equal(0, #tip)
        assert.are.equal("SearchItems", calls[1][1])
        assert.are.equal("linen", calls[1][2])
        assert.is_true(calls[1][3])
    end)

    it("routes SearchRecipes and SearchGuildRecipes to SearchData", function()
        local recipes = SE.SearchRecipes("bolt")
        local guild = SE.SearchGuildRecipes("bolt")
        assert.are.equal(2, recipes[1].recipeID)
        assert.is_true(guild[1].isGuild)
        assert.are.equal("SearchRecipes", calls[1][1])
        assert.are.equal("SearchGuildRecipes", calls[2][1])
    end)

    it("routes sort/collapse/merge helpers to SearchData", function()
        local list = { { recipeID = 1 } }
        SE.SortItemResults(list, "Item", true)
        SE.SortRecipeResults(list, "Recipe", true, false)
        SE.CollapseGuildRecipeRows(list, {})
        SE.MergeRecipeSearchResults(list, list)
        assert.are.equal("SortItemResults", calls[1][1])
        assert.are.equal("SortRecipeResults", calls[2][1])
        assert.are.equal("CollapseGuildRecipeRows", calls[3][1])
        assert.are.equal("MergeRecipeSearchResults", calls[4][1])
    end)

    it("routes Notify helpers to SearchData", function()
        SE.NotifyContainerDataChanged()
        SE.NotifyRecipesChanged()
        assert.are.equal("NotifyContainerDataChanged", calls[1][1])
        assert.are.equal("NotifyRecipesChanged", calls[2][1])
    end)
end)
