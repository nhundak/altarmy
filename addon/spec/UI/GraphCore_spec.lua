--[[
  Unit tests for GraphCore.lua duration axis formatting.
  Run from project root: npm test
]]

describe("GraphCore", function()
    local Core

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
        package.loaded["GraphCore"] = nil
        require("GraphCore")
        Core = AltArmy.GraphCore
    end)

    describe("FormatDurationAxis", function()
        it("formats seconds and minutes", function()
            assert.are.equal("0s", Core.FormatDurationAxis(0))
            assert.are.equal("45s", Core.FormatDurationAxis(45))
            assert.are.equal("30m", Core.FormatDurationAxis(1800))
        end)

        it("formats whole hours without minutes", function()
            assert.are.equal("1h", Core.FormatDurationAxis(3600))
            assert.are.equal("2h", Core.FormatDurationAxis(7200))
        end)

        it("formats hours and minutes with a space", function()
            assert.are.equal("1h 30m", Core.FormatDurationAxis(5400))
        end)

        it("formats whole days for multi-day axis ticks", function()
            assert.are.equal("2d", Core.FormatDurationAxis(86400 * 2))
            assert.are.equal("4d", Core.FormatDurationAxis(86400 * 4))
            assert.are.equal("256d", Core.FormatDurationAxis(86400 * 256))
        end)
    end)
end)
