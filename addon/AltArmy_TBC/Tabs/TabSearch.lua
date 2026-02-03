-- AltArmy TBC — Search tab: item search across characters (bags + bank).

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
if not frame then return end

local PAD = 4
local ROW_HEIGHT = 81  -- 50% taller than 54
local ROW_SPACING = 18
local HEADER_HEIGHT = 18  -- match ROW_SPACING for consistent gap below headers
local NUM_ROWS = 14

local SD = AltArmy.SearchData
if not SD or not SD.SearchWithLocationGroups then return end

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

local colWidths = { Item = 280, Source = 160 }
local colOrder = { "Item", "Source" }
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

-- Scroll frame (viewport for results; gap below headers = ROW_SPACING)
local scrollFrame = CreateFrame("ScrollFrame", "AltArmyTBC_SearchScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -ROW_SPACING)
scrollFrame:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -ROW_SPACING)
scrollFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD)

-- Results area (scroll child; width/height set so scroll frame can size viewport)
local totalColWidth = (colWidths.Item or 280) + (colWidths.Source or 160)
local resultsArea = CreateFrame("Frame", nil, scrollFrame)
resultsArea:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
resultsArea:SetWidth(totalColWidth)
resultsArea:SetHeight(ROW_HEIGHT)  -- non-zero initial so scroll child is valid
scrollFrame:SetScrollChild(resultsArea)

-- Result rows (pool)
local resultRows = {}
local resultList = {}
local function UpdateResults()
    local n = #resultList
    local needRows = math.max(NUM_ROWS, n)
    for i, row in ipairs(resultRows) do
        row:Hide()
        row.entry = nil
    end
    for i = 1, needRows do
        if not resultRows[i] then
            local row = CreateFrame("Frame", nil, resultsArea)
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, -(i - 1) * ROW_SPACING)
            row:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, -(i - 1) * ROW_SPACING)
            row:SetPoint("BOTTOMLEFT", resultsArea, "TOPLEFT", 0, -(i - 1) * ROW_SPACING - ROW_HEIGHT)
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
            resultRows[i] = row
        end
        local entry = resultList[i]
        local row = resultRows[i]
        if entry then
            row:SetHeight(ROW_HEIGHT)
            row:Show()
            row.entry = entry
            local count = entry.count or 1
            local itemText = (entry.itemName and entry.itemName ~= "") and entry.itemName or ("Item " .. (entry.itemID or ""))
            local itemWithCount = itemText .. " x" .. tostring(count)
            if entry.itemLink and GetItemInfo and GetItemInfo(entry.itemLink) then
                row.cells.Item:SetText("|T" .. (select(10, GetItemInfo(entry.itemLink)) or "Interface\\Icons\\INV_Misc_QuestionMark") .. ":0|t " .. itemWithCount)
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
        else
            row:Hide()
            row.entry = nil
        end
    end
    -- Scroll child height so scroll bar range is correct
    local contentHeight = (needRows >= 1) and ((needRows - 1) * ROW_SPACING + ROW_HEIGHT) or ROW_HEIGHT
    resultsArea:SetHeight(contentHeight)
    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
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
    scrollFrame:SetVerticalScroll(0)
end

-- Expose for header search box: switch to Search tab and run search with query.
function frame.SearchWithQuery(self, query)
    if searchEdit and searchEdit.SetText then
        searchEdit:SetText(query or "")
    end
    frame:DoSearch()
end

-- Initial empty state
UpdateResults()

-- When tab is shown, refresh scroll child rect (viewport may have been zero when hidden)
frame:SetScript("OnShow", function()
    if scrollFrame and scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
end)
