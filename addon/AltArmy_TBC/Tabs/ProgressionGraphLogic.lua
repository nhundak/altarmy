-- AltArmy TBC — Pure helpers for progression graph hover/highlight logic.

if not AltArmy then return end

AltArmy.ProgressionGraphLogic = AltArmy.ProgressionGraphLogic or {}

local Logic = AltArmy.ProgressionGraphLogic

Logic.FULL_LINE_ALPHA = 0.9
Logic.FULL_DASH_ALPHA = 0.55
Logic.FULL_MARKER_ALPHA = 1
Logic.DIM_LINE_ALPHA = 0.22
Logic.DIM_DASH_ALPHA = 0.14
Logic.DIM_MARKER_ALPHA = 0.35
Logic.LOG_AXIS_MAX_FLOOR_SECONDS = 300
Logic.OUTLIER_IQR_MULTIPLIER = 3
Logic.OUTLIER_MEDIAN_MULTIPLIER = 5
Logic.OUTLIER_TOP_DURATION_COUNT = 10
Logic.OUTLIER_TOP_MARGIN = 6

function Logic.ComputeSeriesAlphas(dimOthers, isHovered)
    if not dimOthers then
        return Logic.FULL_LINE_ALPHA, Logic.FULL_DASH_ALPHA, Logic.FULL_MARKER_ALPHA
    end
    if isHovered then
        return Logic.FULL_LINE_ALPHA, Logic.FULL_DASH_ALPHA, Logic.FULL_MARKER_ALPHA
    end
    return Logic.DIM_LINE_ALPHA, Logic.DIM_DASH_ALPHA, Logic.DIM_MARKER_ALPHA
end

function Logic.HoverNeedsRebuild(
    hoveredKey, drawnKeys, hoveredMaxSeconds, currentRawYMax,
    hoveredMinSeconds, currentRawYMin, logarithmic
)
    if not hoveredKey then
        return false
    end
    if drawnKeys[hoveredKey] then
        return false
    end
    if logarithmic and hoveredMinSeconds and currentRawYMin and currentRawYMin > 0 then
        if hoveredMinSeconds < currentRawYMin then
            return true
        end
    end
    return hoveredMaxSeconds > currentRawYMax
end

local LOG10 = math.log(10)

local function Log10(value)
    return math.log(value) / LOG10
end

function Logic.ComputeLinearYAxis(rawYMax)
    local yPad = math.max(1, math.floor(rawYMax * 0.08))
    local yMin = 0
    local paddedYMax = rawYMax + yPad
    local yRange = math.max(1, paddedYMax - yMin)
    return {
        yMin = yMin,
        paddedYMax = paddedYMax,
        yRange = yRange,
    }
end

function Logic.ComputeLogAxisFloor(rawYMin)
    if not rawYMin or rawYMin <= 1 then
        return 1
    end

    local exp = math.floor(Log10(rawYMin))
    local scale = 10 ^ exp
    local best = 1

    local function considerCandidates(multiplier)
        for _, mult in ipairs({ 1, 2, 5 }) do
            local candidate = mult * scale * multiplier
            if candidate < rawYMin and candidate > best then
                best = candidate
            end
        end
    end

    considerCandidates(1)
    if best <= 1 then
        considerCandidates(0.1)
    end

    return math.min(Logic.LOG_AXIS_MAX_FLOOR_SECONDS, math.max(1, best))
end

local function ComputeLogYGridTicks(yMin, paddedYMax)
    local gridTicks = {}
    local seen = {}
    local minExp = math.floor(Log10(yMin))
    local maxExp = math.ceil(Log10(paddedYMax))

    for exp = minExp, maxExp do
        local scale = 10 ^ exp
        for _, mult in ipairs({ 1, 2, 5 }) do
            local val = mult * scale
            if val >= yMin and val <= paddedYMax and not seen[val] then
                gridTicks[#gridTicks + 1] = val
                seen[val] = true
            end
        end
    end

    table.sort(gridTicks)
    if #gridTicks == 0 or gridTicks[1] ~= yMin then
        table.insert(gridTicks, 1, yMin)
    end
    return gridTicks
end

function Logic.ComputeLogYAxis(rawYMax, rawYMin)
    local yPad = math.max(1, math.floor(rawYMax * 0.08))
    local paddedYMax = math.max(1, rawYMax + yPad)
    local yMin = Logic.ComputeLogAxisFloor(rawYMin)
    local logMin = Log10(yMin)
    local logMax = Log10(paddedYMax)

    return {
        yMin = yMin,
        paddedYMax = paddedYMax,
        logMin = logMin,
        logMax = logMax,
        gridTicks = ComputeLogYGridTicks(yMin, paddedYMax),
    }
end

function Logic.SampleLeadingGapCurve(gap, endPt, pointCount, axisFloor)
    pointCount = pointCount or 24
    local fromLevel = gap.fromLevel
    local toLevel = endPt.level
    local endSeconds = endPt.seconds
    local levelSpan = toLevel - fromLevel
    if levelSpan <= 0 then
        return {
            { level = fromLevel, seconds = 0 },
            { level = toLevel, seconds = endSeconds },
        }
    end

    local startLevel = fromLevel
    local startSeconds = 0
    if axisFloor and axisFloor > 0 and endSeconds > axisFloor then
        startLevel = fromLevel + (axisFloor / endSeconds) * levelSpan
        startSeconds = axisFloor
    end

    local samples = {}
    for i = 0, pointCount do
        local frac = i / pointCount
        samples[#samples + 1] = {
            level = startLevel + frac * (toLevel - startLevel),
            seconds = startSeconds + frac * (endSeconds - startSeconds),
        }
    end
    return samples
end

local function CopySeriesPoint(pt)
    return {
        level = pt.level,
        seconds = pt.seconds,
        fromLevel = pt.fromLevel,
        toLevel = pt.toLevel,
        totalSeconds = pt.totalSeconds,
        spansGap = pt.spansGap,
        isOutlier = false,
    }
end

local function Percentile(sorted, p)
    local n = #sorted
    if n == 0 then
        return 0
    end
    if n == 1 then
        return sorted[1]
    end

    local index = (n - 1) * p + 1
    local lo = math.floor(index)
    local hi = math.ceil(index)
    if lo == hi then
        return sorted[lo]
    end
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (index - lo)
end

function Logic.IsExtremeOutlier(seconds, allSeconds)
    if not seconds or seconds <= 0 or not allSeconds or #allSeconds < 3 then
        return false
    end

    local sorted = {}
    for _, value in ipairs(allSeconds) do
        sorted[#sorted + 1] = value
    end
    table.sort(sorted)

    local q1 = Percentile(sorted, 0.25)
    local q3 = Percentile(sorted, 0.75)
    local iqr = q3 - q1
    if iqr > 0 then
        return seconds > q3 + Logic.OUTLIER_IQR_MULTIPLIER * iqr
    end

    local median = Percentile(sorted, 0.5)
    return seconds > median * Logic.OUTLIER_MEDIAN_MULTIPLIER
end

function Logic.GetTopDurationPointIndices(points, count)
    count = count or Logic.OUTLIER_TOP_DURATION_COUNT
    local ranked = {}
    for i, pt in ipairs(points) do
        ranked[#ranked + 1] = {
            index = i,
            seconds = pt.seconds or 0,
        }
    end

    table.sort(ranked, function(a, b)
        if a.seconds ~= b.seconds then
            return a.seconds > b.seconds
        end
        return a.index < b.index
    end)

    local indices = {}
    local limit = math.min(count, #ranked)
    for i = 1, limit do
        indices[ranked[i].index] = true
    end
    return indices
end

function Logic.ApplyOutlierFlags(points, ignoreOutliers)
    local marked = {}

    for _, pt in ipairs(points) do
        marked[#marked + 1] = CopySeriesPoint(pt)
    end

    if not ignoreOutliers then
        return marked
    end

    local topDurationIndices = Logic.GetTopDurationPointIndices(marked)
    local topDurationSeconds = {}
    for i, pt in ipairs(marked) do
        if topDurationIndices[i] and pt.seconds and pt.seconds > 0 then
            topDurationSeconds[#topDurationSeconds + 1] = pt.seconds
        end
    end

    for i, pt in ipairs(marked) do
        if topDurationIndices[i] then
            pt.isOutlier = Logic.IsExtremeOutlier(pt.seconds, topDurationSeconds)
        end
    end

    return marked
end

function Logic.BuildSeriesDrawPlan(points)
    local segments = {}
    local markers = {}
    local lastNormalIdx = nil

    for _, pt in ipairs(points) do
        markers[#markers + 1] = { pt = pt }
    end

    for i, pt in ipairs(points) do
        if pt.isOutlier then
            if lastNormalIdx and i == lastNormalIdx + 1 then
                segments[#segments + 1] = {
                    style = "solid",
                    from = points[lastNormalIdx],
                    to = pt,
                    isOutlierSpike = true,
                }
            elseif i > 1 and points[i - 1].isOutlier then
                segments[#segments + 1] = {
                    style = "solid",
                    from = points[i - 1],
                    to = pt,
                    isOutlierSpike = true,
                }
            end
        elseif lastNormalIdx then
            if i > lastNormalIdx + 1 then
                segments[#segments + 1] = {
                    style = "solid",
                    from = points[i - 1],
                    to = pt,
                    isOutlierReturn = true,
                }
            else
                segments[#segments + 1] = {
                    style = "solid",
                    from = points[lastNormalIdx],
                    to = pt,
                }
            end
            lastNormalIdx = i
        else
            lastNormalIdx = i
        end
    end

    return { segments = segments, markers = markers }
end

function Logic.ComputePlotTopY(plotH, padding, margin)
    padding = padding or { bottom = 28 }
    margin = margin or Logic.OUTLIER_TOP_MARGIN
    return padding.bottom + plotH - margin
end

function Logic.PlotSeriesPoint(pt, x, y, plotTopY)
    if pt.isOutlier then
        return x, plotTopY
    end
    return x, y
end

function Logic.GetSeriesScaleBounds(points, ignoreOutliers)
    local yMax = 0
    local yMin = math.huge

    for _, pt in ipairs(points) do
        if not ignoreOutliers or not pt.isOutlier then
            if pt.seconds and pt.seconds > 0 and pt.seconds < yMin then
                yMin = pt.seconds
            end
            if pt.seconds and pt.seconds > yMax then
                yMax = pt.seconds
            end
        end
    end

    if yMin == math.huge then
        yMin = 0
    end
    return yMin, yMax
end

function Logic.YToFraction(y, axis, logarithmic)
    if logarithmic then
        local clamped = math.max(y, axis.yMin)
        local logY = Log10(clamped)
        local logRange = axis.logMax - axis.logMin
        if logRange <= 0 then
            return 0
        end
        return (logY - axis.logMin) / logRange
    end

    if axis.yRange <= 0 then
        return 0
    end
    return (y - axis.yMin) / axis.yRange
end
