--[[
  Unit tests for ProgressionGraphLogic.lua.
  Run from project root: npm test
]]

describe("ProgressionGraphLogic", function()
    local Logic

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Tabs/?.lua"
        package.loaded["ProgressionGraphLogic"] = nil
        require("ProgressionGraphLogic")
        Logic = AltArmy.ProgressionGraphLogic
    end)

    describe("ComputeSeriesAlphas", function()
        it("returns full alphas when not dimming others", function()
            local line, dash, marker = Logic.ComputeSeriesAlphas(false, false)
            assert.are.equal(0.9, line)
            assert.are.equal(0.55, dash)
            assert.are.equal(1, marker)
        end)

        it("returns full alphas for hovered series when dimming", function()
            local line, dash, marker = Logic.ComputeSeriesAlphas(true, true)
            assert.are.equal(0.9, line)
            assert.are.equal(0.55, dash)
            assert.are.equal(1, marker)
        end)

        it("returns dim alphas for non-hovered series when dimming", function()
            local line, dash, marker = Logic.ComputeSeriesAlphas(true, false)
            assert.are.equal(0.22, line)
            assert.are.equal(0.14, dash)
            assert.are.equal(0.35, marker)
        end)
    end)

    describe("HoverNeedsRebuild", function()
        local drawnKeys = { ["Realm\\Bob"] = true }

        it("returns false when hovered key is already drawn", function()
            assert.is_false(Logic.HoverNeedsRebuild("Realm\\Bob", drawnKeys, 5000, 1000))
        end)

        it("returns false when hovered key is nil", function()
            assert.is_false(Logic.HoverNeedsRebuild(nil, drawnKeys, 5000, 1000))
        end)

        it("returns false when new series fits within current scale", function()
            assert.is_false(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 800, 1000))
        end)

        it("returns true when new series exceeds current scale", function()
            assert.is_true(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 1500, 1000))
        end)

        it("returns false when new series equals current scale", function()
            assert.is_false(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 1000, 1000))
        end)
    end)

    describe("ComputeLinearYAxis", function()
        it("pads the max value by 8 percent with a minimum pad of 1", function()
            local axis = Logic.ComputeLinearYAxis(100)
            assert.are.equal(0, axis.yMin)
            assert.are.equal(108, axis.paddedYMax)
            assert.are.equal(108, axis.yRange)
        end)

        it("uses a minimum range of 1 when max is zero", function()
            local axis = Logic.ComputeLinearYAxis(0)
            assert.are.equal(1, axis.paddedYMax)
            assert.are.equal(1, axis.yRange)
        end)
    end)

    describe("ComputeLogAxisFloor", function()
        it("returns 1 when the minimum is at most 1 second", function()
            assert.are.equal(1, Logic.ComputeLogAxisFloor(0))
            assert.are.equal(1, Logic.ComputeLogAxisFloor(1))
        end)

        it("picks the largest 1-2-5 tick below the minimum", function()
            assert.are.equal(5, Logic.ComputeLogAxisFloor(8))
            assert.are.equal(20, Logic.ComputeLogAxisFloor(45))
            assert.are.equal(200, Logic.ComputeLogAxisFloor(300))
        end)

        it("never returns a floor greater than 5 minutes", function()
            assert.are.equal(300, Logic.ComputeLogAxisFloor(3600))
            assert.are.equal(300, Logic.ComputeLogAxisFloor(10000))
        end)
    end)

    describe("ComputeLogYAxis", function()
        it("uses 1-2-5 ticks for grid lines and labels", function()
            local axis = Logic.ComputeLogYAxis(5000, 300)
            assert.are.equal(200, axis.yMin)
            assert.are.equal(5400, axis.paddedYMax)
            assert.are.same({ 200, 500, 1000, 2000, 5000 }, axis.gridTicks)
        end)

        it("falls back to 1 second when all values are very small", function()
            local axis = Logic.ComputeLogYAxis(90, 8)
            assert.are.equal(5, axis.yMin)
            assert.are.same({ 5, 10, 20, 50 }, axis.gridTicks)
        end)

        it("includes the next decade when padded max crosses it", function()
            local axis = Logic.ComputeLogYAxis(9500, 300)
            assert.are.same({ 200, 500, 1000, 2000, 5000, 10000 }, axis.gridTicks)
        end)
    end)

    describe("YToFraction", function()
        local linearAxis = { yMin = 0, yRange = 100 }
        local logAxis = Logic.ComputeLogYAxis(90, 8)

        it("maps linear values proportionally", function()
            assert.are.equal(0.5, Logic.YToFraction(50, linearAxis, false))
        end)

        it("maps logarithmic values on a log scale", function()
            assert.are.equal(0, Logic.YToFraction(logAxis.yMin, logAxis, true))
            assert.is_true(Logic.YToFraction(10, logAxis, true) > Logic.YToFraction(logAxis.yMin, logAxis, true))
            assert.is_true(Logic.YToFraction(90, logAxis, true) > Logic.YToFraction(10, logAxis, true))
        end)

        it("clamps zero to the log floor", function()
            assert.are.equal(Logic.YToFraction(logAxis.yMin, logAxis, true), Logic.YToFraction(0, logAxis, true))
        end)

        it("places the smallest data point near the axis", function()
            local axis = Logic.ComputeLogYAxis(5000, 300)
            local minFraction = Logic.YToFraction(300, axis, true)
            assert.is_true(minFraction < 0.15)
        end)
    end)

    describe("SampleLeadingGapCurve", function()
        local gap = {
            fromLevel = 1,
            toLevel = 61,
            toY = 1000,
            totalSeconds = 60000,
        }
        local endPt = { level = 61, seconds = 1000 }

        it("includes endpoints with linearly interpolated seconds", function()
            local samples = Logic.SampleLeadingGapCurve(gap, endPt, 4)
            assert.are.equal(5, #samples)
            assert.are.equal(1, samples[1].level)
            assert.are.equal(0, samples[1].seconds)
            assert.are.equal(61, samples[5].level)
            assert.are.equal(1000, samples[5].seconds)
            assert.are.equal(250, samples[2].seconds)
        end)

        it("starts at the axis floor intersection when an axis floor is provided", function()
            local samples = Logic.SampleLeadingGapCurve(gap, endPt, 4, 300)
            assert.are.equal(5, #samples)
            assert.are.equal(19, samples[1].level)
            assert.are.equal(300, samples[1].seconds)
            assert.are.equal(61, samples[5].level)
            assert.are.equal(1000, samples[5].seconds)
        end)

        it("defaults to a smooth number of segments", function()
            local samples = Logic.SampleLeadingGapCurve(gap, endPt)
            assert.is_true(#samples >= 16)
        end)
    end)

    describe("HoverNeedsRebuild with logarithmic scale", function()
        local drawnKeys = { ["Realm\\Bob"] = true }

        it("returns true when hovered series has a lower minimum", function()
            assert.is_true(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 5000, 5000, 100, 300, true))
        end)

        it("returns false when hovered series fits within current log bounds", function()
            assert.is_false(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 4000, 5000, 400, 300, true))
        end)
    end)
end)
