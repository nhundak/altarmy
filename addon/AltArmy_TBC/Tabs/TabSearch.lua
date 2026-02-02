-- AltArmy TBC — Search tab: item search across characters (bags + bank).

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
if not frame then return end

local PAD = 4
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 20
local NUM_ROWS = 14
local SEARCH_BAR_HEIGHT = 24

local SD = AltArmy.SearchData
if not SD or not SD.SearchWithLocationGroups then return end

-- Search bar: edit box only (Enter runs search)
local searchBar = CreateFrame("Frame", nil, frame)
searchBar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
searchBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
searchBar:SetHeight(SEARCH_BAR_HEIGHT)

local searchEdit = CreateFrame("EditBox", "AltArmyTBC_SearchEditBox", searchBar)
searchEdit:SetPoint("LEFT", searchBar, "LEFT", 0, 0)
searchEdit:SetPoint("RIGHT", searchBar, "RIGHT", 0, 0)
searchEdit:SetHeight(20)
searchEdit:SetAutoFocus(false)
searchEdit:SetFontObject("GameFontHighlight")
if searchEdit.SetTextInsets then
    searchEdit:SetTextInsets(4, 4, 0, 0)
end
searchEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
    if frame.DoSearch then frame:DoSearch() end
end)
searchEdit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

-- Placeholder for edit box (TBC may not have SetPlaceholderText; skip if missing)
if searchEdit.SetPlaceholderText then
    searchEdit:SetPlaceholderText("Item name or ID")
end

-- Header row
local headerRow = CreateFrame("Frame", nil, frame)
headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - SEARCH_BAR_HEIGHT - 4)
headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 20, -PAD - SEARCH_BAR_HEIGHT - 4)
headerRow:SetHeight(HEADER_HEIGHT)

local colWidths = { Item = 180, Character = 100, Realm = 100, Count = 50, Source = 60 }
local colOrder = { "Item", "Character", "Realm", "Count", "Source" }
local x = 0
for _, colName in ipairs(colOrder) do
    local w = colWidths[colName] or 80
    local label = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", headerRow, "LEFT", x, 0)
    label:SetWidth(w)
    label:SetJustifyH(colName == "Item" and "LEFT" or "RIGHT")
    label:SetText(colName)
    x = x + w
end

-- Results area (simple frame; rows are direct children so they're always laid out)
local resultsArea = CreateFrame("Frame", nil, frame)
resultsArea:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - SEARCH_BAR_HEIGHT - 4 - HEADER_HEIGHT)
resultsArea:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
resultsArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD)

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
            row:SetPoint("TOPLEFT", resultsArea, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", resultsArea, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
            row.cells = {}
            local cx = 0
            for _, colName in ipairs(colOrder) do
                local w = colWidths[colName] or 80
                local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                cell:SetPoint("LEFT", row, "LEFT", cx, 0)
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
            row:Show()
            row.entry = entry
            local itemText = (entry.itemName and entry.itemName ~= "") and entry.itemName or ("Item " .. (entry.itemID or ""))
            if entry.itemLink and GetItemInfo and GetItemInfo(entry.itemLink) then
                row.cells.Item:SetText("|T" .. (select(10, GetItemInfo(entry.itemLink)) or "Interface\\Icons\\INV_Misc_QuestionMark") .. ":0|t " .. itemText)
            else
                row.cells.Item:SetText(itemText)
            end
            row.cells.Character:SetText(entry.characterName or "")
            row.cells.Realm:SetText(entry.realm or "")
            row.cells.Count:SetText(tostring(entry.count or 1))
            row.cells.Source:SetText(entry.location == "bank" and "Bank" or "bags")
        else
            row:Hide()
            row.entry = nil
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
