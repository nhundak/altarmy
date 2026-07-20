-- AltArmy TBC — Search tab: item search across characters (bags + bank).

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
if not frame then
    return
end

local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString
local VirtualList = AltArmy.VirtualList
-- Layout / list metrics packed to stay under Lua 5.1's 200-local / function limit.
local UI = {
    PAD = 4,
    SECTION_INSET = Theme.TAB_SECTION_INSET,
    SECTION_GAP = Theme.SECTION_GAP,
    ROW_HEIGHT = 18,
    -- Right-side (Total column) icon size; match left-side row icon (WoW :0 default ~14)
    OVERLAY_ICON_SIZE = 14,
    HEADER_HEIGHT = 18,
    HEADER_ROW_GAP = 3, -- space between section header and first data row
    -- Extra space between the last recipe row and the "You may also be interested in" header.
    SECTION_GAP_BEFORE_TOOLTIP = 2,
    -- Virtualized list: only render rows near the viewport
    ROW_BUFFER = 6, -- extra rows above/below viewport; larger = fewer refill flickers while scrolling
    ITEM_POOL_SIZE = 40,
    RECIPE_POOL_SIZE = 40,
    TOOLTIP_ONLY_POOL_SIZE = 40,
    -- Refill before the visible window reaches the edge of the painted buffer.
    PAINT_COVER_MARGIN = 1,
    HORIZONTAL_SCROLL_BAR_HEIGHT = 20,
    TOOLTIP_CHUNK_SIZE = 80,
    GRID_SPLIT_FRACTION = 0.6,
    SEARCH_SETTINGS_WIDTH_TRIM = 60,
    SETTINGS_ROW_HEIGHT = 22,
    RECIPE_LEVEL_LABEL_GAP = 6,
    RECIPE_LEVEL_MIN_MAX_GAP = 12,
    RECIPE_LEVEL_RESET_GAP = 4,
    RECIPE_LEVEL_MIN_EDIT_WIDTH = 28,
    RECIPE_LEVEL_DEFAULT_EDIT_WIDTH = 40,
    RECIPE_LEVEL_ROW_GAP = 10,
    FILTER_SECTION_GAP = 12,
    FILTER_DROPDOWN_GAP = 4,
    FILTER_DROPDOWN_POPUP_PAD_LEFT = 10,
    FILTER_DROPDOWN_POPUP_PAD_TOP = 6,
    FILTER_DROPDOWN_POPUP_PAD_BOTTOM = 8,
    FILTER_DROPDOWN_POPUP_PAD_RIGHT = 8,
    FILTER_DROPDOWN_TEXT_INSET = 10,
}
local paint = {
    forceVisible = true,
    itemsFirst = nil,
    itemsLast = nil,
    recipesFirst = nil,
    recipesLast = nil,
    tooltipFirst = nil,
    tooltipLast = nil,
}

local SD = AltArmy.SearchEngine or AltArmy.SearchData
if not SD or not (SD.SearchItems or SD.SearchWithLocationGroups) or not SD.SearchRecipes then
    return
end
if not VirtualList or not VirtualList.GetRenderRange or not VirtualList.ShouldFillPoolRow then
    return
end

local GTD = AltArmy.GuildTabData
local RF = AltArmy.RealmFilter

local function GlobalRealmFilterValue()
    local G = AltArmy.GlobalRealmFilter
    if G and G.Get then
        return G.Get()
    end
    return "all"
end

--- True if the account has characters on more than one realm (used to decide whether to show realm suffix).
local function AccountHasMultipleRealms()
    local DS = AltArmy.DataStore
    if not DS or not DS.GetRealms then return false end
    local realms = DS:GetRealms()
    local n = 0
    for _ in pairs(realms or {}) do
        n = n + 1
        if n > 1 then return true end
    end
    return false
end

local ItemActions = AltArmy.ItemActions

--- Route a left-click on an item result row: Ctrl previews in the Dressing Room, Shift links to chat.
local function HandleItemRowClick(itemLinkOrID, button)
    if not ItemActions then return end
    local action = ItemActions.GetClickAction(
        button,
        IsShiftKeyDown and IsShiftKeyDown() or false,
        IsControlKeyDown and IsControlKeyDown() or false)
    if action == "preview" then
        ItemActions.PreviewInDressingRoom(itemLinkOrID)
    elseif action == "chatlink" then
        ItemActions.InsertLinkIntoChat(itemLinkOrID)
    end
end

-- Recipe link for display/tooltip: try spell first (most recipes), then item (recipe scrolls)
local function GetRecipeLink(recipeID)
    if not recipeID then return nil end
    if _G.GetSpellLink then
        local link = _G.GetSpellLink(recipeID)
        if link and link ~= "" then return link end
    end
    if GetItemInfo then
        local _, link = GetItemInfo(recipeID)
        if link and link ~= "" then return link end
    end
    return nil
end

-- Hidden edit box for header search flow (SearchWithQuery sets text, DoSearch reads it)
local searchEdit = CreateFrame("EditBox", "AltArmyTBC_SearchEditBox", frame)
searchEdit:SetPoint("LEFT", frame, "LEFT", -1000, 0)
searchEdit:SetSize(1, 1)
searchEdit:Hide()
searchEdit:SetAutoFocus(false)
searchEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
    if frame.DoSearch then frame:DoSearch() end
end)
searchEdit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

local SearchColumns = AltArmy.SearchColumns
local colOrder = SearchColumns and SearchColumns.ITEM_COLUMN_ORDER
    or { "Item", "Character", "Total" }
local recipeColOrder = SearchColumns and SearchColumns.RECIPE_COLUMN_ORDER
    or { "Recipe", "Character", "Skill" }
local colWidths = {}
local recipeColWidths = {}

local function SyncSearchColumnWidths(settingsOpen)
    local item = SearchColumns and SearchColumns.GetItemColumnWidths(settingsOpen)
        or { Item = 344, Character = 180, Total = 72 }
    local recipe = SearchColumns and SearchColumns.GetRecipeColumnWidths(settingsOpen)
        or { Recipe = 344, Character = 180, Skill = 72 }
    for k, v in pairs(item) do
        colWidths[k] = v
    end
    for k, v in pairs(recipe) do
        recipeColWidths[k] = v
    end
end

SyncSearchColumnWidths(false)

local function SetCharacterCellTruncated(cell, namePartColored, suffixText, maxTotalWidth)
    if TruncateFontString then
        TruncateFontString(cell, namePartColored, maxTotalWidth, {
            preserveColorCodes = true,
            suffix = suffixText,
        })
    else
        cell:SetText((namePartColored or "") .. (suffixText or ""))
    end
end

local function SetItemCellTruncated(cell, itemName, countSuffix, iconPrefix, maxTotalWidth)
    if TruncateFontString then
        TruncateFontString(cell, itemName, maxTotalWidth, {
            prefix = iconPrefix or "",
            suffix = countSuffix,
            preserveColorCodes = itemName:find("|c", 1, true) ~= nil,
        })
    else
        cell:SetText((iconPrefix or "") .. itemName .. countSuffix)
    end
end

local function buildCharacterNamePart(entry, showRealmSuffix)
    local name = entry.characterName or ""
    if RF and RF.formatColoredCharacterNameRealm then
        return RF.formatColoredCharacterNameRealm(name, entry.realm, showRealmSuffix, entry.classFile)
    end
    local r, g, b = 1, 0.82, 0
    if CC and CC.getRGBOr then
        r, g, b = CC.getRGBOr(entry.classFile, r, g, b)
    end
    return CC and CC.formatHex and CC.formatHex(r, g, b, name)
        or string.format(
            "|cFF%02x%02x%02x%s|r",
            math.floor(r * 255), math.floor(g * 255), math.floor(b * 255),
            name
        )
end

local function maybeHighlightSearchText(text, highlightSearch, query)
    if highlightSearch and query and query ~= "" and GTD and GTD.FormatTextWithSearchHighlight then
        return GTD.FormatTextWithSearchHighlight(text, nil, query)
    end
    return text
end

-- Main tab content: bordered panel (same styling as settings panel).
local tabContentPanel = Theme.CreateTabContentPanel(frame)
local tabContentInner = Theme.CreatePanelInnerContent(tabContentPanel)

-- List viewport: clips results; horizontal scroll when viewport is narrower than totalColWidth.
local listViewport = CreateFrame("Frame", nil, tabContentInner)
listViewport:SetClipsChildren(true)
-- Points set in ApplySearchListLayout

local HINT_NO_SEARCH_RESULTS_BOTH = "No matching items or recipes\nwere found for your search."
local noResultsHint = tabContentInner:CreateFontString(nil, "OVERLAY", "GameFontDisable")
noResultsHint:SetPoint("CENTER", listViewport, "CENTER", 0, 0)
noResultsHint:SetWidth(280)
noResultsHint:SetJustifyH("CENTER")
noResultsHint:SetText(HINT_NO_SEARCH_RESULTS_BOTH)
noResultsHint:Hide()

local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_SearchHorizontalScroll", listViewport)
horizontalScroll:SetAllPoints(listViewport)
horizontalScroll:EnableMouse(true)

-- horizontalScrollChild created after totalColWidth is known; scrollFrame reparented into it below

-- Scroll frame (viewport for results; section headers live inside scroll)
local scrollFrame = CreateFrame("ScrollFrame", "AltArmyTBC_SearchScrollFrame", frame)
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -UI.PAD)
scrollFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PAD - 20, -UI.PAD)
scrollFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", UI.PAD, UI.PAD)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PAD - 20, UI.PAD)
scrollFrame:EnableMouse(true)

-- Custom vertical scroll bar (same style as Gear tab)
UI.SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local searchScrollBar = CreateFrame("Slider", "AltArmyTBC_SearchScrollBar", tabContentInner)
searchScrollBar:SetMinMaxValues(0, 0)
searchScrollBar:SetValueStep(UI.ROW_HEIGHT)
searchScrollBar:SetValue(0)
searchScrollBar:EnableMouse(true)
-- OnValueChanged set below after UpdateVisibleRows is defined

-- Horizontal scroll bar at bottom of list area (like Summary tab)
local UpdateStickyHeaders
local horizontalScrollApi = Theme.CreateHorizontalScrollBar(tabContentInner, {
    name = "AltArmyTBC_SearchHorizontalScrollBar",
    thickness = UI.HORIZONTAL_SCROLL_BAR_HEIGHT - UI.PAD * 2,
    onScroll = function(value)
        if not horizontalScroll then return end
        if horizontalScroll.UpdateScrollChildRect then
            horizontalScroll:UpdateScrollChildRect()
        end
        horizontalScroll:SetHorizontalScroll(value)
        if UpdateStickyHeaders then
            UpdateStickyHeaders()
        end
    end,
    isShown = function()
        return frame:IsShown()
    end,
})
local horizontalScrollBar = horizontalScrollApi.bar

local function OnSearchScrollWheel(_, delta)
    if not searchScrollBar then return end
    local minVal, maxVal = searchScrollBar:GetMinMaxValues()
    local current = searchScrollBar:GetValue()
    local newVal = current - delta * UI.ROW_HEIGHT * 2
    newVal = math.max(minVal, math.min(maxVal, newVal))
    searchScrollBar:SetValue(newVal)
    scrollFrame:SetVerticalScroll(newVal)
end
scrollFrame:SetScript("OnMouseWheel", OnSearchScrollWheel)

-- Results area (scroll child; stacks Items section then Recipes section)
local function getTotalColWidth()
    local w = 0
    for _, colName in ipairs(colOrder) do w = w + (colWidths[colName] or 80) end
    return w
end
local function getRecipeColWidth()
    local w = 0
    for _, colName in ipairs(recipeColOrder) do w = w + (recipeColWidths[colName] or 80) end
    return w
end
local totalColWidth = SearchColumns and SearchColumns.GetResultsTableWidth(false)
    or math.max(getTotalColWidth(), getRecipeColWidth())

-- Horizontal scroll child: holds the vertical scroll frame so the whole results area can scroll horizontally
local horizontalScrollChild = CreateFrame("Frame", nil, horizontalScroll)
horizontalScrollChild:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
horizontalScrollChild:SetHeight(1)
horizontalScrollChild:SetWidth(totalColWidth)
horizontalScroll:SetScrollChild(horizontalScrollChild)

-- Reparent scroll frame into horizontal scroll child so it scrolls with the grid.
-- Inset 2px from the top so row text cannot draw into the seam above the sticky header
-- (ScrollFrame clips its child; a full-bleed top edge lets 1–2px of text peek through).
scrollFrame:ClearAllPoints()
scrollFrame:SetParent(horizontalScrollChild)
scrollFrame:SetPoint("TOPLEFT", horizontalScrollChild, "TOPLEFT", 0, -2)
scrollFrame:SetPoint("BOTTOMLEFT", horizontalScrollChild, "BOTTOMLEFT", 0, 0)
scrollFrame:SetPoint("BOTTOMRIGHT", horizontalScrollChild, "BOTTOMRIGHT", 0, 0)

local function StyleStickySearchHeader(headerRow)
    headerRow:EnableMouse(true)
    headerRow:SetScript("OnMouseWheel", OnSearchScrollWheel)
    local headerBg = headerRow:CreateTexture(nil, "BACKGROUND")
    -- Overhang above the header frame seals the viewport top edge under the sticky header.
    headerBg:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 2)
    headerBg:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 2)
    headerBg:SetPoint("BOTTOMLEFT", headerRow, "BOTTOMLEFT", 0, 0)
    headerBg:SetPoint("BOTTOMRIGHT", headerRow, "BOTTOMRIGHT", 0, 0)
    Theme.StyleGridHeader(headerBg)
    -- Draw above nested scroll frames so row text cannot peek at the viewport seam.
    headerRow:SetFrameLevel((listViewport:GetFrameLevel() or 0) + 40)
end

-- Viewport-fixed strip covering the top seam when a section header is pinned.
local stickyHeaderTopSeal = CreateFrame("Frame", nil, listViewport)
stickyHeaderTopSeal:SetHeight(2)
stickyHeaderTopSeal:SetPoint("TOPLEFT", listViewport, "TOPLEFT", 0, 0)
stickyHeaderTopSeal:SetPoint("TOPRIGHT", listViewport, "TOPRIGHT", 0, 0)
stickyHeaderTopSeal:SetFrameLevel((listViewport:GetFrameLevel() or 0) + 45)
local stickyHeaderTopSealBg = stickyHeaderTopSeal:CreateTexture(nil, "BACKGROUND")
stickyHeaderTopSealBg:SetAllPoints(stickyHeaderTopSeal)
Theme.StyleGridHeader(stickyHeaderTopSealBg)
stickyHeaderTopSeal:EnableMouse(false)
stickyHeaderTopSeal:Hide()

local resultsArea = CreateFrame("Frame", nil, scrollFrame)
resultsArea:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
resultsArea:SetWidth(totalColWidth)
resultsArea:SetHeight(UI.ROW_HEIGHT)
scrollFrame:SetScrollChild(resultsArea)
resultsArea:SetScript("OnMouseWheel", OnSearchScrollWheel)

-- Result list state (declared before section headers; header clicks update sort and refresh).
local resultRows = {}
local itemList = {}
local recipeList = {}
local localRecipeList = {}
local recipeRows = {}
local itemGroups = {}
local tooltipOnlyItemList = {}
local tooltipOnlyItemGroups = {}
local tooltipOnlyResultRows = {}
-- Raw merged recipe hits (pre-collapse). Display list is recipeList after sort+collapse.
-- expandedIDs: set of recipeIDs whose guild rows are currently expanded.
local recipeCollapseState = { mergedList = {}, expandedIDs = {} }
-- Built in UpdateResults; reused by UpdateVisibleRows so scroll does not rebuild guild roster.
local searchRosterByName = nil
local UpdateVisibleRows
local UpdateResults
local RefreshSearchHeaderSortLabels

local sectionSort = {
    items = { key = "Item", ascending = true },
    recipes = { key = "Recipe", ascending = true },
    tooltip = { key = "Item", ascending = true },
}

local function resetSectionSorts()
    sectionSort.items.key = "Item"
    sectionSort.items.ascending = true
    sectionSort.recipes.key = "Recipe"
    sectionSort.recipes.ascending = true
    sectionSort.tooltip.key = "Item"
    sectionSort.tooltip.ascending = true
end

local function resetRecipeCollapseExpanded()
    recipeCollapseState.expandedIDs = {}
end

local function isCraftLibAvailable()
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    return RCL and RCL.IsAvailable and RCL.IsAvailable() or false
end

local function applySectionSorts()
    if sectionSort.items.key then
        itemList = SD.SortItemResults(itemList, sectionSort.items.key, sectionSort.items.ascending)
    end
    if sectionSort.recipes.key then
        local sorted = SD.SortRecipeResults(
            recipeCollapseState.mergedList,
            sectionSort.recipes.key,
            sectionSort.recipes.ascending,
            isCraftLibAvailable())
        if SD.CollapseGuildRecipeRows then
            recipeList = SD.CollapseGuildRecipeRows(sorted, recipeCollapseState.expandedIDs)
        else
            recipeList = sorted
        end
    end
    if sectionSort.tooltip.key then
        tooltipOnlyItemList = SD.SortItemResults(
            tooltipOnlyItemList, sectionSort.tooltip.key, sectionSort.tooltip.ascending)
    end
end

-- Sticky section headers overlay the clipping viewport (not the nested scroll-child),
-- so they seal the top edge above scrolling row text. X is synced to horizontal scroll.
local itemsHeaderRow = CreateFrame("Frame", nil, listViewport)
itemsHeaderRow:SetHeight(UI.HEADER_HEIGHT)
StyleStickySearchHeader(itemsHeaderRow)
itemsHeaderRow:Hide()
local itemsHeaderButtons = {}
-- Recipes section header
local recipesHeaderRow = CreateFrame("Frame", nil, listViewport)
recipesHeaderRow:SetHeight(UI.HEADER_HEIGHT)
StyleStickySearchHeader(recipesHeaderRow)
recipesHeaderRow:Hide()
local recipesHeaderButtons = {}

-- "You may also be interested in:" section header: same columns as items (Item/Character/Total),
-- with the first column label replaced by the section title.
local alsoInterestedHeaderRow = CreateFrame("Frame", nil, listViewport)
alsoInterestedHeaderRow:SetHeight(UI.HEADER_HEIGHT)
StyleStickySearchHeader(alsoInterestedHeaderRow)
alsoInterestedHeaderRow:Hide()
local alsoInterestedHeaderButtons = {}

local function defaultAscendingForSortKey(sortKey)
    return sortKey ~= "Skill"
end

local function createSearchHeaderButton(headerRow, sectionId, colName, justifyLeft)
    local btn = CreateFrame("Button", nil, headerRow)
    btn:SetHeight(UI.HEADER_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    label:SetJustifyH(justifyLeft and "LEFT" or "RIGHT")
    btn.label = label
    btn.colName = colName
    Theme.BindInteractableHover(btn)
    local clickCol = colName
    btn:SetScript("OnClick", function()
        local sortState = sectionSort[sectionId]
        if sortState.key == clickCol then
            sortState.ascending = not sortState.ascending
        else
            sortState.key = clickCol
            sortState.ascending = defaultAscendingForSortKey(clickCol)
        end
        UpdateResults()
    end)
    return btn
end

local function initSearchSectionHeader(headerRow, sectionId, columnOrder, buttonsByCol)
    for _, colName in ipairs(columnOrder) do
        local justifyLeft = colName == "Item" or colName == "Recipe"
        buttonsByCol[colName] = createSearchHeaderButton(headerRow, sectionId, colName, justifyLeft)
    end
end

initSearchSectionHeader(itemsHeaderRow, "items", colOrder, itemsHeaderButtons)
initSearchSectionHeader(recipesHeaderRow, "recipes", recipeColOrder, recipesHeaderButtons)
initSearchSectionHeader(alsoInterestedHeaderRow, "tooltip", colOrder, alsoInterestedHeaderButtons)

local scrollTopFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = itemsHeaderRow,
    scrollFrame = scrollFrame,
    scrollBar = searchScrollBar,
})
local stickyHeaderFadeFrame = scrollTopFade.frame

-- Debounce for tooltip-only search: main results appear immediately.
-- Delay: 1 char → 0.4s; 2 chars → 0.1s; 3+ → start chunked scan immediately.
-- Guild recipes always merge in the same frame as local recipe results.
local tooltipDebounceFrame = CreateFrame("Frame")
local tooltipDebounceRemaining = 0
local tooltipDebounceQuery = nil
local tooltipChunkFrame = CreateFrame("Frame")
local tooltipChunkState = nil
local tooltipChunkGeneration = 0

local function ApplyTooltipOnlyRealmFilter(rows)
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if RF and RF.filterListByRealm then
        return RF.filterListByRealm(rows or {}, GlobalRealmFilterValue(), currentRealm)
    end
    return rows or {}
end

local function ApplyRecipeRealmFilter(rows)
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if RF and RF.filterListByRealm then
        return RF.filterListByRealm(rows or {}, GlobalRealmFilterValue(), currentRealm)
    end
    return rows or {}
end

local function StopTooltipChunkSearch()
    tooltipChunkFrame:SetScript("OnUpdate", nil)
    tooltipChunkState = nil
end

local function StartTooltipChunkSearch(query)
    StopTooltipChunkSearch()
    if not query or query == "" or not frame:IsShown() then return end
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if not categories.Items then return end
    local all = SD.GetAllContainerSlots and SD.GetAllContainerSlots() or {}
    local queryLower, queryID = SD._ParseItemSearchQuery(query)
    if not queryLower then
        tooltipOnlyItemList = {}
        UpdateResults()
        return
    end
    tooltipChunkState = {
        generation = tooltipChunkGeneration,
        query = query,
        queryLower = queryLower,
        queryID = queryID,
        all = all,
        index = 1,
        total = #all,
        matches = {},
    }
    tooltipChunkFrame:SetScript("OnUpdate", function()
        local state = tooltipChunkState
        if not state then
            StopTooltipChunkSearch()
            return
        end
        if state.generation ~= tooltipChunkGeneration then
            StopTooltipChunkSearch()
            return
        end
        if not frame:IsShown() then
            StopTooltipChunkSearch()
            return
        end
        local currentQuery = frame.lastQuery
        if currentQuery and currentQuery ~= state.query then
            StopTooltipChunkSearch()
            return
        end
        local categoriesNow = AltArmy.SearchCategories or { Items = true, Recipes = true }
        if not categoriesNow.Items then
            StopTooltipChunkSearch()
            tooltipOnlyItemList = {}
            UpdateResults()
            return
        end

        local processed = 0
        while processed < UI.TOOLTIP_CHUNK_SIZE and state.index <= state.total do
            local entry = state.all[state.index]
            state.index = state.index + 1
            processed = processed + 1
            if entry and not SD._IsMainSearchMatch(entry, state.queryLower, state.queryID) then
                local searchableText = SD._GetSearchableTextForItem(entry.itemID, entry.itemLink)
                if searchableText and searchableText:find(state.queryLower, 1, true) then
                    if SD._EnsureItemName then
                        SD._EnsureItemName(entry)
                    end
                    table.insert(state.matches, entry)
                end
            end
        end

        if state.index > state.total then
            StopTooltipChunkSearch()
            if state.generation ~= tooltipChunkGeneration then return end
            local rows
            if SD._AggregateAndSort then
                rows = SD._AggregateAndSort(state.matches, state.queryLower)
            else
                local _, fallback = SD.SearchWithLocationGroups(state.query)
                rows = fallback or {}
            end
            tooltipOnlyItemList = ApplyTooltipOnlyRealmFilter(rows)
            UpdateResults()
        end
    end)
end

local function tooltipDebounceOnUpdate(_, elapsed)
    tooltipDebounceRemaining = tooltipDebounceRemaining - elapsed
    if tooltipDebounceRemaining <= 0 then
        tooltipDebounceFrame:SetScript("OnUpdate", nil)
        local query = tooltipDebounceQuery
        tooltipDebounceQuery = nil
        StartTooltipChunkSearch(query)
    end
end

local function ScheduleTooltipSearch(query)
    tooltipChunkGeneration = tooltipChunkGeneration + 1
    StopTooltipChunkSearch()
    tooltipDebounceQuery = nil
    tooltipDebounceFrame:SetScript("OnUpdate", nil)
    if not query or query == "" then
        return
    end
    local delay = (SD.GetSearchTailDebounceSecs and SD.GetSearchTailDebounceSecs(query)) or 0.4
    if delay <= 0 then
        StartTooltipChunkSearch(query)
        return
    end
    tooltipDebounceQuery = query
    tooltipDebounceRemaining = delay
    tooltipDebounceFrame:SetScript("OnUpdate", tooltipDebounceOnUpdate)
end

local function IsTooltipSearchPending()
    if tooltipDebounceFrame:GetScript("OnUpdate") then
        return true
    end
    return tooltipChunkState ~= nil
end

--- Merge guild recipe hits into mergedList in the same frame as local results (no layout).
local function MergeGuildRecipesNow(query)
    if not query or query == "" then
        return
    end
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if not categories.Recipes then
        return
    end
    if not SD.SearchGuildRecipes then
        return
    end
    local guildHits = ApplyRecipeRealmFilter(SD.SearchGuildRecipes(query) or {})
    if SD.MergeRecipeSearchResults then
        recipeCollapseState.mergedList = SD.MergeRecipeSearchResults(localRecipeList, guildHits)
    else
        local merged = {}
        for i = 1, #localRecipeList do
            merged[i] = localRecipeList[i]
        end
        for i = 1, #guildHits do
            merged[#merged + 1] = guildHits[i]
        end
        recipeCollapseState.mergedList = merged
    end
end

local function ScheduleGuildRecipeSearch(query)
    MergeGuildRecipesNow(query)
end

local function CountSearchResults(categories)
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local nTooltipOnly = categories.Items and #tooltipOnlyItemList or 0
    return nItems + nRecipes + nTooltipOnly
end

local function GetNoSearchResultsHintText(categories)
    categories = categories or {}
    local items = categories.Items and true or false
    local recipes = categories.Recipes and true or false
    if not items and not recipes then
        return "Choose Items and/or Recipes above"
    end
    if items and recipes then
        return HINT_NO_SEARCH_RESULTS_BOTH
    end
    if items then
        return "No matching items\nwere found for your search."
    end
    return "No matching recipes\nwere found for your search."
end
frame.GetNoSearchResultsHintText = GetNoSearchResultsHintText

local function ShouldShowNoSearchResultsHint(query, categories, resultCount, tooltipPending)
    if not query or query == "" then
        return false
    end
    if resultCount > 0 then
        return false
    end
    if categories.Items and tooltipPending then
        return false
    end
    return true
end

local function UpdateNoResultsHint()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local show = ShouldShowNoSearchResultsHint(
        frame.lastQuery,
        categories,
        CountSearchResults(categories),
        IsTooltipSearchPending())
    if show then
        noResultsHint:SetText(GetNoSearchResultsHintText(categories))
        noResultsHint:Show()
    else
        noResultsHint:Hide()
    end
end

-- Group overlay: total count (centered in group) + item icon to the right
local groupOverlayPool = {}
local function getGroupOverlay(i)
    if not groupOverlayPool[i] then
        local overlay = CreateFrame("Frame", nil, resultsArea)
        overlay:SetFrameLevel(resultsArea:GetFrameLevel() + 1)
        overlay.total = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        overlay.total:SetJustifyH("RIGHT")
        overlay.icon = overlay:CreateTexture(nil, "OVERLAY")
        overlay.icon:SetSize(UI.OVERLAY_ICON_SIZE, UI.OVERLAY_ICON_SIZE)
        groupOverlayPool[i] = overlay
    end
    return groupOverlayPool[i]
end

local tooltipOnlyGroupOverlayPool = {}
local function getTooltipOnlyGroupOverlay(i)
    if not tooltipOnlyGroupOverlayPool[i] then
        local overlay = CreateFrame("Frame", nil, resultsArea)
        overlay:SetFrameLevel(resultsArea:GetFrameLevel() + 1)
        overlay.total = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        overlay.total:SetJustifyH("RIGHT")
        overlay.icon = overlay:CreateTexture(nil, "OVERLAY")
        overlay.icon:SetSize(UI.OVERLAY_ICON_SIZE, UI.OVERLAY_ICON_SIZE)
        tooltipOnlyGroupOverlayPool[i] = overlay
    end
    return tooltipOnlyGroupOverlayPool[i]
end

local function createItemRow()
    local row = CreateFrame("Frame", nil, resultsArea)
    row:SetHeight(UI.ROW_HEIGHT)
    row:EnableMouse(true)
    row.cells = {}
    local cx = 0
    for _, colName in ipairs(colOrder) do
        local w = colWidths[colName] or 80
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
        cell:SetWidth(w)
        cell:SetHeight(UI.ROW_HEIGHT)
        cell:SetJustifyV("MIDDLE")
        cell:SetJustifyH(colName == "Item" and "LEFT" or "RIGHT")
        cell:SetNonSpaceWrap(false)
        if colName == "Item" or colName == "Character" then cell:SetWordWrap(false) end
        row.cells[colName] = cell
        cx = cx + w
    end
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            if entry.itemLink and entry.itemLink ~= "" then
                GameTooltip:SetHyperlink(entry.itemLink)
            elseif entry.itemID then
                GameTooltip:SetItemByID(entry.itemID)
            else
                GameTooltip:SetText("Item " .. tostring(entry.itemID or "?"))
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        local entry = self.entry
        if not entry then return end
        HandleItemRowClick(entry.itemLink or entry.itemID, button)
    end)
    return row
end

local function createRecipeRow()
    local row = CreateFrame("Frame", nil, resultsArea)
    row:SetHeight(UI.ROW_HEIGHT)
    row:EnableMouse(true)
    row.cells = {}
    local cx = 0
    for _, colName in ipairs(recipeColOrder) do
        local w = recipeColWidths[colName] or 80
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
        cell:SetWidth(w)
        cell:SetHeight(UI.ROW_HEIGHT)
        cell:SetJustifyV("MIDDLE")
        cell:SetJustifyH(colName == "Recipe" and "LEFT" or "RIGHT")
        cell:SetNonSpaceWrap(false)
        if colName == "Recipe" or colName == "Character" then cell:SetWordWrap(false) end
        row.cells[colName] = cell
        cx = cx + w
    end
    -- Clickable character name overlay (own + guildmate; Character column, full row height).
    local charBtn = CreateFrame("Button", nil, row)
    charBtn:SetPoint("TOP", row, "TOP", 0, 0)
    charBtn:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    charBtn:SetPoint("LEFT", row.cells.Character, "LEFT", 0, 0)
    charBtn:SetPoint("RIGHT", row.cells.Character, "RIGHT", 0, 0)
    charBtn:SetFrameLevel(row:GetFrameLevel() + 2)
    charBtn:Hide()
    charBtn:RegisterForClicks("LeftButtonUp")
    charBtn:SetScript("OnClick", function(self)
        local entry = self:GetParent().entry
        if not entry then return end
        -- Summary "Multiple guildmates" row: full-row button; shift-click link, else toggle.
        if entry.isGuildCollapsed and entry.recipeID ~= nil then
            if IsShiftKeyDown() then
                local link = GetRecipeLink(entry.recipeID)
                if link and ChatEdit_InsertLink then
                    ChatEdit_InsertLink(link)
                end
                return
            end
            if entry.isGuildExpanded or recipeCollapseState.expandedIDs[entry.recipeID] then
                recipeCollapseState.expandedIDs[entry.recipeID] = nil
            else
                recipeCollapseState.expandedIDs[entry.recipeID] = true
            end
            UpdateResults()
            return
        end
        local Nav = AltArmy.SearchGuildNav
        if not Nav then return end
        -- Guildmates: whisper the online character. Own characters: guild drill-in.
        if entry.isGuild then
            if Nav.OpenGuildRecipeWhisper then
                Nav.OpenGuildRecipeWhisper(entry.characterName, entry.realm, {
                    rosterByName = searchRosterByName,
                })
            end
            return
        end
        if not Nav.IsGuildRecipeCharacterClickable
            or not Nav.IsGuildRecipeCharacterClickable(entry) then
            return
        end
        if AltArmy.OpenGuildCharacterFromSearch then
            AltArmy.OpenGuildCharacterFromSearch(
                entry.characterName,
                entry.realm,
                entry.professionKey,
                entry.professionName,
                entry.recipeID)
        end
    end)
    Theme.InstallHoverTint(row)
    Theme.BindInteractableHover(charBtn, {
        onEnter = function(self)
            local entry = self:GetParent().entry
            if not entry or not GameTooltip then return end
            local Nav = AltArmy.SearchGuildNav
            if entry.isGuildCollapsed then
                -- Full-row click highlight lives on the row; suppress the Character/Skill-only tint.
                Theme.SetHoverTint(self, false)
                Theme.SetHoverTint(self:GetParent(), true)
                local lines = Nav and Nav.GetCollapsedGuildRecipeTooltipLines
                    and Nav.GetCollapsedGuildRecipeTooltipLines(entry, {
                        rosterByName = searchRosterByName,
                    })
                if not lines or not lines[1] then return end
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                for i = 1, #lines do
                    local line = lines[i]
                    if type(line) == "table" then
                        -- Name left, last-online right-aligned (embedded colors; RGB neutral).
                        GameTooltip:AddDoubleLine(
                            line.left or "", line.right or "", 1, 1, 1, 1, 1, 1)
                    else
                        GameTooltip:AddLine(line, 1, 1, 1, true)
                    end
                end
                GameTooltip:Show()
                return
            end
            local hoverOpts = { rosterByName = searchRosterByName }
            if entry.isGuild and Nav and Nav.IsGuildRecipeCharacterClickable
                and not Nav.IsGuildRecipeCharacterClickable(entry, hoverOpts) then
                -- Offline guildmate: keep tooltip, no interactable highlight.
                Theme.SetHoverTint(self, false)
            end
            local lines = Nav and Nav.GetGuildCharacterHoverTooltipLines
                and Nav.GetGuildCharacterHoverTooltipLines(
                    entry.characterName, entry.realm, hoverOpts)
            if not lines or not lines[1] then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            for i = 1, #lines do
                -- Embedded white/gray + class colors; keep AddLine RGB neutral.
                GameTooltip:AddLine(lines[i], 1, 1, 1, true)
            end
            GameTooltip:Show()
        end,
        onLeave = function(self)
            local parent = self:GetParent()
            local entry = parent and parent.entry
            if entry and entry.isGuildCollapsed then
                Theme.SetHoverTint(parent, false)
            end
            if GameTooltip then GameTooltip:Hide() end
        end,
    })
    row.characterBtn = charBtn
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
        if entry.isGuildCollapsed then
            Theme.SetHoverTint(self, true)
        end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            local link = GetRecipeLink(entry.recipeID)
            if link then
                GameTooltip:SetHyperlink(link)
            else
                GameTooltip:SetText("Recipe " .. tostring(entry.recipeID or "?"))
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.entry and self.entry.isGuildCollapsed then
            Theme.SetHoverTint(self, false)
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        local entry = self.entry
        if not entry then return end
        if IsShiftKeyDown() then
            local link = GetRecipeLink(entry.recipeID)
            if link and ChatEdit_InsertLink then
                ChatEdit_InsertLink(link)
            end
            return
        end
        if entry.isGuildCollapsed and entry.recipeID ~= nil then
            if entry.isGuildExpanded or recipeCollapseState.expandedIDs[entry.recipeID] then
                recipeCollapseState.expandedIDs[entry.recipeID] = nil
            else
                recipeCollapseState.expandedIDs[entry.recipeID] = true
            end
            UpdateResults()
        elseif entry._aaFromCollapse and entry.recipeID ~= nil then
            recipeCollapseState.expandedIDs[entry.recipeID] = nil
            UpdateResults()
        end
    end)
    -- Indent rail for expanded child rows (recipe name omitted).
    local childRail = row:CreateTexture(nil, "ARTWORK")
    childRail:SetWidth(2)
    childRail:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -3)
    childRail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 3)
    childRail:SetColorTexture(0.55, 0.55, 0.60, 0.85)
    childRail:Hide()
    row.collapseChildRail = childRail
    return row
end

local function fillItemRow(row, entry, showRealmSuffix, rowOpts)
    if not row or not entry then return end
    rowOpts = rowOpts or {}
    if rowOpts.scrollDebug then
        if rowOpts.scrollDebugIsTooltip then
            SD.NoteScrollTooltipPaint(rowOpts.scrollDebug)
        else
            SD.NoteScrollItemPaint(rowOpts.scrollDebug)
        end
    end
    local highlightSearch = rowOpts.highlightSearch ~= false
    local searchQuery = rowOpts.searchQuery
    row.entry = entry
    local count = entry.count or 1
    local itemText = (entry.itemName and entry.itemName ~= "") and entry.itemName
        or ("Item " .. (entry.itemID or ""))
    itemText = maybeHighlightSearchText(itemText, highlightSearch, searchQuery)
    local countSuffix = " x" .. tostring(count)
    local iconPrefix = ""
    if entry.itemLink and GetItemInfo and GetItemInfo(entry.itemLink) then
        local icon = select(10, GetItemInfo(entry.itemLink)) or "Interface\\Icons\\INV_Misc_QuestionMark"
        iconPrefix = "|T" .. icon .. ":0|t "
    end
    SetItemCellTruncated(row.cells.Item, itemText, countSuffix, iconPrefix, colWidths.Item or 344)
    local locLabel = entry.location == "bank" and "Bank"
        or (entry.location == "mail" and "Mail")
        or (entry.location == "equipped" and "Equipped")
        or (entry.location == "keyring" and "Keyring")
        or "Bags"
    local namePart = buildCharacterNamePart(entry, showRealmSuffix)
    local suffixText = "|cffffffff (" .. locLabel .. ")|r"
    SetCharacterCellTruncated(row.cells.Character, namePart, suffixText, colWidths.Character or 160)
    row.cells.Total:SetText("")
end

local function restoreRecipeCharacterBtnAnchors(row)
    local charBtn = row.characterBtn
    if not charBtn or not row._aaCollapsedBtnWide then
        return
    end
    charBtn:ClearAllPoints()
    charBtn:SetPoint("TOP", row, "TOP", 0, 0)
    charBtn:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    charBtn:SetPoint("LEFT", row.cells.Character, "LEFT", 0, 0)
    charBtn:SetPoint("RIGHT", row.cells.Character, "RIGHT", 0, 0)
    row._aaCollapsedBtnWide = false
end

local function widenRecipeCharacterBtnForCollapse(row)
    local charBtn = row.characterBtn
    if not charBtn then return end
    -- Character + Skill only: player-list tooltip here; Recipe column keeps the recipe tooltip.
    -- Full-row click highlight is drawn on the row itself.
    charBtn:ClearAllPoints()
    charBtn:SetPoint("TOP", row, "TOP", 0, 0)
    charBtn:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    charBtn:SetPoint("LEFT", row.cells.Character, "LEFT", 0, 0)
    charBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row._aaCollapsedBtnWide = true
end

local function fillRecipeRow(row, entry, showRealmSuffix, rowOpts)
    if not row or not entry then return end
    rowOpts = rowOpts or {}
    local highlightSearch = rowOpts.highlightSearch ~= false
    local searchQuery = rowOpts.searchQuery
    row.entry = entry
    if rowOpts.scrollDebug and SD.NoteScrollRecipePaint then
        SD.NoteScrollRecipePaint(rowOpts.scrollDebug, entry)
    end
    -- Viewport-only CraftLib enrich (search defers this unless filters need it).
    if SD._EnrichRecipeEntry then
        SD._EnrichRecipeEntry(entry)
    end
    if SD.EnsureRecipeDisplayCache then
        SD.EnsureRecipeDisplayCache(entry)
    end

    local isCollapseChild = entry._aaFromCollapse and true or false
    if row.collapseChildRail then
        row.collapseChildRail:SetShown(isCollapseChild)
    end
    if isCollapseChild then
        row.cells.Recipe:SetText("")
    else
        local recipeName = entry._aaRecipeBaseName
            or ("Recipe " .. tostring(entry.recipeID or "?"))
        recipeName = maybeHighlightSearchText(recipeName, highlightSearch, searchQuery)
        local iconPath = entry._aaIconPath or "Interface\\Icons\\INV_Misc_QuestionMark"
        local iconPrefix = ("|T%s:0|t "):format(iconPath)
        SetItemCellTruncated(row.cells.Recipe, recipeName, "", iconPrefix, recipeColWidths.Recipe or 344)
    end

    if entry.isGuildCollapsed then
        SetCharacterCellTruncated(
            row.cells.Character,
            "|cff8ab4f8Multiple guildmates|r",
            nil,
            recipeColWidths.Character or 160)
        row.cells.Skill:SetText(entry._aaSkillCellText or "*")
        if row.characterBtn then
            widenRecipeCharacterBtnForCollapse(row)
            row.characterBtn:Show()
        end
        return
    end

    Theme.SetHoverTint(row, false)
    restoreRecipeCharacterBtnAnchors(row)
    local namePart = buildCharacterNamePart(entry, showRealmSuffix)
    local Nav = AltArmy.SearchGuildNav
    local charSuffix
    if entry.isGuild then
        if Nav and Nav.FormatGuildRecipeCharacterSuffix then
            charSuffix = Nav.FormatGuildRecipeCharacterSuffix(
                entry.characterName, entry.realm, rowOpts)
        else
            charSuffix = "|cff8ab4f8 (Guild)|r"
        end
    end
    SetCharacterCellTruncated(row.cells.Character, namePart, charSuffix, recipeColWidths.Character or 160)
    -- Guildmates always get a Character hit target (tooltip); highlight/click only when online.
    -- Own characters get it when drill-in is available.
    local showCharBtn = false
    if entry.isGuild then
        showCharBtn = true
    elseif Nav and Nav.IsGuildRecipeCharacterClickable
        and Nav.IsGuildRecipeCharacterClickable(entry, rowOpts) then
        showCharBtn = true
    end
    if row.characterBtn then
        row.characterBtn:SetShown(showCharBtn)
    end
    local skillText = entry._aaSkillCellText
    if not skillText then
        local RCL = AltArmy and AltArmy.RecipeCraftLib
        if RCL and RCL.FormatSkillCell then
            skillText = RCL.FormatSkillCell(entry.recipeSkillRequired, entry.skillRank, entry.difficulty)
        else
            skillText = tostring(entry.skillRank or 0)
        end
    end
    row.cells.Skill:SetText(skillText)
end

local function UpdateStickyHeaderFade(headerRows, stickyTops, scrollValue)
    if not stickyHeaderFadeFrame then
        return
    end

    if scrollValue <= 0 or #headerRows == 0 then
        stickyHeaderFadeFrame:Hide()
        return
    end

    local pinnedHeader = nil
    for i = #headerRows, 1, -1 do
        if stickyTops[i] == 0 then
            pinnedHeader = headerRows[i]
            break
        end
    end

    if not pinnedHeader then
        stickyHeaderFadeFrame:Hide()
        return
    end

    local topOverlap = 0
    stickyHeaderFadeFrame:ClearAllPoints()
    stickyHeaderFadeFrame:SetPoint("TOPLEFT", pinnedHeader, "BOTTOMLEFT", 0, topOverlap)
    stickyHeaderFadeFrame:SetPoint("TOPRIGHT", pinnedHeader, "BOTTOMRIGHT", 0, topOverlap)
    stickyHeaderFadeFrame:SetFrameLevel(pinnedHeader:GetFrameLevel() + 50)
    stickyHeaderFadeFrame:Show()
end

local function buildVisibleSearchSections(nItems, nRecipes, nTooltipOnly)
    local sections = {}
    if nItems > 0 then
        sections[#sections + 1] = { id = "items", rowCount = nItems }
    end
    if nRecipes > 0 then
        sections[#sections + 1] = { id = "recipes", rowCount = nRecipes }
    end
    if nTooltipOnly > 0 then
        sections[#sections + 1] = {
            id = "tooltip",
            rowCount = nTooltipOnly,
            gapBefore = (nRecipes > 0) and UI.SECTION_GAP_BEFORE_TOOLTIP or 0,
        }
    end
    return sections
end

UpdateStickyHeaders = function()
    local StickyMod = AltArmy.SearchStickyHeaders
    if not StickyMod or not listViewport then
        return
    end

    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local nTooltipOnly = #tooltipOnlyItemList

    local sections = buildVisibleSearchSections(nItems, nRecipes, nTooltipOnly)
    local headerTops = StickyMod.ComputeSectionLayout(
        sections, UI.HEADER_HEIGHT, UI.HEADER_ROW_GAP, UI.ROW_HEIGHT)
    local scrollValue = searchScrollBar and searchScrollBar:GetValue() or 0
    local stickyTops = StickyMod.ComputeStickyTops(headerTops, scrollValue, UI.HEADER_HEIGHT)

    local headerById = {
        items = itemsHeaderRow,
        recipes = recipesHeaderRow,
        tooltip = alsoInterestedHeaderRow,
    }
    local headerRows = {}
    for i = 1, #sections do
        headerRows[#headerRows + 1] = headerById[sections[i].id]
    end

    local hScroll = (horizontalScroll and horizontalScroll.GetHorizontalScroll
        and horizontalScroll:GetHorizontalScroll()) or 0
    local headerWidth = totalColWidth or 0
    local hasPinnedHeader = false
    for i, headerRow in ipairs(headerRows) do
        local stickyTop = stickyTops[i] or 0
        if stickyTop == 0 then
            hasPinnedHeader = true
        end
        headerRow:ClearAllPoints()
        headerRow:SetPoint("TOPLEFT", listViewport, "TOPLEFT", -hScroll, -stickyTop)
        headerRow:SetWidth(headerWidth)
    end

    if stickyHeaderTopSeal then
        stickyHeaderTopSeal:SetShown(hasPinnedHeader)
    end

    UpdateStickyHeaderFade(headerRows, stickyTops, scrollValue)
end

-- Place a Total-column group overlay spanning pool rows [firstPoolIdx, lastPoolIdx].
local function placeGroupOverlay(overlay, rows, firstPoolIdx, lastPoolIdx, totalColX, totalColW, firstEntry, groupTotal)
    local firstRowFrame = rows[firstPoolIdx]
    local lastRowFrame = rows[lastPoolIdx]
    if not firstRowFrame or not lastRowFrame or not firstRowFrame:IsShown() or not lastRowFrame:IsShown() then
        return
    end
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", firstRowFrame, "TOPLEFT", totalColX, 2)
    overlay:SetPoint("BOTTOMLEFT", lastRowFrame, "BOTTOMLEFT", totalColX, 2)
    overlay:SetPoint("TOPRIGHT", firstRowFrame, "TOPLEFT", totalColX + totalColW, 2)
    overlay:SetPoint("BOTTOMRIGHT", lastRowFrame, "BOTTOMLEFT", totalColX + totalColW, 2)
    overlay.icon:ClearAllPoints()
    overlay.icon:SetPoint("CENTER", overlay, "RIGHT", -2 - UI.OVERLAY_ICON_SIZE / 2, 0)
    local iconPath = "Interface\\Icons\\INV_Misc_QuestionMark"
    if firstEntry and firstEntry.itemLink and GetItemInfo then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(firstEntry.itemLink)
        if tex then iconPath = tex end
    end
    overlay.icon:SetTexture(iconPath)
    overlay.icon:Show()
    overlay.total:ClearAllPoints()
    overlay.total:SetPoint("RIGHT", overlay.icon, "LEFT", -3, 0)
    overlay.total:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    overlay.total:SetWidth(math.max(1, totalColW - UI.OVERLAY_ICON_SIZE - 2))
    overlay.total:SetText(tostring(groupTotal))
    overlay:Show()
end

local function hideUnusedOverlays(pool, usedCount)
    for idx = usedCount + 1, #pool do
        if pool[idx] then pool[idx]:Hide() end
    end
end

local function positionPooledRow(row, rowY)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, rowY)
    row:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, rowY)
    row:SetPoint("BOTTOMLEFT", resultsArea, "TOPLEFT", 0, rowY - UI.ROW_HEIGHT)
end

--- Paint one virtualized section (rows + optional group overlays).
local function paintSearchSection(cfg)
    local range = VirtualList.GetRenderRange(
        cfg.scrollValue, cfg.viewHeight, cfg.sectionTop, UI.ROW_HEIGHT, cfg.rowCount, UI.ROW_BUFFER)
    local paintFirstKey = cfg.paintFirstKey
    local paintLastKey = cfg.paintLastKey
    local refill = cfg.force
        or not range
        or not VirtualList.IsVisibleRangeCovered(
            range.firstVisible, range.lastVisible,
            paint[paintFirstKey], paint[paintLastKey], UI.PAINT_COVER_MARGIN)
    if range and refill then
        local firstRender = range.firstRender
        local lastRender = range.lastRender
        VirtualList.ForEachPoolSlot(cfg.poolSize, firstRender, range.renderCount,
            function(poolIdx, dataIndex)
                local row = cfg.rows[poolIdx]
                if not row then
                    row = cfg.createRow()
                    cfg.rows[poolIdx] = row
                end
                local entry = cfg.list[dataIndex]
                local rowY = VirtualList.RowTopOffset(cfg.sectionTop, dataIndex, UI.ROW_HEIGHT)
                positionPooledRow(row, rowY)
                if VirtualList.ShouldFillPoolRow(cfg.force, row.dataIndex, dataIndex) then
                    cfg.fillRow(row, entry, cfg.showRealmSuffix, cfg.rowOpts)
                    row.dataIndex = dataIndex
                elseif cfg.onSkipFill then
                    cfg.onSkipFill(entry)
                end
                row:Show()
            end,
            function(poolIdx)
                local row = cfg.rows[poolIdx]
                if row then
                    row:Hide()
                    row.entry = nil
                    row.dataIndex = nil
                end
            end)
        if cfg.groups and cfg.getOverlay then
            local overlayIdx = 0
            local totalColX = (colWidths.Item or 280) + (colWidths.Character or 160)
            local totalColW = colWidths.Total or 72
            for _, group in ipairs(cfg.groups) do
                local span = VirtualList.GroupPoolSpan(group, firstRender, lastRender)
                if span then
                    overlayIdx = overlayIdx + 1
                    placeGroupOverlay(
                        cfg.getOverlay(overlayIdx), cfg.rows,
                        span.firstPoolIdx, span.lastPoolIdx,
                        totalColX, totalColW, cfg.list[group.start], group.total)
                end
            end
            hideUnusedOverlays(cfg.overlayPool, overlayIdx)
        end
        paint[paintFirstKey] = firstRender
        paint[paintLastKey] = lastRender
    elseif not range then
        for _, row in ipairs(cfg.rows) do
            row:Hide()
            row.entry = nil
            row.dataIndex = nil
        end
        if cfg.overlayPool then
            hideUnusedOverlays(cfg.overlayPool, 0)
        end
        paint[paintFirstKey], paint[paintLastKey] = nil, nil
    end
end

-- Virtualized list: fill only rows in the visible range + buffer. Call after layout and on scroll.
-- While the visible window stays inside the last painted buffer, skip refills so SetVerticalScroll
-- moves already-filled rows (no blank/flicker). Refill when the visible edge nears the buffer.
UpdateVisibleRows = function()
    local scrollDbg = SD.BeginScrollPaintDebug and SD.BeginScrollPaintDebug() or nil
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local nTooltipOnly = #tooltipOnlyItemList
    -- Show realm suffix only when viewing all realms and account has characters on multiple realms.
    local showRealmSuffix = (GlobalRealmFilterValue() == "all") and AccountHasMultipleRealms()
    local scrollValue = searchScrollBar and searchScrollBar:GetValue() or 0
    local viewHeight = scrollFrame:GetHeight()
    local searchQuery = frame.lastQuery or ""
    local highlightRowOpts = { searchQuery = searchQuery, highlightSearch = true, scrollDebug = scrollDbg }
    if searchRosterByName then
        highlightRowOpts.rosterByName = searchRosterByName
        highlightRowOpts.onlineCache = {}
    end
    local tooltipOnlyRowOpts = {
        highlightSearch = false,
        scrollDebug = scrollDbg,
        scrollDebugIsTooltip = true,
    }
    local force = paint.forceVisible
    local StickyMod = AltArmy.SearchStickyHeaders
    local sectionMetas
    if StickyMod and StickyMod.ComputeSectionLayout then
        local _
        _, sectionMetas = StickyMod.ComputeSectionLayout(
            buildVisibleSearchSections(nItems, nRecipes, nTooltipOnly),
            UI.HEADER_HEIGHT, UI.HEADER_ROW_GAP, UI.ROW_HEIGHT)
    end
    local topsById = {}
    for i = 1, #(sectionMetas or {}) do
        local m = sectionMetas[i]
        topsById[m.id] = m.sectionTop
    end
    local defaultTop = UI.HEADER_HEIGHT + UI.HEADER_ROW_GAP

    paintSearchSection({
        scrollValue = scrollValue,
        viewHeight = viewHeight,
        sectionTop = topsById.items or defaultTop,
        rowCount = nItems,
        force = force,
        paintFirstKey = "itemsFirst",
        paintLastKey = "itemsLast",
        poolSize = UI.ITEM_POOL_SIZE,
        rows = resultRows,
        list = itemList,
        createRow = createItemRow,
        fillRow = fillItemRow,
        showRealmSuffix = showRealmSuffix,
        rowOpts = highlightRowOpts,
        onSkipFill = function()
            if scrollDbg then SD.NoteScrollItemPaint(scrollDbg) end
        end,
        groups = itemGroups,
        getOverlay = getGroupOverlay,
        overlayPool = groupOverlayPool,
    })

    paintSearchSection({
        scrollValue = scrollValue,
        viewHeight = viewHeight,
        sectionTop = topsById.recipes or defaultTop,
        rowCount = nRecipes,
        force = force,
        paintFirstKey = "recipesFirst",
        paintLastKey = "recipesLast",
        poolSize = UI.RECIPE_POOL_SIZE,
        rows = recipeRows,
        list = recipeList,
        createRow = createRecipeRow,
        fillRow = fillRecipeRow,
        showRealmSuffix = showRealmSuffix,
        rowOpts = highlightRowOpts,
        onSkipFill = function(entry)
            if scrollDbg then SD.NoteScrollRecipePaint(scrollDbg, entry) end
        end,
    })

    paintSearchSection({
        scrollValue = scrollValue,
        viewHeight = viewHeight,
        sectionTop = topsById.tooltip or defaultTop,
        rowCount = nTooltipOnly,
        force = force,
        paintFirstKey = "tooltipFirst",
        paintLastKey = "tooltipLast",
        poolSize = UI.TOOLTIP_ONLY_POOL_SIZE,
        rows = tooltipOnlyResultRows,
        list = tooltipOnlyItemList,
        createRow = createItemRow,
        fillRow = fillItemRow,
        showRealmSuffix = showRealmSuffix,
        rowOpts = tooltipOnlyRowOpts,
        onSkipFill = function()
            if scrollDbg then SD.NoteScrollTooltipPaint(scrollDbg) end
        end,
        groups = tooltipOnlyItemGroups,
        getOverlay = getTooltipOnlyGroupOverlay,
        overlayPool = tooltipOnlyGroupOverlayPool,
    })

    paint.forceVisible = false
    UpdateStickyHeaders()
    if scrollDbg and SD.EndScrollPaintDebug then
        SD.EndScrollPaintDebug(scrollDbg)
    end
end

-- Wire scroll to refresh visible rows (must be after UpdateVisibleRows is defined).
-- SetVerticalScroll is sync; UpdateVisibleRows usually no-ops fills while buffer covers the viewport.
searchScrollBar:SetScript("OnValueChanged", function(_, value)
    scrollFrame:SetVerticalScroll(value)
    UpdateVisibleRows()
end)

UpdateResults = function()
    applySectionSorts()
    paint.forceVisible = true
    paint.itemsFirst, paint.itemsLast = nil, nil
    paint.recipesFirst, paint.recipesLast = nil, nil
    paint.tooltipFirst, paint.tooltipLast = nil, nil
    if GTD and GTD.BuildRosterLastOnlineMap then
        searchRosterByName = GTD.BuildRosterLastOnlineMap()
    else
        searchRosterByName = nil
    end
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local contentHeight = 0

    -- Items section: layout header, build groups, set content height (virtualized rows in UpdateVisibleRows)
    if nItems > 0 then
        itemsHeaderRow:Show()
        contentHeight = contentHeight + UI.HEADER_HEIGHT + UI.HEADER_ROW_GAP

        -- Group consecutive rows by item (itemID + itemName); store for UpdateVisibleRows
        itemGroups = {}
        local prevKey = nil
        for i = 1, nItems do
            local entry = itemList[i]
            local key = (entry.itemID or 0) .. "\t" .. (entry.itemName or "")
            if i == 1 or key ~= prevKey then
                table.insert(itemGroups, { start = i, count = 1, total = entry.count or 1 })
                prevKey = key
            else
                local g = itemGroups[#itemGroups]
                g.count = g.count + 1
                g.total = g.total + (entry.count or 1)
                prevKey = key
            end
        end

        contentHeight = contentHeight + nItems * UI.ROW_HEIGHT
    else
        itemsHeaderRow:Hide()
        itemGroups = {}
    end

    -- Recipes section: layout header and content height (virtualized rows in UpdateVisibleRows)
    if nRecipes > 0 then
        recipesHeaderRow:Show()
        contentHeight = contentHeight + UI.HEADER_HEIGHT + UI.HEADER_ROW_GAP
        contentHeight = contentHeight + nRecipes * UI.ROW_HEIGHT
    else
        recipesHeaderRow:Hide()
    end

    -- "You may also be interested in:" section: tooltip-only matches shown after Items and Recipes
    local nTooltipOnly = #tooltipOnlyItemList
    if nTooltipOnly > 0 then
        alsoInterestedHeaderRow:Show()
        if nRecipes > 0 then
            contentHeight = contentHeight + UI.SECTION_GAP_BEFORE_TOOLTIP
        end
        contentHeight = contentHeight + UI.HEADER_HEIGHT + UI.HEADER_ROW_GAP

        tooltipOnlyItemGroups = {}
        local prevKey = nil
        for i = 1, nTooltipOnly do
            local entry = tooltipOnlyItemList[i]
            local key = (entry.itemID or 0) .. "\t" .. (entry.itemName or "")
            if i == 1 or key ~= prevKey then
                table.insert(tooltipOnlyItemGroups, { start = i, count = 1, total = entry.count or 1 })
                prevKey = key
            else
                local g = tooltipOnlyItemGroups[#tooltipOnlyItemGroups]
                g.count = g.count + 1
                g.total = g.total + (entry.count or 1)
            end
        end

        contentHeight = contentHeight + nTooltipOnly * UI.ROW_HEIGHT
    else
        alsoInterestedHeaderRow:Hide()
        tooltipOnlyItemGroups = {}
    end

    if contentHeight < UI.ROW_HEIGHT then
        contentHeight = UI.ROW_HEIGHT
    end
    resultsArea:SetHeight(contentHeight)
    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
    if searchScrollBar and Theme.UpdateVerticalScrollRange then
        Theme.UpdateVerticalScrollRange(
            scrollFrame, searchScrollBar, contentHeight, scrollFrame:GetHeight(), UI.ROW_HEIGHT)
    end
    -- Horizontal scroll: list viewport may be narrower than totalColWidth
    if listViewport and horizontalScroll and horizontalScrollChild and horizontalScrollBar then
        local vw = listViewport:GetWidth()
        if vw and vw > 0 then
            horizontalScrollChild:SetWidth(totalColWidth)
            local vh = listViewport:GetHeight()
            if not vh or vh <= 0 then
                vh = scrollFrame:GetHeight()
            end
            horizontalScrollChild:SetHeight(vh)
            local maxHorzScroll = math.max(0, totalColWidth - vw)
            horizontalScrollApi:SetRange(0, maxHorzScroll)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            local hVal = horizontalScrollBar:GetValue()
            if hVal > maxHorzScroll then
                horizontalScrollBar:SetValue(maxHorzScroll)
                horizontalScrollApi:Apply(maxHorzScroll)
            else
                horizontalScrollApi:Sync()
            end
        end
    end
    RefreshSearchHeaderSortLabels()
    if SD.StartRecipeResultPrewarm then
        SD.StartRecipeResultPrewarm(recipeList)
    end
    UpdateVisibleRows()
    UpdateNoResultsHint()
end

-- Reset list to top; force-nudge so a post-shrink bar/frame desync cannot stick mid-list.
local function ResetSearchVerticalScroll()
    if Theme.SetVerticalScrollOffset and searchScrollBar then
        Theme.SetVerticalScrollOffset(
            scrollFrame, searchScrollBar, 0, select(2, searchScrollBar:GetMinMaxValues()), true)
    elseif searchScrollBar then
        searchScrollBar:SetValue(0)
        scrollFrame:SetVerticalScroll(0)
    end
end

--- Shared search pipeline used by DoSearch and SearchWithQuery.
function frame.RunSearch(_self, query)
    local q = query or ""
    if q:match("^%s*$") then q = "" end
    frame.lastQuery = q
    resetSectionSorts()
    resetRecipeCollapseExpanded()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if q == "" then
        itemList = {}
        tooltipOnlyItemList = {}
        localRecipeList = {}
        recipeCollapseState.mergedList = {}
        recipeList = {}
    else
        if categories.Items then
            -- Skip tooltip scan for the immediate response; tooltip results arrive after debounce.
            local searchFn = SD.SearchItems or SD.SearchWithLocationGroups
            itemList = searchFn(q, true)
            itemList = itemList or {}
            tooltipOnlyItemList = {}
        else
            itemList = {}
            tooltipOnlyItemList = {}
        end
        if categories.Recipes then
            localRecipeList = SD.SearchRecipes(q) or {}
        else
            localRecipeList = {}
        end
        recipeCollapseState.mergedList = localRecipeList
        recipeList = localRecipeList
    end
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if RF and RF.filterListByRealm then
        local rf = GlobalRealmFilterValue()
        itemList = RF.filterListByRealm(itemList, rf, currentRealm)
        localRecipeList = RF.filterListByRealm(localRecipeList, rf, currentRealm)
        recipeCollapseState.mergedList = localRecipeList
        recipeList = localRecipeList
    end
    ScheduleGuildRecipeSearch(q)
    -- Reset before rebuild so shrinking results cannot desync bar (0) vs frame (mid-list).
    ResetSearchVerticalScroll()
    UpdateResults()
    ResetSearchVerticalScroll()
    ScheduleTooltipSearch(q)
end

function frame.DoSearch()
    local query = ""
    if searchEdit then
        query = searchEdit:GetText()
    end
    frame:RunSearch(query)
end

-- Expose for header search box: run search with query directly
function frame.SearchWithQuery(_self, query)
    local q = (query and type(query) == "string") and query:match("^%s*(.-)%s*$") or ""
    frame:RunSearch(q)
    if searchEdit and searchEdit.SetText then
        searchEdit:SetText(query or "")
    end
end


-- Search settings panel (see Tabs/TabSearchSettings.lua).
local searchSettingsApi = AltArmy.TabSearchSettings and AltArmy.TabSearchSettings.Install
    and AltArmy.TabSearchSettings.Install(frame, UI) or nil
local settingsPanel = searchSettingsApi and searchSettingsApi.panel
local ApplySettingsPanelLayout = searchSettingsApi and searchSettingsApi.ApplyLayout
local RefreshSearchSettingsControls = searchSettingsApi and searchSettingsApi.RefreshControls
if not settingsPanel then
    settingsPanel = CreateFrame("Frame", nil, frame)
    settingsPanel:Hide()
    ApplySettingsPanelLayout = function() end
    RefreshSearchSettingsControls = function() end
end

function frame:IsSearchSettingsShown()
    return settingsPanel and settingsPanel:IsShown()
end

local function ApplyTabContentLayout()
    tabContentPanel:ClearAllPoints()
    tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.SECTION_INSET, -UI.SECTION_INSET)
    if settingsPanel:IsShown() then
        tabContentPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -UI.SECTION_GAP, UI.SECTION_INSET)
    else
    tabContentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.SECTION_INSET, UI.SECTION_INSET)
    end
end

-- List viewport and horizontal scroll bar layout.
-- Columns are sized to the viewport, so horizontal scroll is unused; do not reserve
-- UI.HORIZONTAL_SCROLL_BAR_HEIGHT (Summary only reserves that strip when columns overflow).
local function ApplySearchListLayout()
    ApplyTabContentLayout()
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, -UI.PAD)
    listViewport:SetPoint(
        "BOTTOMRIGHT", tabContentPanel, "BOTTOMRIGHT", -UI.SCROLL_GUTTER, UI.PAD)
    horizontalScrollBar:ClearAllPoints()
    horizontalScrollBar:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", UI.PAD, -4)
    horizontalScrollBar:SetPoint("BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, -4)
    Theme.AnchorVerticalScrollBar(searchScrollBar, tabContentPanel, listViewport)
    if noResultsHint and listViewport then
        local vw = listViewport:GetWidth()
        if vw and vw > 0 then
            noResultsHint:SetWidth(math.max(200, vw - 40))
        end
    end
end

local function RelayoutSearchResultRow(row, order, widths)
    if not row or not row.cells then
        return
    end
    local cx = 0
    for _, colName in ipairs(order) do
        local w = widths[colName] or 80
        local cell = row.cells[colName]
        if cell then
            cell:SetWidth(w)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
            cx = cx + w
        end
    end
end

local function LayoutSearchHeaderButtons(buttonsByCol, headerRow, order, widths, sortState, labelTextForCol)
    local x = 0
    for _, colName in ipairs(order) do
        local w = widths[colName] or 80
        local btn = buttonsByCol[colName]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", headerRow, "BOTTOMLEFT", x, 0)
            btn:SetWidth(w)
            btn:SetHeight(UI.HEADER_HEIGHT)
            local base = labelTextForCol and labelTextForCol(colName) or colName
            btn.label:SetText(Theme.FormatSortHeaderLabel(base, sortState and sortState.key == colName,
                sortState and sortState.ascending))
        end
        x = x + w
    end
end

RefreshSearchHeaderSortLabels = function()
    LayoutSearchHeaderButtons(itemsHeaderButtons, itemsHeaderRow, colOrder, colWidths, sectionSort.items)
    LayoutSearchHeaderButtons(
        recipesHeaderButtons, recipesHeaderRow, recipeColOrder, recipeColWidths, sectionSort.recipes)
    LayoutSearchHeaderButtons(
        alsoInterestedHeaderButtons, alsoInterestedHeaderRow, colOrder, colWidths, sectionSort.tooltip,
        function(colName)
            return colName == "Item" and "You may also be interested in:" or colName
        end)
end

local function ApplySearchColumnLayout()
    local settingsOpen = settingsPanel and settingsPanel:IsShown()
    SyncSearchColumnWidths(settingsOpen)
    totalColWidth = SearchColumns and SearchColumns.GetResultsTableWidth(settingsOpen)
        or math.max(getTotalColWidth(), getRecipeColWidth())
    if resultsArea then
        resultsArea:SetWidth(totalColWidth)
    end
    if horizontalScrollChild then
        horizontalScrollChild:SetWidth(totalColWidth)
    end
    RefreshSearchHeaderSortLabels()
    for _, row in ipairs(resultRows) do
        RelayoutSearchResultRow(row, colOrder, colWidths)
    end
    for _, row in ipairs(recipeRows) do
        RelayoutSearchResultRow(row, recipeColOrder, recipeColWidths)
    end
    for _, row in ipairs(tooltipOnlyResultRows) do
        RelayoutSearchResultRow(row, colOrder, colWidths)
    end
end

local searchLayoutUpdateFrame = CreateFrame("Frame")
local searchDeferredUpdatePending = false

local function ScheduleSearchUpdateAfterLayout()
    if searchDeferredUpdatePending then return end
    searchDeferredUpdatePending = true
    searchLayoutUpdateFrame:SetScript("OnUpdate", function(f)
        f:SetScript("OnUpdate", nil)
        searchDeferredUpdatePending = false
        if frame and frame.IsVisible and frame:IsVisible() then
            UpdateResults()
        end
    end)
end

local function RefreshSearchListAfterLayout()
ApplySearchListLayout()
    ApplySearchColumnLayout()
UpdateResults()
    ScheduleSearchUpdateAfterLayout()
end

function frame:ToggleSearchSettings(_self)
    local showSettings = not settingsPanel:IsShown()
    settingsPanel:SetShown(showSettings)
    if showSettings then
        ApplySettingsPanelLayout()
        RefreshSearchSettingsControls()
    end
    RefreshSearchListAfterLayout()
    if AltArmy and AltArmy.UpdateSearchSettingsButtonGlow then
        AltArmy.UpdateSearchSettingsButtonGlow()
    end
end

frame:SetScript("OnSizeChanged", function()
    if settingsPanel and settingsPanel:IsShown() then
        ApplySettingsPanelLayout()
    end
    RefreshSearchListAfterLayout()
end)

-- Initial empty state: layout list viewport then build results (horizontal scroll range set in UpdateResults)
RefreshSearchListAfterLayout()

-- When tab is shown, refresh layout and scroll child rect (viewport may have been zero when hidden)
frame:SetScript("OnShow", function()
    RefreshSearchListAfterLayout()
    if scrollFrame and scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
end)
