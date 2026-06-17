-- AltArmy TBC — Search tab: item search across characters (bags + bank).

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
if not frame then
    return
end

local PAD = 4
local Theme = AltArmy.Theme
local CC = AltArmy.ClassColor
local TruncateFontString = AltArmy.Text and AltArmy.Text.TruncateFontString
local SECTION_INSET = Theme.TAB_SECTION_INSET
local SECTION_GAP = Theme.SECTION_GAP
local ROW_HEIGHT = 18
-- Right-side (Total column) icon size; match left-side row icon (WoW :0 default ~14)
local OVERLAY_ICON_SIZE = 14
local HEADER_HEIGHT = 18
local HEADER_ROW_GAP = 6  -- space between section header and first data row
-- Virtualized list: only render rows near the viewport
local ROW_BUFFER = 3   -- extra rows above/below viewport to render
local ITEM_POOL_SIZE = 32
local RECIPE_POOL_SIZE = 32
local TOOLTIP_ONLY_POOL_SIZE = 32

local SD = AltArmy.SearchData
if not SD or not SD.SearchWithLocationGroups or not SD.SearchRecipes then
    return
end

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
        or { Item = 325, Character = 170, Total = 72 }
    local recipe = SearchColumns and SearchColumns.GetRecipeColumnWidths(settingsOpen)
        or { Recipe = 325, Character = 170, Skill = 72 }
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
        })
    else
        cell:SetText((iconPrefix or "") .. itemName .. countSuffix)
    end
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
local horizontalScrollApi = Theme.CreateHorizontalScrollBar(tabContentInner, {
    name = "AltArmyTBC_SearchHorizontalScrollBar",
    thickness = HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2,
    onScroll = function(value)
        if not horizontalScroll then return end
        if horizontalScroll.UpdateScrollChildRect then
            horizontalScroll:UpdateScrollChildRect()
        end
        horizontalScroll:SetHorizontalScroll(value)
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

-- Reparent scroll frame into horizontal scroll child so it scrolls with the grid
scrollFrame:ClearAllPoints()
scrollFrame:SetParent(horizontalScrollChild)
scrollFrame:SetPoint("TOPLEFT", horizontalScrollChild, "TOPLEFT", 0, 0)
scrollFrame:SetPoint("BOTTOMLEFT", horizontalScrollChild, "BOTTOMLEFT", 0, 0)
scrollFrame:SetPoint("BOTTOMRIGHT", horizontalScrollChild, "BOTTOMRIGHT", 0, 0)

local resultsArea = CreateFrame("Frame", nil, scrollFrame)
resultsArea:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
resultsArea:SetWidth(totalColWidth)
resultsArea:SetHeight(ROW_HEIGHT)
scrollFrame:SetScrollChild(resultsArea)
resultsArea:SetScript("OnMouseWheel", OnSearchScrollWheel)

-- Items section header (created once, shown when items have results)
local itemsHeaderRow = CreateFrame("Frame", nil, resultsArea)
itemsHeaderRow:SetHeight(HEADER_HEIGHT)
local itemsHeaderLabels = {}
local ix = 0
for _, colName in ipairs(colOrder) do
    local w = colWidths[colName] or 80
    local label = itemsHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", itemsHeaderRow, "BOTTOMLEFT", ix, 0)
    label:SetWidth(w)
    label:SetJustifyH(colName == "Item" and "LEFT" or "RIGHT")
    label:SetText(colName)
    itemsHeaderLabels[#itemsHeaderLabels + 1] = label
    ix = ix + w
end
-- Recipes section header
local recipesHeaderRow = CreateFrame("Frame", nil, resultsArea)
recipesHeaderRow:SetHeight(HEADER_HEIGHT)
local recipesHeaderLabels = {}
local rx = 0
for _, colName in ipairs(recipeColOrder) do
    local w = recipeColWidths[colName] or 80
    local label = recipesHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", recipesHeaderRow, "BOTTOMLEFT", rx, 0)
    label:SetWidth(w)
    label:SetJustifyH(colName == "Recipe" and "LEFT" or "RIGHT")
    label:SetText(colName)
    recipesHeaderLabels[#recipesHeaderLabels + 1] = label
    rx = rx + w
end

-- "You may also be interested in:" section header: same columns as items (Item/Character/Total),
-- with the first column label replaced by the section title.
local alsoInterestedHeaderRow = CreateFrame("Frame", nil, resultsArea)
alsoInterestedHeaderRow:SetHeight(HEADER_HEIGHT)
local alsoInterestedHeaderLabels = {}
local aix = 0
for _, colName in ipairs(colOrder) do
    local w = colWidths[colName] or 80
    local label = alsoInterestedHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", alsoInterestedHeaderRow, "BOTTOMLEFT", aix, 0)
    label:SetWidth(w)
    label:SetJustifyH(colName == "Item" and "LEFT" or "RIGHT")
    label:SetText(colName == "Item" and "You may also be interested in:" or colName)
    alsoInterestedHeaderLabels[#alsoInterestedHeaderLabels + 1] = label
    aix = aix + w
end

-- Result rows (pool) for items
local resultRows = {}
local itemList = {}
local recipeList = {}
local recipeRows = {}
local itemGroups = {}  -- built in UpdateResults, used by UpdateVisibleRows for overlays
local tooltipOnlyItemList = {}
local tooltipOnlyItemGroups = {}
local tooltipOnlyResultRows = {}
local UpdateVisibleRows  -- forward-declare for scroll bar script
local UpdateResults      -- forward-declare for debounce callback

-- Debounce for tooltip-only search: main results (ID/name/link) appear immediately;
-- tooltip scan runs after the user stops typing for TOOLTIP_DEBOUNCE_SECS seconds.
local TOOLTIP_DEBOUNCE_SECS = 0.4
local TOOLTIP_CHUNK_SIZE = 80
local tooltipDebounceFrame = CreateFrame("Frame")
local tooltipDebounceRemaining = 0
local tooltipDebounceQuery = nil
local tooltipChunkFrame = CreateFrame("Frame")
local tooltipChunkState = nil
local tooltipChunkGeneration = 0

local function ApplyTooltipOnlyRealmFilter(rows)
    local RF = AltArmy.RealmFilter
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
    if not query or query == "" then
        tooltipDebounceQuery = nil
        tooltipDebounceFrame:SetScript("OnUpdate", nil)
        return
    end
    tooltipDebounceQuery = query
    tooltipDebounceRemaining = TOOLTIP_DEBOUNCE_SECS
    tooltipDebounceFrame:SetScript("OnUpdate", tooltipDebounceOnUpdate)
end

local function IsTooltipSearchPending()
    if tooltipDebounceFrame:GetScript("OnUpdate") then
        return true
    end
    return tooltipChunkState ~= nil
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
        cell:SetJustifyH(colName == "Recipe" and "LEFT" or "RIGHT")
        cell:SetNonSpaceWrap(false)
        if colName == "Recipe" or colName == "Character" then cell:SetWordWrap(false) end
        row.cells[colName] = cell
        cx = cx + w
    end
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

local function fillItemRow(row, entry, showRealmSuffix)
    if not row or not entry then return end
    row.entry = entry
    local count = entry.count or 1
    local itemText = (entry.itemName and entry.itemName ~= "") and entry.itemName
        or ("Item " .. (entry.itemID or ""))
    local countSuffix = " x" .. tostring(count)
    local iconPrefix = ""
    if entry.itemLink and GetItemInfo and GetItemInfo(entry.itemLink) then
        local icon = select(10, GetItemInfo(entry.itemLink)) or "Interface\\Icons\\INV_Misc_QuestionMark"
        iconPrefix = "|T" .. icon .. ":0|t "
    end
    SetItemCellTruncated(row.cells.Item, itemText, countSuffix, iconPrefix, colWidths.Item or 325)
    local locLabel = entry.location == "bank" and "Bank"
        or (entry.location == "mail" and "Mail")
        or (entry.location == "equipped" and "Equipped")
        or "Bags"
    local name = entry.characterName or ""
    local RF = AltArmy.RealmFilter
    local namePart
    if RF and RF.formatColoredCharacterNameRealm then
        namePart = RF.formatColoredCharacterNameRealm(
            name,
            entry.realm,
            showRealmSuffix,
            entry.classFile
        )
    else
        local r, g, b = 1, 0.82, 0
        if CC and CC.getRGBOr then
            r, g, b = CC.getRGBOr(entry.classFile, r, g, b)
        end
        namePart = CC and CC.formatHex and CC.formatHex(r, g, b, name)
            or string.format(
                "|cFF%02x%02x%02x%s|r",
                math.floor(r * 255), math.floor(g * 255), math.floor(b * 255),
                name
            )
    end
    local suffixText = "|cffffffff (" .. locLabel .. ")|r"
    SetCharacterCellTruncated(row.cells.Character, namePart, suffixText, colWidths.Character or 160)
    row.cells.Total:SetText("")
end

local function fillRecipeRow(row, entry, showRealmSuffix)
    if not row or not entry then return end
    row.entry = entry
    local recipeName = "Recipe " .. tostring(entry.recipeID or "?")
    local iconPath = "Interface\\Icons\\INV_Misc_QuestionMark"
    if GetSpellInfo and entry.recipeID then
        local name = GetSpellInfo(entry.recipeID)
        if name then recipeName = name end
    end
    if recipeName == ("Recipe " .. tostring(entry.recipeID or "?")) and GetItemInfo and entry.recipeID then
        local name = GetItemInfo(entry.recipeID)
        if name then recipeName = name end
    end
    if entry.resultItemID and GetItemInfo then
        local _, _, _, _, _, _, _, _, _, resultIcon = GetItemInfo(entry.resultItemID)
        if resultIcon then iconPath = resultIcon end
    end
    if not entry.resultItemID and GetItemInfo and entry.recipeID then
        local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(entry.recipeID)
        if icon then iconPath = icon end
    end
    if not entry.resultItemID and GetSpellInfo and entry.recipeID then
        local _, _, spellIcon = GetSpellInfo(entry.recipeID)
        if spellIcon then iconPath = spellIcon end
    end
    local profName = entry.professionName or ""
    if profName ~= "" then
        recipeName = profName .. ": " .. recipeName
    end
    local iconPrefix = ("|T%s:0|t "):format(iconPath)
    SetItemCellTruncated(row.cells.Recipe, recipeName, "", iconPrefix, recipeColWidths.Recipe or 325)
    local name = entry.characterName or ""
    local RF = AltArmy.RealmFilter
    local namePart
    if RF and RF.formatColoredCharacterNameRealm then
        namePart = RF.formatColoredCharacterNameRealm(name, entry.realm, showRealmSuffix, entry.classFile)
    else
        local r, g, b = 1, 0.82, 0
        if CC and CC.getRGBOr then
            r, g, b = CC.getRGBOr(entry.classFile, r, g, b)
        end
        namePart = CC and CC.formatHex and CC.formatHex(r, g, b, name)
            or string.format(
                "|cFF%02x%02x%02x%s|r",
                math.floor(r * 255), math.floor(g * 255), math.floor(b * 255),
                name
            )
    end
    SetCharacterCellTruncated(row.cells.Character, namePart, nil, recipeColWidths.Character or 160)
    local RCL = AltArmy and AltArmy.RecipeCraftLib
    local skillText
    if RCL and RCL.FormatSkillCell then
        skillText = RCL.FormatSkillCell(entry.recipeSkillRequired, entry.skillRank, entry.difficulty)
    else
        skillText = tostring(entry.skillRank or 0)
    end
    row.cells.Skill:SetText(skillText)
end

-- Virtualized list: fill only rows in the visible range + buffer. Call after layout and on scroll.
UpdateVisibleRows = function()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    -- Show realm suffix only when viewing all realms and account has characters on multiple realms.
    local showRealmSuffix = (GlobalRealmFilterValue() == "all") and AccountHasMultipleRealms()
    local scrollValue = searchScrollBar and searchScrollBar:GetValue() or 0
    local viewHeight = scrollFrame:GetHeight()
    local itemsSectionTop = HEADER_HEIGHT + HEADER_ROW_GAP

    -- Items: visible range and render range (with buffer)
    if nItems > 0 then
        local firstVisible = math.max(1, math.floor((scrollValue - itemsSectionTop) / ROW_HEIGHT) + 1)
        if scrollValue < itemsSectionTop then firstVisible = 1 end
        local lastVisible = math.min(nItems, math.floor((scrollValue + viewHeight - itemsSectionTop) / ROW_HEIGHT))
        local firstRender = math.max(1, firstVisible - ROW_BUFFER)
        local lastRender = math.min(nItems, lastVisible + ROW_BUFFER)
        local itemsFirstRowY = -(HEADER_HEIGHT + HEADER_ROW_GAP)

        local totalColX = (colWidths.Item or 280) + (colWidths.Character or 160)
        local totalColW = colWidths.Total or 72
        local renderCount = lastRender - firstRender + 1
        for poolIdx = 1, ITEM_POOL_SIZE do
            local row = resultRows[poolIdx]
            if not row then
                row = createItemRow()
                resultRows[poolIdx] = row
            end
            if poolIdx <= renderCount then
                local dataIndex = firstRender + poolIdx - 1
                local entry = itemList[dataIndex]
                local rowY = itemsFirstRowY - (dataIndex - 1) * ROW_HEIGHT
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, rowY)
                row:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, rowY)
                row:SetPoint("BOTTOMLEFT", resultsArea, "TOPLEFT", 0, rowY - ROW_HEIGHT)
                fillItemRow(row, entry, showRealmSuffix)
                row:Show()
                row.dataIndex = dataIndex
            else
                row:Hide()
                row.entry = nil
                row.dataIndex = nil
            end
        end

        -- Group overlays: only for groups that intersect [firstRender, lastRender]
        local overlayIdx = 0
        for _, group in ipairs(itemGroups) do
            local gEnd = group.start + group.count - 1
            if gEnd >= firstRender and group.start <= lastRender then
                overlayIdx = overlayIdx + 1
                local overlay = getGroupOverlay(overlayIdx)
                local groupStart = math.max(group.start, firstRender)
                local groupEnd = math.min(gEnd, lastRender)
                local firstPoolIdx = groupStart - firstRender + 1
                local lastPoolIdx = groupEnd - firstRender + 1
                local firstRowFrame = resultRows[firstPoolIdx]
                local lastRowFrame = resultRows[lastPoolIdx]
                if firstRowFrame and lastRowFrame and firstRowFrame:IsShown() and lastRowFrame:IsShown() then
                    overlay:ClearAllPoints()
                    overlay:SetPoint("TOPLEFT", firstRowFrame, "TOPLEFT", totalColX, 2)
                    overlay:SetPoint("BOTTOMLEFT", lastRowFrame, "BOTTOMLEFT", totalColX, 2)
                    overlay:SetPoint("TOPRIGHT", firstRowFrame, "TOPLEFT", totalColX + totalColW, 2)
                    overlay:SetPoint("BOTTOMRIGHT", lastRowFrame, "BOTTOMLEFT", totalColX + totalColW, 2)
                    overlay.icon:ClearAllPoints()
                    overlay.icon:SetPoint("CENTER", overlay, "RIGHT", -2 - OVERLAY_ICON_SIZE / 2, 0)
                    local firstEntry = itemList[group.start]
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
                    overlay.total:SetText(tostring(group.total))
                    overlay:Show()
                end
            end
        end
        for idx = overlayIdx + 1, #groupOverlayPool do
            if groupOverlayPool[idx] then groupOverlayPool[idx]:Hide() end
        end
    else
        for _, row in ipairs(resultRows) do
            row:Hide()
            row.entry = nil
            row.dataIndex = nil
        end
        for idx = 1, #groupOverlayPool do
            if groupOverlayPool[idx] then groupOverlayPool[idx]:Hide() end
        end
    end

    -- Recipes: visible range and render range
    local recipesSectionTop = itemsSectionTop + nItems * ROW_HEIGHT + HEADER_HEIGHT + HEADER_ROW_GAP
    if nItems == 0 then
        recipesSectionTop = HEADER_HEIGHT + HEADER_ROW_GAP
    end
    if nRecipes > 0 then
        local firstVisible = math.max(1, math.floor((scrollValue - recipesSectionTop) / ROW_HEIGHT) + 1)
        if scrollValue < recipesSectionTop then firstVisible = 1 end
        local lastVisible = math.min(nRecipes, math.floor((scrollValue + viewHeight - recipesSectionTop) / ROW_HEIGHT))
        local firstRender = math.max(1, firstVisible - ROW_BUFFER)
        local lastRender = math.min(nRecipes, lastVisible + ROW_BUFFER)
        local recipesFirstRowY = -recipesSectionTop

        local renderCount = lastRender - firstRender + 1
        for poolIdx = 1, RECIPE_POOL_SIZE do
            local row = recipeRows[poolIdx]
            if not row then
                row = createRecipeRow()
                recipeRows[poolIdx] = row
            end
            if poolIdx <= renderCount then
                local dataIndex = firstRender + poolIdx - 1
                local entry = recipeList[dataIndex]
                local rowY = recipesFirstRowY - (dataIndex - 1) * ROW_HEIGHT
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, rowY)
                row:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, rowY)
                row:SetPoint("BOTTOMLEFT", resultsArea, "TOPLEFT", 0, rowY - ROW_HEIGHT)
                fillRecipeRow(row, entry, showRealmSuffix)
                row:Show()
            else
                row:Hide()
                row.entry = nil
            end
        end
    else
        for _, row in ipairs(recipeRows) do
            row:Hide()
            row.entry = nil
        end
    end

    -- "You may also be interested in:" tooltip-only section
    local nTooltipOnly = #tooltipOnlyItemList
    if nTooltipOnly > 0 then
        local tooltipOnlySectionTop
        if nRecipes > 0 then
            tooltipOnlySectionTop = recipesSectionTop + nRecipes * ROW_HEIGHT + HEADER_HEIGHT + HEADER_ROW_GAP
        elseif nItems > 0 then
            tooltipOnlySectionTop = itemsSectionTop + nItems * ROW_HEIGHT + HEADER_HEIGHT + HEADER_ROW_GAP
        else
            tooltipOnlySectionTop = HEADER_HEIGHT + HEADER_ROW_GAP
        end

        local firstVisible = math.max(1, math.floor((scrollValue - tooltipOnlySectionTop) / ROW_HEIGHT) + 1)
        if scrollValue < tooltipOnlySectionTop then firstVisible = 1 end
        local lastVisible = math.min(nTooltipOnly,
            math.floor((scrollValue + viewHeight - tooltipOnlySectionTop) / ROW_HEIGHT))
        local firstRender = math.max(1, firstVisible - ROW_BUFFER)
        local lastRender = math.min(nTooltipOnly, lastVisible + ROW_BUFFER)
        local tooltipOnlyFirstRowY = -tooltipOnlySectionTop

        local totalColX = (colWidths.Item or 280) + (colWidths.Character or 160)
        local totalColW = colWidths.Total or 72
        local renderCount = lastRender - firstRender + 1
        for poolIdx = 1, TOOLTIP_ONLY_POOL_SIZE do
            local row = tooltipOnlyResultRows[poolIdx]
            if not row then
                row = createItemRow()
                tooltipOnlyResultRows[poolIdx] = row
            end
            if poolIdx <= renderCount then
                local dataIndex = firstRender + poolIdx - 1
                local entry = tooltipOnlyItemList[dataIndex]
                local rowY = tooltipOnlyFirstRowY - (dataIndex - 1) * ROW_HEIGHT
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, rowY)
                row:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, rowY)
                row:SetPoint("BOTTOMLEFT", resultsArea, "TOPLEFT", 0, rowY - ROW_HEIGHT)
                fillItemRow(row, entry, showRealmSuffix)
                row:Show()
                row.dataIndex = dataIndex
            else
                row:Hide()
                row.entry = nil
                row.dataIndex = nil
            end
        end

        local overlayIdx = 0
        for _, group in ipairs(tooltipOnlyItemGroups) do
            local gEnd = group.start + group.count - 1
            if gEnd >= firstRender and group.start <= lastRender then
                overlayIdx = overlayIdx + 1
                local overlay = getTooltipOnlyGroupOverlay(overlayIdx)
                local groupStart = math.max(group.start, firstRender)
                local groupEnd = math.min(gEnd, lastRender)
                local firstPoolIdx = groupStart - firstRender + 1
                local lastPoolIdx = groupEnd - firstRender + 1
                local firstRowFrame = tooltipOnlyResultRows[firstPoolIdx]
                local lastRowFrame = tooltipOnlyResultRows[lastPoolIdx]
                if firstRowFrame and lastRowFrame and firstRowFrame:IsShown() and lastRowFrame:IsShown() then
                    overlay:ClearAllPoints()
                    overlay:SetPoint("TOPLEFT", firstRowFrame, "TOPLEFT", totalColX, 2)
                    overlay:SetPoint("BOTTOMLEFT", lastRowFrame, "BOTTOMLEFT", totalColX, 2)
                    overlay:SetPoint("TOPRIGHT", firstRowFrame, "TOPLEFT", totalColX + totalColW, 2)
                    overlay:SetPoint("BOTTOMRIGHT", lastRowFrame, "BOTTOMLEFT", totalColX + totalColW, 2)
                    overlay.icon:ClearAllPoints()
                    overlay.icon:SetPoint("CENTER", overlay, "RIGHT", -2 - OVERLAY_ICON_SIZE / 2, 0)
                    local firstEntry = tooltipOnlyItemList[group.start]
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
                    overlay.total:SetText(tostring(group.total))
                    overlay:Show()
                end
            end
        end
        for idx = overlayIdx + 1, #tooltipOnlyGroupOverlayPool do
            if tooltipOnlyGroupOverlayPool[idx] then tooltipOnlyGroupOverlayPool[idx]:Hide() end
        end
    else
        for _, row in ipairs(tooltipOnlyResultRows) do
            row:Hide()
            row.entry = nil
            row.dataIndex = nil
        end
        for idx = 1, #tooltipOnlyGroupOverlayPool do
            if tooltipOnlyGroupOverlayPool[idx] then tooltipOnlyGroupOverlayPool[idx]:Hide() end
        end
    end
end

-- Wire scroll to refresh visible rows (must be after UpdateVisibleRows is defined)
searchScrollBar:SetScript("OnValueChanged", function(_, value)
    scrollFrame:SetVerticalScroll(value)
    UpdateVisibleRows()
end)

UpdateResults = function()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local contentHeight = 0
    local currentY = 0

    -- Items section: layout header, build groups, set content height (virtualized rows in UpdateVisibleRows)
    if nItems > 0 then
        itemsHeaderRow:ClearAllPoints()
        itemsHeaderRow:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, currentY)
        itemsHeaderRow:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, currentY)
        itemsHeaderRow:Show()
        currentY = currentY - HEADER_HEIGHT - HEADER_ROW_GAP
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
        currentY = currentY - nItems * ROW_HEIGHT
    else
        itemsHeaderRow:Hide()
        itemGroups = {}
    end

    -- Recipes section: layout header and content height (virtualized rows in UpdateVisibleRows)
    if nRecipes > 0 then
        recipesHeaderRow:ClearAllPoints()
        recipesHeaderRow:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, currentY)
        recipesHeaderRow:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, currentY)
        recipesHeaderRow:Show()
        contentHeight = contentHeight + HEADER_HEIGHT + HEADER_ROW_GAP
        contentHeight = contentHeight + nRecipes * ROW_HEIGHT
        currentY = currentY - HEADER_HEIGHT - HEADER_ROW_GAP - nRecipes * ROW_HEIGHT
    else
        recipesHeaderRow:Hide()
    end

    -- "You may also be interested in:" section: tooltip-only matches shown after Items and Recipes
    local nTooltipOnly = #tooltipOnlyItemList
    if nTooltipOnly > 0 then
        alsoInterestedHeaderRow:ClearAllPoints()
        alsoInterestedHeaderRow:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, currentY)
        alsoInterestedHeaderRow:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, currentY)
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
    if searchScrollBar then
        local viewHeight = scrollFrame:GetHeight()
        local maxScroll = math.max(0, contentHeight - viewHeight)
        searchScrollBar:SetMinMaxValues(0, maxScroll)
        searchScrollBar:SetValueStep(ROW_HEIGHT)
        local val = searchScrollBar:GetValue()
        if val > maxScroll then
            searchScrollBar:SetValue(maxScroll)
            scrollFrame:SetVerticalScroll(maxScroll)
        end
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
    UpdateVisibleRows()
    UpdateNoResultsHint()
end

function frame.DoSearch()
    local query = ""
    if searchEdit then
        query = searchEdit:GetText()
    end
    if query and query:match("^%s*$") then query = "" end
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
    recipeList = (categories.Recipes and query ~= "") and (SD.SearchRecipes(query) or {}) or {}
    local RF = AltArmy.RealmFilter
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if RF and RF.filterListByRealm then
        local rf = GlobalRealmFilterValue()
        itemList = RF.filterListByRealm(itemList, rf, currentRealm)
        recipeList = RF.filterListByRealm(recipeList, rf, currentRealm)
    end
    UpdateResults()
    if searchScrollBar then searchScrollBar:SetValue(0) end
    scrollFrame:SetVerticalScroll(0)
    ScheduleTooltipSearch(query)
end

-- Expose for header search box: run search with query directly
function frame.SearchWithQuery(_self, query)
    local q = (query and type(query) == "string") and query:match("^%s*(.-)%s*$") or ""
    frame.lastQuery = q
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if q == "" then
        itemList = {}
        tooltipOnlyItemList = {}
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
        recipeList = categories.Recipes and (SD.SearchRecipes(q) or {}) or {}
    end
    local RF = AltArmy.RealmFilter
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    if RF and RF.filterListByRealm then
        local rf = GlobalRealmFilterValue()
        itemList = RF.filterListByRealm(itemList, rf, currentRealm)
        recipeList = RF.filterListByRealm(recipeList, rf, currentRealm)
    end
    UpdateResults()
    if searchScrollBar then searchScrollBar:SetValue(0) end
    scrollFrame:SetVerticalScroll(0)
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
local FILTER_DROPDOWN_POPUP_PAD_LEFT = 8
local FILTER_DROPDOWN_POPUP_PAD_TOP = 6
local FILTER_DROPDOWN_POPUP_PAD_BOTTOM = 8
local FILTER_DROPDOWN_POPUP_PAD_RIGHT = 8
local FILTER_DROPDOWN_TEXT_INSET = 8
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
    btn:SetHeight(SETTINGS_ROW_HEIGHT)
    btn:SetPoint("TOP", header, "BOTTOM", 0, -FILTER_DROPDOWN_GAP)
    btn:SetPoint("LEFT", filterContent, "LEFT", 0, 0)
    btn:SetPoint("RIGHT", filterContent, "RIGHT", 0, 0)
    Theme.SkinButton(btn)
    if registerCraftFilterWidget then
        AddCraftFilterWidget(btn)
    end

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("LEFT", btn, "LEFT", 4, 0)
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
    local rowHeight = Theme.CHAR_LIST_ROW_HEIGHT or 20
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

local CALLOUT_PAD = 8
local CRAFTLIB_URL = "https://www.curseforge.com/wow/addons/craftlib"
local craftLibCallout = CreateFrame("Frame", nil, filterContent, "BackdropTemplate")
Theme.ApplyBackdrop(craftLibCallout, "section")
craftLibCallout:SetPoint("TOPLEFT", professionDropdownBtn, "BOTTOMLEFT", 0, -FILTER_SECTION_GAP)
craftLibCallout:SetPoint("TOPRIGHT", filterContent, "TOPRIGHT", 0, 0)
craftLibCallout:SetHeight(132)

local craftLibCalloutInner = Theme.CreatePanelInnerContent(craftLibCallout, CALLOUT_PAD)

local craftLibNoticeIcon = craftLibCallout:CreateTexture(nil, "ARTWORK")
craftLibNoticeIcon:SetSize(24, 24)
craftLibNoticeIcon:SetPoint("TOPLEFT", craftLibCalloutInner, "TOPLEFT", 0, 0)
craftLibNoticeIcon:SetTexture("Interface\\AddOns\\AltArmy_TBC\\Textures\\CraftLibIcon")

local craftLibNoticeTitle = craftLibCallout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
craftLibNoticeTitle:SetPoint("LEFT", craftLibNoticeIcon, "RIGHT", 8, 0)
craftLibNoticeTitle:SetPoint("TOP", craftLibNoticeIcon, "TOP", 0, -2)
craftLibNoticeTitle:SetPoint("RIGHT", craftLibCalloutInner, "RIGHT", 0, 0)
craftLibNoticeTitle:SetJustifyH("LEFT")
craftLibNoticeTitle:SetText("CraftLib")
Theme.SetTitleColor(craftLibNoticeTitle)

local craftLibNoticeBody = craftLibCallout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
craftLibNoticeBody:SetPoint("TOPLEFT", craftLibNoticeIcon, "BOTTOMLEFT", 0, -8)
craftLibNoticeBody:SetPoint("RIGHT", craftLibCalloutInner, "RIGHT", 0, 0)
craftLibNoticeBody:SetJustifyH("LEFT")
craftLibNoticeBody:SetWordWrap(true)
Theme.SetLabelColor(craftLibNoticeBody)
craftLibNoticeBody:SetText(
    "Alt Army can do more advanced recipe filtering if you install the CraftLib addon"
)

local craftLibInstallLabel = craftLibCallout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
craftLibInstallLabel:SetPoint("TOPLEFT", craftLibNoticeBody, "BOTTOMLEFT", 0, -10)
craftLibInstallLabel:SetJustifyH("LEFT")
craftLibInstallLabel:SetText("Install from CurseForge")
Theme.SetLabelColor(craftLibInstallLabel)

local craftLibUrlEdit = CreateFrame("EditBox", nil, craftLibCallout)
craftLibUrlEdit:SetHeight(SETTINGS_ROW_HEIGHT)
craftLibUrlEdit:SetPoint("TOPLEFT", craftLibInstallLabel, "BOTTOMLEFT", 0, -4)
craftLibUrlEdit:SetPoint("RIGHT", craftLibCalloutInner, "RIGHT", 0, 0)
craftLibUrlEdit:SetFontObject("GameFontHighlightSmall")
craftLibUrlEdit:SetAutoFocus(false)
craftLibUrlEdit:SetTextInsets(4, 4, 0, 0)
craftLibUrlEdit:SetText(CRAFTLIB_URL)
Theme.ApplyInputTextures(craftLibUrlEdit)
craftLibUrlEdit:SetScript("OnEditFocusGained", function(box)
    box:HighlightText()
end)
craftLibUrlEdit:SetScript("OnEditFocusLost", function(box)
    box:HighlightText(0, 0)
end)
craftLibUrlEdit:SetScript("OnMouseUp", function(box)
    box:SetFocus()
    box:HighlightText()
end)
craftLibUrlEdit:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
end)
craftLibUrlEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
end)
craftLibUrlEdit:SetScript("OnChar", function() end)
craftLibUrlEdit:SetScript("OnTextChanged", function(box)
    if box:GetText() ~= CRAFTLIB_URL then
        box:SetText(CRAFTLIB_URL)
    end
end)

local function SelectCraftLibUrlText()
    if not craftLibUrlEdit or not craftLibUrlEdit.HighlightText then
        return
    end
    craftLibUrlEdit:SetFocus()
    craftLibUrlEdit:HighlightText()
end

craftLibCallout:SetScript("OnShow", function(self)
    self:SetScript("OnUpdate", function(f)
        f:SetScript("OnUpdate", nil)
        SelectCraftLibUrlText()
    end)
end)

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
local function ApplySearchListLayout()
    ApplyTabContentLayout()
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", tabContentInner, "TOPLEFT", 0, -PAD)
    listViewport:SetPoint(
        "BOTTOMRIGHT", tabContentPanel, "BOTTOMRIGHT", -SCROLL_GUTTER, HORIZONTAL_SCROLL_BAR_HEIGHT)
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

local function LayoutSearchHeaderLabels(labels, headerRow, order, widths, labelTextForCol)
    local x = 0
    for i, colName in ipairs(order) do
        local w = widths[colName] or 80
        local label = labels[i]
        if label then
            label:SetWidth(w)
            label:ClearAllPoints()
            label:SetPoint("BOTTOMLEFT", headerRow, "BOTTOMLEFT", x, 0)
            if labelTextForCol then
                label:SetText(labelTextForCol(colName))
            end
        end
        x = x + w
    end
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
    LayoutSearchHeaderLabels(itemsHeaderLabels, itemsHeaderRow, colOrder, colWidths)
    LayoutSearchHeaderLabels(recipesHeaderLabels, recipesHeaderRow, recipeColOrder, recipeColWidths)
    LayoutSearchHeaderLabels(alsoInterestedHeaderLabels, alsoInterestedHeaderRow, colOrder, colWidths, function(colName)
        return colName == "Item" and "You may also be interested in:" or colName
    end)
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
