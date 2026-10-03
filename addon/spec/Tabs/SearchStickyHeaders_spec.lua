--[[
  Unit tests for SearchStickyHeaders.lua sticky header push math.
  Constants must match TabSearch.lua HEADER_HEIGHT and HEADER_ROW_GAP.
]]

describe("SearchStickyHeaders", function()
    local Sticky

    local HEADER_HEIGHT = 18
    local HEADER_ROW_GAP = 3
    local ROW_HEIGHT = 18

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Tabs/?.lua"
        package.loaded["SearchStickyHeaders"] = nil
        require("SearchStickyHeaders")
        Sticky = AltArmy.SearchStickyHeaders
    end)

    local SECTION_GAP_BEFORE_TOOLTIP = 2

    --- Mirrors TabSearch UpdateVisibleRows section-top math (scroll/content coords, top = 0).
    local function computeSectionHeaderTops(nItems, nRecipes, nTooltipOnly)
        local tops = {}
        local itemsSectionTop = HEADER_HEIGHT + HEADER_ROW_GAP
        local currentTop = 0

        if nItems > 0 then
            tops[#tops + 1] = currentTop
            currentTop = currentTop + HEADER_HEIGHT + HEADER_ROW_GAP + nItems * ROW_HEIGHT
        end
        if nRecipes > 0 then
            tops[#tops + 1] = currentTop
            currentTop = currentTop + HEADER_HEIGHT + HEADER_ROW_GAP + nRecipes * ROW_HEIGHT
        end
        if nTooltipOnly > 0 then
            if nRecipes > 0 then
                currentTop = currentTop + SECTION_GAP_BEFORE_TOOLTIP
            end
            tops[#tops + 1] = currentTop
        end

        return tops, itemsSectionTop
    end

    describe("ComputeSectionLayout", function()
        it("matches ComputeSectionHeaderTops for the three search sections", function()
            local sections = {
                { id = "items", rowCount = 10 },
                { id = "recipes", rowCount = 5 },
                { id = "tooltip", rowCount = 3, gapBefore = SECTION_GAP_BEFORE_TOOLTIP },
            }
            local tops, metas = Sticky.ComputeSectionLayout(
                sections, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT)
            local legacy = Sticky.ComputeSectionHeaderTops(
                10, 5, 3, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT, SECTION_GAP_BEFORE_TOOLTIP)
            assert.are.same(legacy, tops)
            assert.are.equal(3, #metas)
            assert.are.equal("items", metas[1].id)
            assert.are.equal(HEADER_HEIGHT + HEADER_ROW_GAP, metas[1].sectionTop)
            assert.are.equal("tooltip", metas[3].id)
        end)
    end)

    describe("ComputeStickyTops", function()
        it("returns natural positions when nothing is scrolled", function()
            local tops = { 0, 300, 600 }
            local sticky = Sticky.ComputeStickyTops(tops, 0, HEADER_HEIGHT)
            assert.are.same({ 0, 300, 600 }, sticky)
        end)

        it("pins the first header at 0 once scrolled past it", function()
            local tops = { 0, 300, 600 }
            local sticky = Sticky.ComputeStickyTops(tops, 50, HEADER_HEIGHT)
            assert.are.equal(0, sticky[1])
            assert.are.equal(250, sticky[2])
            assert.are.equal(550, sticky[3])
        end)

        it("pushes the first header up when the second header reaches the top", function()
            local tops = { 0, 300, 600 }
            local scrollValue = 300
            local sticky = Sticky.ComputeStickyTops(tops, scrollValue, HEADER_HEIGHT)
            assert.are.equal(-18, sticky[1])
            assert.are.equal(0, sticky[2])
            assert.are.equal(300, sticky[3])
        end)

        it("pins the last header with no further push", function()
            local tops = { 0, 300 }
            local scrollValue = 500
            local sticky = Sticky.ComputeStickyTops(tops, scrollValue, HEADER_HEIGHT)
            assert.are.equal(-218, sticky[1])
            assert.are.equal(0, sticky[2])
        end)

        it("handles a single visible section", function()
            local tops = { 0 }
            assert.are.same({ 0 }, Sticky.ComputeStickyTops(tops, 0, HEADER_HEIGHT))
            assert.are.same({ 0 }, Sticky.ComputeStickyTops(tops, 100, HEADER_HEIGHT))
        end)

        it("handles an empty header list", function()
            assert.are.same({}, Sticky.ComputeStickyTops({}, 100, HEADER_HEIGHT))
        end)
    end)

    describe("ComputeSectionHeaderTops", function()
        it("collapses when preceding sections are empty", function()
            local tops = Sticky.ComputeSectionHeaderTops(0, 2, 0, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT)
            assert.are.same({ 0 }, tops)

            tops = Sticky.ComputeSectionHeaderTops(0, 0, 3, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT)
            assert.are.same({ 0 }, tops)
        end)

        it("returns three tops when all sections have results", function()
            local tops = Sticky.ComputeSectionHeaderTops(
                5, 3, 2, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT, SECTION_GAP_BEFORE_TOOLTIP)
            local expected, _ = computeSectionHeaderTops(5, 3, 2)
            assert.are.same(expected, tops)
        end)

        it("adds section gap before tooltip only when recipes precede it", function()
            local withRecipes = Sticky.ComputeSectionHeaderTops(
                0, 2, 1, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT, SECTION_GAP_BEFORE_TOOLTIP)
            local withoutGap = Sticky.ComputeSectionHeaderTops(
                0, 2, 1, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT, 0)
            assert.are.equal(withoutGap[2] + SECTION_GAP_BEFORE_TOOLTIP, withRecipes[2])

            local itemsOnlyThenTooltip = Sticky.ComputeSectionHeaderTops(
                2, 0, 1, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT, SECTION_GAP_BEFORE_TOOLTIP)
            local itemsOnlyNoGapArg = Sticky.ComputeSectionHeaderTops(
                2, 0, 1, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT, 0)
            assert.are.same(itemsOnlyNoGapArg, itemsOnlyThenTooltip)
        end)
    end)
end)
