-- AltArmy TBC — Reputation grid column windowing + bar fill width math (pure helpers).

AltArmy = AltArmy or {}
AltArmy.ReputationGridWindow = AltArmy.ReputationGridWindow or {}

local RGW = AltArmy.ReputationGridWindow

--- 1-based inclusive column index range visible in the horizontal viewport (+ buffer).
--- @param scrollOffset number horizontal scroll pixels
--- @param viewportWidth number visible width of the horizontal scroll frame
--- @param columnWidth number width of one column
--- @param numCols number total display columns
--- @param buffer number extra columns to include on each side (default 0)
--- @return number first, number last
function RGW.GetVisibleColumnRange(scrollOffset, viewportWidth, columnWidth, numCols, buffer)
    buffer = buffer or 0
    if not numCols or numCols <= 0 then
        return 1, 0
    end
    if not columnWidth or columnWidth <= 0 then
        return 1, numCols
    end
    local offset = tonumber(scrollOffset) or 0
    local viewW = tonumber(viewportWidth) or 0
    if viewW <= 0 then
        return 1, numCols
    end
    local first = math.floor(offset / columnWidth) + 1 - buffer
    local last = math.ceil((offset + viewW) / columnWidth) + buffer
    if first < 1 then first = 1 end
    if last > numCols then last = numCols end
    if first > last then
        return 1, 0
    end
    return first, last
end

--- Bar fill width from percent and full bar width; pct clamped 0..100, minimum width 1.
--- @param pct number
--- @param fullWidth number
--- @return number
function RGW.BarFillWidth(pct, fullWidth)
    local w = tonumber(fullWidth) or 0
    if w <= 0 then
        return 1
    end
    local p = tonumber(pct) or 0
    if p < 0 then p = 0 end
    if p > 100 then p = 100 end
    return math.max(1, w * p / 100)
end
