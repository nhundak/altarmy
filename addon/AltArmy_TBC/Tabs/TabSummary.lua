-- AltArmy TBC — Summary tab: character list (Altoholic-style fixed row pool + Update(offset))

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Summary
if not frame then return end

local ROW_HEIGHT = 18
local NUM_ROWS = 14
local HEADER_HEIGHT = 20
local TOTALS_ROW_HEIGHT = 18
local PAD = 4
local WARNING_COL_WIDTH = 20

local SD = AltArmy.SummaryData

local REALM_FILTER_OPTIONS = { "all", "currentRealm" }
local REALM_FILTER_LABELS = { all = "All Characters", currentRealm = "Current Realm Only" }
local function GetSummarySettings()
    AltArmyTBC_SummarySettings = AltArmyTBC_SummarySettings or {}
    local s = AltArmyTBC_SummarySettings
    if s.realmFilter ~= "all" and s.realmFilter ~= "currentRealm" then
        s.realmFilter = "all"
    end
    s.characters = s.characters or {}
    return s
end

local function SummaryCharKey(name, realm)
    return (realm or "") .. "\\" .. (name or "")
end

local function GetSummaryCharSetting(name, realm, key)
    local s = GetSummarySettings()
    local c = s.characters[SummaryCharKey(name, realm)]
    if not c then return false end
    return c[key] == true
end

local function SetSummaryCharSetting(name, realm, pin, hide)
    local s = GetSummarySettings()
    local key = SummaryCharKey(name, realm)
    s.characters[key] = { pin = pin == true, hide = hide == true }
end

local summaryCharListRefresh = function() end  -- set below if CreateCharacterPinHideList is available

local function isCurrentCharacter(entry)
    local currentName = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""
    local currentRealm = GetRealmName and GetRealmName() or ""
    return entry and (entry.name == currentName and entry.realm == currentRealm)
end

-- Column definitions: Name, Level, RestXP, Money, Played, LastOnline, Warning (total width unchanged)
local columns = {
    Name = {
        Width = 129 - WARNING_COL_WIDTH,
        GetText = function(entry) return entry.name or "" end,
        JustifyH = "LEFT",
    },
    Level = {
        Width = 54,
        GetText = function(entry)
            local l = entry.level
            if l == nil then return "" end
            return string.format("%.1f", math.floor((tonumber(l) or 0) * 10) / 10)
        end,
        JustifyH = "RIGHT",
    },
    RestXP = {
        Width = 71,
        headerLabel = "Rest XP",
        GetText = function(entry) return SD and SD.FormatRestXp and SD.FormatRestXp(entry.restXp) or "" end,
        JustifyH = "RIGHT",
    },
    Money = {
        Width = 120,
        GetText = function(entry) return SD and SD.GetMoneyString and SD.GetMoneyString(entry.money) or "" end,
        JustifyH = "RIGHT",
    },
    Played = {
        Width = 109,
        GetText = function(entry) return SD and SD.GetTimeString and SD.GetTimeString(entry.played) or "" end,
        JustifyH = "RIGHT",
    },
    LastOnline = {
        Width = 72,
        headerLabel = "Online",
        GetText = function(entry)
            return SD and SD.FormatLastOnline and SD.FormatLastOnline(entry.lastOnline, isCurrentCharacter(entry)) or ""
        end,
        JustifyH = "RIGHT",
    },
    Warning = {
        Width = WARNING_COL_WIDTH,
        headerLabel = "",
    },
}
local columnOrder = { "Name", "Level", "RestXP", "Money", "Played", "LastOnline", "Warning" }

--- Truncate name with "..." if it exceeds maxWidth; sets fontString text.
--- @return boolean|nil true if the name was truncated (caller may show tooltip with full name).
local function TruncateName(fontString, fullName, maxWidth)
    if not fullName or fullName == "" then
        fontString:SetText("?")
        return false
    end
    fontString:SetText(fullName)
    if fontString:GetStringWidth() <= maxWidth then return false end
    for len = #fullName - 1, 1, -1 do
        local truncated = fullName:sub(1, len) .. "..."
        fontString:SetText(truncated)
        if fontString:GetStringWidth() <= maxWidth then return true end
    end
    fontString:SetText("...")
    return true
end

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

-- Scroll frame (viewport; no template — we use a custom scroll bar like Gear tab)
local scrollFrame = CreateFrame("ScrollFrame", "AltArmyTBC_SummaryScrollFrame", frame)
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD - HEADER_HEIGHT)
scrollFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD + TOTALS_ROW_HEIGHT)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 20, PAD + TOTALS_ROW_HEIGHT)
scrollFrame:EnableMouse(true)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
scrollChild:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, 0)
scrollFrame:SetScrollChild(scrollChild)

-- Custom vertical scroll bar (same style as Gear tab)
local SCROLL_BAR_WIDTH = 20
local SCROLL_BAR_TOP_INSET = 16
local SCROLL_BAR_BOTTOM_INSET = 16
local SCROLL_BAR_RIGHT_OFFSET = 4
local scrollBar = CreateFrame("Slider", "AltArmyTBC_SummaryScrollBar", frame)
scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", SCROLL_BAR_RIGHT_OFFSET, -(PAD + SCROLL_BAR_TOP_INSET))
scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", SCROLL_BAR_RIGHT_OFFSET, SCROLL_BAR_BOTTOM_INSET)
scrollBar:SetWidth(SCROLL_BAR_WIDTH)
scrollBar:SetMinMaxValues(0, 0)
scrollBar:SetValueStep(ROW_HEIGHT)
scrollBar:SetValue(0)
scrollBar:SetOrientation("VERTICAL")
scrollBar:EnableMouse(true)
local vertThumb = scrollBar:CreateTexture(nil, "ARTWORK")
vertThumb:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
vertThumb:SetVertexColor(0.5, 0.5, 0.6, 1)
vertThumb:SetSize(SCROLL_BAR_WIDTH - 4, 24)
scrollBar:SetThumbTexture(vertThumb)
scrollBar:SetScript("OnValueChanged", function(_, value)
    scrollFrame:SetVerticalScroll(value)
end)

local function OnSummaryScrollWheel(_, delta)
    if not scrollBar then return end
    local minVal, maxVal = scrollBar:GetMinMaxValues()
    local current = scrollBar:GetValue()
    local newVal = current - delta * ROW_HEIGHT * 2
    newVal = math.max(minVal, math.min(maxVal, newVal))
    scrollBar:SetValue(newVal)
    scrollFrame:SetVerticalScroll(newVal)
end
scrollFrame:SetScript("OnMouseWheel", OnSummaryScrollWheel)
scrollChild:SetScript("OnMouseWheel", OnSummaryScrollWheel)

local function GetScrollBar()
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
    if cn == "Warning" then
        local headerFrame = CreateFrame("Frame", nil, headerRow)
        headerFrame:SetPoint("LEFT", headerRow, "LEFT", x, 0)
        headerFrame:SetSize(w, HEADER_HEIGHT)
        headerButtons[colName] = headerFrame
    else
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
    end
    x = x + w
end

local totalColWidth = 0
for _, colName in ipairs(columnOrder) do
    local col = columns[colName]
    totalColWidth = totalColWidth + (col and col.Width or 100)
end

-- Totals row (fixed at bottom of list area; reparented to horizontalScrollChild below)
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

-- List viewport: clips list content to left 60% when settings panel is open (so list doesn't show through).
-- Horizontal scroll sits inside so the grid can scroll when viewport is narrower than totalColWidth.
local HORIZONTAL_SCROLL_BAR_HEIGHT = 20
local listViewport = CreateFrame("Frame", nil, frame)
listViewport:SetClipsChildren(true)
-- Points set in ToggleSummarySettings / OnSizeChanged

local horizontalScroll = CreateFrame("ScrollFrame", "AltArmyTBC_SummaryHorizontalScroll", listViewport)
horizontalScroll:SetAllPoints(listViewport)
horizontalScroll:EnableMouse(true)

local horizontalScrollChild = CreateFrame("Frame", nil, horizontalScroll)
horizontalScrollChild:SetPoint("TOPLEFT", horizontalScroll, "TOPLEFT", 0, 0)
horizontalScrollChild:SetHeight(1) -- Updated in layout; width = totalColWidth set in Update
horizontalScrollChild:SetWidth(totalColWidth)
horizontalScroll:SetScrollChild(horizontalScrollChild)

-- Reparent header into horizontal scroll child so it scrolls with the grid
headerRow:ClearAllPoints()
headerRow:SetParent(horizontalScrollChild)
headerRow:SetPoint("TOPLEFT", horizontalScrollChild, "TOPLEFT", 0, 0)
headerRow:SetPoint("TOPRIGHT", horizontalScrollChild, "TOPRIGHT", 0, 0)
headerRow:SetHeight(HEADER_HEIGHT)

-- Reparent vertical scroll frame into horizontal scroll child
scrollFrame:ClearAllPoints()
scrollFrame:SetParent(horizontalScrollChild)
scrollFrame:SetPoint("TOPLEFT", horizontalScrollChild, "TOPLEFT", 0, -HEADER_HEIGHT)
scrollFrame:SetPoint("BOTTOMLEFT", horizontalScrollChild, "BOTTOMLEFT", 0, TOTALS_ROW_HEIGHT)
scrollFrame:SetPoint("BOTTOMRIGHT", horizontalScrollChild, "BOTTOMRIGHT", 0, TOTALS_ROW_HEIGHT)

-- Reparent totals row into horizontal scroll child
totalsRow:ClearAllPoints()
totalsRow:SetParent(horizontalScrollChild)
totalsRow:SetPoint("BOTTOMLEFT", horizontalScrollChild, "BOTTOMLEFT", 0, 0)
totalsRow:SetPoint("BOTTOMRIGHT", horizontalScrollChild, "BOTTOMRIGHT", 0, 0)

-- Horizontal scroll bar at bottom of list area (like Gear tab)
local horizontalScrollBar = CreateFrame("Slider", "AltArmyTBC_SummaryHorizontalScrollBar", frame)
horizontalScrollBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
horizontalScrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - SCROLL_BAR_WIDTH - PAD, PAD)
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
local function ApplySummaryHorizontalScrollValue(value)
    if not horizontalScroll then return end
    lastHorizontalScrollValue = value
    if horizontalScroll.UpdateScrollChildRect then
        horizontalScroll:UpdateScrollChildRect()
    end
    horizontalScroll:SetHorizontalScroll(value)
end
local function SyncSummaryHorizontalScrollPosition()
    if not (horizontalScroll and horizontalScrollBar) then return end
    local value = horizontalScrollBar:GetValue()
    if lastHorizontalScrollValue == value then return end
    ApplySummaryHorizontalScrollValue(value)
end
horizontalScrollBar:SetScript("OnValueChanged", function(_, _value)
    SyncSummaryHorizontalScrollPosition()
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
                ApplySummaryHorizontalScrollValue(value)
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
local hThumbTex = horizontalScrollBar:CreateTexture(nil, "ARTWORK")
hThumbTex:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
hThumbTex:SetVertexColor(0.5, 0.5, 0.6, 1)
hThumbTex:SetSize(24, HORIZONTAL_SCROLL_BAR_HEIGHT - PAD * 2)
horizontalScrollBar:SetThumbTexture(hThumbTex)

-- Summary settings panel (right 40% when visible; same layout as Gear tab)
local SUMMARY_SETTINGS_SPLIT = 0.6
local summarySettingsPanel = CreateFrame("Frame", nil, frame)
local function ApplySummarySettingsPanelLayout()
    local w = frame:GetWidth()
    if w <= 0 then return end
    summarySettingsPanel:ClearAllPoints()
    summarySettingsPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", w * SUMMARY_SETTINGS_SPLIT + PAD, -PAD)
    summarySettingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", w * SUMMARY_SETTINGS_SPLIT + PAD, PAD)
    summarySettingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
    summarySettingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
end
ApplySummarySettingsPanelLayout()
summarySettingsPanel:Hide()
local SETTINGS_TITLE_HEIGHT = 26
local summarySettingsTitle = summarySettingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
summarySettingsTitle:SetPoint("TOPLEFT", summarySettingsPanel, "TOPLEFT", 0, 0)
summarySettingsTitle:SetPoint("TOPRIGHT", summarySettingsPanel, "TOPRIGHT", 0, 0)
summarySettingsTitle:SetJustifyH("LEFT")
summarySettingsTitle:SetText("Summary Settings")
local SETTINGS_ROW_HEIGHT = 22
local btnSummaryRealm = CreateFrame("Button", nil, summarySettingsPanel)
btnSummaryRealm:SetPoint("TOPLEFT", summarySettingsPanel, "TOPLEFT", 0, -SETTINGS_TITLE_HEIGHT)
btnSummaryRealm:SetPoint("TOPRIGHT", summarySettingsPanel, "TOPRIGHT", 0, 0)
btnSummaryRealm:SetHeight(SETTINGS_ROW_HEIGHT)
local btnSummaryRealmBg = btnSummaryRealm:CreateTexture(nil, "BACKGROUND")
btnSummaryRealmBg:SetAllPoints(btnSummaryRealm)
btnSummaryRealmBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
local btnSummaryRealmText = btnSummaryRealm:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btnSummaryRealmText:SetPoint("LEFT", btnSummaryRealm, "LEFT", 4, 0)
btnSummaryRealmText:SetPoint("RIGHT", btnSummaryRealm, "RIGHT", -4, 0)
btnSummaryRealmText:SetJustifyH("LEFT")
local summaryRealmDropdown = CreateFrame("Frame", nil, summarySettingsPanel)
summaryRealmDropdown:SetPoint("TOPLEFT", btnSummaryRealm, "BOTTOMLEFT", 0, -2)
summaryRealmDropdown:SetPoint("TOPRIGHT", btnSummaryRealm, "BOTTOMRIGHT", 0, 0)
summaryRealmDropdown:SetHeight(#REALM_FILTER_OPTIONS * SETTINGS_ROW_HEIGHT + 4)
summaryRealmDropdown:SetFrameLevel(summarySettingsPanel:GetFrameLevel() + 100)
summaryRealmDropdown:Hide()
local summaryRealmDropdownBg = summaryRealmDropdown:CreateTexture(nil, "BACKGROUND")
summaryRealmDropdownBg:SetAllPoints(summaryRealmDropdown)
summaryRealmDropdownBg:SetColorTexture(0.15, 0.15, 0.18, 0.98)
for idx, opt in ipairs(REALM_FILTER_OPTIONS) do
    local b = CreateFrame("Button", nil, summaryRealmDropdown)
    b:SetPoint("TOPLEFT", summaryRealmDropdown, "TOPLEFT", 2, -2 - (idx - 1) * SETTINGS_ROW_HEIGHT)
    b:SetPoint("LEFT", summaryRealmDropdown, "LEFT", 2, 0)
    b:SetPoint("RIGHT", summaryRealmDropdown, "RIGHT", -2, 0)
    b:SetHeight(SETTINGS_ROW_HEIGHT - 2)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "LEFT", 4, 0)
    t:SetText(REALM_FILTER_LABELS[opt] or opt)
    b.option = opt
    b:SetScript("OnClick", function()
        GetSummarySettings().realmFilter = opt
        summaryRealmDropdown:Hide()
        btnSummaryRealmText:SetText(REALM_FILTER_LABELS[opt] or opt)
        UpdateHeaderSortIndicators()
        if summaryCharListRefresh then summaryCharListRefresh() end
        local sb = GetScrollBar()
        local scrollValue = sb and sb:GetValue() or 0
        Update(math.floor(scrollValue / ROW_HEIGHT))
    end)
end
btnSummaryRealm:SetScript("OnClick", function()
    summaryRealmDropdown:SetShown(not summaryRealmDropdown:IsShown())
end)
summarySettingsPanel:SetScript("OnHide", function()
    summaryRealmDropdown:Hide()
end)

-- Character list: Pin/Hide (reusable component, same as Gear tab)
if AltArmy.CreateCharacterPinHideList then
    -- luacheck: push ignore 211
    local _scroll, refresh = AltArmy.CreateCharacterPinHideList(summarySettingsPanel,
        btnSummaryRealm, {
            getSettings = GetSummarySettings,
            getCharSetting = GetSummaryCharSetting,
            setCharSetting = SetSummaryCharSetting,
            onChange = function()
                local sb = GetScrollBar()
                Update(math.floor((sb and sb:GetValue() or 0) / ROW_HEIGHT))
            end,
        })
    if refresh then summaryCharListRefresh = refresh end
    -- luacheck: pop
end

function frame:IsSummarySettingsShown()
    return summarySettingsPanel and summarySettingsPanel:IsShown()
end

local function ApplySummaryListLayout()
    local showSettings = summarySettingsPanel and summarySettingsPanel:IsShown()
    local vpBottomY = PAD + HORIZONTAL_SCROLL_BAR_HEIGHT
    -- List viewport: panel open = leave room for vertical scroll bar then panel; closed = frame minus scroll bar.
    -- Use same bottom Y in both states so the totals row does not jump (panel bottom is already at frame+PAD).
    listViewport:ClearAllPoints()
    listViewport:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
    if showSettings then
        -- End viewport before vertical scroll bar. Y offset = HORIZONTAL_SCROLL_BAR_HEIGHT so bottom matches closed.
        listViewport:SetPoint("BOTTOMRIGHT", summarySettingsPanel, "BOTTOMLEFT", -PAD - SCROLL_BAR_WIDTH,
            HORIZONTAL_SCROLL_BAR_HEIGHT)
    else
        local vpRight = -(PAD + SCROLL_BAR_WIDTH)
        listViewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", vpRight, vpBottomY)
    end
    -- Horizontal scroll bar: same span as list viewport; keep bottom at frame+PAD in both states so it doesn't jump.
    horizontalScrollBar:ClearAllPoints()
    horizontalScrollBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
    if showSettings then
        -- Bar BOTTOMRIGHT at (listViewport right, frame+PAD) via offset from viewport BOTTOMRIGHT
        horizontalScrollBar:SetPoint("BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, PAD - vpBottomY)
    else
        local hrRight = -(PAD + SCROLL_BAR_WIDTH)
        horizontalScrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", hrRight, PAD)
    end
    -- Vertical scroll bar: when open, sit at right edge of list viewport (left 60%); when closed, at frame right.
    if showSettings then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", listViewport, "TOPRIGHT", 0, -(PAD + SCROLL_BAR_TOP_INSET))
        scrollBar:SetPoint("BOTTOMLEFT", listViewport, "BOTTOMRIGHT", 0, SCROLL_BAR_BOTTOM_INSET)
    else
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", SCROLL_BAR_RIGHT_OFFSET, -(PAD + SCROLL_BAR_TOP_INSET))
        scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", SCROLL_BAR_RIGHT_OFFSET, SCROLL_BAR_BOTTOM_INSET)
    end
end

function frame:ToggleSummarySettings(_self)
    local showSettings = not summarySettingsPanel:IsShown()
    summarySettingsPanel:SetShown(showSettings)
    if showSettings then
        ApplySummarySettingsPanelLayout()
        btnSummaryRealmText:SetText(REALM_FILTER_LABELS[GetSummarySettings().realmFilter] or "All Characters")
        if summaryCharListRefresh then summaryCharListRefresh() end
    end
    ApplySummaryListLayout()
    UpdateHeaderSortIndicators()
    local sb = GetScrollBar()
    Update(math.floor((sb and sb:GetValue() or 0) / ROW_HEIGHT))
end
ApplySummaryListLayout()

frame:SetScript("OnSizeChanged", function()
    if summarySettingsPanel and summarySettingsPanel:IsShown() then
        ApplySummarySettingsPanelLayout()
    end
    ApplySummaryListLayout()
end)

-- Row pool: parented to scrollFrame so they're clipped and don't show under settings panel
local rowPool = {}
local prevRow = nil
for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, scrollFrame)
    row:SetHeight(ROW_HEIGHT)
    row:SetWidth(totalColWidth)
    if i == 1 then
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, 0)
    end
    row.cells = {}
    local rowCellX = 0
    for _, colName in ipairs(columnOrder) do
        local col = columns[colName]
        local w = col and col.Width or 100
        if colName == "Warning" then
            local warningFrame = CreateFrame("Frame", nil, row)
            warningFrame:SetPoint("LEFT", row, "LEFT", rowCellX, 0)
            warningFrame:SetSize(w, ROW_HEIGHT)
            warningFrame:EnableMouse(true)
            local mark = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            mark:SetText("!")
            mark:SetPoint("CENTER", warningFrame, "CENTER", 0, 0)
            mark:SetTextColor(1, 0.82, 0, 1)
            warningFrame.mark = mark
            mark:Hide()
            warningFrame:SetScript("OnEnter", function(self)
                if self.tooltipTitle and GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(self.tooltipTitle, 1, 1, 1, true)
                    if self.tooltipLines then
                        for _, line in ipairs(self.tooltipLines) do
                            GameTooltip:AddLine(line, 1, 0.82, 0, true)
                        end
                    end
                    GameTooltip:Show()
                end
            end)
            warningFrame:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            row.cells[colName] = warningFrame
        else
            local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetPoint("LEFT", row, "LEFT", rowCellX, 0)
            cell:SetWidth(w)
            cell:SetJustifyH(col and col.JustifyH or "LEFT")
            if colName == "Name" then
                cell:SetWordWrap(false)
            end
            row.cells[colName] = cell
        end
        rowCellX = rowCellX + w
    end
    -- Overlay for Name column so we can show tooltip with full name when truncated
    local nameOverlay = CreateFrame("Frame", nil, row)
    nameOverlay:SetPoint("LEFT", row, "LEFT", 0, 0)
    nameOverlay:SetSize(columns.Name.Width, ROW_HEIGHT)
    nameOverlay:EnableMouse(true)
    nameOverlay:SetScript("OnEnter", function(self)
        if self.fullNameDisplay and self.wasTruncated and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.fullNameDisplay, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    nameOverlay:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.nameOverlay = nameOverlay
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
    local rawList = AltArmy.Characters and AltArmy.Characters.GetList and AltArmy.Characters:GetList() or {}
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    local RF = AltArmy.RealmFilter
    local filtered
    if RF and RF.filterListByRealm then
        filtered = RF.filterListByRealm(rawList, GetSummarySettings().realmFilter or "all", currentRealm)
    else
        filtered = rawList
    end
    -- Filter hidden; order: pinned first (keep sort), then non-pinned
    local list = {}
    local pinned, rest = {}, {}
    for i = 1, #filtered do
        local e = filtered[i]
        if not GetSummaryCharSetting(e.name, e.realm, "hide") then
            if GetSummaryCharSetting(e.name, e.realm, "pin") then
                pinned[#pinned + 1] = e
            else
                rest[#rest + 1] = e
            end
        end
    end
    for i = 1, #pinned do list[#list + 1] = pinned[i] end
    for i = 1, #rest do list[#list + 1] = rest[i] end
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
        local val = sb:GetValue()
        if val > maxScroll then
            sb:SetValue(maxScroll)
            scrollFrame:SetVerticalScroll(maxScroll)
        end
    end

    -- Horizontal scroll: list viewport may be narrower than totalColWidth (e.g. when settings panel is open)
    if listViewport and horizontalScroll and horizontalScrollChild and horizontalScrollBar then
        local vw = listViewport:GetWidth()
        if vw and vw > 0 then
            horizontalScrollChild:SetWidth(totalColWidth)
            local vh = listViewport:GetHeight()
            if not vh or vh <= 0 then
                vh = HEADER_HEIGHT + scrollFrame:GetHeight() + TOTALS_ROW_HEIGHT
            end
            horizontalScrollChild:SetHeight(vh)
            local maxHorzScroll = math.max(0, totalColWidth - vw)
            horizontalScrollBar:SetMinMaxValues(0, maxHorzScroll)
            horizontalScrollBar:SetValueStep(1)
            horizontalScrollBar:SetShown(maxHorzScroll > 0)
            local hVal = horizontalScrollBar:GetValue()
            if hVal > maxHorzScroll then
                horizontalScrollBar:SetValue(maxHorzScroll)
                ApplySummaryHorizontalScrollValue(maxHorzScroll)
            else
                SyncSummaryHorizontalScrollPosition()
            end
        end
    end

    for i = 1, NUM_ROWS do
        local rowFrame = GetRow(i)
        local j = offset + i
        if j <= numItems then
            local entry = list[j]
            for _, colName in ipairs(columnOrder) do
                local col = columns[colName]
                local cell = rowFrame.cells[colName]
                if colName == "Warning" then
                    local info = { hasMissing = false, instructions = {} }
                    if SD and SD.GetMissingDataInfo then
                        local result = SD.GetMissingDataInfo(entry.name, entry.realm)
                        if result then info = result end
                    end
                    if info.hasMissing and cell and cell.mark then
                        cell.mark:Show()
                        local name = entry.name or ""
                        local r, g, b = 1, 0.82, 0
                        if entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
                            local c = RAID_CLASS_COLORS[entry.classFile]
                            r, g, b = c.r, c.g, c.b
                        end
                        local hex = string.format("|cFF%02x%02x%02x",
                            math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
                        local titlePrefix = "Some data for " .. hex .. name .. "|r"
                        cell.tooltipTitle = titlePrefix .. " has not been gathered yet."
                        cell.tooltipLines = info.instructions
                    else
                        if cell then
                            if cell.mark then cell.mark:Hide() end
                            cell.tooltipTitle = nil
                            cell.tooltipLines = nil
                        end
                    end
                elseif cell and col and col.GetText then
                    if colName == "Name" then
                        local showRealmSuffix = (GetSummarySettings().realmFilter == "all")
                            and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(list)
                        local nameDisplayStr
                        if showRealmSuffix and RF.formatCharacterDisplayNameColored
                            and RF.formatCharacterDisplayName then
                            local r, g, b = 1, 0.82, 0
                            if entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
                                local c = RAID_CLASS_COLORS[entry.classFile]
                                r, g, b = c.r, c.g, c.b
                            end
                            local dispName = RF.formatCharacterDisplayName(entry.name or "", entry.realm, true)
                            nameDisplayStr = RF.formatCharacterDisplayNameColored(dispName, nil, false, r, g, b)
                            cell:SetText(nameDisplayStr)
                        else
                            nameDisplayStr = col.GetText(entry)
                            cell:SetText(nameDisplayStr)
                            local classFile = entry.classFile
                            if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
                                local c = RAID_CLASS_COLORS[classFile]
                                cell:SetTextColor(c.r, c.g, c.b, 1)
                            else
                                cell:SetTextColor(1, 0.82, 0, 1)
                            end
                        end
                        local nameW = columns.Name and columns.Name.Width or (129 - WARNING_COL_WIDTH)
                        local wasTruncated = TruncateName(cell, nameDisplayStr, nameW - 2)
                        local overlay = rowFrame.nameOverlay
                        if overlay then
                            overlay.fullNameDisplay = nameDisplayStr
                            overlay.wasTruncated = wasTruncated
                        end
                    else
                        cell:SetText(col.GetText(entry))
                    end
                end
            end
            rowFrame:Show()
        else
            local warningCell = rowFrame.cells and rowFrame.cells["Warning"]
            if warningCell then
                if warningCell.mark then warningCell.mark:Hide() end
                warningCell.tooltipTitle = nil
                warningCell.tooltipLines = nil
            end
            if rowFrame.nameOverlay then
                rowFrame.nameOverlay.fullNameDisplay = nil
                rowFrame.nameOverlay.wasTruncated = nil
            end
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
end

-- When scroll bar moves, recompute offset (row index) and refresh rows
scrollFrame:SetScript("OnVerticalScroll", function(_self, scrollOffset)
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
