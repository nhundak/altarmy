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

    it("CollapseGuildRecipeRows stays correct across many collapsible recipes", function()
        -- Large multi-recipe input: old impl rescanned j=i..n per collapsed id (O(n^2)).
        local sorted = {}
        local recipeCount = 200
        for id = 1, recipeCount do
            sorted[#sorted + 1] = {
                recipeID = id, characterName = "Own" .. id, isGuild = false, professionName = "Tailoring",
            }
            for g = 1, 4 do
                sorted[#sorted + 1] = {
                    recipeID = id,
                    characterName = "G" .. id .. "_" .. g,
                    isGuild = true,
                    professionName = "Tailoring",
                }
            end
        end
        local out = SP.CollapseGuildRecipeRows(sorted, {})
        -- Each recipe: 1 own row + 1 collapsed summary.
        assert.are.equal(recipeCount * 2, #out)
        local collapsedN = 0
        for i = 1, #out do
            local row = out[i]
            if row.isGuildCollapsed then
                collapsedN = collapsedN + 1
                assert.are.equal(4, #row.guildChars)
                assert.are.equal("G" .. row.recipeID .. "_1", row.guildChars[1].characterName)
                assert.are.equal("G" .. row.recipeID .. "_4", row.guildChars[4].characterName)
            end
        end
        assert.are.equal(recipeCount, collapsedN)
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

    it("SortRecipeResults by Recipe keeps already-ordered within-id rows", function()
        -- Mirrors TabSearch merge: own rows then guild rows, each side A-Z.
        local list = {
            {
                recipeID = 2, recipeNameLower = "beta", professionName = "Alchemy",
                characterName = "Alice",
            },
            {
                recipeID = 2, recipeNameLower = "beta", professionName = "Alchemy",
                characterName = "Bob", isGuild = true,
            },
            {
                recipeID = 1, recipeNameLower = "alpha", professionName = "Alchemy",
                characterName = "Carol",
            },
            {
                recipeID = 1, recipeNameLower = "alpha", professionName = "Alchemy",
                characterName = "Dave", isGuild = true,
            },
        }
        local out = SP.SortRecipeResults(list, "Recipe", true, false)
        assert.are.equal(1, out[1].recipeID)
        assert.are.equal("Carol", out[1].characterName)
        assert.are.equal("Dave", out[2].characterName)
        assert.are.equal(2, out[3].recipeID)
        assert.are.equal("Alice", out[3].characterName)
        assert.are.equal("Bob", out[4].characterName)
    end)

    it("SortRecipeResults by Recipe prefers stamped _aaRecipeSortKey", function()
        local list = {
            {
                recipeID = 1,
                recipeNameLower = "zzz",
                professionName = "Tailoring",
                _aaRecipeSortKey = "alchemy\0alpha",
                characterName = "A",
            },
            {
                recipeID = 2,
                recipeNameLower = "aaa",
                professionName = "Alchemy",
                _aaRecipeSortKey = "tailoring\0zeta",
                characterName = "B",
            },
        }
        local out = SP.SortRecipeResults(list, "Recipe", true, false)
        -- Stamped keys place recipe 1 (alchemy/alpha) before recipe 2 (tailoring/zeta),
        -- not the recipeNameLower/professionName fields.
        assert.are.equal(1, out[1].recipeID)
        assert.are.equal(2, out[2].recipeID)
    end)

    it("EnsureRecipeDisplayCache keeps profession prefix out of the searchable match name", function()
        _G.GetSpellInfo = function(id)
            if id == 20047 then
                return "Enchant 2H Weapon - Impact", nil, "Interface\\Icons\\Spell_Holy_GreaterHeal"
            end
            return nil
        end
        _G.GetItemInfo = function() return nil end
        local entry = {
            professionName = "Enchanting",
            recipeID = 20047,
            skillRank = 300,
        }
        SP.EnsureRecipeDisplayCache(entry)
        assert.are.equal("Enchanting: Enchant 2H Weapon - Impact", entry._aaRecipeBaseName)
        assert.are.equal("Enchanting: ", entry._aaRecipeNamePrefix)
        assert.are.equal("Enchant 2H Weapon - Impact", entry._aaRecipeMatchName)
    end)

    it("FormatHighlightedRecipeName highlights only the recipe match name, not the profession prefix", function()
        local entry = {
            _aaRecipeBaseName = "Enchanting: Enchant 2H Weapon - Impact",
            _aaRecipeNamePrefix = "Enchanting: ",
            _aaRecipeMatchName = "Enchant 2H Weapon - Impact",
        }
        local out = SP.FormatHighlightedRecipeName(entry, "enchant", function(text, query)
            local lower = (text or ""):lower()
            local q = (query or ""):lower()
            local s, e = lower:find(q, 1, true)
            if not s then
                return text
            end
            return text:sub(1, s - 1) .. "<H>" .. text:sub(s, e) .. "</H>" .. text:sub(e + 1)
        end)
        assert.are.equal("Enchanting: <H>Enchant</H> 2H Weapon - Impact", out)
    end)
end)
