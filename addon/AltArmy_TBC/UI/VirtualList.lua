-- AltArmy TBC — Pure helpers for virtualized row lists (viewport → render range).

AltArmy = AltArmy or {}
AltArmy.VirtualList = AltArmy.VirtualList or {}

local VirtualList = AltArmy.VirtualList

--- Which 1-based data indices to render for a scrollable section.
--- Mirrors TabSearch UpdateVisibleRows viewport math (section-relative + buffer).
--- @return table|nil { firstVisible, lastVisible, firstRender, lastRender, renderCount }
function VirtualList.GetRenderRange(scrollValue, viewHeight, sectionTop, rowHeight, count, buffer)
    count = count or 0
    if count < 1 then
        return nil
    end
    scrollValue = scrollValue or 0
    viewHeight = viewHeight or 0
    sectionTop = sectionTop or 0
    rowHeight = rowHeight or 1
    buffer = buffer or 0

    local firstVisible = math.max(1, math.floor((scrollValue - sectionTop) / rowHeight) + 1)
    if scrollValue < sectionTop then
        firstVisible = 1
    end
    local lastVisible = math.min(count, math.floor((scrollValue + viewHeight - sectionTop) / rowHeight))
    local firstRender = math.max(1, firstVisible - buffer)
    local lastRender = math.min(count, lastVisible + buffer)
    return {
        firstVisible = firstVisible,
        lastVisible = lastVisible,
        firstRender = firstRender,
        lastRender = lastRender,
        renderCount = lastRender - firstRender + 1,
    }
end

--- Content-coordinate top offset (negative Y) for a 1-based row in a section.
function VirtualList.RowTopOffset(sectionTop, dataIndex, rowHeight)
    return -(sectionTop or 0) - ((dataIndex or 1) - 1) * (rowHeight or 0)
end

--- Map a group { start, count } that intersects [firstRender, lastRender] to pool indices.
--- @return table|nil { firstPoolIdx, lastPoolIdx }
function VirtualList.GroupPoolSpan(group, firstRender, lastRender)
    if not group or not group.start or not group.count then
        return nil
    end
    local gEnd = group.start + group.count - 1
    if gEnd < firstRender or group.start > lastRender then
        return nil
    end
    local groupStart = math.max(group.start, firstRender)
    local groupEnd = math.min(gEnd, lastRender)
    return {
        firstPoolIdx = groupStart - firstRender + 1,
        lastPoolIdx = groupEnd - firstRender + 1,
    }
end

--- True when [firstVisible, lastVisible] stays inside [paintedFirst, paintedLast]
--- with at least `margin` rows of slack on each side (refill before hitting the edge).
function VirtualList.IsVisibleRangeCovered(firstVisible, lastVisible, paintedFirst, paintedLast, margin)
    if not paintedFirst or not paintedLast or not firstVisible or not lastVisible then
        return false
    end
    margin = margin or 0
    return firstVisible >= (paintedFirst + margin)
        and lastVisible <= (paintedLast - margin)
end

--- Invoke onShow(poolIdx, dataIndex) for active slots and onHide(poolIdx) for the rest.
function VirtualList.ForEachPoolSlot(poolSize, firstRender, renderCount, onShow, onHide)
    poolSize = poolSize or 0
    renderCount = renderCount or 0
    firstRender = firstRender or 1
    for poolIdx = 1, poolSize do
        if poolIdx <= renderCount then
            if onShow then
                onShow(poolIdx, firstRender + poolIdx - 1)
            end
        elseif onHide then
            onHide(poolIdx)
        end
    end
end
