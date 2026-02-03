-- AltArmy TBC — Summary tab: character list (Altoholic-style fixed row pool + Update(offset))

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Summary
if not frame then return end

local ROW_HEIGHT = 18
local NUM_ROWS = 14
local HEADER_HEIGHT = 20
local TOTALS_ROW_HEIGHT = 18
local PAD = 4

local SD = AltArmy.SummaryData

local function isCurrentCharacter(entry)
    local currentName = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""
    local currentRealm = GetRealmName and GetRealmName() or ""
    return entry and (entry.name == currentName and entry.realm == currentRealm)
end

-- Column definitions: Name, Level, RestXP, Money, Played, LastOnline
local columns = {
    Name = {
        Width = 100,
        GetText = function(entry) return entry.name or "" end,
        JustifyH = "LEFT",
    },
    Level = {
        Width = 50,
        GetText = function(entry)
            local l = entry.level
            if l == nil then return "" end
            return string.format("%.1f", math.floor((tonumber(l) or 0) * 10) / 10)
        end,
        JustifyH = "RIGHT",
    },
    RestXP = {
        Width = 65,
        headerLabel = "Rest XP",
        GetText = function(entry) return SD and SD.FormatRestXp and SD.FormatRestXp(entry.restXp) or "" end,
        JustifyH = "RIGHT",
    },
    Money = {
        Width = 115,
        GetText = function(entry) return SD and SD.GetMoneyString and SD.GetMoneyString(entry.money) or "" end,
        JustifyH = "RIGHT",
    },
    Played = {
        Width = 100,
        GetText = function(entry) return SD and SD.GetTimeString and SD.GetTimeString(entry.played) or "" end,
        JustifyH = "RIGHT",
    },
    LastOnline = {
        Width = 85,
        headerLabel = "Last Online",
        GetText = function(entry)
            return SD and SD.FormatLastOnline and SD.FormatLastOnline(entry.lastOnline, isCurrentCharacter(entry)) or ""
        end,
        JustifyH = "RIGHT",
    },
}
local columnOrder = { "Name", "Level", "RestXP", "Money", "Played", "LastOnline" }

-- Column display name -> sort key for Characters:Sort()
local columnToSortKey = {
    Name = "name",
    Level = "level",
    RestXP = "restXp",
    Money = "money",
    Played = "played",
    LastOnline = "lastOnline",
}

local currentSortKey = "name"
local sortAscending = true

local Update -- forward-declare so header OnClick closure can call it

-- Scroll frame (viewport; scroll child height set in Update; bottom inset for totals row)
local scrollFrame = CreateFrame("ScrollFrame", "AltArmyTBC_SummaryScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - HEADER_HEIGHT)
scrollFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD + TOTALS_ROW_HEIGHT)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD + TOTALS_ROW_HEIGHT)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
scrollChild:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, 0)
scrollFrame:SetScrollChild(scrollChild)

-- Resolve scroll bar (UIPanelScrollFrameTemplate uses $parentScrollBar)
local scrollBar
local function GetScrollBar()
    if scrollBar then return scrollBar end
    scrollBar = scrollFrame.ScrollBar or (scrollFrame:GetName() and _G[scrollFrame:GetName() .. "ScrollBar"])
    return scrollBar
end

-- Header row (fixed above scroll area; each column is a clickable button)
local headerRow = CreateFrame("Frame", nil, frame)
headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 20, -PAD)
headerRow:SetHeight(HEADER_HEIGHT)
headerRow:SetFrameLevel(frame:GetFrameLevel() + 10)

local headerButtons = {}
local function UpdateHeaderSortIndicators()
    for _, cn in ipairs(columnOrder) do
        local b = headerButtons[cn]
        if b and b.label then
            local label = (columns[cn] and columns[cn].headerLabel) or cn
            if columnToSortKey[cn] == currentSortKey then
                label = label .. (sortAscending and " ^" or " v")
            end
            b.label:SetText(label)
        end
    end
end

local x = 0
for _, colName in ipairs(columnOrder) do
    local col = columns[colName]
    local w = col and col.Width or 100
    local cn = colName
    local btn = CreateFrame("Button", nil, headerRow)
    btn:SetPoint("LEFT", headerRow, "LEFT", x, 0)
    btn:SetSize(w, HEADER_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function()
        local sortKey = columnToSortKey[cn]
        if sortKey == currentSortKey then
            sortAscending = not sortAscending
        else
            currentSortKey = sortKey
            sortAscending = true
        end
        if AltArmy.Characters and AltArmy.Characters.Sort then
            AltArmy.Characters:Sort(sortAscending, currentSortKey)
        end
        local sb = GetScrollBar()
        local scrollValue = sb and sb:GetValue() or 0
        Update(math.floor(scrollValue / ROW_HEIGHT))
        UpdateHeaderSortIndicators()
    end)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", btn, "LEFT", 0, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    label:SetHeight(HEADER_HEIGHT)
    label:SetJustifyH(col and col.JustifyH or "LEFT")
    label:SetText(col and col.headerLabel or colName)
    btn.label = label
    headerButtons[colName] = btn
    x = x + w
end

local totalColWidth = 0
for _, colName in ipairs(columnOrder) do
    local col = columns[colName]
    totalColWidth = totalColWidth + (col and col.Width or 100)
end

-- Totals row (fixed at bottom of frame)
local totalsRow = CreateFrame("Frame", nil, frame)
totalsRow:SetHeight(TOTALS_ROW_HEIGHT)
totalsRow:SetWidth(totalColWidth)
totalsRow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
totalsRow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD)
totalsRow.cells = {}
local cellX = 0
for _, colName in ipairs(columnOrder) do
    local col = columns[colName]
    local w = col and col.Width or 100
    local cell = totalsRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell:SetPoint("LEFT", totalsRow, "LEFT", cellX, 0)
    cell:SetWidth(w)
    cell:SetJustifyH(col and col.JustifyH or "LEFT")
    totalsRow.cells[colName] = cell
    cellX = cellX + w
end

-- Fixed pool of row buttons (children of frame, stacked; same area as scroll viewport)
local rowPool = {}
local prevRow = nil
for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetWidth(totalColWidth)
    if i == 1 then
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - HEADER_HEIGHT)
    else
        row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, 0)
    end
    row.cells = {}
    local cellX = 0
    for _, colName in ipairs(columnOrder) do
        local col = columns[colName]
        local w = col and col.Width or 100
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetPoint("LEFT", row, "LEFT", cellX, 0)
        cell:SetWidth(w)
        cell:SetJustifyH(col and col.JustifyH or "LEFT")
        row.cells[colName] = cell
        cellX = cellX + w
    end
    rowPool[i] = row
    prevRow = row
end

local function GetRow(index)
    return rowPool[index]
end

--- Update visible rows from the character list using scroll offset (row index).
--- @param offset number 0-based index of first visible row (from scroll position).
Update = function(offset)
    offset = offset or 0
    local list = AltArmy.Characters and AltArmy.Characters.GetList and AltArmy.Characters:GetList() or {}
    local numItems = #list

    -- Set scroll child height so scroll bar range is correct
    local scrollChildHeight = numItems * ROW_HEIGHT
    scrollChild:SetHeight(math.max(scrollChildHeight, scrollFrame:GetHeight()))
    scrollChild:Show()

    local sb = GetScrollBar()
    if sb then
        local maxScroll = math.max(0, scrollChildHeight - scrollFrame:GetHeight())
        sb:SetMinMaxValues(0, maxScroll)
        sb:SetValueStep(ROW_HEIGHT)
        sb:SetStepsPerPage(NUM_ROWS - 1)
    end

    for i = 1, NUM_ROWS do
        local rowFrame = GetRow(i)
        local j = offset + i
        if j <= numItems then
            local entry = list[j]
            for _, colName in ipairs(columnOrder) do
                local col = columns[colName]
                local cell = rowFrame.cells[colName]
                if cell and col and col.GetText then
                    cell:SetText(col.GetText(entry))
                    if colName == "Name" then
                        local classFile = entry.classFile
                        if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
                            local c = RAID_CLASS_COLORS[classFile]
                            cell:SetTextColor(c.r, c.g, c.b, 1)
                        else
                            cell:SetTextColor(1, 0.82, 0, 1)
                        end
                    end
                end
            end
            rowFrame:Show()
        else
            rowFrame:Hide()
        end
    end

    -- Totals row: Level, Money, Played only
    local totalLevel, totalMoney, totalPlayed = 0, 0, 0
    for _, entry in ipairs(list) do
        totalLevel = totalLevel + (tonumber(entry.level) or 0)
        totalMoney = totalMoney + (tonumber(entry.money) or 0)
        totalPlayed = totalPlayed + (tonumber(entry.played) or 0)
    end
    for _, colName in ipairs(columnOrder) do
        local cell = totalsRow.cells[colName]
        if cell then
            if colName == "Level" then
                cell:SetText(string.format("%.1f", math.floor(totalLevel * 10) / 10))
            elseif colName == "Money" then
                cell:SetText(SD and SD.GetMoneyString and SD.GetMoneyString(totalMoney) or "")
            elseif colName == "Played" then
                cell:SetText(SD and SD.GetTimeString and SD.GetTimeString(totalPlayed) or "")
            else
                cell:SetText("")
            end
        end
    end

    if AltArmy.DebugLog then
        AltArmy.DebugLog("Summary Update: " .. numItems .. " item(s), offset=" .. offset)
    end
end

-- When scroll bar moves, recompute offset (row index) and refresh rows
scrollFrame:SetScript("OnVerticalScroll", function(self, scrollOffset)
    local offsetIndex = math.floor((scrollOffset or 0) / ROW_HEIGHT)
    Update(offsetIndex)
end)

-- Run Update when Summary tab is shown (invalidate so list is fresh)
frame:SetScript("OnShow", function()
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if AltArmy.Characters and AltArmy.Characters.Sort then
        AltArmy.Characters:Sort(sortAscending, currentSortKey)
    end
    UpdateHeaderSortIndicators()
    local sb = GetScrollBar()
    local scrollValue = sb and sb:GetValue() or 0
    local offsetIndex = math.floor(scrollValue / ROW_HEIGHT)
    Update(offsetIndex)
end)

-- Thin wrapper for external refresh (e.g. minimap, main frame OnShow)
function AltArmy.RefreshSummary()
    if not frame or not frame:IsShown() then return end
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if AltArmy.Characters and AltArmy.Characters.Sort then
        AltArmy.Characters:Sort(sortAscending, currentSortKey)
    end
    UpdateHeaderSortIndicators()
    local sb = GetScrollBar()
    local scrollValue = sb and sb:GetValue() or 0
    Update(math.floor(scrollValue / ROW_HEIGHT))
end

if AltArmy.MainFrame then
    local oldOnShow = AltArmy.MainFrame:GetScript("OnShow")
    AltArmy.MainFrame:SetScript("OnShow", function()
        if oldOnShow then oldOnShow() end
        if AltArmy.RefreshSummary then AltArmy.RefreshSummary() end
    end)
end

-- Optional: run once when player is known so list is non-empty on first open
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        if frame:IsShown() then
            Update(0)
        end
    end
end)
