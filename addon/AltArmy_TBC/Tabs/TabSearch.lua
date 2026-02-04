-- AltArmy TBC — Search tab: item search across characters (bags + bank).

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
if not frame then return end

local PAD = 4
local ROW_HEIGHT = 18
local ROW_SPACING = 18
-- Right-side (Total column) icon size; match left-side row icon (WoW :0 default ~14)
local OVERLAY_ICON_SIZE = 14
local HEADER_HEIGHT = 18  -- match ROW_SPACING for consistent gap below headers
local NUM_ROWS = 14

local SD = AltArmy.SearchData
if not SD or not SD.SearchWithLocationGroups then return end

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

-- Header row
local headerRow = CreateFrame("Frame", nil, frame)
headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 20, -PAD)
headerRow:SetHeight(HEADER_HEIGHT)

local colWidths = { Item = 330, Source = 160, Total = 70 }  -- total 560
local colOrder = { "Item", "Source", "Total" }
local x = 0
for _, colName in ipairs(colOrder) do
    local w = colWidths[colName] or 80
    local label = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", headerRow, "BOTTOMLEFT", x, 0)
    label:SetWidth(w)
    label:SetJustifyH(colName == "Item" and "LEFT" or "RIGHT")
    label:SetText(colName)
    x = x + w
end

-- Scroll frame (viewport for results; no template — custom scroll bar like Gear tab)
local scrollFrame = CreateFrame("ScrollFrame", "AltArmyTBC_SearchScrollFrame", frame)
scrollFrame:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -ROW_SPACING)
scrollFrame:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -ROW_SPACING)
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
searchScrollBar:SetScript("OnValueChanged", function(_, value)
    scrollFrame:SetVerticalScroll(value)
end)

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

-- Results area (scroll child; width/height set so scroll frame can size viewport)
local function getTotalColWidth()
    local w = 0
    for _, colName in ipairs(colOrder) do w = w + (colWidths[colName] or 80) end
    return w
end
local totalColWidth = getTotalColWidth()
local resultsArea = CreateFrame("Frame", nil, scrollFrame)
resultsArea:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
resultsArea:SetWidth(totalColWidth)
resultsArea:SetHeight(ROW_HEIGHT)  -- non-zero initial so scroll child is valid
scrollFrame:SetScrollChild(resultsArea)
resultsArea:SetScript("OnMouseWheel", OnSearchScrollWheel)

-- Result rows (pool)
local resultRows = {}
local resultList = {}

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

local function UpdateResults()
    local n = #resultList
    local needRows = math.max(NUM_ROWS, n)

    -- Group consecutive rows by item (itemID + itemName)
    local groups = {}
    local prevKey = nil
    for i = 1, n do
        local entry = resultList[i]
        local key = (entry.itemID or 0) .. "\t" .. (entry.itemName or "")
        if i == 1 or key ~= prevKey then
            table.insert(groups, { start = i, count = 1, total = entry.count or 1 })
            prevKey = key
        else
            local g = groups[#groups]
            g.count = g.count + 1
            g.total = g.total + (entry.count or 1)
            prevKey = key
        end
    end

    for _, row in ipairs(resultRows) do
        row:Hide()
        row.entry = nil
    end
    for i = 1, needRows do
        if not resultRows[i] then
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
            resultRows[i] = row
        end
        local entry = resultList[i]
        local row = resultRows[i]
        -- Position extra rows (beyond n) on top of last row so scroll bounds = content height
        local rowY = (i <= n) and (-(i - 1) * ROW_HEIGHT) or (-(n - 1) * ROW_HEIGHT)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, rowY)
        row:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, rowY)
        row:SetPoint("BOTTOMLEFT", resultsArea, "TOPLEFT", 0, rowY - ROW_HEIGHT)
        if entry then
            row:SetHeight(ROW_HEIGHT)
            row:Show()
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
            local r, g, b = 1, 0.82, 0  -- gold fallback
            local classFile = entry.classFile
            if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
                local c = RAID_CLASS_COLORS[classFile]
                r, g, b = c.r, c.g, c.b
            end
            local R, G, B = math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
            row.cells.Source:SetText(string.format("|cFF%02x%02x%02x%s|r|cFFFFFFFF (%s)|r", R, G, B, name, locLabel))
            row.cells.Total:SetText("")  -- total shown in group overlay
        else
            row:Hide()
            row.entry = nil
        end
    end

    -- Total column: overlay per group; total centered vertically in the group
    local totalColX = (colWidths.Item or 280) + (colWidths.Source or 160)
    local totalColW = colWidths.Total or 70
    for idx, group in ipairs(groups) do
        local overlay = getGroupOverlay(idx)
        local startRow = group.start
        local groupSize = group.count
        local firstRowFrame = resultRows[startRow]
        local lastRowFrame = resultRows[startRow + groupSize - 1]
        overlay:ClearAllPoints()
        overlay:SetPoint("TOPLEFT", firstRowFrame, "TOPLEFT", totalColX, 2)
        overlay:SetPoint("BOTTOMLEFT", lastRowFrame, "BOTTOMLEFT", totalColX, 2)
        overlay:SetPoint("TOPRIGHT", firstRowFrame, "TOPLEFT", totalColX + totalColW, 2)
        overlay:SetPoint("BOTTOMRIGHT", lastRowFrame, "BOTTOMLEFT", totalColX + totalColW, 2)
        -- Icon on the right edge, vertically centered
        overlay.icon:ClearAllPoints()
        overlay.icon:SetPoint("CENTER", overlay, "RIGHT", -2 - OVERLAY_ICON_SIZE / 2, 0)
        local firstEntry = resultList[group.start]
        local iconPath = "Interface\\Icons\\INV_Misc_QuestionMark"
        if firstEntry and firstEntry.itemLink and GetItemInfo then
            local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(firstEntry.itemLink)
            if tex then iconPath = tex end
        end
        overlay.icon:SetTexture(iconPath)
        overlay.icon:Show()
        -- Total right-aligned, 3px gap before icon; vertically centered
        overlay.total:ClearAllPoints()
        overlay.total:SetPoint("RIGHT", overlay.icon, "LEFT", -3, 0)
        overlay.total:SetPoint("CENTER", overlay, "CENTER", 0, 0)
        overlay.total:SetWidth(math.max(1, totalColW - OVERLAY_ICON_SIZE - 2))
        overlay.total:SetText(tostring(group.total))
        overlay:Show()
    end
    for idx = #groups + 1, #groupOverlayPool do
        if groupOverlayPool[idx] then groupOverlayPool[idx]:Hide() end
    end

    -- Scroll child height = exactly the height of n rows (no extra scroll past last item)
    local contentHeight = (n >= 1) and (n * ROW_HEIGHT) or ROW_HEIGHT
    resultsArea:SetHeight(contentHeight)
    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
    -- Update custom scroll bar range and clamp value
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
end

function frame.DoSearch()
    local query = ""
    if searchEdit then
        query = searchEdit:GetText()
    end
    if query and query:match("^%s*$") then query = "" end
    resultList = SD.SearchWithLocationGroups(query) or {}
    UpdateResults()
    if searchScrollBar then searchScrollBar:SetValue(0) end
    scrollFrame:SetVerticalScroll(0)
end

-- Expose for header search box: run search with query directly
-- (don't rely on edit box; SetText/GetText can be out of sync).
function frame.SearchWithQuery(_self, query)
    local q = (query and type(query) == "string") and query:match("^%s*(.-)%s*$") or ""
    if q == "" then
        resultList = {}
    else
        resultList = SD.SearchWithLocationGroups(q) or {}
    end
    UpdateResults()
    if searchScrollBar then searchScrollBar:SetValue(0) end
    scrollFrame:SetVerticalScroll(0)
    if searchEdit and searchEdit.SetText then
        searchEdit:SetText(query or "")
    end
end

-- Initial empty state
UpdateResults()

-- When tab is shown, refresh scroll child rect (viewport may have been zero when hidden)
frame:SetScript("OnShow", function()
    if scrollFrame and scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
end)
