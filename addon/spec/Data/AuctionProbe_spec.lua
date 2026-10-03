--[[ Unit tests for AuctionProbe.lua — run: npm test ]]

describe("AuctionProbe", function()
    local P
    local timers
    local rows
    local requested

    -- One replicate row as C_AuctionHouse.GetReplicateItemInfo returns it (18 values).
    local function row(itemID, count, buyout, owner, hasAllInfo)
        return {
            info = { "Item " .. itemID, 134400, count, 1, true, 10, "", 100, 5, buyout, 0, nil, nil, owner,
                nil, 0, itemID, hasAllInfo ~= false },
            link = "|Hitem:" .. itemID .. "::::::::60:::::|h[Item]|h",
            timeLeft = 3,
        }
    end

    local function installApi()
        _G.C_AuctionHouse = {
            ReplicateItems = function() requested = requested + 1 end,
            GetNumReplicateItems = function() return #rows end,
            GetReplicateItemInfo = function(i)
                local r = rows[i + 1]
                if not r then return nil end
                return unpack(r.info, 1, 18)
            end,
            GetReplicateItemLink = function(i) return rows[i + 1] and rows[i + 1].link end,
            GetReplicateItemTimeLeft = function(i) return rows[i + 1] and rows[i + 1].timeLeft end,
        }
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.CreateFrame = function()
            return {
                RegisterEvent = function() end,
                UnregisterEvent = function() end,
                SetScript = function() end,
            }
        end
        package.path = package.path .. ";AltArmy_TBC/Data/Auctions/?.lua;AltArmy_TBC/Data/?.lua"
        package.loaded["Debug"] = nil
        package.loaded["AuctionProbe"] = nil
        require("Debug")
        require("AuctionProbe")
        P = AltArmy.AuctionProbe
        assert.truthy(P)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        AltArmy.Debug.Ensure()
        timers = {}
        rows = {}
        requested = 0
        _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
        _G.GetServerTime = function() return 7000 end
        _G.GetRealmName = function() return "Classic Beta PvE" end
        _G.UnitFactionGroup = function() return "Horde" end
        _G.GetBuildInfo = function() return "1.60.1", "69913", "Sep 1 2026", 16001 end
        installApi()
        P._ResetForTests()
    end)

    local function saved()
        return AltArmyTBC_Options.debug.auctionProbe
    end

    it("says the API is missing without asking for a scan", function()
        _G.C_AuctionHouse = { GetNumOwnedAuctions = function() return 0 end }
        local ok, reason = P.Start()
        assert.is_false(ok)
        assert.equals("missing", reason)
        assert.same({ "ReplicateItems", "GetNumReplicateItems", "GetReplicateItemInfo",
            "GetReplicateItemLink", "GetReplicateItemTimeLeft" }, saved().missing)
        assert.equals("missing", saved().outcome)
        assert.equals(16001, saved().interface)
    end)

    it("asks for the listings once and waits for them", function()
        assert.is_true((P.Start()))
        assert.equals(1, requested)
        assert.is_true(P.IsWaiting())
        local ok, reason = P.Start()
        assert.is_false(ok)
        assert.equals("waiting", reason)
        assert.equals(1, requested)
    end)

    it("records how many listings came back and which fields they carry", function()
        rows = { row(2770, 20, 3340, "Seller"), row(2770, 5, 320, nil), row(7067, 1, 700, nil, false) }
        P.Start()
        P.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
        local got = saved()
        assert.equals("listed", got.outcome)
        assert.equals(3, got.listings)
        assert.equals(3, got.read)
        assert.same({ name = 3, count = 3, buyout = 3, minBid = 3, owner = 1, itemID = 3, hasAllInfo = 2,
            link = 3, timeLeft = 3 }, got.fields)
        assert.equals(7000, got.t)
        assert.equals("Classic Beta PvE", got.realm)
        assert.equals("Horde", got.faction)
        assert.is_false(P.IsWaiting())
    end)

    it("keeps the first rows as a sample", function()
        for i = 1, P.SAMPLE + 10 do
            rows[i] = row(1000 + i, 1, 100 * i, nil)
        end
        P.Start()
        P.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
        local got = saved()
        assert.equals(P.SAMPLE, #got.sample)
        assert.same({ itemID = 1001, count = 1, buyout = 100, minBid = 100, timeLeft = 3, hasAllInfo = true,
            name = "Item 1001", link = rows[1].link }, got.sample[1])
        assert.equals(P.SAMPLE + 10, got.read)
    end)

    it("reads no more rows than its limit", function()
        for i = 1, P.MAX_READ + 5 do
            rows[i] = row(2770, 1, 100, nil)
        end
        P.Start()
        P.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
        assert.equals(P.MAX_READ + 5, saved().listings)
        assert.equals(P.MAX_READ, saved().read)
    end)

    it("ignores listings nobody asked it for", function()
        rows = { row(2770, 20, 3340, nil) }
        P.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
        assert.is_nil(saved())
    end)

    it("records a closed auction house as the reason nothing came", function()
        P.Start()
        P.OnEvent("AUCTION_HOUSE_CLOSED")
        assert.equals("closed", saved().outcome)
        assert.is_false(P.IsWaiting())
    end)

    it("gives up when the listings never come", function()
        P.Start()
        assert.equals(P.TIMEOUT, timers[1].seconds)
        timers[1].fn()
        assert.equals("timeout", saved().outcome)
        assert.is_false(P.IsWaiting())
    end)

    it("leaves a finished probe alone when its timer fires", function()
        rows = { row(2770, 20, 3340, nil) }
        P.Start()
        P.OnEvent("REPLICATE_ITEM_LIST_UPDATE")
        timers[1].fn()
        assert.equals("listed", saved().outcome)
    end)

    it("records an error the client raises instead of failing", function()
        _G.C_AuctionHouse.ReplicateItems = function() error("not at an auction house") end
        local ok, reason = P.Start()
        assert.is_false(ok)
        assert.equals("error", reason)
        assert.equals("error", saved().outcome)
        assert.truthy(saved().error:find("not at an auction house", 1, true))
    end)
end)
