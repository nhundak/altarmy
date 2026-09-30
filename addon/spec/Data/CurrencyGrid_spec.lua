--[[ Unit tests for CurrencyGrid.lua (Economy tab, Currency view) — run: npm test ]]

describe("CurrencyGrid", function()
    local G

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["CurrencyGrid"] = nil
        require("CurrencyGrid")
        G = AltArmy.CurrencyGrid
        assert.truthy(G)
    end)

    local META = {
        [1901] = { name = "Honor Points", header = "Player vs. Player", headerOrder = 1, order = 2 },
        [1900] = { name = "Arena Points", header = "Player vs. Player", headerOrder = 1, order = 3 },
        [3001] = { name = "Merchant's Favor", header = "Miscellaneous", headerOrder = 2, order = 5 },
    }

    local function names(rows)
        local out = {}
        for _, r in ipairs(rows) do
            out[#out + 1] = r.isHeader and ("# " .. r.name) or r.name
        end
        return out
    end

    describe("BuildRows", function()
        it("groups the union of currencies under headers in native order", function()
            local rows = G.BuildRows({
                { CurrencyList = { [3001] = 4 } },
                { CurrencyList = { [1900] = 0, [1901] = 10 } },
            }, META)
            assert.are.same({ "# Player vs. Player", "Honor Points", "Arena Points",
                "# Miscellaneous", "Merchant's Favor" }, names(rows))
            assert.equals(1901, rows[2].currencyID)
        end)

        it("names a currency with no details by its id, in an Other group last", function()
            local rows = G.BuildRows({ { CurrencyList = { [42] = 1, [3001] = 1 } } }, META)
            assert.are.same({ "# Miscellaneous", "Merchant's Favor", "# Other", "#42" }, names(rows))
        end)

        it("puts a Gold row first, before any header, when asked", function()
            local rows = G.BuildRows({ { CurrencyList = { [3001] = 4 } }, {} }, META, { gold = true })
            assert.are.same({ "Gold", "# Miscellaneous", "Merchant's Favor" }, names(rows))
            assert.is_true(rows[1].isGold)
            assert.equals(G.GOLD_ID, rows[1].currencyID)
        end)

        it("shows Gold alone when characters have no currency data", function()
            assert.are.same({ "Gold" }, names(G.BuildRows({ {} }, META, { gold = true })))
            assert.are.same({}, G.BuildRows({}, META, { gold = true }))
        end)

        it("is empty when nobody has currency data", function()
            assert.are.same({}, G.BuildRows({ {}, { CurrencyList = {} } }, META))
            assert.are.same({}, G.BuildRows({}, nil))
        end)
    end)

    describe("FilterRows", function()
        local function rows()
            return G.BuildRows({ { CurrencyList = { [1900] = 1, [1901] = 1, [3001] = 1 } } }, META,
                { gold = true })
        end

        it("keeps every row for an empty or blank filter", function()
            assert.equals(6, #G.FilterRows(rows(), ""))
            assert.equals(6, #G.FilterRows(rows(), "   "))
            assert.equals(6, #G.FilterRows(rows(), nil))
        end)

        it("keeps matching currencies (case-insensitive substring) under their headers", function()
            assert.are.same({ "# Player vs. Player", "Honor Points", "Arena Points" },
                names(G.FilterRows(rows(), " POINTS ")))
            assert.are.same({ "# Miscellaneous", "Merchant's Favor" }, names(G.FilterRows(rows(), "favor")))
        end)

        it("matches Gold like any currency, and treats the filter as plain text", function()
            assert.are.same({ "Gold" }, names(G.FilterRows(rows(), "gol")))
            assert.are.same({}, G.FilterRows(rows(), "%a"))
            assert.are.same({ "# Miscellaneous", "Merchant's Favor" }, names(G.FilterRows(rows(), "t's")))
        end)

        it("drops headers whose currencies don't match, even if the header name does", function()
            assert.are.same({}, G.FilterRows(rows(), "miscellaneous"))
        end)
    end)

    describe("SortRowsForCharacter", function()
        local function rows()
            return G.BuildRows({ { CurrencyList = { [1900] = 1, [1901] = 1, [3001] = 1 } } }, META)
        end

        it("sorts within each header group and keeps headers in place", function()
            local amounts = { [1901] = 5, [1900] = 50, [3001] = 1 }
            local sorted = G.SortRowsForCharacter(rows(), function(id) return amounts[id] end, true)
            assert.are.same({ "# Player vs. Player", "Arena Points", "Honor Points",
                "# Miscellaneous", "Merchant's Favor" }, names(sorted))
            sorted = G.SortRowsForCharacter(rows(), function(id) return amounts[id] end, false)
            assert.are.same({ "# Player vs. Player", "Honor Points", "Arena Points",
                "# Miscellaneous", "Merchant's Favor" }, names(sorted))
        end)

        it("keeps Gold at the top", function()
            local rows = G.BuildRows({ { CurrencyList = { [1900] = 1, [1901] = 1 } } }, META, { gold = true })
            local amounts = { [G.GOLD_ID] = 1, [1901] = 5, [1900] = 50 }
            for _, high in ipairs({ true, false }) do
                local sorted = G.SortRowsForCharacter(rows, function(id) return amounts[id] end, high)
                assert.equals("Gold", sorted[1].name)
                assert.equals("# Player vs. Player", names(sorted)[2])
            end
        end)

        it("puts currencies the character has no record of last, either direction", function()
            local amounts = { [1900] = 3 }
            for _, high in ipairs({ true, false }) do
                local sorted = G.SortRowsForCharacter(rows(), function(id) return amounts[id] end, high)
                assert.equals("Arena Points", sorted[2].name)
            end
        end)
    end)

    describe("CompareByAmount", function()
        local a, b, c = { name = "A" }, { name = "B" }, { name = "C" }
        local amounts = { A = 10, B = 20 }
        local function amountOf(e) return amounts[e.name] end
        local function byName(x, y) return x.name < y.name end

        it("orders by amount in either direction", function()
            assert.is_true(G.CompareByAmount(b, a, amountOf, true, byName))
            assert.is_false(G.CompareByAmount(a, b, amountOf, true, byName))
            assert.is_true(G.CompareByAmount(a, b, amountOf, false, byName))
        end)

        it("sorts characters with no data last", function()
            assert.is_true(G.CompareByAmount(a, c, amountOf, true, byName))
            assert.is_true(G.CompareByAmount(a, c, amountOf, false, byName))
            assert.is_false(G.CompareByAmount(c, a, amountOf, false, byName))
        end)

        it("falls back to the tie-break", function()
            amounts.C = 10
            assert.is_true(G.CompareByAmount(a, c, amountOf, true, byName))
            assert.is_false(G.CompareByAmount(c, a, amountOf, true, byName))
            amounts.C = nil
        end)
    end)

    describe("FormatAmount", function()
        it("groups thousands", function()
            assert.equals("0", G.FormatAmount(0))
            assert.equals("999", G.FormatAmount(999))
            assert.equals("1,500", G.FormatAmount(1500))
            assert.equals("12,345,678", G.FormatAmount(12345678))
        end)

        it("shows a dash for no data", function()
            assert.equals("—", G.FormatAmount(nil))
        end)
    end)

    describe("MoneyVariants", function()
        local ICONS = { gold = "g", silver = "s", copper = "c" }

        it("lists full, then without copper, then without silver", function()
            assert.are.same({ "12,345g 67s 89c", "12,345g 67s", "12,345g" },
                G.MoneyVariants(123456789, ICONS))
        end)

        it("keeps zero silver and copper once there is gold", function()
            assert.are.same({ "1g 0s 5c", "1g 0s", "1g" }, G.MoneyVariants(10005, ICONS))
        end)

        it("skips leading zeros and always keeps one part", function()
            assert.are.same({ "67s 89c", "67s" }, G.MoneyVariants(6789, ICONS))
            assert.are.same({ "0c" }, G.MoneyVariants(0, ICONS))
        end)

        it("is a dash with no data", function()
            assert.are.same({ "—" }, G.MoneyVariants(nil, ICONS))
        end)
    end)

    describe("EnsureSettings", function()
        it("creates defaults under the economy options", function()
            _G.AltArmyTBC_Options = nil
            local s = G.EnsureSettings()
            assert.is_true(s.showSelfFirst)
            assert.is_true(s.scoreSortDescending)
            assert.are.same({}, s.characters)
            assert.equals(s, AltArmyTBC_Options.economy.currency)
        end)

        it("keeps saved choices and repairs bad ones", function()
            _G.AltArmyTBC_Options = { economy = { currency = { showSelfFirst = false,
                scoreSortDescending = "x", characters = 5 } } }
            local s = G.EnsureSettings()
            assert.is_false(s.showSelfFirst)
            assert.is_true(s.scoreSortDescending)
            assert.are.same({}, s.characters)
        end)
    end)
end)
