--[[ Unit tests for SearchPresent.lua — sort / aggregate / collapse. ]]

describe("SearchPresent", function()
    local SP

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["SearchPresent"] = nil
        require("SearchPresent")
        SP = AltArmy.SearchPresent
        assert.truthy(SP)
    end)

    it("AggregateItemRows groups by item/char/location and sorts by match score", function()
        local raw = {
            {
                itemID = 1, itemName = "Bolt of Linen Cloth", itemNameLower = "bolt of linen cloth",
                itemLink = "x", characterName = "A", realm = "R", location = "bag", count = 2,
                classFile = "MAGE",
            },
            {
                itemID = 1, itemName = "Bolt of Linen Cloth", itemNameLower = "bolt of linen cloth",
                itemLink = "x", characterName = "A", realm = "R", location = "bank", count = 1,
                classFile = "MAGE",
            },
            {
                itemID = 2, itemName = "Linen Cloth", itemNameLower = "linen cloth",
                itemLink = "y", characterName = "B", realm = "R", location = "bag", count = 5,
                classFile = "WARRIOR",
            },
        }
        local rows = SP.AggregateItemRows(raw, "linen cloth")
        -- Exact match "Linen Cloth" should come before contains match "Bolt of Linen Cloth".
        assert.are.equal(2, rows[1].itemID)
        assert.are.equal(5, rows[1].count)
        -- Item 1 has bag then bank for same char.
        local item1 = {}
        for i = 1, #rows do
            if rows[i].itemID == 1 then
                item1[#item1 + 1] = rows[i]
            end
        end
        assert.are.equal(2, #item1)
        assert.are.equal("bag", item1[1].location)
        assert.are.equal(2, item1[1].count)
    end)

    it("CollapseGuildRecipeRows collapses 3+ guild rows and expands with descriptors", function()
        local sorted = {
            { recipeID = 10, characterName = "Own", isGuild = false, professionName = "Tailoring" },
            { recipeID = 10, characterName = "G1", isGuild = true, professionName = "Tailoring" },
            { recipeID = 10, characterName = "G2", isGuild = true, professionName = "Tailoring" },
            { recipeID = 10, characterName = "G3", isGuild = true, professionName = "Tailoring" },
        }
        local collapsed = SP.CollapseGuildRecipeRows(sorted, {})
        assert.are.equal(2, #collapsed)
        assert.is_false(collapsed[1].isGuild and true or false)
        assert.is_true(collapsed[2].isGuildCollapsed)
        assert.are.equal(3, #collapsed[2].guildChars)

        local expanded = SP.CollapseGuildRecipeRows(sorted, { [10] = true })
        assert.are.equal(5, #expanded)
        assert.is_true(expanded[2].isGuildCollapsed)
        assert.is_true(expanded[3]._aaFromCollapse)
        assert.are.equal("G1", expanded[3].characterName)
    end)

    it("SortItemResults sorts by Item name", function()
        local list = {
            { itemID = 2, itemName = "Wool", characterName = "A", realm = "R", location = "bag", count = 1 },
            { itemID = 1, itemName = "Linen", characterName = "A", realm = "R", location = "bag", count = 1 },
        }
        local sorted = SP.SortItemResults(list, "Item", true)
        assert.are.equal("Linen", sorted[1].itemName)
        assert.are.equal("Wool", sorted[2].itemName)
    end)
end)
