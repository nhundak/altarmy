-- AltArmy TBC — Pure helpers for search tab sticky section headers.

if not AltArmy then return end

AltArmy.SearchStickyHeaders = AltArmy.SearchStickyHeaders or {}

local Sticky = AltArmy.SearchStickyHeaders

--- Layout for a list of visible sections.
--- Each section: { id=, rowCount=, gapBefore= (optional, before this section's header) }.
--- Returns headerTops (content Y of each header) and sectionMetas
--- ({ id, rowCount, sectionTop } where sectionTop is the first data row Y).
function Sticky.ComputeSectionLayout(sections, headerHeight, headerRowGap, rowHeight)
    local headerTops = {}
    local sectionMetas = {}
    local currentTop = 0
    local blockHeight = (headerHeight or 0) + (headerRowGap or 0)
    rowHeight = rowHeight or 0

    for i = 1, #(sections or {}) do
        local sec = sections[i]
        local gapBefore = tonumber(sec.gapBefore) or 0
        if gapBefore > 0 then
            currentTop = currentTop + gapBefore
        end
        headerTops[#headerTops + 1] = currentTop
        local sectionTop = currentTop + blockHeight
        sectionMetas[#sectionMetas + 1] = {
            id = sec.id,
            rowCount = sec.rowCount or 0,
            sectionTop = sectionTop,
        }
        currentTop = sectionTop + (sec.rowCount or 0) * rowHeight
    end

    return headerTops, sectionMetas
end

--- Content-coordinate tops for visible section headers (top of list = 0).
--- Optional `sectionGapBeforeTooltip` adds space after the recipes block before the
--- "You may also be interested in" header (when both sections are present).
function Sticky.ComputeSectionHeaderTops(
    nItems, nRecipes, nTooltipOnly, headerHeight, headerRowGap, rowHeight, sectionGapBeforeTooltip)
    local sections = {}
    if nItems and nItems > 0 then
        sections[#sections + 1] = { id = "items", rowCount = nItems }
    end
    if nRecipes and nRecipes > 0 then
        sections[#sections + 1] = { id = "recipes", rowCount = nRecipes }
    end
    if nTooltipOnly and nTooltipOnly > 0 then
        local gap = 0
        if nRecipes and nRecipes > 0 then
            gap = tonumber(sectionGapBeforeTooltip) or 0
        end
        sections[#sections + 1] = { id = "tooltip", rowCount = nTooltipOnly, gapBefore = gap }
    end
    local tops = Sticky.ComputeSectionLayout(sections, headerHeight, headerRowGap, rowHeight)
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
