--[[ Unit tests for the generated Writs.lua (Economy tab, Craftsman's Writs) — run: npm test ]]

describe("Writs", function()
    local W

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["Writs"] = nil
        require("Writs")
        W = AltArmy.Writs
        assert.truthy(W)
    end)

    it("lists the 150 writs by tier with their reputation", function()
        assert.equals(150, #W.LIST)
        local byTier = {}
        for _, writ in ipairs(W.LIST) do
            byTier[writ.tier] = (byTier[writ.tier] or 0) + 1
            assert.equals(W.REP[writ.tier], writ.rep, writ.name)
            assert.equals(writ, W.ById[writ.id])
            assert.equals(writ, W.ByQuest[writ.quest])
            assert.equals("Craftsman's Writ: " .. writ.short, writ.name)
            assert.is_true(writ.count >= 1, writ.name)
        end
        assert.same({ Journeyman = 45, Expert = 60, Artisan = 45 }, byTier)
        assert.same({ Journeyman = 75, Expert = 125, Artisan = 200 }, W.REP)
    end)

    it("names an item some recipe makes for every writ, and every reagent", function()
        for _, writ in ipairs(W.LIST) do
            assert.is_true(#writ.items >= 1, writ.name)
            for _, item in ipairs(writ.items) do
                assert.truthy(W.ITEMS[item], writ.name)
                assert.truthy(W.ByOutput[item], writ.name)
            end
        end
        for spell, recipe in pairs(W.RECIPES) do
            assert.truthy(W.ITEMS[recipe.out], spell)
            assert.is_true(recipe.n >= 1, spell)
            assert.is_true(#recipe.reagents >= 1, spell)
            for _, r in ipairs(recipe.reagents) do
                assert.truthy(W.ITEMS[r.item], spell)
                assert.is_true(r.count >= 1, spell)
            end
        end
    end)

    it("resolves the awkward names", function()
        assert.same({ 3391 }, W.ById[264011].items) -- "Elixir of Ogre's Strength": the item has no apostrophe
        assert.equals("Elixir of Ogre Strength", W.ITEMS[3391].name)
        assert.same({ 9366, 217273 }, W.ById[264078].items) -- two Golden Scale Gauntlets, each a recipe's
        assert.same({ 4383 }, W.ById[264031].items) -- the other Moonsight Rifle is no recipe's
        assert.equals(94004, W.ById[264011].quest)
    end)

    it("knows vendor prices, bonding and crafts per cast", function()
        assert.equals(100, W.ITEMS[2321].vendor) -- Fine Thread
        assert.equals(1, W.ITEMS[2321].per)
        assert.is_nil(W.ITEMS[4306].vendor) -- Silk Cloth
        assert.is_true(W.ITEMS[18240].bop) -- Ogre Tannin
        assert.equals(200, W.ById[264037].count) -- Crafted Solid Shot: one cast makes 200
        assert.equals(2, #W.ByOutput[18258]) -- Gordok Ogre Suit: Tailoring and Leatherworking
    end)
end)
