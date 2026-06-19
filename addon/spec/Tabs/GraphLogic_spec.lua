--[[
  Unit tests for GraphLogic.lua.
  Run from project root: npm test
]]

describe("GraphLogic", function()
    local Logic

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Tabs/?.lua"
        package.loaded["GraphLogic"] = nil
        require("GraphLogic")
        Logic = AltArmy.GraphLogic
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
        it("snaps the axis top to nice duration ticks with 8 percent padding", function()
            local axis = Logic.ComputeLinearYAxis(100)
            assert.are.equal(0, axis.yMin)
            assert.are.equal(120, axis.paddedYMax)
            assert.are.equal(120, axis.yRange)
            assert.are.same({ 0, 30, 60, 90, 120 }, axis.gridTicks)
        end)

        it("uses a minimum range of 1 when max is zero", function()
            local axis = Logic.ComputeLinearYAxis(0)
            assert.are.equal(5, axis.paddedYMax)
            assert.are.same({ 0, 5 }, axis.gridTicks)
        end)

        it("uses 30 minute steps for multi-hour ranges", function()
            local axis = Logic.ComputeLinearYAxis(7020)
            assert.are.same({ 0, 1800, 3600, 5400, 7200, 9000 }, axis.gridTicks)
            assert.are.equal(9000, axis.paddedYMax)
        end)

        it("uses 2 minute steps for ten-minute ranges", function()
            local axis = Logic.ComputeLinearYAxis(500)
            assert.are.same({ 0, 120, 240, 360, 480, 600 }, axis.gridTicks)
            assert.are.equal(600, axis.paddedYMax)
        end)
    end)

    describe("ComputeLinearYGridTicks", function()
        it("always includes zero when the minimum is zero", function()
            local ticks, top = Logic.ComputeLinearYGridTicks(0, 600, 4)
            assert.are.equal(0, ticks[1])
            assert.is_true(top >= 600)
        end)
    end)

    describe("ComputeLogAxisFloor", function()
        it("returns 1 when the minimum is at most 1 second", function()
            assert.are.equal(1, Logic.ComputeLogAxisFloor(0))
            assert.are.equal(1, Logic.ComputeLogAxisFloor(1))
        end)

        it("picks the largest duration candidate below the minimum", function()
            assert.are.equal(5, Logic.ComputeLogAxisFloor(8))
            assert.are.equal(30, Logic.ComputeLogAxisFloor(45))
            assert.are.equal(180, Logic.ComputeLogAxisFloor(300))
        end)

        it("never returns a floor greater than 5 minutes", function()
            assert.are.equal(300, Logic.ComputeLogAxisFloor(3600))
            assert.are.equal(300, Logic.ComputeLogAxisFloor(10000))
        end)

        it("ignores the 5 minute cap when ignoreMaxFloor is set", function()
            assert.are.equal(2700, Logic.ComputeLogAxisFloor(3600, true))
            assert.are.equal(7200, Logic.ComputeLogAxisFloor(10000, true))
        end)
    end)

    describe("ComputeLogYAxis", function()
        it("uses duration-friendly ticks for grid lines and labels", function()
            local axis = Logic.ComputeLogYAxis(5000, 300)
            assert.are.equal(180, axis.yMin)
            assert.are.equal(5400, axis.paddedYMax)
            assert.are.same({ 180, 300, 600, 900, 1800, 2700, 3600, 5400 }, axis.gridTicks)
        end)

        it("falls back to 1 second when all values are very small", function()
            local axis = Logic.ComputeLogYAxis(90, 8)
            assert.are.equal(5, axis.yMin)
            assert.are.equal(120, axis.paddedYMax)
            assert.are.same({ 5, 10, 15, 30, 60, 120 }, axis.gridTicks)
        end)

        it("snaps the axis top to the next duration tick", function()
            local axis = Logic.ComputeLogYAxis(9500, 300)
            assert.are.equal(10800, axis.paddedYMax)
            assert.is_true(axis.gridTicks[#axis.gridTicks] <= axis.paddedYMax)
        end)

        it("includes power-of-two day ticks beyond 24 hours", function()
            local oneDay = 86400
            local twoDays = oneDay * 2
            local fourDays = oneDay * 4
            local axis = Logic.ComputeLogYAxis(twoDays + oneDay / 2, 3600, true)
            assert.are.equal(fourDays, axis.paddedYMax)
            local hasTick = {}
            for _, tick in ipairs(axis.gridTicks) do
                hasTick[tick] = true
            end
            assert.is_true(hasTick[oneDay])
            assert.is_true(hasTick[twoDays])
            assert.is_true(hasTick[fourDays])
        end)

        it("snaps the axis top up to 256 days", function()
            local maxDays = 86400 * 256
            local axis = Logic.ComputeLogYAxis(86400 * 200, 3600, true)
            assert.are.equal(maxDays, axis.paddedYMax)
            assert.are.equal(maxDays, axis.gridTicks[#axis.gridTicks])
        end)
    end)

    describe("FilterLogYGridTicks", function()
        local function logFraction(val, logMin, logMax)
            local logRange = logMax - logMin
            if logRange <= 0 then
                return 0
            end
            return (math.log(val) / math.log(10) - logMin) / logRange
        end

        local function assertMinSpacing(ticks, logMin, logMax, minSpacing)
            for i = 2, #ticks do
                local spacing = logFraction(ticks[i], logMin, logMax) - logFraction(ticks[i - 1], logMin, logMax)
                assert.is_true(
                    spacing + 1e-9 >= minSpacing,
                    string.format("ticks %s and %s are only %.3f apart", ticks[i - 1], ticks[i], spacing)
                )
            end
        end

        it("returns empty or single tick lists unchanged", function()
            assert.are.same({}, Logic.FilterLogYGridTicks({}, 0, 1, 0.1))
            assert.are.same({ 30 }, Logic.FilterLogYGridTicks({ 30 }, 1.47, 4.93, 0.1))
        end)

        it("always keeps the bottom tick", function()
            local axis = Logic.ComputeLogYAxis(86400, 30, true)
            local filtered = Logic.FilterLogYGridTicks(
                axis.gridTicks, axis.logMin, axis.logMax, Logic.LOG_Y_MIN_TICK_SPACING_FRACTION
            )
            assert.are.equal(axis.gridTicks[1], filtered[1])
        end)

        it("skips ticks that crowd the bottom of a wide log scale", function()
            local axis = Logic.ComputeLogYAxis(86400, 45, true)
            local filtered = Logic.FilterLogYGridTicks(
                axis.gridTicks, axis.logMin, axis.logMax, Logic.LOG_Y_MIN_TICK_SPACING_FRACTION
            )
            assert.is_true(#filtered < #axis.gridTicks)
            local hasTick = {}
            for _, tick in ipairs(filtered) do
                hasTick[tick] = true
            end
            assert.are.equal(30, filtered[1])
            assert.is_nil(hasTick[60], "1m should be skipped when too close to 30s")
            assertMinSpacing(filtered, axis.logMin, axis.logMax, Logic.LOG_Y_MIN_TICK_SPACING_FRACTION)
        end)

        it("measures spacing from the last kept tick, not the previous candidate", function()
            local logMin = math.log(30) / math.log(10)
            local logMax = math.log(86400) / math.log(10)
            local filtered = Logic.FilterLogYGridTicks(
                { 30, 60, 120, 180, 300, 600 }, logMin, logMax, 0.12
            )
            assert.are.same({ 30, 120, 600 }, filtered)
        end)

        it("keeps all ticks when the range is narrow", function()
            local axis = Logic.ComputeLogYAxis(90, 8)
            local filtered = Logic.FilterLogYGridTicks(
                axis.gridTicks, axis.logMin, axis.logMax, Logic.LOG_Y_MIN_TICK_SPACING_FRACTION
            )
            assert.are.same(axis.gridTicks, filtered)
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

        it("places the smallest data point in the lower portion of the axis", function()
            local axis = Logic.ComputeLogYAxis(5000, 300)
            local minFraction = Logic.YToFraction(300, axis, true)
            assert.is_true(minFraction < 0.2)
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

        it("limits bounds to points within an optional level range", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 500),
                makePoint(30, 200),
            }
            local yMin, yMax = Logic.GetSeriesScaleBounds(points, false, 15, 25)
            assert.are.equal(500, yMin)
            assert.are.equal(500, yMax)
        end)

        it("ignores level bounds when min and max are nil", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 500),
            }
            local yMin, yMax = Logic.GetSeriesScaleBounds(points, false, nil, nil)
            assert.are.equal(100, yMin)
            assert.are.equal(500, yMax)
        end)
    end)

    describe("ChooseXLabelInterval", function()
        it("returns denser intervals for narrow zoom ranges", function()
            assert.are.equal(1, Logic.ChooseXLabelInterval(5))
            assert.are.equal(2, Logic.ChooseXLabelInterval(12))
            assert.are.equal(5, Logic.ChooseXLabelInterval(30))
            assert.are.equal(10, Logic.ChooseXLabelInterval(70))
        end)
    end)

    describe("NormalizeZoomRange", function()
        it("orders, snaps, and clamps the drag range", function()
            local minLevel, maxLevel = Logic.NormalizeZoomRange(25.4, 12.6, 0, 70, 2)
            assert.are.equal(13, minLevel)
            assert.are.equal(25, maxLevel)
        end)

        it("returns nil when the span is below the minimum", function()
            assert.is_nil(Logic.NormalizeZoomRange(10, 10.5, 0, 70, 2))
        end)

        it("clamps to the full axis range", function()
            local minLevel, maxLevel = Logic.NormalizeZoomRange(-5, 80, 0, 70, 2)
            assert.are.equal(0, minLevel)
            assert.are.equal(70, maxLevel)
        end)
    end)

    describe("ClipDrawPlanToRange", function()
        it("drops markers outside the range", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 120),
                makePoint(30, 140),
            }
            local plan = Logic.BuildSeriesDrawPlan(points)
            local clipped = Logic.ClipDrawPlanToRange(plan, 15, 25)
            assert.are.equal(1, #clipped.markers)
            assert.are.equal(20, clipped.markers[1].pt.level)
        end)

        it("interpolates segment endpoints at range boundaries", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
                makePoint(30, 300),
            }
            local plan = Logic.BuildSeriesDrawPlan(points)
            local clipped = Logic.ClipDrawPlanToRange(plan, 15, 25)
            assert.are.equal(2, #clipped.segments)
            assert.are.equal(15, clipped.segments[1].from.level)
            assert.are.equal(150, clipped.segments[1].from.seconds)
            assert.are.equal(20, clipped.segments[1].to.level)
            assert.are.equal(200, clipped.segments[1].to.seconds)
            assert.are.equal(20, clipped.segments[2].from.level)
            assert.are.equal(200, clipped.segments[2].from.seconds)
            assert.are.equal(25, clipped.segments[2].to.level)
            assert.are.equal(250, clipped.segments[2].to.seconds)
        end)

        it("drops segments fully outside the range", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
            }
            local plan = Logic.BuildSeriesDrawPlan(points)
            local clipped = Logic.ClipDrawPlanToRange(plan, 25, 35)
            assert.are.equal(0, #clipped.segments)
            assert.are.equal(0, #clipped.markers)
        end)

        it("drops segments that collapse to a single point after clipping", function()
            local pt = makePoint(20, 200)
            local plan = {
                segments = {
                    { style = "solid", from = pt, to = pt },
                },
                markers = { { pt = pt } },
            }
            local clipped = Logic.ClipDrawPlanToRange(plan, 15, 25)
            assert.are.equal(0, #clipped.segments)
            assert.are.equal(1, #clipped.markers)
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
