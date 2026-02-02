-- AltArmy TBC — Summary tab: character list (Altoholic-style fixed row pool + Update(offset))

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Summary
if not frame then return end

local ROW_HEIGHT = 18
local NUM_ROWS = 14
local HEADER_HEIGHT = 20
local PAD = 4

-- Column definitions (Name, Realm); extend later for Level, Class, etc.
local columns = {
    Name = {
        Width = 250,
        GetText = function(entry) return entry.name or "" end,
        JustifyH = "LEFT",
    },
    Realm = {
        Width = 180,
        GetText = function(entry) return entry.realm or "" end,
        JustifyH = "LEFT",
    },
}
local columnOrder = { "Name", "Realm" }

-- Scroll frame (viewport; scroll child height set in Update)
local scrollFrame = CreateFrame("ScrollFrame", "AltArmyTBC_SummaryScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - HEADER_HEIGHT)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD)

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

-- Header row (fixed above scroll area)
local headerRow = CreateFrame("Frame", nil, frame)
headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 20, -PAD)
headerRow:SetHeight(HEADER_HEIGHT)

local headerFonts = {}
local x = 0
for _, colName in ipairs(columnOrder) do
    local col = columns[colName]
    local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", headerRow, "LEFT", x, 0)
    fs:SetText(colName)
    headerFonts[colName] = fs
    x = x + (col and col.Width or 100)
end

local totalColWidth = 0
for _, colName in ipairs(columnOrder) do
    local col = columns[colName]
    totalColWidth = totalColWidth + (col and col.Width or 100)
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
local function Update(offset)
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
                end
            end
            rowFrame:Show()
        else
            rowFrame:Hide()
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
