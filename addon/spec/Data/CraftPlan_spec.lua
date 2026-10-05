--[[ Unit tests for CraftPlan.lua (Economy tab: the cheapest way to buy or craft an item) — run: npm test ]]

describe("CraftPlan", function()
    local P

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["CraftPlan"] = nil
        require("CraftPlan")
        P = AltArmy.CraftPlan
        assert.truthy(P)
    end)

    local function lv(price, units, tail)
        return { price = price, units = units, listings = 1, tail = tail == true }
    end

    -- A tiny Forever: a robe from bolts (from cloth), thread (vendor) and silk (thin on the AH).
    local ITEMS = {
        [1] = { name = "Robe", stack = 1 },
        [2] = { name = "Bolt", stack = 20 },
        [3] = { name = "Cloth", stack = 20 },
        [4] = { name = "Thread", stack = 20, vendor = 100, per = 1 },
        [5] = { name = "Silk", stack = 10 },
        [6] = { name = "Tannin", stack = 20, bop = true },
        [7] = { name = "Suit", stack = 1 },
        [8] = { name = "Shot", stack = 200 },
        [9] = { name = "Ouroboros", stack = 1 },
        [10] = { name = "Thing", stack = 1 },
        [11] = { name = "Part", stack = 1 },
    }
    local RECIPES = {
        [100] = { out = 1, n = 1, prof = "Tailoring", name = "Robe",
            reagents = { { item = 2, count = 2 }, { item = 4, count = 2 }, { item = 5, count = 2 } } },
        [101] = { out = 2, n = 1, prof = "Tailoring", name = "Bolt", reagents = { { item = 3, count = 4 } } },
        [102] = { out = 7, n = 1, prof = "Leatherworking", name = "Suit", reagents = { { item = 6, count = 1 } } },
        [103] = { out = 8, n = 200, prof = "Engineering", name = "Shot", reagents = { { item = 3, count = 1 } } },
        [104] = { out = 9, n = 1, prof = "Alchemy", name = "Ouroboros", reagents = { { item = 9, count = 1 } } },
        [105] = { out = 10, n = 1, prof = "Engineering", name = "Thing",
            reagents = { { item = 2, count = 1 }, { item = 11, count = 1 } } },
        [106] = { out = 11, n = 1, prof = "Engineering", name = "Part", reagents = { { item = 2, count = 1 } } },
    }
    local KNOWN = { [100] = "Tailor", [101] = "Tailor", [102] = "Leather", [103] = "Engineer", [104] = "Alch",
        [105] = "Engineer", [106] = "Engineer" }
    local DISCOUNT = { Tailor = 0.15, Me = 0 }

    local function context(over)
        local ctx = {
            book = {
                [1] = { lv(1000, 2) },
                [2] = { lv(50, 1), lv(80, 5) },
                [3] = { lv(20, 100) },
                [4] = { lv(90, 10) },
                [5] = { lv(30, 1) },
                [6] = { lv(5, 10) },
            },
            items = ITEMS, recipes = RECIPES, byOutput = {}, current = "Me",
            knownBy = function(spell) return KNOWN[spell] end,
            discountOf = function(name) return DISCOUNT[name or "Me"] or 0 end,
        }
        for spell, r in pairs(RECIPES) do
            local list = ctx.byOutput[r.out] or {}
            list[#list + 1] = spell
            ctx.byOutput[r.out] = list
        end
        for _, list in pairs(ctx.byOutput) do table.sort(list) end
        for k, v in pairs(over or {}) do ctx[k] = v end
        return ctx
    end

    describe("VendorUnitPrice", function()
        it("takes the discount off and rounds up", function()
            assert.equals(85, P.VendorUnitPrice(ITEMS[4], 0.15))
            assert.equals(100, P.VendorUnitPrice(ITEMS[4], 0))
            assert.equals(100, P.VendorUnitPrice({ vendor = 500, per = 5 }, 0))
            assert.equals(34, P.VendorUnitPrice({ vendor = 100, per = 3 }, 0))
        end)
    end)

    describe("AhCost", function()
        it("buys cheapest first", function()
            local cost, short, approx = P.AhCost({ lv(50, 1), lv(80, 5) }, 3)
            assert.equals(210, cost)
            assert.equals(0, short)
            assert.is_false(approx)
        end)

        it("prices units the book is short of at the dearest level", function()
            local cost, short = P.AhCost({ lv(50, 1), lv(80, 5) }, 10)
            assert.equals(770, cost)
            assert.equals(4, short)
        end)

        it("skips units already taken from the ladder", function()
            assert.equals(160, P.AhCost({ lv(50, 1), lv(80, 5) }, 2, 1))
        end)

        it("is approximate from the tail", function()
            local _, _, approx = P.AhCost({ lv(50, 1), lv(80, 5, true) }, 2)
            assert.is_true(approx)
        end)

        it("is nil with nothing listed", function()
            assert.is_nil(P.AhCost(nil, 1))
            assert.is_nil(P.AhCost({}, 1))
        end)
    end)

    describe("Plan", function()
        it("crafts when that beats the auction house, pricing each reagent its cheapest way", function()
            local plan = P.Plan(1, 1, context())
            assert.equals("craft", plan.option)
            assert.equals("Tailor", plan.who)
            assert.equals(100, plan.spell)
            assert.equals(1, plan.casts)
            -- bolts: AH 50 + 80 (crafting 2 is 8 cloth = 160); thread: the Tailor's vendor price 85 x 2 beats
            -- the AH's 90 x 2; silk: one at 30, one short at 30
            assert.equals(130 + 170 + 60, plan.cost)
            assert.equals(1, plan.short)
            assert.is_false(plan.approx)
            assert.same({ "ah", "vendor", "ah" },
                { plan.children[1].option, plan.children[2].option, plan.children[3].option })
            assert.equals("Tailor", plan.children[2].who)
        end)

        it("applies the discount of whoever uses the units", function()
            -- Bought outright, the current character (no discount) pays 100 at the vendor: the AH's 90 wins
            local plan = P.Plan(4, 2, context())
            assert.equals("ah", plan.option)
            assert.equals(180, plan.cost)
            local forTailor = P.Plan(4, 2, context(), "Tailor")
            assert.equals("vendor", forTailor.option)
            assert.equals(170, forTailor.cost)
        end)

        it("buys when nobody knows the recipe", function()
            local plan = P.Plan(1, 1, context({ knownBy = function() return nil end }))
            assert.equals("ah", plan.option)
            assert.equals(1000, plan.cost)
            assert.is_nil(plan.children)
        end)

        it("never buys a bind-on-pickup item, so a craft needing one has no route", function()
            assert.is_nil(P.Plan(6, 1, context()))
            assert.is_nil(P.Plan(7, 1, context()))
        end)

        it("counts whole casts", function()
            local plan = P.Plan(8, 250, context())
            assert.equals("craft", plan.option)
            assert.equals(2, plan.casts)
            assert.equals(40, plan.cost)
            assert.equals(2, plan.children[1].qty)
        end)

        it("ends a recipe that consumes its own output", function()
            assert.is_nil(P.Plan(9, 1, context()))
        end)

        it("crafts no deeper than maxDepth", function()
            local plan = P.Plan(1, 1, context({ maxDepth = 0 }))
            assert.equals("ah", plan.option)
        end)

        it("takes a summary scan's levels as they are", function()
            local two = P.Plan(2, 2, context({ summary = true }))
            assert.is_false(two.approx)
        end)

        it("is nil with nothing to buy or craft", function()
            assert.is_nil(P.Plan(5, 1, context({ book = {} })))
        end)

        it("still plans vendor buys and crafts without a scan", function()
            local plan = P.Plan(4, 1, context({ book = {} }), "Tailor")
            assert.equals("vendor", plan.option)
            assert.equals(85, plan.cost)
        end)
    end)

    describe("Craft", function()
        it("crafts even when buying is cheaper", function()
            local plan = P.Craft(2, 1, context())
            assert.equals("craft", plan.option)
            assert.equals(80, plan.cost)
            assert.equals("ah", P.Plan(2, 1, context()).option)
        end)

        it("is nil when nobody knows a recipe or a reagent has no route", function()
            assert.is_nil(P.Craft(3, 1, context()))
            assert.is_nil(P.Craft(7, 1, context()))
        end)
    end)

    describe("Share", function()
        it("walks one ladder for the auction house buys of an item in several branches", function()
            local plan = P.Plan(10, 1, context())
            assert.equals(50 + 50, plan.cost) -- each branch took the cheapest bolt as its own
            local shared = P.Share(plan, context())
            assert.equals(50 + 80, shared.cost)
            assert.equals(80, shared.children[2].cost)
            assert.equals(80, shared.children[2].children[1].cost)
            assert.equals(100, plan.cost, "the plan given is left alone")
        end)

        it("leaves a plan with nothing shared as it is", function()
            local plan = P.Plan(1, 1, context())
            assert.equals(plan, P.Share(plan, context()))
        end)
    end)

    describe("Steps", function()
        it("lists vendor buys, auction house buys, then crafts bottom up", function()
            local steps = P.Steps(P.Plan(1, 1, context()))
            assert.same({
                { kind = "vendor", who = "Tailor", item = 4, qty = 2, cost = 170, short = 0, approx = false },
                { kind = "ah", item = 2, qty = 2, cost = 130, short = 0, approx = false },
                { kind = "ah", item = 5, qty = 2, cost = 60, short = 1, approx = false },
                { kind = "craft", who = "Tailor", item = 1, qty = 1, spell = 100, casts = 1 },
            }, steps)
        end)

        it("merges buys of one item and casts of one recipe", function()
            local steps = P.Steps(P.Share(P.Plan(10, 1, context()), context()))
            assert.same({
                { kind = "ah", item = 2, qty = 2, cost = 130, short = 0, approx = false },
                { kind = "craft", who = "Engineer", item = 11, qty = 1, spell = 106, casts = 1 },
                { kind = "craft", who = "Engineer", item = 10, qty = 1, spell = 105, casts = 1 },
            }, steps)
        end)

        it("is just the buy for a bought item", function()
            local steps = P.Steps(P.Plan(1, 1, context({ knownBy = function() return nil end })))
            assert.same({ { kind = "ah", item = 1, qty = 1, cost = 1000, short = 0, approx = false } }, steps)
        end)
    end)
end)
