-- AltArmy TBC — Search tab: item search across characters (bags + bank).

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
if not frame then
    print("[AltArmy] TabSearch: frame is nil (AltArmy or TabFrames.Search missing), returning early")
    return
end

local PAD = 4
local ROW_HEIGHT = 18
-- Right-side (Total column) icon size; match left-side row icon (WoW :0 default ~14)
local OVERLAY_ICON_SIZE = 14
local HEADER_HEIGHT = 18
local HEADER_ROW_GAP = 6  -- space between section header and first data row
-- Virtualized list: only render rows near the viewport
local ROW_BUFFER = 3   -- extra rows above/below viewport to render
local ITEM_POOL_SIZE = 32
local RECIPE_POOL_SIZE = 32

local SD = AltArmy.SearchData
if not SD or not SD.SearchWithLocationGroups or not SD.SearchRecipes then
    print("[AltArmy] TabSearch: SearchData missing or missing SearchWithLocationGroups/SearchRecipes, returning early")
    return
end
print("[AltArmy] TabSearch: loaded, frame and SearchData OK")

local REALM_FILTER_OPTIONS = { "all", "currentRealm" }
local REALM_FILTER_LABELS = { all = "All Characters", currentRealm = "Current Realm Only" }
local function GetSearchSettings()
    AltArmyTBC_SearchSettings = AltArmyTBC_SearchSettings or {}
    local s = AltArmyTBC_SearchSettings
    if s.realmFilter ~= "all" and s.realmFilter ~= "currentRealm" then
        s.realmFilter = "all"
    end
    return s
end

-- Insert item link into chat (same as shift-clicking item in bags)
local function InsertItemLinkIntoChat(itemLinkOrID)
    local link = itemLinkOrID
    if type(link) == "number" and GetItemInfo then
        local _, itemLink = GetItemInfo(link)
        link = itemLink
    end
    if type(link) == "string" and link ~= "" and ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
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

local colWidths = { Item = 325, Character = 160, Total = 70 }  -- items table (first col -5 for total width)
local colOrder = { "Item", "Character", "Total" }
local recipeColWidths = { Recipe = 325, Character = 160, Skill = 70 }  -- first col -5
local recipeColOrder = { "Recipe", "Character", "Skill" }

--- Truncate name part only; suffix (e.g. " (Bags)") is never truncated. Sets cell to truncatedName + suffix.
--- @param cell FontString
--- @param namePartColored string Colored name (e.g. |cFFrrggbbName-Realm|r)
--- @param suffixText string|nil Optional suffix (e.g. |cFFFFFFFF (Bags)|r); if nil, truncate whole namePart.
--- @param maxTotalWidth number Cell width
local function SetCharacterCellTruncated(cell, namePartColored, suffixText, maxTotalWidth)
    local maxNameW = maxTotalWidth - 2
    if suffixText and suffixText ~= "" then
        cell:SetText(suffixText)
        maxNameW = maxNameW - cell:GetStringWidth()
        if maxNameW < 10 then maxNameW = 10 end
    end
    local prefix = namePartColored:match("^|c%x%x%x%x%x%x%x%x")
    local visible
    if prefix and #namePartColored >= 12 and namePartColored:sub(-2) == "|r" then
        visible = namePartColored:sub(11, -3)
    else
        prefix = ""
        visible = namePartColored
    end
    if visible == "" then
        cell:SetText((suffixText and suffixText or ""))
        return
    end
    cell:SetText(prefix .. visible .. (prefix ~= "" and "|r" or ""))
    if cell:GetStringWidth() <= maxNameW then
        cell:SetText(prefix .. visible .. (prefix ~= "" and "|r" or "") .. (suffixText or ""))
        return
    end
    for len = #visible - 1, 1, -1 do
        local truncated = visible:sub(1, len) .. "..."
        cell:SetText(prefix .. truncated .. (prefix ~= "" and "|r" or ""))
        if cell:GetStringWidth() <= maxNameW then
            cell:SetText(prefix .. truncated .. (prefix ~= "" and "|r" or "") .. (suffixText or ""))
            return
        end
    end
    cell:SetText(prefix .. "..." .. (prefix ~= "" and "|r" or "") .. (suffixText or ""))
end

-- Scroll frame (viewport for results; section headers live inside scroll)
local scrollFrame = CreateFrame("ScrollFrame", "AltArmyTBC_SearchScrollFrame", frame)
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
scrollFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 20, -PAD)
scrollFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD)
scrollFrame:EnableMouse(true)

-- Custom vertical scroll bar (same style as Gear tab)
local SCROLL_BAR_WIDTH = 20
local SCROLL_BAR_TOP_INSET = 16
local SCROLL_BAR_BOTTOM_INSET = 16
local SCROLL_BAR_RIGHT_OFFSET = 4
local searchScrollBar = CreateFrame("Slider", "AltArmyTBC_SearchScrollBar", frame)
searchScrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", SCROLL_BAR_RIGHT_OFFSET, -(PAD + SCROLL_BAR_TOP_INSET))
searchScrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", SCROLL_BAR_RIGHT_OFFSET, SCROLL_BAR_BOTTOM_INSET)
searchScrollBar:SetWidth(SCROLL_BAR_WIDTH)
searchScrollBar:SetMinMaxValues(0, 0)
searchScrollBar:SetValueStep(ROW_HEIGHT)
searchScrollBar:SetValue(0)
searchScrollBar:SetOrientation("VERTICAL")
searchScrollBar:EnableMouse(true)
local searchVertThumb = searchScrollBar:CreateTexture(nil, "ARTWORK")
searchVertThumb:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
searchVertThumb:SetVertexColor(0.5, 0.5, 0.6, 1)
searchVertThumb:SetSize(SCROLL_BAR_WIDTH - 4, 24)
searchScrollBar:SetThumbTexture(searchVertThumb)
-- OnValueChanged set below after UpdateVisibleRows is defined

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
local totalColWidth = math.max(getTotalColWidth(), getRecipeColWidth())
local resultsArea = CreateFrame("Frame", nil, scrollFrame)
resultsArea:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
resultsArea:SetWidth(totalColWidth)
resultsArea:SetHeight(ROW_HEIGHT)
scrollFrame:SetScrollChild(resultsArea)
resultsArea:SetScript("OnMouseWheel", OnSearchScrollWheel)

-- Items section header (created once, shown when items have results)
local itemsHeaderRow = CreateFrame("Frame", nil, resultsArea)
itemsHeaderRow:SetHeight(HEADER_HEIGHT)
local ix = 0
for _, colName in ipairs(colOrder) do
    local w = colWidths[colName] or 80
    local label = itemsHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", itemsHeaderRow, "BOTTOMLEFT", ix, 0)
    label:SetWidth(w)
    label:SetJustifyH(colName == "Item" and "LEFT" or "RIGHT")
    label:SetText(colName)
    ix = ix + w
end
-- Recipes section header
local recipesHeaderRow = CreateFrame("Frame", nil, resultsArea)
recipesHeaderRow:SetHeight(HEADER_HEIGHT)
local rx = 0
for _, colName in ipairs(recipeColOrder) do
    local w = recipeColWidths[colName] or 80
    local label = recipesHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", recipesHeaderRow, "BOTTOMLEFT", rx, 0)
    label:SetWidth(w)
    label:SetJustifyH(colName == "Recipe" and "LEFT" or "RIGHT")
    label:SetText(colName)
    rx = rx + w
end

-- Result rows (pool) for items
local resultRows = {}
local itemList = {}
local recipeList = {}
local recipeRows = {}
local itemGroups = {}  -- built in UpdateResults, used by UpdateVisibleRows for overlays
local UpdateVisibleRows  -- forward-declare for scroll bar script

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
        if colName == "Character" then cell:SetWordWrap(false) end
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
        if button ~= "LeftButton" or not IsShiftKeyDown() then return end
        local entry = self.entry
        if not entry then return end
        InsertItemLinkIntoChat(entry.itemLink or entry.itemID)
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
        if colName == "Character" then cell:SetWordWrap(false) end
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
    local itemWithCount = itemText .. " x" .. tostring(count)
    if entry.itemLink and GetItemInfo and GetItemInfo(entry.itemLink) then
        local icon = select(10, GetItemInfo(entry.itemLink)) or "Interface\\Icons\\INV_Misc_QuestionMark"
        row.cells.Item:SetText("|T" .. icon .. ":0|t " .. itemWithCount)
    else
        row.cells.Item:SetText(itemWithCount)
    end
    local locLabel = entry.location == "bank" and "Bank" or "Bags"
    local name = entry.characterName or ""
    local r, g, b = 1, 0.82, 0
    local classFile = entry.classFile
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        r, g, b = c.r, c.g, c.b
    end
    local RF = AltArmy.RealmFilter
    local namePart
    local suffixText = "|cFFFFFFFF (" .. locLabel .. ")|r"
    if showRealmSuffix and RF and RF.formatCharacterDisplayNameColored and RF.formatCharacterDisplayName then
        namePart = RF.formatCharacterDisplayNameColored(
                RF.formatCharacterDisplayName(name, entry.realm, true), nil, false, r, g, b)
    else
        local R, G, B = math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
        namePart = string.format("|cFF%02x%02x%02x%s|r", R, G, B, name)
    end
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
    row.cells.Recipe:SetText(("|T%s:0|t "):format(iconPath) .. recipeName)
    local name = entry.characterName or ""
    local r, g, b = 1, 0.82, 0
    if entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
        local c = RAID_CLASS_COLORS[entry.classFile]
        r, g, b = c.r, c.g, c.b
    end
    local RF = AltArmy.RealmFilter
    local namePart
    if showRealmSuffix and RF and RF.formatCharacterDisplayNameColored and RF.formatCharacterDisplayName then
        namePart = RF.formatCharacterDisplayNameColored(
                RF.formatCharacterDisplayName(name, entry.realm, true), nil, false, r, g, b)
    else
        local R, G, B = math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
        namePart = string.format("|cFF%02x%02x%02x%s|r", R, G, B, name)
    end
    SetCharacterCellTruncated(row.cells.Character, namePart, nil, recipeColWidths.Character or 160)
    row.cells.Skill:SetText(tostring(entry.skillRank or 0))
end

-- Virtualized list: fill only rows in the visible range + buffer. Call after layout and on scroll.
UpdateVisibleRows = function()
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    local nItems = categories.Items and #itemList or 0
    local nRecipes = categories.Recipes and #recipeList or 0
    local RF = AltArmy.RealmFilter
    local combinedForRealms = {}
    for i = 1, nItems do combinedForRealms[#combinedForRealms + 1] = itemList[i] end
    for i = 1, nRecipes do combinedForRealms[#combinedForRealms + 1] = recipeList[i] end
    local showRealmSuffix = (GetSearchSettings().realmFilter == "all")
        and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(combinedForRealms)
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
        local totalColW = colWidths.Total or 70
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
    if nRecipes > 0 then
        local recipesSectionTop = itemsSectionTop + nItems * ROW_HEIGHT + HEADER_HEIGHT + HEADER_ROW_GAP
        if nItems == 0 then
            recipesSectionTop = HEADER_HEIGHT + HEADER_ROW_GAP
        end
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
end

-- Wire scroll to refresh visible rows (must be after UpdateVisibleRows is defined)
searchScrollBar:SetScript("OnValueChanged", function(_, value)
    scrollFrame:SetVerticalScroll(value)
    UpdateVisibleRows()
end)

local function UpdateResults()
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
    else
        recipesHeaderRow:Hide()
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
    UpdateVisibleRows()
end

function frame.DoSearch()
    print("[AltArmy] TabSearch DoSearch called")
    local query = ""
    if searchEdit then
        query = searchEdit:GetText()
    end
    if query and query:match("^%s*$") then query = "" end
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    itemList = (categories.Items and query ~= "") and (SD.SearchWithLocationGroups(query) or {}) or {}
    recipeList = (categories.Recipes and query ~= "") and (SD.SearchRecipes(query) or {}) or {}
    local RF = AltArmy.RealmFilter
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    local s = GetSearchSettings()
    if RF and RF.filterListByRealm then
        itemList = RF.filterListByRealm(itemList, s.realmFilter or "all", currentRealm)
        recipeList = RF.filterListByRealm(recipeList, s.realmFilter or "all", currentRealm)
    end
    UpdateResults()
    if searchScrollBar then searchScrollBar:SetValue(0) end
    scrollFrame:SetVerticalScroll(0)
end

-- Expose for header search box: run search with query directly
function frame.SearchWithQuery(_self, query)
    print("[AltArmy] TabSearch SearchWithQuery called, query='" .. tostring(query) .. "'")
    local q = (query and type(query) == "string") and query:match("^%s*(.-)%s*$") or ""
    frame.lastQuery = q
    local categories = AltArmy.SearchCategories or { Items = true, Recipes = true }
    if q == "" then
        itemList = {}
        recipeList = {}
    else
        itemList = categories.Items and (SD.SearchWithLocationGroups(q) or {}) or {}
        recipeList = categories.Recipes and (SD.SearchRecipes(q) or {}) or {}
    end
    local RF = AltArmy.RealmFilter
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    local s = GetSearchSettings()
    if RF and RF.filterListByRealm then
        itemList = RF.filterListByRealm(itemList, s.realmFilter or "all", currentRealm)
        recipeList = RF.filterListByRealm(recipeList, s.realmFilter or "all", currentRealm)
    end
    UpdateResults()
    if searchScrollBar then searchScrollBar:SetValue(0) end
    scrollFrame:SetVerticalScroll(0)
    if searchEdit and searchEdit.SetText then
        searchEdit:SetText(query or "")
    end
    local ni, nr = #itemList, #recipeList
    print("[AltArmy] TabSearch SearchWithQuery done, items=" .. tostring(ni) .. " recipes=" .. tostring(nr))
end

-- Search settings panel (right 40% when visible); defined after UpdateVisibleRows
local SEARCH_SETTINGS_SPLIT = 0.6
local searchSettingsPanel = CreateFrame("Frame", nil, frame)
local function ApplySearchSettingsPanelLayout()
    local w = frame:GetWidth()
    if w <= 0 then return end
    searchSettingsPanel:ClearAllPoints()
    searchSettingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", w * SEARCH_SETTINGS_SPLIT + PAD, -PAD)
    searchSettingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", w * SEARCH_SETTINGS_SPLIT + PAD, PAD)
    searchSettingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
    searchSettingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
end
ApplySearchSettingsPanelLayout()
searchSettingsPanel:Hide()
local searchPanelBg = searchSettingsPanel:CreateTexture(nil, "BACKGROUND")
searchPanelBg:SetAllPoints(searchSettingsPanel)
searchPanelBg:SetColorTexture(0.18, 0.18, 0.22, 0.98)
local SETTINGS_TITLE_HEIGHT = 26
local searchSettingsTitle = searchSettingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
searchSettingsTitle:SetPoint("TOPLEFT", searchSettingsPanel, "TOPLEFT", 0, 0)
searchSettingsTitle:SetPoint("TOPRIGHT", searchSettingsPanel, "TOPRIGHT", 0, 0)
searchSettingsTitle:SetJustifyH("LEFT")
searchSettingsTitle:SetText("Search Settings")
local SETTINGS_ROW_HEIGHT = 22
local btnSearchRealm = CreateFrame("Button", nil, searchSettingsPanel)
btnSearchRealm:SetPoint("TOPLEFT", searchSettingsPanel, "TOPLEFT", 0, -SETTINGS_TITLE_HEIGHT)
btnSearchRealm:SetPoint("TOPRIGHT", searchSettingsPanel, "TOPRIGHT", 0, 0)
btnSearchRealm:SetHeight(SETTINGS_ROW_HEIGHT)
local btnSearchRealmBg = btnSearchRealm:CreateTexture(nil, "BACKGROUND")
btnSearchRealmBg:SetAllPoints(btnSearchRealm)
btnSearchRealmBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
local btnSearchRealmText = btnSearchRealm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btnSearchRealmText:SetPoint("LEFT", btnSearchRealm, "LEFT", 4, 0)
btnSearchRealmText:SetPoint("RIGHT", btnSearchRealm, "RIGHT", -4, 0)
btnSearchRealmText:SetJustifyH("LEFT")
local searchRealmDropdown = CreateFrame("Frame", nil, searchSettingsPanel)
searchRealmDropdown:SetPoint("TOPLEFT", btnSearchRealm, "BOTTOMLEFT", 0, -2)
searchRealmDropdown:SetPoint("TOPRIGHT", btnSearchRealm, "BOTTOMRIGHT", 0, 0)
searchRealmDropdown:SetHeight(#REALM_FILTER_OPTIONS * SETTINGS_ROW_HEIGHT + 4)
searchRealmDropdown:SetFrameLevel(searchSettingsPanel:GetFrameLevel() + 100)
searchRealmDropdown:Hide()
local searchRealmDropdownBg = searchRealmDropdown:CreateTexture(nil, "BACKGROUND")
searchRealmDropdownBg:SetAllPoints(searchRealmDropdown)
searchRealmDropdownBg:SetColorTexture(0.15, 0.15, 0.18, 0.98)
for idx, opt in ipairs(REALM_FILTER_OPTIONS) do
    local b = CreateFrame("Button", nil, searchRealmDropdown)
    b:SetPoint("TOPLEFT", searchRealmDropdown, "TOPLEFT", 2, -2 - (idx - 1) * SETTINGS_ROW_HEIGHT)
    b:SetPoint("LEFT", searchRealmDropdown, "LEFT", 2, 0)
    b:SetPoint("RIGHT", searchRealmDropdown, "RIGHT", -2, 0)
    b:SetHeight(SETTINGS_ROW_HEIGHT - 2)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "LEFT", 4, 0)
    t:SetText(REALM_FILTER_LABELS[opt] or opt)
    b.option = opt
    b:SetScript("OnClick", function()
        GetSearchSettings().realmFilter = opt
        searchRealmDropdown:Hide()
        btnSearchRealmText:SetText(REALM_FILTER_LABELS[opt] or opt)
        if frame.lastQuery and frame.lastQuery ~= "" and frame.SearchWithQuery then
            frame:SearchWithQuery(frame.lastQuery)
        end
        UpdateVisibleRows()
    end)
end
btnSearchRealm:SetScript("OnClick", function()
    searchRealmDropdown:SetShown(not searchRealmDropdown:IsShown())
end)
searchSettingsPanel:SetScript("OnHide", function()
    searchRealmDropdown:Hide()
end)

function frame:IsSearchSettingsShown()
    return searchSettingsPanel and searchSettingsPanel:IsShown()
end

function frame:ToggleSearchSettings(_self)
    local showSettings = not searchSettingsPanel:IsShown()
    searchSettingsPanel:SetShown(showSettings)
    if showSettings then
        ApplySearchSettingsPanelLayout()
        btnSearchRealmText:SetText(REALM_FILTER_LABELS[GetSearchSettings().realmFilter] or "All Characters")
    end
    local panelLeftX = -PAD - SCROLL_BAR_RIGHT_OFFSET - 4
    if showSettings then
        scrollFrame:SetPoint("BOTTOMRIGHT", searchSettingsPanel, "BOTTOMLEFT", panelLeftX, PAD)
        searchScrollBar:SetPoint("TOPRIGHT", searchSettingsPanel, "TOPRIGHT", panelLeftX, -(PAD + SCROLL_BAR_TOP_INSET))
        searchScrollBar:SetPoint("BOTTOMRIGHT", searchSettingsPanel, "BOTTOMRIGHT", panelLeftX, SCROLL_BAR_BOTTOM_INSET)
    else
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD)
        searchScrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", SCROLL_BAR_RIGHT_OFFSET, -(PAD + SCROLL_BAR_TOP_INSET))
        searchScrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", SCROLL_BAR_RIGHT_OFFSET, SCROLL_BAR_BOTTOM_INSET)
    end
    if scrollFrame.UpdateScrollChildRect then scrollFrame:UpdateScrollChildRect() end
    UpdateVisibleRows()
end

frame:SetScript("OnSizeChanged", function()
    if searchSettingsPanel and searchSettingsPanel:IsShown() then
        ApplySearchSettingsPanelLayout()
        local panelLeftX = -PAD - SCROLL_BAR_RIGHT_OFFSET - 4
        scrollFrame:SetPoint("BOTTOMRIGHT", searchSettingsPanel, "BOTTOMLEFT", panelLeftX, PAD)
        searchScrollBar:SetPoint("TOPRIGHT", searchSettingsPanel, "TOPRIGHT", panelLeftX, -(PAD + SCROLL_BAR_TOP_INSET))
        searchScrollBar:SetPoint("BOTTOMRIGHT", searchSettingsPanel, "BOTTOMRIGHT", panelLeftX, SCROLL_BAR_BOTTOM_INSET)
    end
end)

-- Initial empty state
UpdateResults()

-- When tab is shown, refresh scroll child rect (viewport may have been zero when hidden)
frame:SetScript("OnShow", function()
    if scrollFrame and scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
end)
