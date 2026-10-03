--[[ Unit tests for AuctionatorSearch.lua — run: npm test ]]

describe("AuctionatorSearch", function()
    local AZ
    local calls

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["AuctionatorSearch"] = nil
        require("AuctionatorSearch")
        AZ = AltArmy.AuctionatorSearch
        assert.truthy(AZ)
    end)

    local function shown(isShown)
        return { IsShown = function() return isShown end }
    end

    before_each(function()
        calls = {}
        _G.AuctionHouseFrame = nil
        _G.AuctionFrame = nil
        _G.Auctionator = { API = { v1 = {
            MultiSearchAdvanced = function(callerID, terms)
                calls[#calls + 1] = { callerID = callerID, terms = terms }
            end,
        } } }
    end)

    after_each(function()
        _G.Auctionator = nil
        _G.AuctionHouseFrame = nil
        _G.AuctionFrame = nil
    end)

    describe("IsAvailable", function()
        it("is true with Auctionator at the modern auction house", function()
            _G.AuctionHouseFrame = shown(true)
            assert.is_true(AZ.IsAvailable())
        end)

        it("is true with Auctionator at the legacy auction house", function()
            _G.AuctionFrame = shown(true)
            assert.is_true(AZ.IsAvailable())
        end)

        it("is false away from the auction house", function()
            assert.is_false(AZ.IsAvailable())
            _G.AuctionHouseFrame = shown(false)
            assert.is_false(AZ.IsAvailable())
        end)

        it("is false without Auctionator's search API", function()
            _G.AuctionHouseFrame = shown(true)
            _G.Auctionator = nil
            assert.is_false(AZ.IsAvailable())
            _G.Auctionator = { API = { v1 = {} } }
            assert.is_false(AZ.IsAvailable())
        end)
    end)

    describe("Search", function()
        it("hands the terms to Auctionator's temporary shopping list search", function()
            _G.AuctionHouseFrame = shown(true)
            local terms = { { searchString = "Tin Ore", quantity = 20, isExact = true } }
            assert.is_true(AZ.Search(terms))
            assert.equals(1, #calls)
            assert.equals("Alt Army", calls[1].callerID)
            assert.same(terms, calls[1].terms)
        end)

        it("does nothing when unavailable or with no terms", function()
            assert.is_false(AZ.Search({ { searchString = "Tin Ore", isExact = true } }))
            _G.AuctionHouseFrame = shown(true)
            assert.is_false(AZ.Search({}))
            assert.equals(0, #calls)
        end)

        it("returns false when Auctionator raises an error", function()
            _G.AuctionHouseFrame = shown(true)
            Auctionator.API.v1.MultiSearchAdvanced = function() error("boom") end
            assert.is_false(AZ.Search({ { searchString = "Tin Ore", isExact = true } }))
        end)
    end)
end)
