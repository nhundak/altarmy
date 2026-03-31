-- AltArmy TBC — Reputation tab: factions (rows) × characters (columns)

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Reputation
if not frame then return end

local DS = AltArmy.DataStore
local SD = AltArmy.SummaryData
local PAD = 4
local FACTION_LABEL_WIDTH = 150
local REP_ROW_HEIGHT = 46
local REP_BAR_HEIGHT = 20
local REP_STANDING_ROW_HEIGHT = 12
local REP_STANDING_BAR_GAP = 1
local REP_CELL_CONTENT_SHIFT_DOWN = 5
-- Vertically center standing + gap + bar in the cell (matches faction label centered in the row).
local REP_CELL_CONTENT_TOP_PAD = (REP_ROW_HEIGHT - REP_STANDING_ROW_HEIGHT - REP_STANDING_BAR_GAP - REP_BAR_HEIGHT) / 2
local MISSING_DATA_TEXT_R, MISSING_DATA_TEXT_G, MISSING_DATA_TEXT_B = 0.78, 0.68, 0.4
-- Match TabGear header: name row + message row (Reputation uses only one text line, centered in full height)
local MESSAGE_ROW_HEIGHT = 12
local COLUMN_HEADER_HEIGHT_GEAR = 18
local SCROLL_BAR_WIDTH = 20
local FIXED_HEADER_ROW_HEIGHT = COLUMN_HEADER_HEIGHT_GEAR + MESSAGE_ROW_HEIGHT
local COLUMN_WIDTH = 96
local SCROLL_BAR_TOP_INSET = 16
local SCROLL_BAR_BOTTOM_INSET = 16
local SCROLL_BAR_RIGHT_OFFSET = 4
local HORIZONTAL_SCROLL_BAR_HEIGHT = 20
local MIN_SCROLL_CHILD_WIDTH = 400
local GRID_SPLIT_FRACTION = 0.6

-- Hover: light tint (same texture family as scroll/settings panels); works without SetBackdrop on Buttons.
local SORTABLE_HOVER_BG = "Interface\\Tooltips\\UI-Tooltip-Background"
local SORTABLE_HOVER_TINT = 0.22

local function CreateSortableHoverTint(target, bandHeight)
    local t = target:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(SORTABLE_HOVER_BG)
    if bandHeight then
        t:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        t:SetHeight(bandHeight)
    else
        t:SetAllPoints(true)
    end
    t:SetVertexColor(1, 1, 1, 0)
    target.reputationHoverTint = t
end

local function SortableHoverEnter(target)
    local t = target.reputationHoverTint
    if t then
        t:SetVertexColor(1, 1, 1, SORTABLE_HOVER_TINT)
    end
end

local function SortableHoverLeave(target)
    local t = target.reputationHoverTint
    if t then
        t:SetVertexColor(1, 1, 1, 0)
    end
end

-- Reputation settings (AltArmyTBC_ReputationSettings)
local SORT_OPTIONS = { "Name", "Level", "Avg Item Level", "Time Played" }
local REALM_FILTER_OPTIONS = { "all", "currentRealm" }
local function RealmFilterValid(val)
    for _, o in ipairs(REALM_FILTER_OPTIONS) do
        if o == val then return true end
    end
    return false
end
local function SortOptionValid(val)
    for _, o in ipairs(SORT_OPTIONS) do
        if o == val then return true end
    end
    return false
end

local function GetReputationSettings()
    AltArmyTBC_ReputationSettings = AltArmyTBC_ReputationSettings or {}
    local s = AltArmyTBC_ReputationSettings
    if not s.primarySort or not SortOptionValid(s.primarySort) then s.primarySort = "Time Played" end
    if not s.secondarySort or not SortOptionValid(s.secondarySort) then s.secondarySort = "Name" end
    if s.showSelfFirst == nil then s.showSelfFirst = true end
    if not s.realmFilter or not RealmFilterValid(s.realmFilter) then s.realmFilter = "all" end
    s.characters = s.characters or {}
    return s
end

local function CharKey(name, realm)
    return (realm or "") .. "\\" .. (name or "")
end

local function GetCharSetting(name, realm, key)
    local s = GetReputationSettings()
    local c = s.characters[CharKey(name, realm)]
    if not c then return false end
    return c[key] == true
end

local function SetCharSetting(name, realm, pin, hide)
    local s = GetReputationSettings()
    local key = CharKey(name, realm)
    s.characters[key] = { pin = pin == true, hide = hide == true }
end

local function GetSortValue(entry, sortKey)
    if sortKey == "Name" then return entry.name or "" end
    if sortKey == "Level" then return tonumber(entry.level) or 0 end
    if sortKey == "Avg Item Level" then return tonumber(entry.avgItemLevel) or 0 end
    if sortKey == "Time Played" then return tonumber(entry.played) or 0 end
    return 0
end

local function CompareBySort(entryA, entryB, primary, secondary)
    local va = GetSortValue(entryA, primary)
    local vb = GetSortValue(entryB, primary)
    if primary == "Name" then
        if va ~= vb then return va < vb end
    else
        if va ~= vb then return va > vb end
    end
    va = GetSortValue(entryA, secondary)
    vb = GetSortValue(entryB, secondary)
    if secondary == "Name" then
        return va < vb
    else
        return va > vb
    end
end

-- Session-only: sort columns by reputation with this faction.
-- Same row: high first -> low first -> off; other row: switch to that faction (high first).
local factionSortFactionID = nil
local factionSortHighFirst = true

-- Session-only: sort faction rows by this character's rep (column header click).
-- Same column: high first -> low first -> off; other column: switch (high first).
local columnSortName = nil
local columnSortRealm = nil
local columnSortHighFirst = true

local lastFactionRows = {}

local NO_FACTION_REP = -999999999

-- Faction-column sort: v2 snapshot rows (all table entries) left; any legacy scalar rep right.
local function GetReputationStorageSortGroup(char)
    if not char then return 0 end
    if not DS.HasModuleData or not DS:HasModuleData(char, "reputations") then
        return 0
    end
    local reps = char.Reputations
    if not reps then return 0 end
    for _, v in pairs(reps) do
        if type(v) == "number" then
            return 1
        end
    end
    return 0
end

local function GetReputationStorageSortGroupForEntry(entry)
    if not entry or not DS or not DS.GetCharacter then return 0 end
    return GetReputationStorageSortGroup(DS:GetCharacter(entry.name, entry.realm))
end

local function GetFactionEarnedForEntry(entry, factionID)
    if not entry or not factionID or not DS or not DS.GetCharacter then
        return NO_FACTION_REP
    end
    local char = DS:GetCharacter(entry.name, entry.realm)
    if not char or not DS.HasModuleData or not DS:HasModuleData(char, "reputations") then
        return NO_FACTION_REP
    end
    local reps = char.Reputations
    if not reps then return NO_FACTION_REP end
    local v = reps[factionID]
    if v == nil then return NO_FACTION_REP end
    if type(v) == "table" then
        local e = tonumber(v.e)
        if e == nil then return NO_FACTION_REP end
        return e
    end
    return tonumber(v) or NO_FACTION_REP
end

--- True if this character has discovered rep for the faction (same notion as grid / GetReputationInfo standing).
local function FactionHasDiscoveredRepForCharacter(entry, factionID)
    if not entry or not factionID or not DS or not DS.GetCharacter or not DS.GetReputationInfo then
        return false
    end
    local char = DS:GetCharacter(entry.name, entry.realm)
    if not char then return false end
    local standing = DS:GetReputationInfo(char, factionID)
    return standing ~= nil
end

local function CompareByFactionRep(entryA, entryB, factionID, highFirst, primary, secondary)
    local ga = GetReputationStorageSortGroupForEntry(entryA)
    local gb = GetReputationStorageSortGroupForEntry(entryB)
    if ga ~= gb then
        return ga < gb
    end
    local ea = GetFactionEarnedForEntry(entryA, factionID)
    local eb = GetFactionEarnedForEntry(entryB, factionID)
    if ea ~= eb then
        if highFirst then
            return ea > eb
        else
            return ea < eb
        end
    end
    return CompareBySort(entryA, entryB, primary, secondary)
end

local function GetDisplayList()
    if not AltArmy.Characters or not AltArmy.Characters.GetList then return {} end
    local rawList = AltArmy.Characters:GetList()
    if #rawList == 0 then return rawList end

    local settings = GetReputationSettings()
    local currentName = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""
    local currentRealm = (GetRealmName and GetRealmName()) or ""

    local visible = {}
    for i = 1, #rawList do
        local e = rawList[i]
        if not GetCharSetting(e.name, e.realm, "hide") then
            visible[#visible + 1] = e
        end
    end

    local primary = settings.primarySort or "Time Played"
    local secondary = settings.secondarySort or "Name"
    local showSelfFirst = settings.showSelfFirst ~= false

    local function sortPair(a, b)
        if factionSortFactionID then
            return CompareByFactionRep(a, b, factionSortFactionID, factionSortHighFirst, primary, secondary)
        end
        return CompareBySort(a, b, primary, secondary)
    end

    local list = {}
    if factionSortFactionID then
        -- Faction sort: v2 rep rows left, v1 legacy scalars right; then rep value + tie-breakers
        for i = 1, #visible do
            list[i] = visible[i]
        end
        table.sort(list, sortPair)
    else
        local selfEntry = nil
        local pinned = {}
        local nonPinned = {}
        for i = 1, #visible do
            local e = visible[i]
            local isSelf = (e.name == currentName and e.realm == currentRealm)
            if isSelf then
                selfEntry = e
            elseif GetCharSetting(e.name, e.realm, "pin") then
                pinned[#pinned + 1] = e
            else
                nonPinned[#nonPinned + 1] = e
            end
        end
        table.sort(pinned, sortPair)
        table.sort(nonPinned, sortPair)
        if showSelfFirst and selfEntry then list[#list + 1] = selfEntry end
        for i = 1, #pinned do list[#list + 1] = pinned[i] end
        for i = 1, #nonPinned do list[#list + 1] = nonPinned[i] end
        if not showSelfFirst and selfEntry then list[#list + 1] = selfEntry end
    end

    local RF = AltArmy.RealmFilter
    if RF and RF.filterListByRealm then
        list = RF.filterListByRealm(list, settings.realmFilter or "all", currentRealm)
    end
    return list
end

local function OnReputationHeaderColumnClick(self, button)
    if button ~= "LeftButton" then return end
    local idx = self.reputationHeaderColumnIndex
    if not idx then return end
    local list = GetDisplayList()
    local e = list[idx]
    if not e then return end
    local sn = e.name or ""
    local sr = e.realm or ""
    if columnSortName == sn and columnSortRealm == sr then
        if columnSortHighFirst then
            columnSortHighFirst = false
        else
            columnSortName = nil
            columnSortRealm = nil
        end
    else
        columnSortName = sn
        columnSortRealm = sr
        columnSortHighFirst = true
    end
    if frame and frame.RefreshGrid then frame:RefreshGrid() end
end

local factionFilterEdit

local function FilterReputationFactionRows(rows, filterText)
    local f = AltArmy.ReputationFactionFilter
    if f and f.filterRows then
        return f.filterRows(rows, filterText)
    end
    return rows
end

local function GetDisplayFactionRows()
    local filterText = factionFilterEdit and factionFilterEdit:GetText() or ""
    local base = FilterReputationFactionRows(lastFactionRows, filterText)
    if not base or #base == 0 or not columnSortName then return base end
    local sorted = {}
    for i = 1, #base do
        sorted[i] = base[i]
    end
    local entry = { name = columnSortName, realm = columnSortRealm or "" }
    table.sort(sorted, function(ra, rb)
        if not ra or not rb then return false end
        local discA = FactionHasDiscoveredRepForCharacter(entry, ra.factionID)
        local discB = FactionHasDiscoveredRepForCharacter(entry, rb.factionID)
        if discA ~= discB then
            return discA
        end
        local ea = GetFactionEarnedForEntry(entry, ra.factionID)
        local eb = GetFactionEarnedForEntry(entry, rb.factionID)
        if ea ~= eb then
            if columnSortHighFirst then
                return ea > eb
            else
                return ea < eb
            end
        end
        return (ra.name or "") < (rb.name or "")
    end)
    return sorted
end

local dims = {
    rowHeight = REP_ROW_HEIGHT,
    columnWidth = COLUMN_WIDTH,
    scrollableGridHeight = REP_ROW_HEIGHT + PAD,
}

-- Faction name column offsets each row by (rowHeight - label line height) / 2; grid first row must match.
local REP_FACTION_LABEL_TEXT_HEIGHT = 14
local function GetFirstRowCellVerticalOffset()
    return (dims.rowHeight - REP_FACTION_LABEL_TEXT_HEIGHT) / 2
end

local rightPanel = CreateFrame("Frame", nil, frame)
rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)

local contentArea = CreateFrame("Frame", nil, rightPanel)
contentArea:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, -PAD)
contentArea:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -SCROLL_BAR_WIDTH,
    SCROLL_BAR_BOTTOM_INSET + HORIZONTAL_SCROLL_BAR_HEIGHT)

local verticalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_ReputationVerticalScroll", contentArea)
verticalScroll:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
verticalScroll:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
verticalScroll:EnableMouse(true)

local verticalScrollChild = CreateFrame("Frame", nil, verticalScroll)
verticalScrollChild:SetPoint("TOPLEFT", verticalScroll, "TOPLEFT", 0, 0)
verticalScrollChild:SetHeight(FIXED_HEADER_ROW_HEIGHT + dims.scrollableGridHeight)
verticalScrollChild:SetWidth(MIN_SCROLL_CHILD_WIDTH)
verticalScrollChild:EnableMouse(true)
verticalScroll:SetScrollChild(verticalScrollChild)

local scrollTopSpacer = CreateFrame("Frame", nil, verticalScrollChild)
scrollTopSpacer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, 0)
scrollTopSpacer:SetPoint("TOPRIGHT", verticalScrollChild, "TOPRIGHT", 0, 0)
scrollTopSpacer:SetHeight(FIXED_HEADER_ROW_HEIGHT)

local fixedHeaderRow = CreateFrame("Frame", nil, contentArea)
fixedHeaderRow:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
fixedHeaderRow:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)
fixedHeaderRow:SetHeight(FIXED_HEADER_ROW_HEIGHT)
fixedHeaderRow:SetFrameLevel(contentArea:GetFrameLevel() + 20)
local HEADER_BG_OVERHANG = 6
local HEADER_BG_BOTTOM_INSET = 6
local headerBg = fixedHeaderRow:CreateTexture(nil, "BACKGROUND")
headerBg:SetPoint("BOTTOMLEFT", fixedHeaderRow, "BOTTOMLEFT", 0, HEADER_BG_BOTTOM_INSET)
headerBg:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, HEADER_BG_BOTTOM_INSET)
headerBg:SetPoint("TOPLEFT", fixedHeaderRow, "TOPLEFT", 0, HEADER_BG_OVERHANG)
headerBg:SetPoint("TOPRIGHT", fixedHeaderRow, "TOPRIGHT", 0, HEADER_BG_OVERHANG)
headerBg:SetColorTexture(0.12, 0.12, 0.15, 1)
fixedHeaderRow:EnableMouse(true)

-- Faction name filter (styled like main window header search)
local headerCornerFrame = CreateFrame("Frame", nil, fixedHeaderRow)
headerCornerFrame:SetPoint("TOPLEFT", fixedHeaderRow, "TOPLEFT", 0, 0)
headerCornerFrame:SetSize(FACTION_LABEL_WIDTH, FIXED_HEADER_ROW_HEIGHT)

factionFilterEdit = CreateFrame("EditBox", "AltArmyTBC_ReputationFactionFilterEdit", headerCornerFrame)
factionFilterEdit:SetHeight(20)
local FACTION_FILTER_EDIT_Y = 6 -- nudge up vs visual center (font baseline / header band)
factionFilterEdit:SetPoint("LEFT", headerCornerFrame, "LEFT", 2, FACTION_FILTER_EDIT_Y)
factionFilterEdit:SetPoint("RIGHT", headerCornerFrame, "RIGHT", -2, FACTION_FILTER_EDIT_Y)
factionFilterEdit:SetAutoFocus(false)
factionFilterEdit:SetFontObject("GameFontHighlight")
if factionFilterEdit.SetTextInsets then
    factionFilterEdit:SetTextInsets(4, 4, 0, 0)
end
local filterEditBg = factionFilterEdit:CreateTexture(nil, "BACKGROUND")
filterEditBg:SetAllPoints(factionFilterEdit)
filterEditBg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
local filterEditBorder = factionFilterEdit:CreateTexture(nil, "BORDER")
filterEditBorder:SetPoint("TOPLEFT", factionFilterEdit, "TOPLEFT", -1, 1)
filterEditBorder:SetPoint("BOTTOMRIGHT", factionFilterEdit, "BOTTOMRIGHT", 1, -1)
filterEditBorder:SetColorTexture(0.4, 0.4, 0.4, 1)

local FACTION_FILTER_PLACEHOLDER = "Filter faction"
if factionFilterEdit.SetPlaceholderText then
    factionFilterEdit:SetPlaceholderText(FACTION_FILTER_PLACEHOLDER)
else
    local factionFilterHint = factionFilterEdit:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    factionFilterHint:SetPoint("LEFT", factionFilterEdit, "LEFT", 4, 0)
    factionFilterHint:SetPoint("RIGHT", factionFilterEdit, "RIGHT", -4, 0)
    factionFilterHint:SetJustifyH("LEFT")
    factionFilterHint:SetText(FACTION_FILTER_PLACEHOLDER)
    factionFilterHint:SetTextColor(0.5, 0.5, 0.5, 1)
    factionFilterEdit.factionFilterHint = factionFilterHint
end

local function updateFactionFilterPlaceholderVisibility()
    local hint = factionFilterEdit.factionFilterHint
    if not hint then return end
    local text = factionFilterEdit:GetText()
    local trimmed = text and text:match("^%s*(.-)%s*$") or ""
    local hasFocus = factionFilterEdit:HasFocus()
    if trimmed == "" and not hasFocus then
        hint:Show()
    else
        hint:Hide()
    end
end

factionFilterEdit:SetScript("OnTextChanged", function()
    updateFactionFilterPlaceholderVisibility()
    if frame.RefreshGrid then
        frame:RefreshGrid()
    end
end)
factionFilterEdit:SetScript("OnEditFocusGained", updateFactionFilterPlaceholderVisibility)
factionFilterEdit:SetScript("OnEditFocusLost", updateFactionFilterPlaceholderVisibility)
factionFilterEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
end)
factionFilterEdit:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
end)

local headerHorizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_ReputationHeaderHorizontalScroll", fixedHeaderRow)
headerHorizontalScroll:SetPoint("TOPLEFT", headerCornerFrame, "TOPRIGHT", 0, 0)
headerHorizontalScroll:SetPoint("BOTTOMRIGHT", fixedHeaderRow, "BOTTOMRIGHT", 0, 0)
headerHorizontalScroll:EnableMouse(true)
local headerGridContainer = CreateFrame("Frame", nil, headerHorizontalScroll)
headerGridContainer:SetPoint("TOPLEFT", headerHorizontalScroll, "TOPLEFT", 0, 0)
headerGridContainer:SetHeight(FIXED_HEADER_ROW_HEIGHT)
headerHorizontalScroll:SetScrollChild(headerGridContainer)

local verticalScrollBar = CreateFrame("Slider", "AltArmyTBC_ReputationVerticalScrollBar", rightPanel)
verticalScrollBar:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", SCROLL_BAR_RIGHT_OFFSET + 4,
    -(PAD + SCROLL_BAR_TOP_INSET))
verticalScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", SCROLL_BAR_RIGHT_OFFSET + 4,
    SCROLL_BAR_BOTTOM_INSET)
verticalScrollBar:SetWidth(SCROLL_BAR_WIDTH)
verticalScrollBar:SetMinMaxValues(0, 0)
verticalScrollBar:SetValueStep(dims.rowHeight)
verticalScrollBar:SetValue(0)
verticalScrollBar:SetOrientation("VERTICAL")
verticalScrollBar:EnableMouse(true)
local vertThumb = verticalScrollBar:CreateTexture(nil, "ARTWORK")
vertThumb:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
vertThumb:SetVertexColor(0.5, 0.5, 0.6, 1)
vertThumb:SetSize(SCROLL_BAR_WIDTH - 4, 24)
verticalScrollBar:SetThumbTexture(vertThumb)
verticalScrollBar:SetScript("OnValueChanged", function(_, value)
    verticalScroll:SetVerticalScroll(value)
end)

local function OnReputationScrollWheel(_, delta)
    if not verticalScrollBar then return end
    local minVal, maxVal = verticalScrollBar:GetMinMaxValues()
    local current = verticalScrollBar:GetValue()
    local newVal = current - delta * dims.rowHeight * 2
    newVal = math.max(minVal, math.min(maxVal, newVal))
    verticalScrollBar:SetValue(newVal)
    verticalScroll:SetVerticalScroll(newVal)
end
verticalScroll:SetScript("OnMouseWheel", OnReputationScrollWheel)
verticalScrollChild:SetScript("OnMouseWheel", OnReputationScrollWheel)

local factionHeaderContainer = CreateFrame("Frame", nil, verticalScrollChild)
factionHeaderContainer:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", 0, -FIXED_HEADER_ROW_HEIGHT)
factionHeaderContainer:SetPoint("BOTTOMLEFT", verticalScrollChild, "BOTTOMLEFT", 0, 0)
factionHeaderContainer:SetWidth(FACTION_LABEL_WIDTH)

local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_ReputationHorizontalScroll", verticalScrollChild)
horizontalScroll:SetPoint("TOPLEFT", verticalScrollChild, "TOPLEFT", FACTION_LABEL_WIDTH, -FIXED_HEADER_ROW_HEIGHT)
horizontalScroll:SetPoint("BOTTOMRIGHT", verticalScrollChild, "BOTTOMRIGHT", 0, 0)
horizontalScroll:EnableMouse(true)

local gridContainer = CreateFrame("Frame", nil, horizontalScroll)
gridContainer:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
gridContainer:SetHeight(dims.scrollableGridHeight)
horizontalScroll:SetScrollChild(gridContainer)

local function TruncateName(fontString, fullName, maxWidth)
    if not fullName or fullName == "" then
        fontString:SetText("?")
        return "?"
    end
    fontString:SetText(fullName)
    if fontString:GetStringWidth() <= maxWidth then
        return fullName
    end
    for len = #fullName - 1, 1, -1 do
        local truncated = fullName:sub(1, len) .. "..."
        fontString:SetText(truncated)
        if fontString:GetStringWidth() <= maxWidth then
            return truncated
        end
    end
    fontString:SetText("...")
    return "..."
end

-- Header column pool: same layout as TabGear (name row + message row; Reputation leaves message empty)
local headerColumnPool = {}
local function GetHeaderColumnFrame(index)
    if not headerColumnPool[index] then
        local col = CreateFrame("Button", nil, headerGridContainer)
        col:SetSize(dims.columnWidth, FIXED_HEADER_ROW_HEIGHT)
        CreateSortableHoverTint(col, COLUMN_HEADER_HEIGHT_GEAR)
        if col.RegisterForClicks then
            col:RegisterForClicks("LeftButtonUp")
        end
        col.header = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        col.header:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
        col.header:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, 0)
        col.header:SetHeight(COLUMN_HEADER_HEIGHT_GEAR)
        col.header:SetJustifyH("CENTER")
        col.header:SetJustifyV("MIDDLE")
        col.header:SetWordWrap(false)
        col.message = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        col.message:SetPoint("TOP", col.header, "BOTTOM", 0, 0)
        col.message:SetPoint("LEFT", col, "LEFT", 0, 0)
        col.message:SetPoint("RIGHT", col, "RIGHT", 0, 0)
        col.message:SetHeight(MESSAGE_ROW_HEIGHT)
        col.message:SetJustifyH("CENTER")
        col.message:SetWordWrap(true)
        col.message:SetNonSpaceWrap(true)
        col:SetScript("OnEnter", function(self)
            SortableHoverEnter(self)
            if self.tooltipText and self.tooltipText ~= "" and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.tooltipText, self.classR or 1, self.classG or 0.82, self.classB or 0)
                GameTooltip:Show()
            end
        end)
        col:SetScript("OnLeave", function(self)
            SortableHoverLeave(self)
            if GameTooltip then GameTooltip:Hide() end
        end)
        col:SetScript("OnMouseUp", OnReputationHeaderColumnClick)
        headerColumnPool[index] = col
    end
    return headerColumnPool[index]
end

local function CreateRepCell(col, rowH, colW)
    local cell = CreateFrame("Frame", nil, col)
    local innerW = colW - 8
    cell:SetSize(innerW, rowH)
    cell.standing = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local topPad = math.floor(REP_CELL_CONTENT_TOP_PAD + 0.5) + REP_CELL_CONTENT_SHIFT_DOWN
    cell.standing:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -topPad)
    cell.standing:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -2, -topPad)
    cell.standing:SetHeight(REP_STANDING_ROW_HEIGHT)
    cell.standing:SetJustifyH("CENTER")
    cell.standing:SetWordWrap(false)
    cell.barBg = cell:CreateTexture(nil, "BACKGROUND")
    cell.barBg:SetColorTexture(0.12, 0.12, 0.12, 1)
    cell.barBg:SetPoint("TOPLEFT", cell.standing, "BOTTOMLEFT", 0, -REP_STANDING_BAR_GAP)
    cell.barBg:SetPoint("TOPRIGHT", cell.standing, "BOTTOMRIGHT", 0, -REP_STANDING_BAR_GAP)
    cell.barBg:SetHeight(REP_BAR_HEIGHT)
    cell.barFill = cell:CreateTexture(nil, "ARTWORK")
    cell.barFill:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    cell.barFill:SetPoint("BOTTOMLEFT", cell.barBg, "BOTTOMLEFT", 0, 0)
    cell.barFill:SetHeight(REP_BAR_HEIGHT)
    -- Progress numbers sit on top of the bar (same band as the fill).
    cell.progress = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.progress:SetPoint("TOPLEFT", cell.barBg, "TOPLEFT", 2, 0)
    cell.progress:SetPoint("BOTTOMRIGHT", cell.barBg, "BOTTOMRIGHT", -2, 0)
    cell.progress:SetJustifyH("CENTER")
    cell.progress:SetJustifyV("MIDDLE")
    cell.progress:SetWordWrap(false)
    cell:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local e = self.missingDataTooltipEntry
        if e and SD and SD.PresentMissingDataTooltip then
            if SD.PresentMissingDataTooltip(self, "ANCHOR_BOTTOMLEFT", e.name, e.realm, e.classFile) then
                return
            end
        end
        if not self.tooltipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.tooltipTitle, 1, 1, 1)
        if self.tooltipLines then
            for _, line in ipairs(self.tooltipLines) do
                if type(line) == "table" and line.text then
                    GameTooltip:AddLine(line.text, line.r or 0.9, line.g or 0.9, line.b or 0.9, line.wrap == true)
                else
                    GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
                end
            end
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return cell
end

local columnPool = {}
local function GetColumnFrame(index)
    if not columnPool[index] then
        local col = CreateFrame("Frame", nil, gridContainer)
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
        col.cells = {}
        columnPool[index] = col
    end
    return columnPool[index]
end

local function EnsureCell(col, rowIndex)
    if not col.cells[rowIndex] then
        col.cells[rowIndex] = CreateRepCell(col, dims.rowHeight, dims.columnWidth)
    end
    return col.cells[rowIndex]
end

local horizontalScrollBar = CreateFrame("Slider", "AltArmyTBC_ReputationHorizontalScrollBar", rightPanel)
horizontalScrollBar:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", PAD, PAD)
horizontalScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -SCROLL_BAR_WIDTH - PAD, PAD)
horizontalScrollBar:SetHeight(HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2)
horizontalScrollBar:SetOrientation("HORIZONTAL")
horizontalScrollBar:SetMinMaxValues(0, 0)
horizontalScrollBar:SetValueStep(1)
horizontalScrollBar:SetValue(0)
horizontalScrollBar:EnableMouse(true)
local lastHorizontalScrollValue = nil
local horizontalBarDragging = false
local horizontalDragStartX = 0
local horizontalDragStartValue = 0
local function ApplyHorizontalScrollValue(value)
    if not horizontalScroll then return end
    lastHorizontalScrollValue = value
    if horizontalScroll.UpdateScrollChildRect then
        horizontalScroll:UpdateScrollChildRect()
    end
    horizontalScroll:SetHorizontalScroll(value)
    if headerHorizontalScroll then
        if headerHorizontalScroll.UpdateScrollChildRect then
            headerHorizontalScroll:UpdateScrollChildRect()
        end
        headerHorizontalScroll:SetHorizontalScroll(value)
    end
end
local function SyncHorizontalScrollPosition()
    if not (horizontalScroll and horizontalScrollBar) then return end
    local value = horizontalScrollBar:GetValue()
    if lastHorizontalScrollValue == value then return end
    ApplyHorizontalScrollValue(value)
end
horizontalScrollBar:SetScript("OnValueChanged", function()
    SyncHorizontalScrollPosition()
end)
horizontalScrollBar:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    horizontalBarDragging = true
    horizontalDragStartX = select(1, GetCursorPosition())
    horizontalDragStartValue = horizontalScrollBar:GetValue()
end)
horizontalScrollBar:SetScript("OnUpdate", function()
    if not frame:IsShown() then return end
    if horizontalBarDragging then
        if not IsMouseButtonDown(1) then
            horizontalBarDragging = false
        else
            local minVal, maxVal = horizontalScrollBar:GetMinMaxValues()
            local barWidth = horizontalScrollBar:GetWidth()
            if barWidth and barWidth > 0 and maxVal > minVal then
                local scale = (horizontalScrollBar.GetEffectiveScale and horizontalScrollBar:GetEffectiveScale())
                    or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
                if scale <= 0 then scale = 1 end
                local cursorX = select(1, GetCursorPosition()) / scale
                local startX = horizontalDragStartX / scale
                local deltaX = cursorX - startX
                local value = horizontalDragStartValue + deltaX * (maxVal - minVal) / barWidth
                value = math.max(minVal, math.min(maxVal, value))
                horizontalScrollBar:SetValue(value)
                ApplyHorizontalScrollValue(value)
            end
        end
    end
end)
if horizontalScrollBar.SetBackdrop then
    horizontalScrollBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil,
        tile = true, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    horizontalScrollBar:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
end
local repHorizThumb = horizontalScrollBar:CreateTexture(nil, "ARTWORK")
repHorizThumb:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
repHorizThumb:SetVertexColor(0.5, 0.5, 0.6, 1)
repHorizThumb:SetSize(24, HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2)
horizontalScrollBar:SetThumbTexture(repHorizThumb)

local factionLabelPool = {}
local function GetFactionLabelRow(i)
    if not factionLabelPool[i] then
        local row = CreateFrame("Button", nil, factionHeaderContainer)
        CreateSortableHoverTint(row, nil)
        if row.RegisterForClicks then
            row:RegisterForClicks("LeftButtonUp")
        end
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetJustifyV("MIDDLE")
        row.text:SetWordWrap(false)
        row:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            local fid = self.factionID
            if not fid then return end
            if factionSortFactionID == fid then
                if factionSortHighFirst then
                    factionSortHighFirst = false
                else
                    factionSortFactionID = nil
                end
            else
                factionSortFactionID = fid
                factionSortHighFirst = true
            end
            if frame.RefreshGrid then
                frame:RefreshGrid()
            end
        end)
        row:SetScript("OnEnter", SortableHoverEnter)
        row:SetScript("OnLeave", SortableHoverLeave)
        factionLabelPool[i] = row
    end
    return factionLabelPool[i]
end

local function StandingDisplayText(standing)
    if not standing or standing == "" then return "—" end
    local lower = standing:lower()
    return lower:sub(1, 1):upper() .. lower:sub(2)
end

--- "Standing: " uses tooltip default color; standing name uses bar/standing color.
local function RepTooltipStandingLine(standing)
    local shown = StandingDisplayText(standing)
    local r, g, b = DS.GetReputationBarColorsForStanding(standing)
    local hex = string.format("|cFF%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    return "Standing: " .. hex .. shown .. "|r"
end

local function RepCellTooltipTitleClassColored(entry, factionName)
    local n = (entry and entry.name) or "?"
    local r, g, b = 1, 0.82, 0
    if entry and entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
        local c = RAID_CLASS_COLORS[entry.classFile]
        r, g, b = c.r, c.g, c.b
    end
    local hex = string.format("|cFF%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    return hex .. n .. "|r — " .. (factionName or "?")
end

local function UpdateGridWithOffset()
    if not AltArmy.Characters or not DS then return end
    local list = GetDisplayList()
    local numCols = #list
    local factionRows = GetDisplayFactionRows()
    local numRows = #factionRows

    for idx, col in pairs(columnPool) do
        if idx > numCols then col:Hide() end
    end
    for idx, col in pairs(headerColumnPool) do
        if idx > numCols then col:Hide() end
    end

    for _, lab in pairs(factionLabelPool) do
        lab:Hide()
    end

    for r = 1, numRows do
        local row = GetFactionLabelRow(r)
        local fr = factionRows[r]
        row.factionID = fr and fr.factionID
        row:SetSize(FACTION_LABEL_WIDTH, dims.rowHeight)
        row:ClearAllPoints()
        if r == 1 then
            local off = (dims.rowHeight - REP_FACTION_LABEL_TEXT_HEIGHT) / 2
            row:SetPoint("TOPLEFT", factionHeaderContainer, "TOPLEFT", 0, -off)
        else
            row:SetPoint("TOPLEFT", factionLabelPool[r - 1], "BOTTOMLEFT", 0, 0)
        end

        local isSorted = fr and factionSortFactionID and factionSortFactionID == fr.factionID
        local suffix = isSorted and (factionSortHighFirst and " >" or " <") or ""
        local baseMax = FACTION_LABEL_WIDTH - 6
        local nameMax = (suffix ~= "") and (baseMax - 14) or baseMax
        if isSorted then
            row.text:SetTextColor(1, 0.82, 0, 1)
        else
            row.text:SetTextColor(0.9, 0.9, 0.9, 1)
        end
        local shown = TruncateName(row.text, fr and fr.name or "?", nameMax)
        if suffix ~= "" then
            row.text:SetText(shown .. suffix)
        end
        row:Show()
    end

    for c = 1, numCols do
        local entry = list[c]
        local headerCol = GetHeaderColumnFrame(c)
        headerCol:ClearAllPoints()
        headerCol:SetPoint("TOPLEFT", headerGridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD, 0)
        headerCol:Show()

        local classR, classG, classB = 1, 0.82, 0
        if entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
            local rc = RAID_CLASS_COLORS[entry.classFile]
            classR, classG, classB = rc.r, rc.g, rc.b
        end
        headerCol.reputationHeaderColumnIndex = c
        local displayName = entry.name or "?"
        local isColSorted = columnSortName
            and entry.name == columnSortName
            and (entry.realm or "") == (columnSortRealm or "")
        -- Column sort: same ^ / v as Summary headers; yellow name when active (faction rows use > / <).
        if isColSorted then
            classR, classG, classB = 1, 0.82, 0
        end
        headerCol.classR, headerCol.classG, headerCol.classB = classR, classG, classB
        -- High rep first = descending = " v"; low first = ascending = " ^" (matches TabSummary.lua)
        local hdrSuffix = isColSorted and (columnSortHighFirst and " v" or " ^") or ""
        local baseHeaderMax = dims.columnWidth - 4
        local headerMax = (hdrSuffix ~= "") and (baseHeaderMax - 14) or baseHeaderMax
        headerCol.header:SetTextColor(classR, classG, classB, 1)
        local shown = TruncateName(headerCol.header, displayName, headerMax)
        if hdrSuffix ~= "" then
            headerCol.header:SetText(shown .. hdrSuffix)
        end
        headerCol.truncated = (shown ~= displayName)
        local RF = AltArmy.RealmFilter
        local hasRealm = entry.realm and entry.realm ~= ""
        if headerCol.truncated or hasRealm then
            headerCol.tooltipText = RF and RF.formatCharacterDisplayName
                and RF.formatCharacterDisplayName(entry.name or "?", entry.realm or "", hasRealm)
                or displayName
        else
            headerCol.tooltipText = nil
        end

        -- Gear tab always shows the second row (empty when no fit message); match that layout
        headerCol.message:SetText("")
        headerCol.message:SetTextColor(0.9, 0.9, 0.9, 1)
        headerCol.message:Show()

        local col = GetColumnFrame(c)
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", gridContainer, "TOPLEFT", (c - 1) * dims.columnWidth + PAD - 4, 0)
        col:Show()

        local charData = DS.GetCharacter and DS:GetCharacter(entry.name, entry.realm)
        local hasRep = charData and DS.HasModuleData and DS:HasModuleData(charData, "reputations")

        for r = 1, numRows do
            local cell = EnsureCell(col, r)
            cell:ClearAllPoints()
            if r == 1 then
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", 4, -2)
            else
                cell:SetPoint("TOPLEFT", col.cells[r - 1], "BOTTOMLEFT", 0, 0)
            end
            cell:Show()
            cell.barBg:Show()
            cell.barFill:Show()
            cell.missingDataTooltipEntry = nil

            local factionID = factionRows[r] and factionRows[r].factionID
            local fname = factionRows[r] and factionRows[r].name or "?"
            cell.tooltipTitle = (entry.name or "?") .. " — " .. fname
            cell.tooltipLines = nil

            if not hasRep then
                cell.standing:SetText("—")
                cell.standing:SetTextColor(0.6, 0.6, 0.6, 1)
                cell.progress:SetText("No data")
                cell.progress:SetTextColor(0.55, 0.55, 0.55, 1)
                cell.barFill:SetVertexColor(0.35, 0.35, 0.35, 1)
                local bw = cell.barBg:GetWidth()
                if bw and bw > 0 then cell.barFill:SetWidth(1) end
                cell.tooltipLines = { "Reputation data not collected for this character." }
            elseif not factionID then
                cell.standing:SetText("—")
                cell.progress:SetText("")
                cell.barFill:SetVertexColor(0.3, 0.3, 0.3, 1)
                local bw = cell.barBg:GetWidth()
                if bw and bw > 0 then cell.barFill:SetWidth(1) end
            else
                local rawRep = charData.Reputations[factionID]
                local isV1Legacy = type(rawRep) == "number"
                local standing, repEarned, nextLevel, rate = DS:GetReputationInfo(charData, factionID)
                if not standing then
                    -- Faction not discovered on this character: no standing dash, no bar; tooltip only.
                    cell.standing:SetText("")
                    cell.standing:SetTextColor(0.7, 0.7, 0.7, 1)
                    cell.progress:SetText("")
                    cell.progress:SetTextColor(0.7, 0.7, 0.7, 1)
                    cell.barBg:Hide()
                    cell.barFill:Hide()
                    cell.tooltipTitle = RepCellTooltipTitleClassColored(entry, fname)
                    cell.tooltipLines = { "Not yet discovered" }
                elseif isV1Legacy then
                    -- Empty standing; "(missing data)" in the bar band (no bar fill).
                    cell.standing:SetText("")
                    cell.standing:SetTextColor(0.92, 0.92, 0.92, 1)
                    cell.progress:SetText("(missing data)")
                    cell.progress:SetTextColor(MISSING_DATA_TEXT_R, MISSING_DATA_TEXT_G, MISSING_DATA_TEXT_B, 1)
                    cell.barBg:Hide()
                    cell.barFill:Hide()
                    cell.tooltipTitle = nil
                    cell.tooltipLines = nil
                    cell.missingDataTooltipEntry = {
                        name = entry.name or "",
                        realm = entry.realm or "",
                        classFile = entry.classFile,
                    }
                else
                    cell.standing:SetText(StandingDisplayText(standing))
                    local br, bgc, bb = DS.GetReputationBarColorsForStanding(standing)
                    cell.standing:SetTextColor(br, bgc, bb, 1)
                    local progText = DS.FormatReputationProgressText(standing, repEarned, nextLevel)
                    cell.progress:SetText(progText)
                    cell.progress:SetTextColor(0.92, 0.92, 0.92, 1)
                    cell.barFill:SetVertexColor(br, bgc, bb, 1)
                    local pct = tonumber(rate) or 0
                    if pct < 0 then pct = 0 end
                    if pct > 100 then pct = 100 end
                    local bw = cell.barBg:GetWidth()
                    if bw and bw > 0 then
                        local fw = math.max(1, bw * pct / 100)
                        cell.barFill:SetWidth(fw)
                    end
                    cell.tooltipTitle = RepCellTooltipTitleClassColored(entry, fname)
                    cell.tooltipLines = {
                        RepTooltipStandingLine(standing),
                        "Progress: " .. progText,
                    }
                end
            end
        end

        for rr = numRows + 1, #(col.cells or {}) do
            if col.cells[rr] then col.cells[rr]:Hide() end
        end
    end
end

function frame:RefreshGrid(_self)
    if not AltArmy.Characters then return end
    if AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
    if AltArmy.Characters.Sort then
        AltArmy.Characters:Sort(false, "level")
    end

    if DS and DS.GetCurrentReputationFactionRows then
        lastFactionRows = DS:GetCurrentReputationFactionRows()
    else
        lastFactionRows = {}
    end
    local filterText = factionFilterEdit and factionFilterEdit:GetText() or ""
    local factionRowsForLayout = FilterReputationFactionRows(lastFactionRows, filterText)
    local numRows = #factionRowsForLayout
    dims.scrollableGridHeight = math.max(dims.rowHeight + PAD, numRows * dims.rowHeight + PAD)

    if verticalScrollChild then
        verticalScrollChild:SetHeight(FIXED_HEADER_ROW_HEIGHT + dims.scrollableGridHeight)
    end
    if gridContainer then
        gridContainer:SetHeight(dims.scrollableGridHeight)
    end

    for _, col in pairs(columnPool) do
        col:SetSize(dims.columnWidth, dims.scrollableGridHeight)
        for r, cell in pairs(col.cells or {}) do
            cell:SetSize(dims.columnWidth - 8, dims.rowHeight)
            if r == 1 then
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", col, "TOPLEFT", 4, -GetFirstRowCellVerticalOffset())
            else
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", col.cells[r - 1], "BOTTOMLEFT", 0, 0)
            end
        end
    end

    for _, lab in pairs(factionLabelPool) do
        lab:SetHeight(dims.rowHeight)
    end

    local list = GetDisplayList()
    local numCols = #list
    local viewWidth = verticalScroll and verticalScroll:GetWidth() or 0
    local viewHeight = verticalScroll and verticalScroll:GetHeight() or 0
    local gridContentWidth = numCols * dims.columnWidth + PAD
    local gridViewWidth = math.max(0, viewWidth - FACTION_LABEL_WIDTH)

    if verticalScrollChild and verticalScroll then
        verticalScrollChild:SetWidth(math.max(MIN_SCROLL_CHILD_WIDTH, viewWidth))
        if gridContainer then
            gridContainer:SetWidth(math.max(0, gridContentWidth))
        end
        if headerGridContainer then
            headerGridContainer:SetWidth(math.max(0, gridContentWidth))
        end
        if verticalScrollBar then
            local totalChildHeight = FIXED_HEADER_ROW_HEIGHT + dims.scrollableGridHeight
            local maxVertScroll = math.max(0, totalChildHeight - viewHeight)
            verticalScrollBar:SetMinMaxValues(0, maxVertScroll)
            verticalScrollBar:SetValueStep(dims.rowHeight)
            verticalScrollBar:SetStepsPerPage(10)
        end
        if horizontalScrollBar and horizontalScroll and gridContainer then
            local maxHorzScroll = math.max(0, gridContentWidth - gridViewWidth)
            horizontalScrollBar:SetMinMaxValues(0, maxHorzScroll)
            horizontalScrollBar:SetValueStep(1)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            horizontalScrollBar:SetValue(0)
            lastHorizontalScrollValue = 0
            horizontalScroll:SetHorizontalScroll(0)
            if headerHorizontalScroll then
                headerHorizontalScroll:SetHorizontalScroll(0)
            end
        end
    end

    UpdateGridWithOffset()

    -- Bar widths need layout after first show (barBg width is 0 until anchors resolve)
    if gridContainer then
        gridContainer:SetScript("OnUpdate", function(g)
            g:SetScript("OnUpdate", nil)
            UpdateGridWithOffset()
        end)
    end
end

frame:SetScript("OnShow", function()
    frame:RefreshGrid()
end)

frame:RegisterEvent("UPDATE_FACTION")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_FACTION" or event == "PLAYER_ENTERING_WORLD" then
        if frame:IsShown() then
            frame:RefreshGrid()
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        if frame:IsShown() then
            frame:RefreshGrid()
        end
    end
end)

-- ---- Settings panel (60% grid / 40% settings) ----
local settingsPanel = CreateFrame("Frame", nil, frame)
local function ApplySettingsPanelLayout()
    local w = frame:GetWidth()
    if w <= 0 then return end
    settingsPanel:ClearAllPoints()
    settingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", w * GRID_SPLIT_FRACTION + PAD, -PAD)
    settingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", w * GRID_SPLIT_FRACTION + PAD, PAD)
    settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
    settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
end
ApplySettingsPanelLayout()
settingsPanel:Hide()

local SETTINGS_ROW_HEIGHT = 22
local repSettingsTitle = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
repSettingsTitle:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 0, 0)
repSettingsTitle:SetPoint("TOPRIGHT", settingsPanel, "TOPRIGHT", 0, 0)
repSettingsTitle:SetJustifyH("LEFT")
repSettingsTitle:SetText("Reputation Settings")

local primaryDropdown, secondaryDropdown, realmDropdown
local repCharListRefresh = function() end

local sortingContent = CreateFrame("Frame", nil, settingsPanel)
sortingContent:SetPoint("TOPLEFT", repSettingsTitle, "BOTTOMLEFT", 0, -8)
sortingContent:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMRIGHT", 0, 0)

local showSelfFirstCheck = CreateFrame("CheckButton", nil, sortingContent)
showSelfFirstCheck:SetPoint("TOPLEFT", sortingContent, "TOPLEFT", 0, 0)
showSelfFirstCheck:SetSize(24, 24)
local showSelfFirstBg = showSelfFirstCheck:CreateTexture(nil, "BACKGROUND")
showSelfFirstBg:SetAllPoints(showSelfFirstCheck)
showSelfFirstBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
local showSelfFirstCheckTex = showSelfFirstCheck:CreateTexture(nil, "OVERLAY")
showSelfFirstCheckTex:SetPoint("CENTER", showSelfFirstCheck, "CENTER", 0, 0)
showSelfFirstCheckTex:SetSize(16, 16)
showSelfFirstCheckTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
showSelfFirstCheck:SetCheckedTexture(showSelfFirstCheckTex)
local showSelfFirstLabel = showSelfFirstCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
showSelfFirstLabel:SetPoint("LEFT", showSelfFirstCheck, "RIGHT", 4, 0)
showSelfFirstLabel:SetText("Show self first")
showSelfFirstCheck:SetScript("OnClick", function()
    GetReputationSettings().showSelfFirst = showSelfFirstCheck:GetChecked()
    frame:RefreshGrid()
end)

local btnPrimary = CreateFrame("Button", nil, sortingContent)
btnPrimary:SetPoint("TOPLEFT", showSelfFirstCheck, "BOTTOMLEFT", 0, -6)
btnPrimary:SetPoint("TOPRIGHT", sortingContent, "TOPRIGHT", 0, 0)
btnPrimary:SetHeight(SETTINGS_ROW_HEIGHT)
local btnPrimaryBg = btnPrimary:CreateTexture(nil, "BACKGROUND")
btnPrimaryBg:SetAllPoints(btnPrimary)
btnPrimaryBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
local btnPrimaryText = btnPrimary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btnPrimaryText:SetPoint("LEFT", btnPrimary, "LEFT", 4, 0)
btnPrimaryText:SetPoint("RIGHT", btnPrimary, "RIGHT", -4, 0)
btnPrimaryText:SetJustifyH("LEFT")
primaryDropdown = CreateFrame("Frame", nil, sortingContent)
primaryDropdown:SetPoint("TOPLEFT", btnPrimary, "BOTTOMLEFT", 0, -2)
primaryDropdown:SetPoint("TOPRIGHT", btnPrimary, "BOTTOMRIGHT", 0, 0)
primaryDropdown:SetHeight(#SORT_OPTIONS * SETTINGS_ROW_HEIGHT + 4)
primaryDropdown:SetFrameLevel(sortingContent:GetFrameLevel() + 100)
primaryDropdown:Hide()
local primaryDropdownBg = primaryDropdown:CreateTexture(nil, "BACKGROUND")
primaryDropdownBg:SetAllPoints(primaryDropdown)
primaryDropdownBg:SetColorTexture(0.15, 0.15, 0.18, 0.98)
for idx, opt in ipairs(SORT_OPTIONS) do
    local b = CreateFrame("Button", nil, primaryDropdown)
    b:SetPoint("TOPLEFT", primaryDropdown, "TOPLEFT", 2, -2 - (idx - 1) * SETTINGS_ROW_HEIGHT)
    b:SetPoint("LEFT", primaryDropdown, "LEFT", 2, 0)
    b:SetPoint("RIGHT", primaryDropdown, "RIGHT", -2, 0)
    b:SetHeight(SETTINGS_ROW_HEIGHT - 2)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "LEFT", 4, 0)
    t:SetText(opt)
    b:SetScript("OnClick", function()
        GetReputationSettings().primarySort = opt
        primaryDropdown:Hide()
        btnPrimaryText:SetText("Primary Sort: " .. opt)
        frame:RefreshGrid()
        if repCharListRefresh then repCharListRefresh() end
    end)
end
btnPrimary:SetScript("OnClick", function()
    primaryDropdown:SetShown(not primaryDropdown:IsShown())
    secondaryDropdown:Hide()
    realmDropdown:Hide()
end)

local btnSecondary = CreateFrame("Button", nil, sortingContent)
btnSecondary:SetPoint("TOPLEFT", btnPrimary, "BOTTOMLEFT", 0, -6)
btnSecondary:SetPoint("TOPRIGHT", sortingContent, "TOPRIGHT", 0, 0)
btnSecondary:SetHeight(SETTINGS_ROW_HEIGHT)
local btnSecondaryBg = btnSecondary:CreateTexture(nil, "BACKGROUND")
btnSecondaryBg:SetAllPoints(btnSecondary)
btnSecondaryBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
local btnSecondaryText = btnSecondary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btnSecondaryText:SetPoint("LEFT", btnSecondary, "LEFT", 4, 0)
btnSecondaryText:SetPoint("RIGHT", btnSecondary, "RIGHT", -4, 0)
btnSecondaryText:SetJustifyH("LEFT")
secondaryDropdown = CreateFrame("Frame", nil, sortingContent)
secondaryDropdown:SetPoint("TOPLEFT", btnSecondary, "BOTTOMLEFT", 0, -2)
secondaryDropdown:SetPoint("TOPRIGHT", btnSecondary, "BOTTOMRIGHT", 0, 0)
secondaryDropdown:SetHeight(#SORT_OPTIONS * SETTINGS_ROW_HEIGHT + 4)
secondaryDropdown:SetFrameLevel(sortingContent:GetFrameLevel() + 100)
secondaryDropdown:Hide()
local secondaryDropdownBg = secondaryDropdown:CreateTexture(nil, "BACKGROUND")
secondaryDropdownBg:SetAllPoints(secondaryDropdown)
secondaryDropdownBg:SetColorTexture(0.15, 0.15, 0.18, 0.98)
for idx, opt in ipairs(SORT_OPTIONS) do
    local b = CreateFrame("Button", nil, secondaryDropdown)
    b:SetPoint("TOPLEFT", secondaryDropdown, "TOPLEFT", 2, -2 - (idx - 1) * SETTINGS_ROW_HEIGHT)
    b:SetPoint("LEFT", secondaryDropdown, "LEFT", 2, 0)
    b:SetPoint("RIGHT", secondaryDropdown, "RIGHT", -2, 0)
    b:SetHeight(SETTINGS_ROW_HEIGHT - 2)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "LEFT", 4, 0)
    t:SetText(opt)
    b:SetScript("OnClick", function()
        GetReputationSettings().secondarySort = opt
        secondaryDropdown:Hide()
        btnSecondaryText:SetText("Secondary Sort: " .. opt)
        frame:RefreshGrid()
        if repCharListRefresh then repCharListRefresh() end
    end)
end
btnSecondary:SetScript("OnClick", function()
    secondaryDropdown:SetShown(not secondaryDropdown:IsShown())
    primaryDropdown:Hide()
    realmDropdown:Hide()
end)

local REALM_FILTER_LABELS = { all = "All Characters", currentRealm = "Current Realm Only" }
local btnRealm = CreateFrame("Button", nil, sortingContent)
btnRealm:SetPoint("TOPLEFT", btnSecondary, "BOTTOMLEFT", 0, -6)
btnRealm:SetPoint("TOPRIGHT", sortingContent, "TOPRIGHT", 0, 0)
btnRealm:SetHeight(SETTINGS_ROW_HEIGHT)
local btnRealmBg = btnRealm:CreateTexture(nil, "BACKGROUND")
btnRealmBg:SetAllPoints(btnRealm)
btnRealmBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
local btnRealmText = btnRealm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btnRealmText:SetPoint("LEFT", btnRealm, "LEFT", 4, 0)
btnRealmText:SetPoint("RIGHT", btnRealm, "RIGHT", -4, 0)
btnRealmText:SetJustifyH("LEFT")
realmDropdown = CreateFrame("Frame", nil, sortingContent)
realmDropdown:SetPoint("TOPLEFT", btnRealm, "BOTTOMLEFT", 0, -2)
realmDropdown:SetPoint("TOPRIGHT", btnRealm, "BOTTOMRIGHT", 0, 0)
realmDropdown:SetHeight(#REALM_FILTER_OPTIONS * SETTINGS_ROW_HEIGHT + 4)
realmDropdown:SetFrameLevel(sortingContent:GetFrameLevel() + 100)
realmDropdown:Hide()
local realmDropdownBg = realmDropdown:CreateTexture(nil, "BACKGROUND")
realmDropdownBg:SetAllPoints(realmDropdown)
realmDropdownBg:SetColorTexture(0.15, 0.15, 0.18, 0.98)
for idx, opt in ipairs(REALM_FILTER_OPTIONS) do
    local b = CreateFrame("Button", nil, realmDropdown)
    b:SetPoint("TOPLEFT", realmDropdown, "TOPLEFT", 2, -2 - (idx - 1) * SETTINGS_ROW_HEIGHT)
    b:SetPoint("LEFT", realmDropdown, "LEFT", 2, 0)
    b:SetPoint("RIGHT", realmDropdown, "RIGHT", -2, 0)
    b:SetHeight(SETTINGS_ROW_HEIGHT - 2)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "LEFT", 4, 0)
    t:SetText(REALM_FILTER_LABELS[opt] or opt)
    b:SetScript("OnClick", function()
        GetReputationSettings().realmFilter = opt
        realmDropdown:Hide()
        btnRealmText:SetText("Realm: " .. (REALM_FILTER_LABELS[opt] or opt))
        frame:RefreshGrid()
        if repCharListRefresh then repCharListRefresh() end
    end)
end
btnRealm:SetScript("OnClick", function()
    realmDropdown:SetShown(not realmDropdown:IsShown())
    primaryDropdown:Hide()
    secondaryDropdown:Hide()
end)

if AltArmy.CreateCharacterPinHideList then
    -- luacheck: push ignore 211
    local _scroll, refresh = AltArmy.CreateCharacterPinHideList(sortingContent, btnRealm, {
        getSettings = GetReputationSettings,
        getCharSetting = GetCharSetting,
        setCharSetting = SetCharSetting,
        onChange = function()
            frame:RefreshGrid()
        end,
    })
    if refresh then repCharListRefresh = refresh end
    -- luacheck: pop
end

settingsPanel:SetScript("OnHide", function()
    primaryDropdown:Hide()
    secondaryDropdown:Hide()
    realmDropdown:Hide()
end)

function frame:IsReputationSettingsShown()
    return settingsPanel and settingsPanel:IsShown()
end

function frame:ToggleReputationSettings(_self)
    local showSettings = not settingsPanel:IsShown()
    settingsPanel:SetShown(showSettings)
    if showSettings then
        ApplySettingsPanelLayout()
    end
    rightPanel:ClearAllPoints()
    rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
    if showSettings then
        rightPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -(PAD + SCROLL_BAR_RIGHT_OFFSET + 4), 0)
    else
        rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    end
    if showSettings then
        local s = GetReputationSettings()
        btnPrimaryText:SetText("Primary Sort: " .. s.primarySort)
        btnSecondaryText:SetText("Secondary Sort: " .. s.secondarySort)
        btnRealmText:SetText("Realm: " .. (REALM_FILTER_LABELS[s.realmFilter] or s.realmFilter or "All Characters"))
        showSelfFirstCheck:SetChecked(s.showSelfFirst)
        if AltArmy.Characters and AltArmy.Characters.InvalidateView then
            AltArmy.Characters:InvalidateView()
        end
        if repCharListRefresh then repCharListRefresh() end
    end
    frame:RefreshGrid()
end

frame:SetScript("OnSizeChanged", function()
    if settingsPanel and settingsPanel:IsShown() then
        ApplySettingsPanelLayout()
        rightPanel:ClearAllPoints()
        rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
        rightPanel:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMLEFT", -(PAD + SCROLL_BAR_RIGHT_OFFSET + 4), 0)
        frame:RefreshGrid()
    end
end)
