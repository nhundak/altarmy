--[[ Unit tests for AuctionBook.lua — run: npm test ]]

describe("AuctionBook", function()
    local B

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["AuctionBook"] = nil
        require("AuctionBook")
        B = AltArmy.AuctionBook
        assert.truthy(B)
    end)

    before_each(function()
        _G.AltArmyTBC_AuctionBook = nil
    end)

    local function tally(listings)
        local t = B.NewTally()
        for _, l in ipairs(listings) do
            B.Add(t, l[1], l[2], l[3])
        end
        return t
    end

    describe("Add", function()
        it("prices a stack per unit, rounded up", function()
            local t = tally({ { 5631, 39, 10686 } })
            assert.equals("5631:274*39*1", B.Encode(t))
        end)

        it("pools listings at the same unit price", function()
            local t = tally({ { 2770, 20, 3340 }, { 2770, 5, 835 }, { 2770, 1, 64 } })
            assert.equals("2770:64*1*1,167*25*2", B.Encode(t))
            assert.equals(3, t.listings)
        end)

        it("counts a listing without a buyout but does not price it", function()
            local t = tally({ { 2770, 20, 0 }, { 2770, 1, 64 } })
            assert.equals("2770:64*1*1", B.Encode(t))
            assert.equals(2, t.listings)
            assert.equals(1, t.bidOnly)
        end)

        it("skips rows the client returned without an item, count or buyout", function()
            local t = tally({ { nil, 1, 100 }, { 2770, 0, 100 }, { 2770, nil, 100 }, { 0, 1, 100 },
                { 2770, 1, nil } })
            assert.equals("", B.Encode(t))
            assert.equals(0, t.listings)
        end)
    end)

    describe("Encode", function()
        it("lists items by id and levels cheapest first", function()
            local t = tally({ { 7067, 1, 12000 }, { 2770, 1, 167 }, { 7067, 1, 700 }, { 2770, 1, 64 } })
            assert.equals("2770:64*1*1,167*1*1;7067:700*1*1,12000*1*1", B.Encode(t))
        end)

        it("folds the levels past the limit into a tail at their cheapest price", function()
            local listings = {}
            for i = 1, B.MAX_LEVELS + 3 do
                listings[#listings + 1] = { 2770, 2, 2 * (100 + i) }
            end
            local text = B.Encode(tally(listings))
            local levels = {}
            for level in text:gmatch("[^,]+") do
                levels[#levels + 1] = level
            end
            assert.equals(B.MAX_LEVELS + 1, #levels)
            assert.equals("2770:101*2*1", levels[1])
            assert.equals("~" .. (100 + B.MAX_LEVELS + 1) .. "*6*3", levels[#levels])
        end)
    end)

    describe("Store", function()
        local function scan(t, realm, faction)
            return { t = t, realm = realm or "Classic Beta PvE", faction = faction or "Horde",
                complete = true, listings = 1, bidOnly = 0, source = "own", items = "2770:64*1*1" }
        end

        it("creates the log on first use", function()
            B.Store(scan(1000), 1000)
            assert.equals(B.VERSION, AltArmyTBC_AuctionBook.version)
            assert.equals(1, #AltArmyTBC_AuctionBook.scans)
            assert.equals(1000, AltArmyTBC_AuctionBook.scans[1].t)
        end)

        it("keeps only the newest scans of an auction house", function()
            for i = 1, B.MAX_SCANS + 2 do
                B.Store(scan(1000 * i), 1000 * i)
            end
            local scans = AltArmyTBC_AuctionBook.scans
            assert.equals(B.MAX_SCANS, #scans)
            assert.equals(3000, scans[1].t)
            assert.equals(1000 * (B.MAX_SCANS + 2), scans[#scans].t)
        end)

        it("counts each realm and faction on its own", function()
            for i = 1, B.MAX_SCANS do
                B.Store(scan(1000 * i), 1000 * i)
            end
            B.Store(scan(9000, "Classic Beta PvE", "Alliance"), 9000)
            B.Store(scan(9500, "Classic Beta PvP 2", "Horde"), 9500)
            assert.equals(B.MAX_SCANS + 2, #AltArmyTBC_AuctionBook.scans)
        end)

        it("drops scans past their age", function()
            B.Store(scan(1000), 1000)
            B.Store(scan(2000 + B.MAX_AGE), 2000 + B.MAX_AGE)
            local scans = AltArmyTBC_AuctionBook.scans
            assert.equals(1, #scans)
            assert.equals(2000 + B.MAX_AGE, scans[1].t)
        end)

        it("replaces a log it cannot read", function()
            _G.AltArmyTBC_AuctionBook = "garbage"
            B.Store(scan(1000), 1000)
            assert.equals(1, #AltArmyTBC_AuctionBook.scans)
        end)
    end)

    describe("the client's cooldown", function()
        it("is none before any request", function()
            assert.equals(0, B.CooldownLeft(5000))
        end)

        it("counts down from the last request, whoever made it", function()
            B.NoteRequest(5000)
            assert.equals(B.COOLDOWN, B.CooldownLeft(5000))
            assert.equals(B.COOLDOWN - 60, B.CooldownLeft(5060))
            assert.equals(0, B.CooldownLeft(5000 + B.COOLDOWN))
            assert.equals(0, B.CooldownLeft(5000 + B.COOLDOWN + 99))
        end)

        it("is none when the clock went backwards", function()
            B.NoteRequest(5000)
            assert.equals(0, B.CooldownLeft(100))
        end)
    end)
end)
