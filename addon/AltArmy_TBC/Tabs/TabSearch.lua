-- AltArmy TBC — Search tab: item search across characters (bags + bank).

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
if not frame then
    return
end

local PAD = 4
local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString
local VirtualList = AltArmy.VirtualList
local SECTION_INSET = Theme.TAB_SECTION_INSET
local SECTION_GAP = Theme.SECTION_GAP
local ROW_HEIGHT = 18
-- Right-side (Total column) icon size; match left-side row icon (WoW :0 default ~14)
local OVERLAY_ICON_SIZE = 14
local HEADER_HEIGHT = 18
local HEADER_ROW_GAP = 3  -- space between section header and first data row
-- Virtualized list: only render rows near the viewport
local ROW_BUFFER = 6   -- extra rows above/below viewport; larger = fewer refill flickers while scrolling
local ITEM_POOL_SIZE = 40
local RECIPE_POOL_SIZE = 40
local TOOLTIP_ONLY_POOL_SIZE = 40
-- Refill before the visible window reaches the edge of the painted buffer.
local PAINT_COVER_MARGIN = 1
local forceVisiblePaint = true
local paintedItemsFirst, paintedItemsLast = nil, nil
local paintedRecipesFirst, paintedRecipesLast = nil, nil
local paintedTooltipFirst, paintedTooltipLast = nil, nil

local SD = AltArmy.SearchData
if not SD or not SD.SearchWithLocationGroups or not SD.SearchRecipes then
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
local HORIZONTAL_SCROLL_BAR_HEIGHT = 20
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
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
scrollFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 20, -PAD)
scrollFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD)
scrollFrame:EnableMouse(true)

-- Custom vertical scroll bar (same style as Gear tab)
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local searchScrollBar = CreateFrame("Slider", "AltArmyTBC_SearchScrollBar", tabContentInner)
searchScrollBar:SetMinMaxValues(0, 0)
searchScrollBar:SetValueStep(ROW_HEIGHT)
searchScrollBar:SetValue(0)
searchScrollBar:EnableMouse(true)
-- OnValueChanged set below after UpdateVisibleRows is defined

-- Horizontal scroll bar at bottom of list area (like Summary tab)
local UpdateStickyHeaders
local horizontalScrollApi = Theme.CreateHorizontalScrollBar(tabContentInner, {
    name = "AltArmyTBC_SearchHorizontalScrollBar",
    thickness = HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2,
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
    local newVal = current - delta * ROW_HEIGHT * 2
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
resultsArea:SetHeight(ROW_HEIGHT)
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

local function isCraftLibAvailable()
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    return RCL and RCL.IsAvailable and RCL.IsAvailable() or false
end

local function applySectionSorts()
    if sectionSort.items.key then
        itemList = SD.SortItemResults(itemList, sectionSort.items.key, sectionSort.items.ascending)
    end
    if sectionSort.recipes.key then
        recipeList = SD.SortRecipeResults(
            recipeList, sectionSort.recipes.key, sectionSort.recipes.ascending, isCraftLibAvailable())
    end
    if sectionSort.tooltip.key then
        tooltipOnlyItemList = SD.SortItemResults(
            tooltipOnlyItemList, sectionSort.tooltip.key, sectionSort.tooltip.ascending)
    end
end

-- Sticky section headers overlay the clipping viewport (not the nested scroll-child),
-- so they seal the top edge above scrolling row text. X is synced to horizontal scroll.
local itemsHeaderRow = CreateFrame("Frame", nil, listViewport)
itemsHeaderRow:SetHeight(HEADER_HEIGHT)
StyleStickySearchHeader(itemsHeaderRow)
itemsHeaderRow:Hide()
local itemsHeaderButtons = {}
-- Recipes section header
local recipesHeaderRow = CreateFrame("Frame", nil, listViewport)
recipesHeaderRow:SetHeight(HEADER_HEIGHT)
StyleStickySearchHeader(recipesHeaderRow)
recipesHeaderRow:Hide()
local recipesHeaderButtons = {}

-- "You may also be interested in:" section header: same columns as items (Item/Character/Total),
-- with the first column label replaced by the section title.
local alsoInterestedHeaderRow = CreateFrame("Frame", nil, listViewport)
alsoInterestedHeaderRow:SetHeight(HEADER_HEIGHT)
StyleStickySearchHeader(alsoInterestedHeaderRow)
alsoInterestedHeaderRow:Hide()
local alsoInterestedHeaderButtons = {}

local function defaultAscendingForSortKey(sortKey)
    return sortKey ~= "Skill"
end

local function createSearchHeaderButton(headerRow, sectionId, colName, justifyLeft)
    local btn = CreateFrame("Button", nil, headerRow)
    btn:SetHeight(HEADER_HEIGHT)
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
local TOOLTIP_CHUNK_SIZE = 80
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
        while processed < TOOLTIP_CHUNK_SIZE and state.index <= state.total do
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

--- Merge guild recipe hits into recipeList in the same frame as local results (no layout).
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
        recipeList = SD.MergeRecipeSearchResults(localRecipeList, guildHits)
    else
        recipeList = {}
        for i = 1, #localRecipeList do
            recipeList[i] = localRecipeList[i]
        end
        for i = 1, #guildHits do
            recipeList[#recipeList + 1] = guildHits[i]
        end
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
        overlay.icon:SetSize(OVERLAY_ICON_SIZE, OVERLAY_ICON_SIZE)
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
        overlay.icon:SetSize(OVERLAY_ICON_SIZE, OVERLAY_ICON_SIZE)
        tooltipOnlyGroupOverlayPool[i] = overlay
    end
    return tooltipOnlyGroupOverlayPool[i]
end

local function createItemRow()
    local row = CreateFrame("Frame", nil, resultsArea)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row.cells = {}
    local cx = 0
    for _, colName in ipairs(colOrder) do
        local w = colWidths[colName] or 80
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
        cell:SetWidth(w)
        cell:SetHeight(ROW_HEIGHT)
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
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row.cells = {}
    local cx = 0
    for _, colName in ipairs(recipeColOrder) do
        local w = recipeColWidths[colName] or 80
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
        cell:SetWidth(w)
        cell:SetHeight(ROW_HEIGHT)
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
        local Nav = AltArmy.SearchGuildNav
        if not Nav or not Nav.IsGuildRecipeCharacterClickable
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
    Theme.BindInteractableHover(charBtn, {
        onEnter = function(self)
            local entry = self:GetParent().entry
            if not entry or not GameTooltip then return end
            local Nav = AltArmy.SearchGuildNav
            local lines = Nav and Nav.GetGuildCharacterHoverTooltipLines
                and Nav.GetGuildCharacterHoverTooltipLines(entry.characterName, entry.realm)
            if not lines or not lines[1] then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(lines[1], 1, 1, 1, true)
            if lines[2] then
                GameTooltip:AddLine(lines[2], 1, 1, 1, true)
            end
            if lines[3] then
                -- Embedded white/gray + class colors; keep AddLine RGB neutral.
                GameTooltip:AddLine(lines[3], 1, 1, 1, true)
            end
            GameTooltip:Show()
        end,
        onLeave = function()
            if GameTooltip then GameTooltip:Hide() end
        end,
    })
    row.characterBtn = charBtn
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
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
    row:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not IsShiftKeyDown() then return end
        local entry = self.entry
        if not entry then return end
        local link = GetRecipeLink(entry.recipeID)
        if link and ChatEdit_InsertLink then
            ChatEdit_InsertLink(link)
        end
    end)
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
    local recipeName = entry._aaRecipeBaseName
        or ("Recipe " .. tostring(entry.recipeID or "?"))
    recipeName = maybeHighlightSearchText(recipeName, highlightSearch, searchQuery)
    local iconPath = entry._aaIconPath or "Interface\\Icons\\INV_Misc_QuestionMark"
    local iconPrefix = ("|T%s:0|t "):format(iconPath)
    SetItemCellTruncated(row.cells.Recipe, recipeName, "", iconPrefix, recipeColWidths.Recipe or 344)
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
    local clickable = Nav and Nav.IsGuildRecipeCharacterClickable
        and Nav.IsGuildRecipeCharacterClickable(entry)
    if row.characterBtn then
        row.characterBtn:SetShown(clickable and true or false)
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

UpdateStickyHeaders = function()
    local StickyMod = AltArmy.SearchStickyHeaders
    if not StickyMod or not listViewport then
        return
    end

    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local nTooltipOnly = #tooltipOnlyItemList

    local headerTops = StickyMod.ComputeSectionHeaderTops(
        nItems, nRecipes, nTooltipOnly, HEADER_HEIGHT, HEADER_ROW_GAP, ROW_HEIGHT)
    local scrollValue = searchScrollBar and searchScrollBar:GetValue() or 0
    local stickyTops = StickyMod.ComputeStickyTops(headerTops, scrollValue, HEADER_HEIGHT)

    local headerRows = {}
    if nItems > 0 then
        headerRows[#headerRows + 1] = itemsHeaderRow
    end
    if nRecipes > 0 then
        headerRows[#headerRows + 1] = recipesHeaderRow
    end
    if nTooltipOnly > 0 then
        headerRows[#headerRows + 1] = alsoInterestedHeaderRow
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
    overlay.icon:SetPoint("CENTER", overlay, "RIGHT", -2 - OVERLAY_ICON_SIZE / 2, 0)
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
    overlay.total:SetWidth(math.max(1, totalColW - OVERLAY_ICON_SIZE - 2))
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
    row:SetPoint("BOTTOMLEFT", resultsArea, "TOPLEFT", 0, rowY - ROW_HEIGHT)
end

-- Virtualized list: fill only rows in the visible range + buffer. Call after layout and on scroll.
-- While the visible window stays inside the last painted buffer, skip refills so SetVerticalScroll
-- moves already-filled rows (no blank/flicker). Refill when the visible edge nears the buffer.
UpdateVisibleRows = function()
    local scrollDbg = SD.BeginScrollPaintDebug and SD.BeginScrollPaintDebug() or nil
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    -- Show realm suffix only when viewing all realms and account has characters on multiple realms.
    local showRealmSuffix = (GlobalRealmFilterValue() == "all") and AccountHasMultipleRealms()
    local scrollValue = searchScrollBar and searchScrollBar:GetValue() or 0
    local viewHeight = scrollFrame:GetHeight()
    local itemsSectionTop = HEADER_HEIGHT + HEADER_ROW_GAP
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
    local force = forceVisiblePaint

    -- Items: visible range and render range (with buffer)
    local itemsRange = VirtualList.GetRenderRange(
        scrollValue, viewHeight, itemsSectionTop, ROW_HEIGHT, nItems, ROW_BUFFER)
    local refillItems = force
        or not itemsRange
        or not VirtualList.IsVisibleRangeCovered(
            itemsRange.firstVisible, itemsRange.lastVisible,
            paintedItemsFirst, paintedItemsLast, PAINT_COVER_MARGIN)
    if itemsRange and refillItems then
        local firstRender = itemsRange.firstRender
        local lastRender = itemsRange.lastRender
        local totalColX = (colWidths.Item or 280) + (colWidths.Character or 160)
        local totalColW = colWidths.Total or 72
        VirtualList.ForEachPoolSlot(ITEM_POOL_SIZE, firstRender, itemsRange.renderCount,
            function(poolIdx, dataIndex)
                local row = resultRows[poolIdx]
                if not row then
                    row = createItemRow()
                    resultRows[poolIdx] = row
                end
                local entry = itemList[dataIndex]
                local rowY = VirtualList.RowTopOffset(itemsSectionTop, dataIndex, ROW_HEIGHT)
                positionPooledRow(row, rowY)
                if VirtualList.ShouldFillPoolRow(force, row.dataIndex, dataIndex) then
                    fillItemRow(row, entry, showRealmSuffix, highlightRowOpts)
                    row.dataIndex = dataIndex
                elseif scrollDbg then
                    SD.NoteScrollItemPaint(scrollDbg)
                end
                row:Show()
            end,
            function(poolIdx)
                local row = resultRows[poolIdx]
                if row then
                    row:Hide()
                    row.entry = nil
                    row.dataIndex = nil
                end
            end)

        local overlayIdx = 0
        for _, group in ipairs(itemGroups) do
            local span = VirtualList.GroupPoolSpan(group, firstRender, lastRender)
            if span then
                overlayIdx = overlayIdx + 1
                placeGroupOverlay(
                    getGroupOverlay(overlayIdx), resultRows,
                    span.firstPoolIdx, span.lastPoolIdx,
                    totalColX, totalColW, itemList[group.start], group.total)
            end
        end
        hideUnusedOverlays(groupOverlayPool, overlayIdx)
        paintedItemsFirst = firstRender
        paintedItemsLast = lastRender
    elseif not itemsRange then
        for _, row in ipairs(resultRows) do
            row:Hide()
            row.entry = nil
            row.dataIndex = nil
        end
        hideUnusedOverlays(groupOverlayPool, 0)
        paintedItemsFirst, paintedItemsLast = nil, nil
    end

    -- Recipes: visible range and render range
    local recipesSectionTop = itemsSectionTop + nItems * ROW_HEIGHT + HEADER_HEIGHT + HEADER_ROW_GAP
    if nItems == 0 then
        recipesSectionTop = HEADER_HEIGHT + HEADER_ROW_GAP
    end
    local recipesRange = VirtualList.GetRenderRange(
        scrollValue, viewHeight, recipesSectionTop, ROW_HEIGHT, nRecipes, ROW_BUFFER)
    local refillRecipes = force
        or not recipesRange
        or not VirtualList.IsVisibleRangeCovered(
            recipesRange.firstVisible, recipesRange.lastVisible,
            paintedRecipesFirst, paintedRecipesLast, PAINT_COVER_MARGIN)
    if recipesRange and refillRecipes then
        VirtualList.ForEachPoolSlot(RECIPE_POOL_SIZE, recipesRange.firstRender, recipesRange.renderCount,
            function(poolIdx, dataIndex)
                local row = recipeRows[poolIdx]
                if not row then
                    row = createRecipeRow()
                    recipeRows[poolIdx] = row
                end
                local entry = recipeList[dataIndex]
                local rowY = VirtualList.RowTopOffset(recipesSectionTop, dataIndex, ROW_HEIGHT)
                positionPooledRow(row, rowY)
                if VirtualList.ShouldFillPoolRow(force, row.dataIndex, dataIndex) then
                    fillRecipeRow(row, entry, showRealmSuffix, highlightRowOpts)
                    row.dataIndex = dataIndex
                elseif scrollDbg then
                    SD.NoteScrollRecipePaint(scrollDbg, entry)
                end
                row:Show()
            end,
            function(poolIdx)
                local row = recipeRows[poolIdx]
                if row then
                    row:Hide()
                    row.entry = nil
                    row.dataIndex = nil
                end
            end)
        paintedRecipesFirst = recipesRange.firstRender
        paintedRecipesLast = recipesRange.lastRender
    elseif not recipesRange then
        for _, row in ipairs(recipeRows) do
            row:Hide()
            row.entry = nil
            row.dataIndex = nil
        end
        paintedRecipesFirst, paintedRecipesLast = nil, nil
    end

    -- "You may also be interested in:" tooltip-only section
    local nTooltipOnly = #tooltipOnlyItemList
    local tooltipOnlySectionTop
    if nRecipes > 0 then
        tooltipOnlySectionTop = recipesSectionTop + nRecipes * ROW_HEIGHT + HEADER_HEIGHT + HEADER_ROW_GAP
    elseif nItems > 0 then
        tooltipOnlySectionTop = itemsSectionTop + nItems * ROW_HEIGHT + HEADER_HEIGHT + HEADER_ROW_GAP
    else
        tooltipOnlySectionTop = HEADER_HEIGHT + HEADER_ROW_GAP
    end
    local tooltipOnlyRange = VirtualList.GetRenderRange(
        scrollValue, viewHeight, tooltipOnlySectionTop, ROW_HEIGHT, nTooltipOnly, ROW_BUFFER)
    local refillTooltip = force
        or not tooltipOnlyRange
        or not VirtualList.IsVisibleRangeCovered(
            tooltipOnlyRange.firstVisible, tooltipOnlyRange.lastVisible,
            paintedTooltipFirst, paintedTooltipLast, PAINT_COVER_MARGIN)
    if tooltipOnlyRange and refillTooltip then
        local firstRender = tooltipOnlyRange.firstRender
        local lastRender = tooltipOnlyRange.lastRender
        local totalColX = (colWidths.Item or 280) + (colWidths.Character or 160)
        local totalColW = colWidths.Total or 72
        VirtualList.ForEachPoolSlot(TOOLTIP_ONLY_POOL_SIZE, firstRender, tooltipOnlyRange.renderCount,
            function(poolIdx, dataIndex)
                local row = tooltipOnlyResultRows[poolIdx]
                if not row then
                    row = createItemRow()
                    tooltipOnlyResultRows[poolIdx] = row
                end
                local entry = tooltipOnlyItemList[dataIndex]
                local rowY = VirtualList.RowTopOffset(tooltipOnlySectionTop, dataIndex, ROW_HEIGHT)
                positionPooledRow(row, rowY)
                if VirtualList.ShouldFillPoolRow(force, row.dataIndex, dataIndex) then
                    fillItemRow(row, entry, showRealmSuffix, tooltipOnlyRowOpts)
                    row.dataIndex = dataIndex
                elseif scrollDbg then
                    SD.NoteScrollTooltipPaint(scrollDbg)
                end
                row:Show()
            end,
            function(poolIdx)
                local row = tooltipOnlyResultRows[poolIdx]
                if row then
                    row:Hide()
                    row.entry = nil
                    row.dataIndex = nil
                end
            end)

        local overlayIdx = 0
        for _, group in ipairs(tooltipOnlyItemGroups) do
            local span = VirtualList.GroupPoolSpan(group, firstRender, lastRender)
            if span then
                overlayIdx = overlayIdx + 1
                placeGroupOverlay(
                    getTooltipOnlyGroupOverlay(overlayIdx), tooltipOnlyResultRows,
                    span.firstPoolIdx, span.lastPoolIdx,
                    totalColX, totalColW, tooltipOnlyItemList[group.start], group.total)
            end
        end
        hideUnusedOverlays(tooltipOnlyGroupOverlayPool, overlayIdx)
        paintedTooltipFirst = firstRender
        paintedTooltipLast = lastRender
    elseif not tooltipOnlyRange then
        for _, row in ipairs(tooltipOnlyResultRows) do
            row:Hide()
            row.entry = nil
            row.dataIndex = nil
        end
        hideUnusedOverlays(tooltipOnlyGroupOverlayPool, 0)
        paintedTooltipFirst, paintedTooltipLast = nil, nil
    end

    forceVisiblePaint = false
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
    forceVisiblePaint = true
    paintedItemsFirst, paintedItemsLast = nil, nil
    paintedRecipesFirst, paintedRecipesLast = nil, nil
    paintedTooltipFirst, paintedTooltipLast = nil, nil
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
        contentHeight = contentHeight + HEADER_HEIGHT + HEADER_ROW_GAP

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

        contentHeight = contentHeight + nItems * ROW_HEIGHT
    else
        itemsHeaderRow:Hide()
        itemGroups = {}
    end

    -- Recipes section: layout header and content height (virtualized rows in UpdateVisibleRows)
    if nRecipes > 0 then
        recipesHeaderRow:Show()
        contentHeight = contentHeight + HEADER_HEIGHT + HEADER_ROW_GAP
        contentHeight = contentHeight + nRecipes * ROW_HEIGHT
    else
        recipesHeaderRow:Hide()
    end

    -- "You may also be interested in:" section: tooltip-only matches shown after Items and Recipes
    local nTooltipOnly = #tooltipOnlyItemList
    if nTooltipOnly > 0 then
        alsoInterestedHeaderRow:Show()
        contentHeight = contentHeight + HEADER_HEIGHT + HEADER_ROW_GAP

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

        contentHeight = contentHeight + nTooltipOnly * ROW_HEIGHT
    else
        alsoInterestedHeaderRow:Hide()
        tooltipOnlyItemGroups = {}
    end

    if contentHeight < ROW_HEIGHT then
        contentHeight = ROW_HEIGHT
    end
    resultsArea:SetHeight(contentHeight)
    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
    if searchScrollBar and Theme.UpdateVerticalScrollRange then
        Theme.UpdateVerticalScrollRange(
            scrollFrame, searchScrollBar, contentHeight, scrollFrame:GetHeight(), ROW_HEIGHT)
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

function frame.DoSearch()
    local query = ""
    if searchEdit then
        query = searchEdit:GetText()
    end
    if query and query:match("^%s*$") then query = "" end
    frame.lastQuery = query or ""
    resetSectionSorts()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if categories.Items and query ~= "" then
        -- Skip tooltip scan for the immediate response; tooltip results arrive after debounce.
        itemList = SD.SearchWithLocationGroups(query, true)
        itemList = itemList or {}
        tooltipOnlyItemList = {}
    else
        itemList = {}
        tooltipOnlyItemList = {}
    end
    if categories.Recipes and query ~= "" then
        localRecipeList = SD.SearchRecipes(query) or {}
    else
        localRecipeList = {}
    end
    recipeList = localRecipeList
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if RF and RF.filterListByRealm then
        local rf = GlobalRealmFilterValue()
        itemList = RF.filterListByRealm(itemList, rf, currentRealm)
        localRecipeList = RF.filterListByRealm(localRecipeList, rf, currentRealm)
        recipeList = localRecipeList
    end
    ScheduleGuildRecipeSearch(query)
    -- Reset before rebuild so shrinking results cannot desync bar (0) vs frame (mid-list).
    ResetSearchVerticalScroll()
    UpdateResults()
    ResetSearchVerticalScroll()
    ScheduleTooltipSearch(query)
end

-- Expose for header search box: run search with query directly
function frame.SearchWithQuery(_self, query)
    local q = (query and type(query) == "string") and query:match("^%s*(.-)%s*$") or ""
    frame.lastQuery = q
    resetSectionSorts()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if q == "" then
        itemList = {}
        tooltipOnlyItemList = {}
        localRecipeList = {}
        recipeList = {}
    else
        if categories.Items then
            -- Skip tooltip scan for the immediate response; tooltip results arrive after debounce.
            itemList = SD.SearchWithLocationGroups(q, true)
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
        recipeList = localRecipeList
    end
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if RF and RF.filterListByRealm then
        local rf = GlobalRealmFilterValue()
        itemList = RF.filterListByRealm(itemList, rf, currentRealm)
        localRecipeList = RF.filterListByRealm(localRecipeList, rf, currentRealm)
        recipeList = localRecipeList
    end
    ScheduleGuildRecipeSearch(q)
    -- Reset before rebuild so shrinking results cannot desync bar (0) vs frame (mid-list).
    ResetSearchVerticalScroll()
    UpdateResults()
    ResetSearchVerticalScroll()
    if searchEdit and searchEdit.SetText then
        searchEdit:SetText(query or "")
    end
    ScheduleTooltipSearch(q)
end

-- Search settings panel: right 40% of frame when visible (list 60%, both full height).
local GRID_SPLIT_FRACTION = 0.6
local SEARCH_SETTINGS_WIDTH_TRIM = 60
local SETTINGS_ROW_HEIGHT = 22
local RECIPE_LEVEL_LABEL_GAP = 6
local RECIPE_LEVEL_MIN_MAX_GAP = 12
local RECIPE_LEVEL_RESET_GAP = 4
local RECIPE_LEVEL_MIN_EDIT_WIDTH = 28
local RECIPE_LEVEL_DEFAULT_EDIT_WIDTH = 40
local settingsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
Theme.ApplyBackdrop(settingsPanel, "section")

local applyRecipeLevelFilterRowLayout
local SyncCraftFilterDropdowns

local function ApplySettingsPanelLayout()
    local w = frame:GetWidth()
    if w <= 0 then
        return
    end
    local settingsLeft = w * GRID_SPLIT_FRACTION + SECTION_GAP + SEARCH_SETTINGS_WIDTH_TRIM
    settingsPanel:ClearAllPoints()
    settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", settingsLeft, -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", settingsLeft, SECTION_INSET)
    settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SECTION_INSET, -SECTION_INSET)
    settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
    if applyRecipeLevelFilterRowLayout then
        applyRecipeLevelFilterRowLayout()
    end
    if SyncCraftFilterDropdowns then
        SyncCraftFilterDropdowns()
    end
end

ApplySettingsPanelLayout()
settingsPanel:Hide()

local settingsContent = Theme.CreateSettingsPanelContent(settingsPanel)
local searchSettingsTitle = settingsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
searchSettingsTitle:SetPoint("TOPLEFT", settingsContent, "TOPLEFT", 0, 0)
searchSettingsTitle:SetPoint("TOPRIGHT", settingsContent, "TOPRIGHT", 0, 0)
searchSettingsTitle:SetJustifyH("LEFT")
searchSettingsTitle:SetText("Search Settings")
Theme.SetTitleColor(searchSettingsTitle)

local filterContent = CreateFrame("Frame", nil, settingsContent)
filterContent:SetPoint("TOPLEFT", searchSettingsTitle, "BOTTOMLEFT", 0, -8)
filterContent:SetPoint("BOTTOMRIGHT", settingsContent, "BOTTOMRIGHT", 0, 0)

local SS = AltArmy.SearchSettings
local RCL = AltArmy.RecipeCraftLib

local UpdateRecipeLevelResetButtonVisibility

local function RerunSearchIfActive()
    if frame.lastQuery and frame.lastQuery ~= "" and frame.SearchWithQuery then
        frame:SearchWithQuery(frame.lastQuery)
    elseif frame.DoSearch then
        frame:DoSearch()
    end
    if UpdateRecipeLevelResetButtonVisibility then
        UpdateRecipeLevelResetButtonVisibility()
    end
    if AltArmy and AltArmy.UpdateSearchSettingsButtonGlow then
        AltArmy.UpdateSearchSettingsButtonGlow()
    end
end

local RECIPE_LEVEL_ROW_GAP = 10

local function SetRecipeLevelHeaderColor(fontString)
    if not fontString or not fontString.SetTextColor then
        return
    end
    local value = Theme.COLORS and Theme.COLORS.value
    if value then
        fontString:SetTextColor(value[1], value[2], value[3], value[4])
    else
        fontString:SetTextColor(1, 1, 1, 1)
    end
end

local recipeLevelHeader = filterContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
recipeLevelHeader:SetText("Recipe Level")
SetRecipeLevelHeaderColor(recipeLevelHeader)

local professionSectionAnchor = CreateFrame("Frame", nil, filterContent)
professionSectionAnchor:SetSize(1, 1)
professionSectionAnchor:SetPoint("TOPLEFT", filterContent, "TOPLEFT", 0, 0)

local minLevelLabel = filterContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
minLevelLabel:SetPoint("TOPLEFT", recipeLevelHeader, "BOTTOMLEFT", 0, -RECIPE_LEVEL_ROW_GAP)
minLevelLabel:SetText("Min")

local minLevelEdit = CreateFrame("EditBox", nil, filterContent)
minLevelEdit:SetSize(RECIPE_LEVEL_DEFAULT_EDIT_WIDTH, SETTINGS_ROW_HEIGHT)
minLevelEdit:SetFontObject("GameFontHighlightSmall")
minLevelEdit:SetAutoFocus(false)
minLevelEdit:SetNumeric(true)
minLevelEdit:SetJustifyH("CENTER")
minLevelEdit:SetPoint("LEFT", minLevelLabel, "RIGHT", 6, -2)
Theme.ApplyInputTextures(minLevelEdit)
minLevelEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
end)
local suppressRecipeFilterTextChanged = false

local function ApplyRecipeLevelFilterMin(box, normalizeDisplay)
    if suppressRecipeFilterTextChanged or not SS or not SS.SetRecipeLevelFilterMin then
        return
    end
    SS.SetRecipeLevelFilterMin(box:GetText())
    if normalizeDisplay then
        suppressRecipeFilterTextChanged = true
        box:SetText(tostring(SS.GetRecipeLevelFilter().min))
        suppressRecipeFilterTextChanged = false
    end
    RerunSearchIfActive()
end

local function ApplyRecipeLevelFilterMax(box, normalizeDisplay)
    if suppressRecipeFilterTextChanged or not SS or not SS.SetRecipeLevelFilterMax then
        return
    end
    SS.SetRecipeLevelFilterMax(box:GetText())
    if normalizeDisplay then
        suppressRecipeFilterTextChanged = true
        box:SetText(tostring(SS.GetRecipeLevelFilter().max))
        suppressRecipeFilterTextChanged = false
    end
    RerunSearchIfActive()
end

minLevelEdit:SetScript("OnTextChanged", function(box)
    ApplyRecipeLevelFilterMin(box, false)
end)
minLevelEdit:SetScript("OnEditFocusLost", function(box)
    ApplyRecipeLevelFilterMin(box, true)
end)

local maxLevelLabel = filterContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
maxLevelLabel:SetPoint("LEFT", minLevelEdit, "RIGHT", 12, 0)
maxLevelLabel:SetPoint("TOP", minLevelLabel, "TOP", 0, 0)
maxLevelLabel:SetText("Max")

local maxLevelEdit = CreateFrame("EditBox", nil, filterContent)
maxLevelEdit:SetSize(RECIPE_LEVEL_DEFAULT_EDIT_WIDTH, SETTINGS_ROW_HEIGHT)
maxLevelEdit:SetFontObject("GameFontHighlightSmall")
maxLevelEdit:SetAutoFocus(false)
maxLevelEdit:SetNumeric(true)
maxLevelEdit:SetJustifyH("CENTER")
maxLevelEdit:SetPoint("LEFT", maxLevelLabel, "RIGHT", 6, -2)
maxLevelEdit:SetPoint("TOP", minLevelEdit, "TOP", 0, 0)
Theme.ApplyInputTextures(maxLevelEdit)
maxLevelEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
end)
maxLevelEdit:SetScript("OnTextChanged", function(box)
    ApplyRecipeLevelFilterMax(box, false)
end)
maxLevelEdit:SetScript("OnEditFocusLost", function(box)
    ApplyRecipeLevelFilterMax(box, true)
end)

local function ResetRecipeLevelFilterControls()
    if not SS or not SS.ResetRecipeLevelFilter then
        return
    end
    SS.ResetRecipeLevelFilter()
    suppressRecipeFilterTextChanged = true
    minLevelEdit:SetText(tostring(SS.MIN_RECIPE_LEVEL or 0))
    maxLevelEdit:SetText(tostring(SS.MAX_RECIPE_LEVEL or 375))
    suppressRecipeFilterTextChanged = false
    minLevelEdit:ClearFocus()
    maxLevelEdit:ClearFocus()
    RerunSearchIfActive()
end

local recipeLevelResetBtn = CreateFrame("Button", nil, filterContent, "BackdropTemplate")
recipeLevelResetBtn:SetSize(SETTINGS_ROW_HEIGHT, SETTINGS_ROW_HEIGHT)
recipeLevelResetBtn:SetPoint("RIGHT", filterContent, "RIGHT", 0, 0)
recipeLevelResetBtn:SetPoint("TOP", minLevelEdit, "TOP", 0, 0)
Theme.ApplyBackdrop(recipeLevelResetBtn, "section")
if Theme.InstallHoverTint then
    Theme.InstallHoverTint(recipeLevelResetBtn)
end
local recipeLevelResetIcon = recipeLevelResetBtn:CreateTexture(nil, "ARTWORK")
recipeLevelResetIcon:SetSize(14, 14)
recipeLevelResetIcon:SetPoint("CENTER", recipeLevelResetBtn, "CENTER", 0, 0)
recipeLevelResetIcon:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Undo")
recipeLevelResetBtn:SetScript("OnClick", ResetRecipeLevelFilterControls)

applyRecipeLevelFilterRowLayout = function()
    local rowWidth = filterContent:GetWidth()
    if not rowWidth or rowWidth <= 0 then
        return
    end
    local resetW = SETTINGS_ROW_HEIGHT
    local minLabelW = minLevelLabel:GetStringWidth()
    if not minLabelW or minLabelW <= 0 then
        minLabelW = 18
    end
    local maxLabelW = maxLevelLabel:GetStringWidth()
    if not maxLabelW or maxLabelW <= 0 then
        maxLabelW = 22
    end
    local fixed = minLabelW + RECIPE_LEVEL_LABEL_GAP + RECIPE_LEVEL_MIN_MAX_GAP + maxLabelW
        + RECIPE_LEVEL_LABEL_GAP + resetW + RECIPE_LEVEL_RESET_GAP
    local editW = math.max(RECIPE_LEVEL_MIN_EDIT_WIDTH, math.floor((rowWidth - fixed) / 2 + 0.5))
    minLevelEdit:SetWidth(editW)
    maxLevelEdit:SetWidth(editW)
end

recipeLevelResetBtn:SetScript("OnEnter", function(self)
    if Theme.SetHoverTint then
        Theme.SetHoverTint(self, true)
    end
    if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Reset recipe level filter (0–375)")
        GameTooltip:Show()
    end
end)
recipeLevelResetBtn:SetScript("OnLeave", function(self)
    if Theme.SetHoverTint then
        Theme.SetHoverTint(self, false)
    end
    if GameTooltip then
        GameTooltip:Hide()
    end
end)

UpdateRecipeLevelResetButtonVisibility = function()
    if not recipeLevelResetBtn or not minLevelEdit or not minLevelEdit:IsShown() then
        return
    end
    local filterActive = SS and SS.IsRecipeLevelFilterActive and SS.IsRecipeLevelFilterActive()
    recipeLevelResetBtn:SetShown(filterActive)
end

local FILTER_SECTION_GAP = 12
local FILTER_DROPDOWN_GAP = 4
local FILTER_DROPDOWN_POPUP_PAD_LEFT = 10
local FILTER_DROPDOWN_POPUP_PAD_TOP = 6
local FILTER_DROPDOWN_POPUP_PAD_BOTTOM = 8
local FILTER_DROPDOWN_POPUP_PAD_RIGHT = 8
local FILTER_DROPDOWN_TEXT_INSET = 10
local craftFilterWidgets = {}
local craftFilterDropdowns = {}

local function AddCraftFilterWidget(widget)
    craftFilterWidgets[#craftFilterWidgets + 1] = widget
end

local function CloseCraftFilterDropdowns(exceptPopup)
    for i = 1, #craftFilterDropdowns do
        local popup = craftFilterDropdowns[i]
        if popup and popup ~= exceptPopup and popup.Hide then
            popup:Hide()
        end
    end
end

local function SetDropdownButtonSummary(btn, btnText, summary)
    btn.fullSummaryText = summary
    local maxW = (btn:GetWidth() or 0) - FILTER_DROPDOWN_TEXT_INSET
    if maxW <= 0 then
        btnText:SetText(summary)
        btn.wasSummaryTruncated = false
        return
    end
    if TruncateFontString then
        btn.wasSummaryTruncated = TruncateFontString(btnText, summary, maxW, { returnBoolean = true })
    else
        btnText:SetText(summary)
        btn.wasSummaryTruncated = false
    end
end

local function CreateFilterSectionHeader(relativeTo, text, registerInCraftFilter)
    local header = filterContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header:SetPoint("TOP", relativeTo, "BOTTOM", 0, -FILTER_SECTION_GAP)
    header:SetPoint("LEFT", filterContent, "LEFT", 0, 0)
    header:SetPoint("RIGHT", filterContent, "RIGHT", 0, 0)
    header:SetJustifyH("LEFT")
    header:SetText(text)
    SetRecipeLevelHeaderColor(header)
    if registerInCraftFilter ~= false then
        AddCraftFilterWidget(header)
    end
    return header
end

local function CreateMultiSelectFilterDropdown(config)
    local registerCraftFilterWidget = config.registerCraftFilterWidget ~= false
    local header = CreateFilterSectionHeader(
        config.relativeTo,
        config.title,
        registerCraftFilterWidget
    )

    local btn = CreateFrame("Button", nil, filterContent)
    local dropdownRowHeight = Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or (Theme.CHAR_LIST_ROW_HEIGHT or 20) + 4
    btn:SetHeight(SETTINGS_ROW_HEIGHT + 4)
    btn:SetPoint("TOP", header, "BOTTOM", 0, -FILTER_DROPDOWN_GAP)
    btn:SetPoint("LEFT", filterContent, "LEFT", 0, 0)
    btn:SetPoint("RIGHT", filterContent, "RIGHT", 0, 0)
    Theme.SkinButton(btn)
    if registerCraftFilterWidget then
        AddCraftFilterWidget(btn)
    end

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    btnText:SetJustifyH("LEFT")

    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            if self.wasSummaryTruncated and self.fullSummaryText and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.fullSummaryText, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btn:HookScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
    end

    local popup = CreateFrame("Frame", nil, filterContent, "BackdropTemplate")
    popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    local rowHeight = dropdownRowHeight
    popup:SetHeight(
        FILTER_DROPDOWN_POPUP_PAD_TOP
            + #config.keys * rowHeight
            + FILTER_DROPDOWN_POPUP_PAD_BOTTOM
    )
    popup:SetFrameLevel(filterContent:GetFrameLevel() + 100)
    popup:Hide()
    Theme.ApplyBackdrop(popup, "section")
    craftFilterDropdowns[#craftFilterDropdowns + 1] = popup

    local checks = {}
    local prevRow
    local RefreshDropdown
    for idx, key in ipairs(config.keys) do
        local rowOpts = {
            rowHeight = dropdownRowHeight,
            text = (config.getRowLabel and config.getRowLabel(key)) or config.labels[key] or key,
            fullWidthHover = true,
            rightInset = FILTER_DROPDOWN_POPUP_PAD_RIGHT,
            onClick = function(checked)
                if config.setEnabled then
                    config.setEnabled(key, checked)
                end
                RefreshDropdown()
                RerunSearchIfActive()
            end,
        }
        if idx == 1 then
            rowOpts.point = "TOPLEFT"
            rowOpts.relativeTo = popup
            rowOpts.relativePoint = "TOPLEFT"
            rowOpts.x = FILTER_DROPDOWN_POPUP_PAD_LEFT
            rowOpts.y = -FILTER_DROPDOWN_POPUP_PAD_TOP
        else
            rowOpts.relativeTo = prevRow
            rowOpts.relativePoint = "BOTTOMLEFT"
            rowOpts.point = "TOPLEFT"
            rowOpts.x = 0
            rowOpts.y = 0
        end
        local row = Theme.CreateLabeledCheckbox(popup, rowOpts)
        checks[key] = row.check
        prevRow = row
    end

    local function RefreshDropdownImpl()
        local filterMap = config.getFilter and config.getFilter() or {}
        local summary = SS and SS.FormatMultiSelectFilterSummary
            and SS.FormatMultiSelectFilterSummary(config.keys, config.labels, filterMap)
            or ""
        SetDropdownButtonSummary(btn, btnText, summary)
        for key, check in pairs(checks) do
            if check and check.SetChecked then
                check:SetChecked(filterMap[key] ~= false)
            end
        end
    end
    RefreshDropdown = RefreshDropdownImpl

    btn:SetScript("OnClick", function()
        local show = not popup:IsShown()
        CloseCraftFilterDropdowns(show and popup or nil)
        popup:SetShown(show)
    end)

    RefreshDropdownImpl()
    return btn, { popup = popup, refresh = RefreshDropdownImpl, header = header }
end

local professionDropdownBtn
local professionDropdown
professionDropdownBtn, professionDropdown = CreateMultiSelectFilterDropdown({
    relativeTo = professionSectionAnchor,
    title = "Professions",
    keys = SS and SS.GetProfessionDropdownOrder and SS.GetProfessionDropdownOrder() or {},
    labels = SS and SS.PROFESSION_LABELS or {},
    registerCraftFilterWidget = false,
    getFilter = function()
        return SS and SS.GetProfessionFilter and SS.GetProfessionFilter() or {}
    end,
    setEnabled = function(key, checked)
        if SS and SS.SetProfessionEnabled then
            SS.SetProfessionEnabled(key, checked)
        end
    end,
})

recipeLevelHeader:SetPoint("TOPLEFT", professionDropdownBtn, "BOTTOMLEFT", 0, -FILTER_SECTION_GAP)

local DIFFICULTY_LABELS = {
    orange = "Orange",
    yellow = "Yellow",
    green = "Green",
    gray = "Gray",
}
local DIFFICULTY_DROPDOWN_ORDER = { "gray", "green", "yellow", "orange" }

local function ColoredDifficultyLabel(band)
    local plain = DIFFICULTY_LABELS[band] or band
    local recipeCraftLib = AltArmy.RecipeCraftLib
    local hex = recipeCraftLib and recipeCraftLib.GetDifficultyColorHex
        and recipeCraftLib.GetDifficultyColorHex(band)
    if not hex then
        return plain
    end
    return string.format("|c%s%s|r", hex, plain)
end

local SOURCE_LABELS = {
    trainer = "Trainer",
    vendor = "Vendor",
    quest = "Quest",
    drop = "Drop",
    reputation = "Reputation",
    starter = "Starter",
}
local SOURCE_DROPDOWN_ORDER = { "drop", "quest", "reputation", "starter", "trainer", "vendor" }

local difficultyDropdownBtn
local difficultyDropdown
difficultyDropdownBtn, difficultyDropdown = CreateMultiSelectFilterDropdown({
    relativeTo = minLevelLabel,
    title = "Difficulty",
    keys = DIFFICULTY_DROPDOWN_ORDER,
    labels = DIFFICULTY_LABELS,
    getRowLabel = ColoredDifficultyLabel,
    getFilter = function()
        return SS and SS.GetDifficultyFilter and SS.GetDifficultyFilter() or {}
    end,
    setEnabled = function(key, checked)
        if SS and SS.SetDifficultyBandEnabled then
            SS.SetDifficultyBandEnabled(key, checked)
        end
    end,
})
local _, sourceDropdown = CreateMultiSelectFilterDropdown({
    relativeTo = difficultyDropdownBtn,
    title = "Source",
    keys = SOURCE_DROPDOWN_ORDER,
    labels = SOURCE_LABELS,
    getFilter = function()
        return SS and SS.GetSourceFilter and SS.GetSourceFilter() or {}
    end,
    setEnabled = function(key, checked)
        if SS and SS.SetSourceTypeEnabled then
            SS.SetSourceTypeEnabled(key, checked)
        end
    end,
})

SyncCraftFilterDropdowns = function()
    if professionDropdown and professionDropdown.refresh then
        professionDropdown.refresh()
    end
    if difficultyDropdown and difficultyDropdown.refresh then
        difficultyDropdown.refresh()
    end
    if sourceDropdown and sourceDropdown.refresh then
        sourceDropdown.refresh()
    end
end

settingsPanel:HookScript("OnHide", function()
    CloseCraftFilterDropdowns()
end)

local craftLibCallout = Theme.CreateCraftLibInstallCallout(filterContent, {
    introText = "Install CraftLib addon to see:",
    bulletLines = {
        "Advanced filtering options",
        "Recipe skill requirements",
        "Color coded difficulty",
        "All recipe icons",
    },
})
craftLibCallout:SetPoint("TOPLEFT", professionDropdownBtn, "BOTTOMLEFT", 0, -FILTER_SECTION_GAP)
craftLibCallout:SetPoint("TOPRIGHT", filterContent, "TOPRIGHT", 0, 0)

local function SetCraftFilterWidgetsShown(shown)
    for i = 1, #craftFilterWidgets do
        local widget = craftFilterWidgets[i]
        if widget and widget.SetShown then
            widget:SetShown(shown)
        end
    end
end

local function RefreshSearchSettingsControls()
    if applyRecipeLevelFilterRowLayout then
        applyRecipeLevelFilterRowLayout()
    end
    if not SS or not SS.GetRecipeLevelFilter then
        return
    end
    local f = SS.GetRecipeLevelFilter()
    local craftLibReady = RCL and RCL.IsAvailable and RCL.IsAvailable()
    SyncCraftFilterDropdowns()
    if professionDropdown and professionDropdown.header then
        professionDropdown.header:Show()
        SetRecipeLevelHeaderColor(professionDropdown.header)
    end
    if professionDropdownBtn then
        professionDropdownBtn:Show()
    end
    if craftLibReady then
        recipeLevelHeader:Show()
        minLevelLabel:Show()
        minLevelEdit:Show()
        maxLevelLabel:Show()
        maxLevelEdit:Show()
        SetCraftFilterWidgetsShown(true)
        craftLibCallout:Hide()
        suppressRecipeFilterTextChanged = true
        minLevelEdit:SetText(tostring(f.min or 0))
        maxLevelEdit:SetText(tostring(f.max or 375))
        suppressRecipeFilterTextChanged = false
        SetRecipeLevelHeaderColor(recipeLevelHeader)
        SetRecipeLevelHeaderColor(difficultyDropdown and difficultyDropdown.header)
        SetRecipeLevelHeaderColor(sourceDropdown and sourceDropdown.header)
        if UpdateRecipeLevelResetButtonVisibility then
            UpdateRecipeLevelResetButtonVisibility()
        end
        if Theme.SetLabelColor then
            Theme.SetLabelColor(minLevelLabel)
            Theme.SetLabelColor(maxLevelLabel)
        end
    else
        recipeLevelHeader:Hide()
        minLevelLabel:Hide()
        minLevelEdit:Hide()
        maxLevelLabel:Hide()
        maxLevelEdit:Hide()
        recipeLevelResetBtn:Hide()
        SetCraftFilterWidgetsShown(false)
        CloseCraftFilterDropdowns()
        craftLibCallout:Show()
    end
end

RefreshSearchSettingsControls()

function frame:IsSearchSettingsShown()
    return settingsPanel and settingsPanel:IsShown()
end

local function ApplyTabContentLayout()
    tabContentPanel:ClearAllPoints()
    tabContentPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", SECTION_INSET, -SECTION_INSET)
    if settingsPanel:IsShown() then
        tabContentPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -SECTION_GAP, SECTION_INSET)
    else
    tabContentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SECTION_INSET, SECTION_INSET)
    end
end

-- List viewport and horizontal scroll bar layout.
-- Columns are sized to the viewport, so horizontal scroll is unused; do not reserve
-- HORIZONTAL_SCROLL_BAR_HEIGHT (Summary only reserves that strip when columns overflow).
local function ApplySearchListLayout()
    ApplyTabContentLayout()
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, -PAD)
    listViewport:SetPoint(
        "BOTTOMRIGHT", tabContentPanel, "BOTTOMRIGHT", -SCROLL_GUTTER, PAD)
    horizontalScrollBar:ClearAllPoints()
    horizontalScrollBar:SetPoint("BOTTOMLEFT", tabContentInner, "BOTTOMLEFT", PAD, -4)
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
            btn:SetHeight(HEADER_HEIGHT)
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
