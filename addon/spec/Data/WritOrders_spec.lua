--[[ Unit tests for WritOrders.lua (Economy tab: a writ's order read from the quest log) — run: npm test ]]

describe("WritOrders", function()
    local O

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["WritOrders"] = nil
        require("WritOrders")
        O = AltArmy.WritOrders
        assert.truthy(O)
    end)

    describe("ParseObjective", function()
        it("reads the item and counts", function()
            local name, have, need = O.ParseObjective("Lesser Wizard's Robe: 0/2")
            assert.equals("Lesser Wizard's Robe", name)
            assert.equals(0, have)
            assert.equals(2, need)
        end)

        it("forgives spacing", function()
            local name, have, need = O.ParseObjective("  Crafted Solid Shot : 150 / 200 ")
            assert.equals("Crafted Solid Shot", name)
            assert.equals(150, have)
            assert.equals(200, need)
        end)

        it("is nil for anything else", function()
            assert.is_nil(O.ParseObjective("Speak to the customer"))
            assert.is_nil(O.ParseObjective(": 0/1"))
            assert.is_nil(O.ParseObjective(nil))
        end)
    end)

    describe("Resolve", function()
        local ITEMS = { [3391] = { name = "Elixir of Ogre Strength" }, [9366] = { name = "Golden Scale Gauntlets" },
            [217273] = { name = "Golden Scale Gauntlets" } }

        it("finds the candidate of that name, case and punctuation aside", function()
            assert.equals(3391, O.Resolve("Elixir of Ogre Strength", { 3391 }, ITEMS))
            assert.equals(3391, O.Resolve("ELIXIR OF OGRE-STRENGTH ", { 3391 }, ITEMS))
            assert.equals(9366, O.Resolve("golden scale gauntlets", { 9366, 217273 }, ITEMS))
        end)

        it("is nil for a name no candidate has", function()
            assert.is_nil(O.Resolve("Runecloth Bag", { 3391 }, ITEMS))
            assert.is_nil(O.Resolve("", { 3391 }, ITEMS))
            assert.is_nil(O.Resolve("Elixir of Ogre Strength", nil, ITEMS))
        end)
    end)

    describe("Record", function()
        it("keeps an order and says when it is news", function()
            local store = {}
            assert.is_true(O.Record(store, 94247, 4316, 2, 100))
            assert.same({ item = 4316, count = 2, t = 100 }, store[94247])
            assert.is_false(O.Record(store, 94247, 4316, 2, 200))
            assert.equals(100, store[94247].t)
            assert.is_true(O.Record(store, 94247, 4316, 3, 300))
            assert.equals(3, store[94247].count)
        end)

        it("keeps a count without an item", function()
            local store = {}
            assert.is_true(O.Record(store, 94247, nil, 2, 100))
            assert.same({ count = 2, t = 100 }, store[94247])
        end)

        it("ignores a missing count", function()
            local store = {}
            assert.is_false(O.Record(store, 94247, 4316, nil, 100))
            assert.is_false(O.Record(store, 94247, 4316, 0, 100))
            assert.is_nil(store[94247])
        end)
    end)

    describe("Orders", function()
        it("lives in the account data, created on first use", function()
            _G.AltArmyTBC_Data = {}
            local orders = O.Orders()
            assert.equals(orders, AltArmyTBC_Data.WritOrders)
            assert.equals(orders, O.Orders())
            _G.AltArmyTBC_Data = nil
            assert.same({}, O.Orders())
        end)
    end)
end)
