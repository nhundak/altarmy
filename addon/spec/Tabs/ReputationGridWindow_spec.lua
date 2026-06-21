--[[
  Unit tests for ReputationGridWindow.lua (column windowing + bar fill width math).
]]

describe("ReputationGridWindow", function()
    local RGW

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        assert(loadfile("AltArmy_TBC/ReputationGridWindow.lua"))()
        RGW = AltArmy.ReputationGridWindow
    end)

    describe("GetVisibleColumnRange", function()
        it("returns first visible column through last for offset 0", function()
            local first, last = RGW.GetVisibleColumnRange(0, 280, 70, 12, 0)
            assert.are.equal(1, first)
            assert.are.equal(4, last)
        end)

        it("clamps last to numCols when offset is large", function()
            local first, last = RGW.GetVisibleColumnRange(700, 280, 70, 12, 0)
            assert.are.equal(11, first)
            assert.are.equal(12, last)
        end)

        it("returns (1, 0) when numCols is 0", function()
            local first, last = RGW.GetVisibleColumnRange(0, 280, 70, 0, 2)
            assert.are.equal(1, first)
            assert.are.equal(0, last)
        end)

        it("widens range by buffer on both sides", function()
            local first, last = RGW.GetVisibleColumnRange(140, 280, 70, 20, 2)
            assert.are.equal(1, first)
            assert.are.equal(8, last)
        end)

        it("keeps the same range for small offset changes within one column", function()
            local f1, l1 = RGW.GetVisibleColumnRange(10, 280, 70, 20, 2)
            local f2, l2 = RGW.GetVisibleColumnRange(35, 280, 70, 20, 2)
            assert.are.equal(f1, f2)
            assert.are.equal(l1, l2)
        end)
    end)

    describe("BarFillWidth", function()
        it("returns 1 for pct 0 (minimum floor)", function()
            assert.are.equal(1, RGW.BarFillWidth(0, 58))
        end)

        it("returns half width for pct 50", function()
            assert.are.equal(29, RGW.BarFillWidth(50, 58))
        end)

        it("returns full width for pct 100", function()
            assert.are.equal(58, RGW.BarFillWidth(100, 58))
        end)

        it("clamps pct above 100", function()
            assert.are.equal(58, RGW.BarFillWidth(150, 58))
        end)

        it("clamps negative pct to floor of 1", function()
            assert.are.equal(1, RGW.BarFillWidth(-10, 58))
        end)
    end)
end)
