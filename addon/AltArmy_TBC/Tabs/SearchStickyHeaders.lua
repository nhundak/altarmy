-- AltArmy TBC — Pure helpers for search tab sticky section headers.

if not AltArmy then return end

AltArmy.SearchStickyHeaders = AltArmy.SearchStickyHeaders or {}

local Sticky = AltArmy.SearchStickyHeaders

--- Content-coordinate tops for visible section headers (top of list = 0).
function Sticky.ComputeSectionHeaderTops(nItems, nRecipes, nTooltipOnly, headerHeight, headerRowGap, rowHeight)
    local tops = {}
    local currentTop = 0
    local blockHeight = headerHeight + headerRowGap

    if nItems > 0 then
        tops[#tops + 1] = currentTop
        currentTop = currentTop + blockHeight + nItems * rowHeight
    end
    if nRecipes > 0 then
        tops[#tops + 1] = currentTop
        currentTop = currentTop + blockHeight + nRecipes * rowHeight
    end
    if nTooltipOnly > 0 then
        tops[#tops + 1] = currentTop
    end

    return tops
end

--- Viewport-relative Y for each header; later headers push earlier ones upward.
function Sticky.ComputeStickyTops(headerTops, scrollValue, headerHeight)
    local stickyTops = {}
    if not headerTops or #headerTops == 0 then
        return stickyTops
    end

    scrollValue = scrollValue or 0
    headerHeight = headerHeight or 0

    for i, headerTop in ipairs(headerTops) do
        local naturalTop = headerTop - scrollValue
        local stickyTop = naturalTop
        if stickyTop < 0 then
            stickyTop = 0
        end

        local nextTop = headerTops[i + 1]
        if nextTop ~= nil then
            local nextNatural = nextTop - scrollValue
            local pushLimit = nextNatural - headerHeight
            if stickyTop > pushLimit then
                stickyTop = pushLimit
            end
        end

        stickyTops[i] = stickyTop
    end

    return stickyTops
end
