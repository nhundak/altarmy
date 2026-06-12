--[[
  Documents empty-state visibility for TabSearch.lua when a query has no results.
]]

describe("Search tab no-results hint", function()
    local function shouldShowNoSearchResultsHint(query, categories, resultCount, tooltipPending)
        if not query or query == "" then
            return false
        end
        if resultCount > 0 then
            return false
        end
        if categories.Items and tooltipPending then
            return false
        end
        return true
    end

    it("is hidden when there is no query", function()
        assert.is_false(shouldShowNoSearchResultsHint("", { Items = true, Recipes = true }, 0, false))
        assert.is_false(shouldShowNoSearchResultsHint(nil, { Items = true, Recipes = true }, 0, false))
    end)

    it("is shown when there is a query and no results", function()
        assert.is_true(shouldShowNoSearchResultsHint("iron", { Items = true, Recipes = true }, 0, false))
    end)

    it("is hidden when results exist", function()
        assert.is_false(shouldShowNoSearchResultsHint("iron", { Items = true, Recipes = true }, 1, false))
    end)

    it("waits for tooltip search while items are enabled", function()
        assert.is_false(shouldShowNoSearchResultsHint("iron", { Items = true, Recipes = true }, 0, true))
        assert.is_true(shouldShowNoSearchResultsHint("iron", { Items = false, Recipes = true }, 0, true))
    end)
end)
