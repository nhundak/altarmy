--[[ Unit tests for WaylaidCosts.lua (Economy tab, Waylaid Crates) — run: npm test ]]

describe("WaylaidCosts", function()
    local W

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["WaylaidCosts"] = nil
        require("WaylaidCosts")
        W = AltArmy.WaylaidCosts
        assert.truthy(W)
    end)

    local function lv(price, units, tail)
        return { price = price, units = units, listings = 1, tail = tail == true }
    end

    describe("CostForUnits", function()
        it("buys the cheapest units first", function()
            assert.equals(60, W.CostForUnits({ lv(10, 3), lv(15, 9) }, 5))
        end)

        it("fits exactly on a level boundary", function()
            assert.equals(30, W.CostForUnits({ lv(10, 3), lv(15, 9) }, 3))
        end)

        it("is nil when too few units are listed", function()
            assert.is_nil(W.CostForUnits({ lv(10, 3) }, 4))
            assert.is_nil(W.CostForUnits(nil, 1))
        end)

        it("prices the tail at its cheapest price and says so", function()
            local cost, approx = W.CostForUnits({ lv(10, 1), lv(20, 5, true) }, 3)
            assert.equals(50, cost)
            assert.is_true(approx)
            local _, exact = W.CostForUnits({ lv(10, 1), lv(20, 5, true) }, 1)
            assert.is_false(exact)
        end)

        it("costs nothing for no units", function()
            assert.equals(0, W.CostForUnits({}, 0))
        end)
    end)

    local CRATES = {
        GENERIC = 900,
        LIST = {},
        ById = {
            [900] = { id = 900, name = "Waylaid Crate", short = "Waylaid Crate (unread)", random = true, bundles = {} },
            [901] = { id = 901, name = "Waylaid Crate: Apprentice Ore", short = "Apprentice Ore", tier = "Apprentice",
                kind = "Gathered", bundles = { { item = 1, count = 20, name = "Copper Ore" },
                    { item = 2, count = 20, name = "Tin Ore" } } },
            [902] = { id = 902, name = "Waylaid Crate: Expert Ingots", short = "Expert Ingots", tier = "Expert",
                kind = "Crafted", bundles = { { item = 3, count = 10, name = "Gold Bar" } } },
            [903] = { id = 903, name = "Waylaid Crate: Artisan Parts", short = "Artisan Parts", tier = "Artisan",
                kind = "Crafted", bundles = { { item = 4, count = 5, name = "Thorium Widget" } } },
        },
    }
    for _, id in ipairs({ 900, 901, 902, 903 }) do
        CRATES.LIST[#CRATES.LIST + 1] = CRATES.ById[id]
    end

    local function byId(rows)
        local out = {}
        for _, r in ipairs(rows) do
            out[r.id] = r
        end
        return out
    end

    describe("BuildRows", function()
        local book = {
            [900] = { lv(500, 4) },
            [901] = { lv(1000, 1), lv(1200, 2) },
            [902] = { lv(3000, 1) },
            [1] = { lv(50, 20) }, -- Copper Ore: 1000c for 20
            [2] = { lv(30, 25) }, -- Tin Ore: 600c for 20, cheaper
            [3] = { lv(900, 4) }, -- Gold Bar: only 4 of 10 listed
        }

        it("lists only the crates on the auction house", function()
            local rows = byId(W.BuildRows(book, CRATES))
            assert.truthy(rows[900])
            assert.truthy(rows[901])
            assert.truthy(rows[902])
            assert.is_nil(rows[903])
        end)

        it("fills with the cheapest bundle and adds the cheapest crate", function()
            local r = byId(W.BuildRows(book, CRATES))[901]
            assert.equals(1000, r.price)
            assert.equals(3, r.listed)
            assert.equals("Tin Ore", r.bundle.name)
            assert.equals(600, r.bundle.cost)
            assert.equals(1600, r.total)
            assert.equals("20 x Tin Ore", r.bundleText)
            assert.equals("Gathered", r.kind)
            assert.equals("Apprentice", r.tier)
        end)

        it("has no total when no bundle can be bought in full", function()
            local r = byId(W.BuildRows(book, CRATES))[902]
            assert.is_nil(r.bundle)
            assert.is_nil(r.total)
            assert.equals(1, r.shortBundles)
            assert.equals("not enough listed", r.bundleText)
        end)

        it("says when no bundle item is listed at all", function()
            local r = byId(W.BuildRows({ [901] = { lv(1000, 1) } }, CRATES))[901]
            assert.is_nil(r.total)
            assert.equals(2, r.unlisted)
            assert.equals("none listed", r.bundleText)
        end)

        it("prices an unread crate without a fill", function()
            local r = byId(W.BuildRows(book, CRATES))[900]
            assert.equals(500, r.price)
            assert.is_true(r.random)
            assert.is_nil(r.total)
            assert.equals("random", r.bundleText)
        end)

        it("keeps every bundle's cost for the tooltip, cheapest first", function()
            local rows = byId(W.BuildRows(book, CRATES))
            assert.equals(2, #rows[901].options)
            assert.equals("Tin Ore", rows[901].options[1].name)
            assert.equals(600, rows[901].options[1].cost)
            assert.equals("Copper Ore", rows[901].options[2].name)
            assert.equals(1000, rows[901].options[2].cost)
            assert.is_nil(rows[902].options[1].cost)
            assert.equals(4, rows[902].options[1].listed)
        end)

        it("lists bundles that cannot be bought after the priced ones", function()
            local r = byId(W.BuildRows({ [901] = { lv(1000, 1) }, [2] = { lv(30, 25) } }, CRATES))[901]
            assert.equals("Tin Ore", r.options[1].name)
            assert.equals("Copper Ore", r.options[2].name)
            assert.is_nil(r.options[2].cost)
        end)
    end)

    describe("Compare", function()
        local a = { name = "A", tier = "Apprentice", price = 10, total = 100,
            bundle = { name = "Tin Ore", cost = 90 } }
        local b = { name = "B", tier = "Expert", price = 20, total = 50,
            bundle = { name = "Gold Bar", cost = 30 } }
        local n = { name = "C", tier = "Artisan", price = 5 }

        local function sorted(key, asc)
            local rows = { a, b, n }
            table.sort(rows, function(x, y) return W.Compare(x, y, key, asc) end)
            return { rows[1].name, rows[2].name, rows[3].name }
        end

        it("sorts by total, rows without a total last either way", function()
            assert.same({ "B", "A", "C" }, sorted("total", true))
            assert.same({ "A", "B", "C" }, sorted("total", false))
        end)

        it("sorts by fill cost and fill name, rows without a fill last", function()
            assert.same({ "B", "A", "C" }, sorted("bundleCost", true))
            assert.same({ "A", "B", "C" }, sorted("bundleCost", false))
            assert.same({ "B", "A", "C" }, sorted("bundle", true))
        end)

        it("sorts by crate price", function()
            assert.same({ "C", "A", "B" }, sorted("price", true))
        end)

        it("sorts crates by tier in game order", function()
            assert.same({ "A", "B", "C" }, sorted("crate", true))
            assert.same({ "C", "B", "A" }, sorted("crate", false))
        end)
    end)

    describe("AgeText", function()
        local function fmt(s)
            return s .. "s"
        end

        it("says how long ago the scan was taken", function()
            assert.equals("Scanned 120s ago", W.AgeText(1000, 1120, fmt))
        end)

        it("says just now within a minute, or if the clock went back", function()
            assert.equals("Scanned just now", W.AgeText(1000, 1030, fmt))
            assert.equals("Scanned just now", W.AgeText(1000, 900, fmt))
        end)
    end)

    describe("AgeLevel", function()
        it("is fresh under 15 minutes, stale up to 30, then old", function()
            assert.equals("fresh", W.AgeLevel(1000, 1000 + 14 * 60 + 59))
            assert.equals("stale", W.AgeLevel(1000, 1000 + 15 * 60))
            assert.equals("stale", W.AgeLevel(1000, 1000 + 30 * 60))
            assert.equals("old", W.AgeLevel(1000, 1000 + 30 * 60 + 1))
        end)

        it("is fresh if the clock went back", function()
            assert.equals("fresh", W.AgeLevel(1000, 900))
        end)
    end)

    describe("EnsureOptions", function()
        it("defaults to the currency view, crates sorted by total", function()
            _G.AltArmyTBC_Options = nil
            local o = W.EnsureOptions()
            assert.equals("currency", o.activeView)
            assert.equals("total", o.waylaidSortKey)
            assert.is_true(o.waylaidSortAscending)
            assert.equals(o, AltArmyTBC_Options.economy)
        end)

        it("keeps saved choices and repairs bad ones", function()
            _G.AltArmyTBC_Options = { economy = { activeView = "supply", waylaidSortKey = "bogus",
                waylaidSortAscending = false } }
            local o = W.EnsureOptions()
            assert.equals("supply", o.activeView)
            assert.equals("total", o.waylaidSortKey)
            assert.is_false(o.waylaidSortAscending)
            _G.AltArmyTBC_Options.economy.activeView = "nope"
            assert.equals("currency", W.EnsureOptions().activeView)
            _G.AltArmyTBC_Options.economy.activeView = "waylaid"
            assert.equals("waylaid", W.EnsureOptions().activeView)
        end)
    end)
end)
