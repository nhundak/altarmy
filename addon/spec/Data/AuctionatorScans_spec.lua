--[[ Unit tests for AuctionatorScans.lua — run: npm test ]]

describe("AuctionatorScans", function()
    local AS
    local faction

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.CreateFrame = _G.CreateFrame or function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
            }
        end
        package.loaded["AuctionatorScans"] = nil
        require("AuctionatorScans")
        AS = AltArmy.AuctionatorScans
        assert.truthy(AS)
    end)

    before_each(function()
        faction = "Horde"
        _G.AltArmyTBC_AuctionScans = nil
        _G.Auctionator = nil
        _G.time = function() return 5000 end
        _G.GetRealmName = function() return "Dream Scythe" end
        _G.UnitFactionGroup = function() return faction end
        AS._ResetForTests()
    end)

    it("records the faction, realm and Auctionator's realm key", function()
        _G.Auctionator = { State = { CurrentRealm = "DreamScythe" } }
        AS.Record(1000)
        assert.same({ version = 1, scans = {
            { t = 1000, faction = "Horde", realm = "Dream Scythe", key = "DreamScythe" },
        } }, AltArmyTBC_AuctionScans)
    end)

    it("falls back to the realm name without Auctionator's state", function()
        AS.Record(1000)
        assert.equals("Dream Scythe", AltArmyTBC_AuctionScans.scans[1].key)
    end)

    it("coalesces updates on the same key and faction within five minutes", function()
        AS.Record(1000)
        AS.Record(1000 + 299)
        assert.equals(1, #AltArmyTBC_AuctionScans.scans)
        assert.equals(1299, AltArmyTBC_AuctionScans.scans[1].t)
        AS.Record(1299 + 300)
        assert.equals(2, #AltArmyTBC_AuctionScans.scans)
    end)

    it("starts a new entry when the faction changes", function()
        AS.Record(1000)
        faction = "Alliance"
        AS.Record(1010)
        assert.equals(2, #AltArmyTBC_AuctionScans.scans)
        assert.equals("Alliance", AltArmyTBC_AuctionScans.scans[2].faction)
    end)

    it("skips a character without a faction", function()
        faction = nil
        AS.Record(1000)
        assert.equals(0, #AS.GetLog().scans)
    end)

    it("drops entries older than 30 days and keeps at most 50", function()
        AS.Record(1000)
        AS.Record(1000 + AS.MAX_AGE + 1000)
        assert.equals(1, #AltArmyTBC_AuctionScans.scans)
        for i = 1, 60 do
            AS.Record(1000 + AS.MAX_AGE + 1000 + i * 600)
        end
        local scans = AltArmyTBC_AuctionScans.scans
        assert.equals(50, #scans)
        assert.equals(1000 + AS.MAX_AGE + 1000 + 60 * 600, scans[#scans].t)
    end)

    it("replaces a malformed log", function()
        _G.AltArmyTBC_AuctionScans = { scans = "nope" }
        AS.Record(1000)
        assert.equals(1, #AltArmyTBC_AuctionScans.scans)
    end)

    it("does not register without Auctionator", function()
        assert.is_false(AS.Register())
    end)

    it("registers for Auctionator's database updates, once", function()
        local calls = {}
        _G.Auctionator = { API = { v1 = { RegisterForDBUpdate = function(id, callback)
            calls[#calls + 1] = { id = id, callback = callback }
        end } } }
        assert.is_true(AS.Register())
        assert.is_true(AS.Register())
        assert.equals(1, #calls)
        assert.equals("AltArmy", calls[1].id)
        calls[1].callback()
        assert.equals(1, #AltArmyTBC_AuctionScans.scans)
    end)
end)
