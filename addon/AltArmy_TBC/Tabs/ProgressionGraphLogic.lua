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

function Logic.ComputeSeriesAlphas(dimOthers, isHovered)
    if not dimOthers then
        return Logic.FULL_LINE_ALPHA, Logic.FULL_DASH_ALPHA, Logic.FULL_MARKER_ALPHA
    end
    if isHovered then
        return Logic.FULL_LINE_ALPHA, Logic.FULL_DASH_ALPHA, Logic.FULL_MARKER_ALPHA
    end
    return Logic.DIM_LINE_ALPHA, Logic.DIM_DASH_ALPHA, Logic.DIM_MARKER_ALPHA
end

function Logic.HoverNeedsRebuild(hoveredKey, drawnKeys, hoveredMaxSeconds, currentRawYMax)
    if not hoveredKey then
        return false
    end
    if drawnKeys[hoveredKey] then
        return false
    end
    return hoveredMaxSeconds > currentRawYMax
end
