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

    describe("Compare select all", function()
        it("shows the All row only when there are more than four characters", function()
            assert.is_false(Logic.ShouldShowCompareSelectAll(4))
            assert.is_true(Logic.ShouldShowCompareSelectAll(5))
        end)

        it("checks All only when every compare character is selected", function()
            assert.is_false(Logic.IsCompareSelectAllChecked(5, 4))
            assert.is_true(Logic.IsCompareSelectAllChecked(5, 5))
            assert.is_false(Logic.IsCompareSelectAllChecked(0, 0))
        end)

        it("selects all when not fully selected and deselects when fully selected", function()
            assert.is_true(Logic.GetCompareSelectAllAction(false))
            assert.is_false(Logic.GetCompareSelectAllAction(true))
        end)
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

    local function makePoint(level, seconds)
        return {
            level = level,
            seconds = seconds,
            fromLevel = level - 1,
            toLevel = level,
            totalSeconds = seconds,
        }
    end

    describe("ApplyRollingAverage", function()
        it("returns unchanged seconds when the window size is 1", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
            }
            local smoothed = Logic.ApplyRollingAverage(points, 1)
            assert.are.equal(100, smoothed[1].seconds)
            assert.are.equal(200, smoothed[2].seconds)
        end)

        it("computes a centered rolling average with partial windows at the edges", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
                makePoint(30, 300),
                makePoint(40, 400),
                makePoint(50, 500),
            }
            local smoothed = Logic.ApplyRollingAverage(points, 5)
            assert.are.equal(200, smoothed[1].seconds)
            assert.are.equal(250, smoothed[2].seconds)
            assert.are.equal(300, smoothed[3].seconds)
            assert.are.equal(350, smoothed[4].seconds)
            assert.are.equal(400, smoothed[5].seconds)
        end)

        it("defaults to a window of 5", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
                makePoint(30, 300),
                makePoint(40, 400),
                makePoint(50, 500),
            }
            local smoothed = Logic.ApplyRollingAverage(points)
            assert.are.equal(300, smoothed[3].seconds)
        end)

        it("clears outlier flags so the smoothed line stays on-chart", function()
            local points = { makePoint(10, 8000) }
            points[1].isOutlier = true
            local smoothed = Logic.ApplyRollingAverage(points, 3)
            assert.is_false(smoothed[1].isOutlier)
        end)

        it("uses shrunk virtual values when shrinkOutliers is enabled", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
                makePoint(30, 8000),
                makePoint(40, 120),
                makePoint(50, 110),
            }
            points[3].isOutlier = true

            local raw = Logic.ApplyRollingAverage(points, 5, false)
            assert.is_true(raw[3].seconds > 1000)

            local shrunk = Logic.ApplyRollingAverage(points, 5, true)
            assert.are.equal(146, shrunk[3].seconds)
        end)
    end)

    describe("BuildShrunkVirtualSeconds", function()
        it("replaces outlier seconds with the max non-outlier value", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 8000),
                makePoint(30, 120),
            }
            points[2].isOutlier = true

            local virtual = Logic.BuildShrunkVirtualSeconds(points)
            assert.are.equal(100, virtual[1])
            assert.are.equal(120, virtual[2])
            assert.are.equal(120, virtual[3])
        end)
    end)

    describe("ApplyOutlierFlags", function()
        it("does not flag outliers when disabled", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 10000),
            }
            local marked = Logic.ApplyOutlierFlags(points, false)
            assert.is_false(marked[2].isOutlier)
        end)

        it("flags extreme values among the longest-duration levels", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 120),
                makePoint(30, 110),
                makePoint(40, 105),
                makePoint(50, 8000),
            }
            local marked = Logic.ApplyOutlierFlags(points, true)
            assert.is_false(marked[1].isOutlier)
            assert.is_false(marked[4].isOutlier)
            assert.is_true(marked[5].isOutlier)
        end)

        it("flags only the cap-wait spike among the ten longest durations", function()
            local points = {}
            for level = 20, 49 do
                points[#points + 1] = makePoint(level, 3600)
            end
            points[#points + 1] = makePoint(61, 205200)
            for level = 62, 70 do
                points[#points + 1] = makePoint(level, 21600)
            end

            local marked = Logic.ApplyOutlierFlags(points, true)
            assert.is_true(marked[31].isOutlier)
            for i = 32, #marked do
                assert.is_false(marked[i].isOutlier)
            end
            for i = 1, 30 do
                assert.is_false(marked[i].isOutlier)
            end
        end)

        it("does not flag long durations outside the top ten", function()
            local points = { makePoint(1, 205200) }
            for level = 2, 16 do
                points[#points + 1] = makePoint(level, 21600)
            end

            local marked = Logic.ApplyOutlierFlags(points, true)
            assert.is_true(marked[1].isOutlier)
            for i = 11, #marked do
                assert.is_false(marked[i].isOutlier)
            end
        end)
    end)

    describe("BuildSeriesDrawPlan", function()
        it("spikes up to the true outlier position then returns to the next level", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 8000),
                makePoint(30, 110),
            }
            points[2].isOutlier = true

            local plan = Logic.BuildSeriesDrawPlan(points)
            assert.are.equal(2, #plan.segments)
            assert.are.equal("solid", plan.segments[1].style)
            assert.are.equal(10, plan.segments[1].from.level)
            assert.are.equal(20, plan.segments[1].to.level)
            assert.are.equal(8000, plan.segments[1].to.seconds)
            assert.is_true(plan.segments[1].isOutlierSpike)
            assert.are.equal("solid", plan.segments[2].style)
            assert.are.equal(20, plan.segments[2].from.level)
            assert.are.equal(30, plan.segments[2].to.level)
            assert.is_true(plan.segments[2].isOutlierReturn)
            assert.are.equal(3, #plan.markers)
            assert.is_true(plan.markers[2].pt.isOutlier)
        end)

        it("spikes to a trailing outlier and marks it near the plot top", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 8000),
            }
            points[2].isOutlier = true

            local plan = Logic.BuildSeriesDrawPlan(points)
            assert.are.equal(1, #plan.segments)
            assert.are.equal("solid", plan.segments[1].style)
            assert.are.equal(20, plan.segments[1].to.level)
            assert.are.equal(8000, plan.segments[1].to.seconds)
            assert.is_true(plan.segments[1].isOutlierSpike)
            assert.are.equal(2, #plan.markers)
            assert.are.equal(10, plan.markers[1].pt.level)
            assert.is_true(plan.markers[2].pt.isOutlier)
            assert.are.equal(20, plan.markers[2].pt.level)
        end)

        it("chains consecutive outliers off the chart", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 8000),
                makePoint(30, 9000),
                makePoint(40, 110),
            }
            points[2].isOutlier = true
            points[3].isOutlier = true

            local plan = Logic.BuildSeriesDrawPlan(points)
            assert.are.equal(3, #plan.segments)
            assert.is_true(plan.segments[1].isOutlierSpike)
            assert.is_true(plan.segments[2].isOutlierSpike)
            assert.are.equal(20, plan.segments[2].from.level)
            assert.are.equal(30, plan.segments[2].to.level)
            assert.is_true(plan.segments[3].isOutlierReturn)
            assert.are.equal(40, plan.segments[3].to.level)
        end)

        it("keeps solid segments between normal points", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 120),
            }
            local plan = Logic.BuildSeriesDrawPlan(points)
            assert.are.equal("solid", plan.segments[1].style)
        end)
    end)

    describe("PlotSeriesPoint", function()
        it("clamps outlier points to the plot top", function()
            local pt = makePoint(20, 8000)
            pt.isOutlier = true
            local x, y = Logic.PlotSeriesPoint(pt, 120, 500, 400)
            assert.are.equal(120, x)
            assert.are.equal(400, y)
        end)

        it("keeps normal points at their true y position", function()
            local pt = makePoint(20, 120)
            local x, y = Logic.PlotSeriesPoint(pt, 120, 180, 400)
            assert.are.equal(120, x)
            assert.are.equal(180, y)
        end)
    end)

    describe("GetSeriesScaleBounds", function()
        it("excludes outliers from axis bounds when requested", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 9000),
            }
            points[2].isOutlier = true
            local yMin, yMax = Logic.GetSeriesScaleBounds(points, true)
            assert.are.equal(100, yMin)
            assert.are.equal(100, yMax)
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

    describe("BuildClassVariationIndices", function()
        it("assigns variation 0 to a lone class member", function()
            local indices = Logic.BuildClassVariationIndices({ "WARRIOR", "MAGE" })
            assert.are.same({ 0, 0 }, indices)
        end)

        it("cycles 0,1,2 within each class in order", function()
            local indices = Logic.BuildClassVariationIndices({
                "WARRIOR", "MAGE", "WARRIOR", "WARRIOR", "WARRIOR",
            })
            assert.are.same({ 0, 0, 1, 2, 0 }, indices)
        end)

        it("returns an empty table for no entries", function()
            assert.are.same({}, Logic.BuildClassVariationIndices({}))
        end)
    end)

    describe("VaryColor", function()
        it("returns the color unchanged for code 0", function()
            local r, g, b = Logic.VaryColor(0.5, 0.4, 0.3, 0)
            assert.are.equal(0.5, r)
            assert.are.equal(0.4, g)
            assert.are.equal(0.3, b)
        end)

        it("brightens toward white for code 1 on normal colors", function()
            local r, g, b = Logic.VaryColor(0.4, 0.4, 0.4, 1)
            local expected = 0.4 + (1 - 0.4) * Logic.COLOR_VARIATION_BRIGHTEN
            assert.are.equal(expected, r)
            assert.are.equal(expected, g)
            assert.are.equal(expected, b)
            assert.is_true(r > 0.4)
        end)

        it("darkens for code 2 on normal colors", function()
            local r, g, b = Logic.VaryColor(0.4, 0.4, 0.4, 2)
            local expected = 0.4 * Logic.COLOR_VARIATION_DARKEN
            assert.are.equal(expected, r)
            assert.are.equal(expected, g)
            assert.are.equal(expected, b)
            assert.is_true(r < 0.4)
        end)

        it("uses two distinct darker shades for near-white colors", function()
            local r1 = Logic.VaryColor(1, 1, 1, 1)
            local r2 = Logic.VaryColor(1, 1, 1, 2)
            assert.is_true(r1 < 1)
            assert.is_true(r2 < 1)
            assert.is_true(r1 > r2)
            assert.are.equal(1 * Logic.COLOR_VARIATION_DARKEN_LIGHT, r1)
            assert.are.equal(1 * Logic.COLOR_VARIATION_DARKEN, r2)
        end)
    end)
end)
