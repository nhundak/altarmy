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

describe("Search tab no-results hint message", function()
    local function getNoSearchResultsHintText(categories)
        categories = categories or {}
        local items = categories.Items and true or false
        local recipes = categories.Recipes and true or false
        if not items and not recipes then
            return "Choose Items and/or Recipes above"
        end
        if items and recipes then
            return "No matching items or recipes\nwere found for your search."
        end
        if items then
            return "No matching items\nwere found for your search."
        end
        return "No matching recipes\nwere found for your search."
    end

    it("uses the full message when both categories are selected", function()
        assert.are.equal(
            "No matching items or recipes\nwere found for your search.",
            getNoSearchResultsHintText({ Items = true, Recipes = true })
        )
    end)

    it("omits recipes when only items is selected", function()
        assert.are.equal(
            "No matching items\nwere found for your search.",
            getNoSearchResultsHintText({ Items = true, Recipes = false })
        )
    end)

    it("omits items when only recipes is selected", function()
        assert.are.equal(
            "No matching recipes\nwere found for your search.",
            getNoSearchResultsHintText({ Items = false, Recipes = true })
        )
    end)

    it("prompts to choose categories when neither is selected", function()
        assert.are.equal(
            "Choose Items and/or Recipes above",
            getNoSearchResultsHintText({ Items = false, Recipes = false })
        )
    end)
end)
