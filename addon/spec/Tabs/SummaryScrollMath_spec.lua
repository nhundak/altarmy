--[[
  Documents virtual-list vertical scroll math for TabSummary.lua (fixed row pool).
  Constants must match TabSummary.lua ROW_HEIGHT and GetVisibleRowCount().
]]

describe("Summary tab virtual list scroll math", function()
    local ROW_HEIGHT = 18
    local ROW_POOL_SIZE = 20
    local HORIZONTAL_SCROLL_BAR_HEIGHT = 20

    --- Mirrors TabSummary GetVisibleRowCount().
    local function visibleRowsFromViewport(viewportH)
        if not viewportH or viewportH <= 0 then
            return 1
        end
        local rows = math.min(ROW_POOL_SIZE, math.max(1, math.ceil(viewportH / ROW_HEIGHT)))
        return math.max(1, rows - 1)
    end

    --- Mirrors TabSummary GetSummaryListViewportBottomInset().
    local function listViewportBottomInset(needsHorizontalScroll, summaryRowLift)
        if needsHorizontalScroll then
            return HORIZONTAL_SCROLL_BAR_HEIGHT
        end
        return summaryRowLift or 0
    end

    --- Mirrors TabSummary Update(): max pixel scroll for the slider / ScrollFrame.
    local function maxScrollPixels(numItems, visibleRows)
        return math.max(0, (numItems - visibleRows) * ROW_HEIGHT)
    end

    --- Mirrors TabSummary GetSummaryScrollViewportHeight().
    local function scrollViewportHeight(listViewportH, scrollFrameH, headerHeight, totalsRowHeight)
        if listViewportH and listViewportH > 0 then
            return math.max(1, listViewportH - headerHeight - totalsRowHeight)
        end
        return math.max(1, scrollFrameH > 0 and scrollFrameH or 1)
    end

    it("derives scroll viewport height from list viewport, not stale scroll frame", function()
        local HEADER_HEIGHT = 20
        local TOTALS_ROW_HEIGHT = 18
        assert.are.equal(262, scrollViewportHeight(300, 240, HEADER_HEIGHT, TOTALS_ROW_HEIGHT))
        assert.are.equal(240, scrollViewportHeight(0, 240, HEADER_HEIGHT, TOTALS_ROW_HEIGHT))
    end)

    it("derives visible rows from viewport height", function()
        assert.are.equal(1, visibleRowsFromViewport(0))
        assert.are.equal(13, visibleRowsFromViewport(14 * ROW_HEIGHT))
        assert.are.equal(15, visibleRowsFromViewport(280))
    end)

    it("changes row count by one when horizontal scroll reserve replaces summary lift", function()
        local PAD = 4
        local HEADER_HEIGHT = 20
        local TOTALS_ROW_HEIGHT = 18
        local listH = 300
        local insetDelta = HORIZONTAL_SCROLL_BAR_HEIGHT - PAD
        local vhNoBar = scrollViewportHeight(listH, 0, HEADER_HEIGHT, TOTALS_ROW_HEIGHT)
        local vhWithBar = scrollViewportHeight(listH - insetDelta, 0, HEADER_HEIGHT, TOTALS_ROW_HEIGHT)
        assert.are.equal(1, visibleRowsFromViewport(vhNoBar) - visibleRowsFromViewport(vhWithBar))
    end)

    it("reserves bottom space for the horizontal scroll bar only when needed", function()
        assert.are.equal(20, listViewportBottomInset(true, 4))
        assert.are.equal(4, listViewportBottomInset(false, 4))
    end)

    it("allows one ROW_HEIGHT scroll when there is exactly one row beyond the pool", function()
        local visibleRows = 15
        assert.are.equal(ROW_HEIGHT, maxScrollPixels(visibleRows + 1, visibleRows))
    end)

    it("does not require scroll when all items fit in the row pool", function()
        local visibleRows = 15
        assert.are.equal(0, maxScrollPixels(visibleRows, visibleRows))
        assert.are.equal(0, maxScrollPixels(3, visibleRows))
    end)

    it("reserves one row below the viewport fit for spacing", function()
        local viewportH = 280
        assert.are.equal(math.ceil(viewportH / ROW_HEIGHT) - 1, visibleRowsFromViewport(viewportH))
    end)
end)
