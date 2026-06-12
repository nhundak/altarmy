-- AltArmy TBC — Progression tab: time-per-level multi-character line graph.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Progression
if not frame then return end

local LPD = AltArmy.LevelProgressData
local Core = AltArmy.GraphCore
local Logic = AltArmy.ProgressionGraphLogic
local Theme = AltArmy.Theme

local SELECTOR_WIDTH = 150
local SELECTOR_SCROLLBAR_WIDTH = 14
local X_LEVEL_LABEL_INTERVAL = 10
local OPTIONS_PANEL_HEIGHT = 64
local OPTIONS_PANEL_GAP = 4
local ROW_HEIGHT = 20
local OUTLIER_INFO_ICON_SIZE = 14
local SECTION_HEADER_HEIGHT = 18
local INSUFFICIENT_SECTION_GAP = 10
local LINE_THICKNESS = 2
local DASH_THICKNESS = 1
local MARKER_HIT_SIZE = 18
local MARKER_DOT_SIZE = 4
local FULL_LINE_ALPHA = Logic.FULL_LINE_ALPHA
local FULL_DASH_ALPHA = Logic.FULL_DASH_ALPHA
local DIM_LINE_ALPHA = Logic.DIM_LINE_ALPHA
local DIM_DASH_ALPHA = Logic.DIM_DASH_ALPHA

AltArmyTBC_ProgressionSettings = AltArmyTBC_ProgressionSettings or {}

local RF = AltArmy.RealmFilter
local hoveredCompareEntry = nil

local currentX, currentY = nil, nil
local currentRawYMax = 0
local currentRawYMin = 0
local currentLogAxisYMin = nil
local drawnKeys = {}
local seriesGroups = {}

local markerDotPool = { free = {} }
local markerHitPool = { free = {} }
local hoveredLogarithmicPreview = false
local hoveredOutliersPreview = false
local hoveredRollingAveragePreview = false
local suppressLogarithmicHoverPreview = false
local suppressOutliersHoverPreview = false
local suppressRollingAverageHoverPreview = false

local RebuildGraph
local ApplyHighlight
local HandleCompareRowEnter
local HandleCompareRowLeave
local UpdateSelectAllCheckbox

local function CharKey(realm, name)
    return (realm or "") .. "\\" .. (name or "")
end

local function EnsureSettings()
    AltArmyTBC_ProgressionSettings.selected = AltArmyTBC_ProgressionSettings.selected or {}
    if AltArmyTBC_ProgressionSettings.logarithmic == nil then
        AltArmyTBC_ProgressionSettings.logarithmic = false
    end
    if AltArmyTBC_ProgressionSettings.ignoreOutliers == nil then
        AltArmyTBC_ProgressionSettings.ignoreOutliers = false
    end
    if AltArmyTBC_ProgressionSettings.rollingAverage == nil then
        AltArmyTBC_ProgressionSettings.rollingAverage = false
    end
    return AltArmyTBC_ProgressionSettings
end

local function IsLogarithmic()
    if hoveredLogarithmicPreview and not suppressLogarithmicHoverPreview then
        return true
    end
    return EnsureSettings().logarithmic == true
end

local function IsIgnoreOutliers()
    if hoveredOutliersPreview and not suppressOutliersHoverPreview then
        return true
    end
    return EnsureSettings().ignoreOutliers == true
end

local function IsRollingAverage()
    if hoveredRollingAveragePreview and not suppressRollingAverageHoverPreview then
        return true
    end
    return EnsureSettings().rollingAverage == true
end

local function WireOptionRowCheck(getSaved, setSaved, clearHoverPreview, setHoverSuppress)
    return function(self)
        local wasChecked = getSaved() == true
        local nowChecked = self:GetChecked() and true or false
        setSaved(nowChecked)
        if wasChecked and not nowChecked then
            clearHoverPreview()
            setHoverSuppress(true)
        end
        RebuildGraph()
    end
end

local function IsSelected(realm, name)
    local s = EnsureSettings()
    return s.selected[CharKey(realm, name)] == true
end

local function SetSelected(realm, name, on)
    local s = EnsureSettings()
    if on then
        s.selected[CharKey(realm, name)] = true
    else
        s.selected[CharKey(realm, name)] = nil
    end
end

local function GetRealmFilterValue()
    local GRF = AltArmy.GlobalRealmFilter
    if GRF and GRF.Get then
        return GRF.Get()
    end
    return "currentRealm"
end

local function ApplyRealmFilter(list)
    if not list then return {} end
    if not RF or not RF.filterListByRealm then return list end
    local currentRealm = (GetRealmName and GetRealmName()) or ""
    return RF.filterListByRealm(list, GetRealmFilterValue(), currentRealm)
end

local function GetSelectedCharacters()
    local out = {}
    if not LPD or not LPD.GetCharactersWithHistory then return out end
    for _, entry in ipairs(ApplyRealmFilter(LPD.GetCharactersWithHistory())) do
        if IsSelected(entry.realm, entry.name) then
            out[#out + 1] = entry
        end
    end
    return out
end

local function EntryKey(entry)
    if not entry then return "" end
    return CharKey(entry.realm, entry.name)
end

local function GetCharactersToDraw()
    local out = {}
    local seen = {}

    for _, entry in ipairs(GetSelectedCharacters()) do
        local key = EntryKey(entry)
        if not seen[key] then
            out[#out + 1] = entry
            seen[key] = true
        end
    end

    if hoveredCompareEntry then
        local key = EntryKey(hoveredCompareEntry)
        if not seen[key] then
            out[#out + 1] = hoveredCompareEntry
            seen[key] = true
        end
    end

    return out
end

local function SetRowHoverHighlight(row, on)
    Theme.SetHoverTint(row, on)
end

local function BindCompareRowHover(row, entry)
    local function onEnter()
        HandleCompareRowEnter(row, entry)
    end

    local function onLeave()
        HandleCompareRowLeave(row, entry)
    end

    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row.check:SetScript("OnEnter", onEnter)
    row.check:SetScript("OnLeave", onLeave)
    if row.nameButton then
        row.nameButton:SetScript("OnEnter", onEnter)
        row.nameButton:SetScript("OnLeave", onLeave)
    end
end

local function OnCompareRowUnchecked(row, entry)
    if hoveredCompareEntry and EntryKey(hoveredCompareEntry) == EntryKey(entry) then
        hoveredCompareEntry = nil
    end
    row.suppressHoverPreview = true
end

local function ToggleCompareSelection(row, entry)
    local wasChecked = IsSelected(entry.realm, entry.name)
    local checked = not wasChecked
    row.check:SetChecked(checked)
    SetSelected(entry.realm, entry.name, checked)
    if wasChecked and not checked then
        OnCompareRowUnchecked(row, entry)
    end
    if UpdateSelectAllCheckbox then
        UpdateSelectAllCheckbox()
    end
    RebuildGraph()
end

-- Layout: graph (left) + selector (right)
local graphFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
graphFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
graphFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
graphFrame:SetPoint("RIGHT", frame, "RIGHT", -SELECTOR_WIDTH - 4, 0)
Theme.ApplyBackdrop(graphFrame, "graph")
graphFrame:EnableMouse(false)

local HINT_SELECT_CHARACTERS = "Select one or more characters on the right\nto compare time per level."
local HINT_LEVEL_UP_PROGRESSION =
    "As you level up your characters\nthis page will display graphs of their progression"
local HINT_NO_HISTORY = "No level history yet.\nLevel up characters while\nlevel history is enabled."

local graphHint = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
graphHint:SetPoint("CENTER", graphFrame, "CENTER", 0, 0)
graphHint:SetWidth(graphFrame:GetWidth() - 40)
graphHint:SetText(HINT_SELECT_CHARACTERS)
graphHint:SetJustifyH("CENTER")

local function UpdateEmptyGraphHint()
    if not LPD or not LPD.GetCharactersWithHistory then return end

    local list = ApplyRealmFilter(LPD.GetCharactersWithHistory())
    local insufficientList = {}
    if LPD.GetCharactersWithInsufficientHistory then
        insufficientList = ApplyRealmFilter(LPD.GetCharactersWithInsufficientHistory())
    end

    if #list == 0 and #insufficientList == 0 then
        graphHint:SetText(HINT_NO_HISTORY)
    elseif #list == 0 then
        graphHint:SetText(HINT_LEVEL_UP_PROGRESSION)
    else
        graphHint:SetText(HINT_SELECT_CHARACTERS)
    end
end

-- Options panel (top right)
local optionsPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
optionsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
optionsPanel:SetSize(SELECTOR_WIDTH, OPTIONS_PANEL_HEIGHT)
Theme.ApplyBackdrop(optionsPanel, "section")

local function CreateOptionRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)
    row:EnableMouse(true)

    Theme.InstallHoverTint(row)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.check:SetSize(18, 18)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    return row
end

local logRow = CreateOptionRow(optionsPanel)
logRow:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 6, -6)
logRow:SetPoint("RIGHT", optionsPanel, "RIGHT", -6, 0)
logRow.label:SetText("Logarithmic")
logRow.check:SetChecked(EnsureSettings().logarithmic == true)
logRow.check:SetScript("OnClick", WireOptionRowCheck(
    function() return EnsureSettings().logarithmic end,
    function(v) EnsureSettings().logarithmic = v end,
    function() hoveredLogarithmicPreview = false end,
    function() suppressLogarithmicHoverPreview = true end
))

local outlierRow = CreateOptionRow(optionsPanel)
outlierRow:SetPoint("TOPLEFT", logRow, "BOTTOMLEFT", 0, 0)
outlierRow:SetPoint("RIGHT", optionsPanel, "RIGHT", -6, 0)
outlierRow.label:SetText("Shrink Outliers")
outlierRow.infoIcon = outlierRow:CreateTexture(nil, "ARTWORK")
outlierRow.infoIcon:SetTexture("Interface\\Common\\help-i")
outlierRow.infoIcon:SetSize(OUTLIER_INFO_ICON_SIZE, OUTLIER_INFO_ICON_SIZE)
outlierRow.infoIcon:SetPoint("RIGHT", outlierRow, "RIGHT", 0, 0)
outlierRow.label:ClearAllPoints()
outlierRow.label:SetPoint("LEFT", outlierRow.check, "RIGHT", 2, 0)
outlierRow.label:SetPoint("RIGHT", outlierRow.infoIcon, "LEFT", -4, 0)
outlierRow.check:SetChecked(EnsureSettings().ignoreOutliers == true)
outlierRow.check:SetScript("OnClick", WireOptionRowCheck(
    function() return EnsureSettings().ignoreOutliers end,
    function(v) EnsureSettings().ignoreOutliers = v end,
    function() hoveredOutliersPreview = false end,
    function() suppressOutliersHoverPreview = true end
))

local rollingAverageRow = CreateOptionRow(optionsPanel)
rollingAverageRow:SetPoint("TOPLEFT", outlierRow, "BOTTOMLEFT", 0, 0)
rollingAverageRow:SetPoint("RIGHT", optionsPanel, "RIGHT", -6, 0)
rollingAverageRow.label:SetText("Rolling Average")
rollingAverageRow.check:SetChecked(EnsureSettings().rollingAverage == true)
rollingAverageRow.check:SetScript("OnClick", WireOptionRowCheck(
    function() return EnsureSettings().rollingAverage end,
    function(v) EnsureSettings().rollingAverage = v end,
    function() hoveredRollingAveragePreview = false end,
    function() suppressRollingAverageHoverPreview = true end
))

-- Selector panel
local selectorPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
selectorPanel:SetPoint("TOPRIGHT", optionsPanel, "BOTTOMRIGHT", 0, -OPTIONS_PANEL_GAP)
selectorPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
selectorPanel:SetWidth(SELECTOR_WIDTH)
Theme.ApplyBackdrop(selectorPanel, "section")

local selectorTitle = selectorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
selectorTitle:SetPoint("TOPLEFT", selectorPanel, "TOPLEFT", 8, -8)
selectorTitle:SetText("Compare")
Theme.SetTitleColor(selectorTitle)

local selectorScroll = CreateFrame("ScrollFrame", nil, selectorPanel)
selectorScroll:SetPoint("TOPLEFT", selectorTitle, "BOTTOMLEFT", 0, -6)
selectorScroll:SetPoint("BOTTOMRIGHT", selectorPanel, "BOTTOMRIGHT", -(SELECTOR_SCROLLBAR_WIDTH + 6), 4)
selectorScroll:EnableMouse(true)
selectorScroll:EnableMouseWheel(true)

local selectorChild = CreateFrame("Frame", nil, selectorScroll)
selectorChild:SetPoint("TOPLEFT", selectorScroll, "TOPLEFT", 0, 0)
selectorChild:SetWidth(1)
selectorScroll:SetScrollChild(selectorChild)

local selectorScrollBar = CreateFrame("Slider", nil, selectorPanel)
selectorScrollBar:SetOrientation("VERTICAL")
selectorScrollBar:SetPoint("TOPRIGHT", selectorScroll, "TOPRIGHT", SELECTOR_SCROLLBAR_WIDTH + 2, 0)
selectorScrollBar:SetPoint("BOTTOMRIGHT", selectorScroll, "BOTTOMRIGHT", SELECTOR_SCROLLBAR_WIDTH + 2, 0)
selectorScrollBar:SetWidth(SELECTOR_SCROLLBAR_WIDTH)
selectorScrollBar:SetMinMaxValues(0, 0)
selectorScrollBar:SetValueStep(ROW_HEIGHT)
selectorScrollBar:SetValue(0)
selectorScrollBar:EnableMouse(true)

local selectorScrollBarBg = selectorScrollBar:CreateTexture(nil, "BACKGROUND")
selectorScrollBarBg:SetAllPoints(selectorScrollBar)
Theme.StyleScrollTrack(selectorScrollBarBg)

local selectorScrollBarThumb = selectorScrollBar:CreateTexture(nil, "OVERLAY")
selectorScrollBarThumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
selectorScrollBarThumb:SetSize(SELECTOR_SCROLLBAR_WIDTH + 4, 24)
selectorScrollBar:SetThumbTexture(selectorScrollBarThumb)

local function UpdateSelectorScrollbar()
    local maxScroll = math.max(0, selectorChild:GetHeight() - selectorScroll:GetHeight())
    local prevScroll = selectorScrollBar:GetValue()
    selectorScrollBar:SetMinMaxValues(0, maxScroll)
    local newScroll = math.min(prevScroll, maxScroll)
    selectorScrollBar:SetValue(newScroll)
    selectorScroll:SetVerticalScroll(newScroll)
    selectorScrollBar:SetShown(maxScroll > 0)
end

selectorScrollBar:SetScript("OnValueChanged", function(_, value)
    selectorScroll:SetVerticalScroll(value)
end)

local function OnSelectorScrollWheel(_, delta)
    local cur = selectorScrollBar:GetValue()
    local lo, hi = selectorScrollBar:GetMinMaxValues()
    selectorScrollBar:SetValue(math.max(lo, math.min(hi, cur - delta * ROW_HEIGHT * 2)))
end
selectorScroll:SetScript("OnMouseWheel", OnSelectorScrollWheel)
selectorChild:SetScript("OnMouseWheel", OnSelectorScrollWheel)

local selectorRows = {}
local insufficientRows = {}
local selectAllRow = nil

local insufficientHeader = selectorChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
insufficientHeader:SetText("Not enough data:")
insufficientHeader:Hide()

local function UpdateSelectorLayout(hasCompareSection)
    if hasCompareSection then
        selectorTitle:Show()
        selectorScroll:ClearAllPoints()
        selectorScroll:SetPoint("TOPLEFT", selectorTitle, "BOTTOMLEFT", 0, -6)
        selectorScroll:SetPoint("BOTTOMRIGHT", selectorPanel, "BOTTOMRIGHT", -(SELECTOR_SCROLLBAR_WIDTH + 6), 4)
    else
        selectorTitle:Hide()
        selectorScroll:ClearAllPoints()
        selectorScroll:SetPoint("TOPLEFT", selectorPanel, "TOPLEFT", 4, -8)
        selectorScroll:SetPoint("BOTTOMRIGHT", selectorPanel, "BOTTOMRIGHT", -(SELECTOR_SCROLLBAR_WIDTH + 6), 4)
    end
    selectorScrollBar:ClearAllPoints()
    selectorScrollBar:SetPoint("TOPRIGHT", selectorScroll, "TOPRIGHT", SELECTOR_SCROLLBAR_WIDTH + 2, 0)
    selectorScrollBar:SetPoint("BOTTOMRIGHT", selectorScroll, "BOTTOMRIGHT", SELECTOR_SCROLLBAR_WIDTH + 2, 0)
end

local function PositionListRow(row, yOffset)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", selectorChild, "TOPLEFT", 0, -yOffset)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("RIGHT", selectorChild, "RIGHT", 0, 0)
end

local function GetSelectorRow(i)
    if not selectorRows[i] then
        local row = CreateFrame("Frame", nil, selectorChild)
        row:EnableMouse(true)

        Theme.InstallHoverTint(row)

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.check:SetSize(18, 18)

        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(10, 10)
        row.swatch:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.swatch:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.swatch, "RIGHT", 4, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        row.nameButton = CreateFrame("Button", nil, row)
        row.nameButton:SetPoint("TOPLEFT", row.swatch, "TOPLEFT", -2, 0)
        row.nameButton:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
        row.nameButton:SetFrameLevel(row:GetFrameLevel() + 2)
        row.nameButton:RegisterForClicks("LeftButtonUp")

        selectorRows[i] = row
    end
    return selectorRows[i]
end

local function GetInsufficientRow(i)
    if not insufficientRows[i] then
        local row = CreateFrame("Frame", nil, selectorChild)

        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(10, 10)
        row.swatch:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.swatch:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.label:SetPoint("LEFT", row.swatch, "RIGHT", 4, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        insufficientRows[i] = row
    end
    return insufficientRows[i]
end

local function GetCompareList()
    if not LPD or not LPD.GetCharactersWithHistory then return {} end
    return ApplyRealmFilter(LPD.GetCharactersWithHistory())
end

local function CountCompareSelected(list)
    local count = 0
    for _, entry in ipairs(list) do
        if IsSelected(entry.realm, entry.name) then
            count = count + 1
        end
    end
    return count
end

local function AreAllCompareSelected()
    local list = GetCompareList()
    return Logic.IsCompareSelectAllChecked(#list, CountCompareSelected(list))
end

local function SetAllCompareSelected(selectAll)
    for _, entry in ipairs(GetCompareList()) do
        SetSelected(entry.realm, entry.name, selectAll)
    end
end

local function EnsureSelectAllRow()
    if selectAllRow then
        return selectAllRow
    end

    selectAllRow = CreateFrame("Frame", nil, selectorChild)
    selectAllRow:EnableMouse(true)

    selectAllRow.check = CreateFrame("CheckButton", nil, selectAllRow, "UICheckButtonTemplate")
    selectAllRow.check:SetPoint("LEFT", selectAllRow, "LEFT", 2, 0)
    selectAllRow.check:SetSize(18, 18)

    selectAllRow.label = selectAllRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectAllRow.label:SetPoint("LEFT", selectAllRow.check, "RIGHT", 2, 0)
    selectAllRow.label:SetPoint("RIGHT", selectAllRow, "RIGHT", -2, 0)
    selectAllRow.label:SetJustifyH("LEFT")
    selectAllRow.label:SetWordWrap(false)
    selectAllRow.label:SetText("All")

    selectAllRow.labelButton = CreateFrame("Button", nil, selectAllRow)
    selectAllRow.labelButton:SetPoint("TOPLEFT", selectAllRow.label, "TOPLEFT", -2, 0)
    selectAllRow.labelButton:SetPoint("BOTTOMRIGHT", selectAllRow, "BOTTOMRIGHT", -2, 0)
    selectAllRow.labelButton:SetFrameLevel(selectAllRow:GetFrameLevel() + 2)
    selectAllRow.labelButton:RegisterForClicks("LeftButtonUp")
    selectAllRow.labelButton:SetScript("OnClick", function()
        selectAllRow.check:Click()
    end)

    selectAllRow.check:SetScript("OnClick", function(self)
        local wasSelectAll = AreAllCompareSelected()
        local selectAll = Logic.GetCompareSelectAllAction(wasSelectAll)
        SetAllCompareSelected(selectAll)
        self:SetChecked(selectAll)
        for _, row in ipairs(selectorRows) do
            if row:IsShown() and row.entry then
                row.check:SetChecked(selectAll)
            end
        end
        if wasSelectAll and not selectAll and hoveredCompareEntry then
            local hoverKey = EntryKey(hoveredCompareEntry)
            hoveredCompareEntry = nil
            for _, row in ipairs(selectorRows) do
                if row:IsShown() and row.entry and EntryKey(row.entry) == hoverKey then
                    row.suppressHoverPreview = true
                    break
                end
            end
        end
        RebuildGraph()
    end)

    return selectAllRow
end

UpdateSelectAllCheckbox = function()
    if selectAllRow and selectAllRow:IsShown() then
        selectAllRow.check:SetChecked(AreAllCompareSelected())
    end
end

local function FormatDurationUnit(value, singular, plural)
    if value == 1 then
        return "1 " .. singular
    end
    return string.format("%d %s", value, plural)
end

local function FormatDurationPrecise(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    if seconds <= 0 then
        return "0 seconds"
    end

    local days = math.floor(seconds / 86400)
    local rem = seconds % 86400
    local hours = math.floor(rem / 3600)
    rem = rem % 3600
    local minutes = math.floor(rem / 60)
    local secs = rem % 60

    local parts = {}
    if days > 0 then
        parts[#parts + 1] = FormatDurationUnit(days, "day", "days")
    end
    if hours > 0 then
        parts[#parts + 1] = FormatDurationUnit(hours, "hour", "hours")
    end
    if minutes > 0 then
        parts[#parts + 1] = FormatDurationUnit(minutes, "minute", "minutes")
    end
    if secs > 0 and days == 0 and hours == 0 then
        parts[#parts + 1] = FormatDurationUnit(secs, "second", "seconds")
    end

    if #parts == 0 then
        return "0 seconds"
    end
    return table.concat(parts, " ")
end

local function FormatTooltipTitle(entry)
    local name = (entry and entry.name) or "?"
    local realm = entry and entry.realm
    local classFile = entry and entry.classFile
    if RF and RF.formatColoredCharacterNameRealm then
        return RF.formatColoredCharacterNameRealm(name, realm, true, classFile)
    end
    if realm and realm ~= "" then
        return name .. " — " .. realm
    end
    return name
end

local function ShowSegmentTooltip(owner, entry, fromLevel, toLevel, totalSeconds, perLevelSeconds)
    if not GameTooltip or not owner then return end

    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(FormatTooltipTitle(entry), 1, 1, 1, true)
    GameTooltip:AddLine(string.format("Level %d-%d", fromLevel, toLevel), 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(FormatDurationPrecise(totalSeconds), 0.9, 0.9, 0.9, true)
    local levelSpan = toLevel - fromLevel
    if levelSpan > 1 then
        local perLevel = perLevelSeconds or (totalSeconds / levelSpan)
        GameTooltip:AddLine(
            string.format("(%s per level)", FormatDurationPrecise(perLevel)),
            0.9, 0.9, 0.9, true
        )
    end
    GameTooltip:Show()
end

local function ShowOutlierOptionTooltip(owner)
    if not GameTooltip or not owner then return end

    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Shrink Outliers", 1, 1, 1, true)
    GameTooltip:AddLine(
        "Extremely long times are artificially shifted down so you can see more details on the other levels.",
        0.9, 0.9, 0.9, true
    )
    GameTooltip:AddLine(
        "For example, if your character sat at level 60 for several days, "
            .. "the graph can be hard to read unless you turn this feature on.",
        0.9, 0.9, 0.9, true
    )
    GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
    GameTooltip:Show()
end

local function HideOutlierOptionTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function ReleaseMarkerDot(dot)
    if not dot then return end
    dot:Hide()
    table.insert(markerDotPool.free, dot)
end

local function ReleaseMarkerHit(hf)
    if not hf then return end
    hf:Hide()
    hf:SetScript("OnEnter", nil)
    hf:SetScript("OnLeave", nil)
    table.insert(markerHitPool.free, hf)
end

local function AcquireMarkerDot(r, g, b, alpha, px, py)
    local dot = table.remove(markerDotPool.free)
    if not dot then
        dot = graphFrame:CreateTexture(nil, "OVERLAY")
    end
    dot:ClearAllPoints()
    dot:SetColorTexture(r, g, b, alpha or 1)
    dot:SetSize(MARKER_DOT_SIZE, MARKER_DOT_SIZE)
    dot:SetPoint("CENTER", graphFrame, "BOTTOMLEFT", px, py)
    dot:Show()
    return dot
end

local function AcquireMarkerHit(px, py)
    local hf = table.remove(markerHitPool.free)
    if not hf then
        hf = CreateFrame("Frame", nil, graphFrame)
        hf:EnableMouse(true)
        hf:SetFrameLevel(graphFrame:GetFrameLevel() + 50)
    end
    hf:ClearAllPoints()
    hf:SetSize(MARKER_HIT_SIZE, MARKER_HIT_SIZE)
    hf:SetPoint("CENTER", graphFrame, "BOTTOMLEFT", px, py)
    hf:Show()
    return hf
end

local function AddStyledObject(group, obj, r, g, b, fullAlpha, dimAlpha, useColorTexture)
    group.objects[#group.objects + 1] = {
        obj = obj,
        r = r,
        g = g,
        b = b,
        fullAlpha = fullAlpha,
        dimAlpha = dimAlpha,
        useColorTexture = useColorTexture,
    }
end

local function ApplyObjectAlpha(styled, dimOthers, isHovered)
    local alpha = dimOthers and (isHovered and styled.fullAlpha or styled.dimAlpha) or styled.fullAlpha
    if styled.useColorTexture then
        styled.obj:SetColorTexture(styled.r, styled.g, styled.b, alpha)
    else
        styled.obj:SetVertexColor(styled.r, styled.g, styled.b, alpha)
    end
end

local function TrackNewCoreObjects(group, r, g, b, fullAlpha, dimAlpha, lineCountBefore, texCountBefore)
    for i = lineCountBefore + 1, #Core.graphLines do
        AddStyledObject(group, Core.graphLines[i], r, g, b, fullAlpha, dimAlpha)
    end
    for i = texCountBefore + 1, #Core.graphTextures do
        AddStyledObject(group, Core.graphTextures[i], r, g, b, fullAlpha, dimAlpha)
    end
end

local function AddSegmentMarker(group, px, py, r, g, b, alpha, entry, pt)
    local dot = AcquireMarkerDot(r, g, b, alpha, px, py)
    group.markerDots[#group.markerDots + 1] = dot
    AddStyledObject(group, dot, r, g, b, FULL_LINE_ALPHA, DIM_LINE_ALPHA, true)

    local hf = AcquireMarkerHit(px, py)
    group.markerHits[#group.markerHits + 1] = hf

    hf:SetScript("OnEnter", function(self)
        dot:SetSize(MARKER_DOT_SIZE + 3, MARKER_DOT_SIZE + 3)
        ShowSegmentTooltip(self, entry, pt.fromLevel, pt.toLevel, pt.totalSeconds, pt.seconds)
    end)
    hf:SetScript("OnLeave", function()
        dot:SetSize(MARKER_DOT_SIZE, MARKER_DOT_SIZE)
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function ReleaseSeriesGroupResources(group)
    if not group then return end
    for _, styled in ipairs(group.objects) do
        Core.ReleaseDrawnObject(styled.obj)
    end
    wipe(group.objects)
    for _, dot in ipairs(group.markerDots) do
        ReleaseMarkerDot(dot)
    end
    wipe(group.markerDots)
    for _, hf in ipairs(group.markerHits) do
        ReleaseMarkerHit(hf)
    end
    wipe(group.markerHits)
end

local function ReleaseAllSeriesGroups()
    for i = #seriesGroups, 1, -1 do
        ReleaseSeriesGroupResources(seriesGroups[i])
    end
    wipe(seriesGroups)
    wipe(drawnKeys)
end

local function GetSeriesSecondsBounds(entry)
    if not LPD or not entry or not Logic then return 0, 0 end
    local series = LPD.GetSeriesForCharacter(entry.name, entry.realm)
    local drawable = LPD.PrepareDrawableSeries(series)
    local marked = Logic.ApplyOutlierFlags(drawable.usable, IsIgnoreOutliers())
    if IsRollingAverage() then
        marked = Logic.ApplyRollingAverage(
            marked,
            Logic.ROLLING_AVERAGE_WINDOW,
            IsIgnoreOutliers()
        )
    end
    return Logic.GetSeriesScaleBounds(marked, true)
end

local function PrepareCharGraphData(entry, drawable)
    local ignoreOutliers = IsIgnoreOutliers()
    local markedPoints = Logic.ApplyOutlierFlags(drawable.usable, ignoreOutliers)
    if IsRollingAverage() then
        markedPoints = Logic.ApplyRollingAverage(
            markedPoints,
            Logic.ROLLING_AVERAGE_WINDOW,
            ignoreOutliers
        )
    end
    local drawPlan = Logic.BuildSeriesDrawPlan(markedPoints)
    local cr, cg, cb = LPD.GetClassColor(entry.classFile)
    return {
        entry = entry,
        drawable = drawable,
        markedPoints = markedPoints,
        drawPlan = drawPlan,
        r = cr,
        g = cg,
        b = cb,
    }
end

local function DrawLineSegment(group, x1, y1, x2, y2, style, r, g, b)
    if style == "dashed" then
        local lineCountBefore = #Core.graphLines
        local texCountBefore = #Core.graphTextures
        Core.CreateDashedLine(graphFrame, x1, y1, x2, y2, DASH_THICKNESS, r, g, b, FULL_DASH_ALPHA)
        TrackNewCoreObjects(group, r, g, b, FULL_DASH_ALPHA, DIM_DASH_ALPHA, lineCountBefore, texCountBefore)
    else
        local line = Core.CreateLine(graphFrame, x1, y1, x2, y2, LINE_THICKNESS, r, g, b, FULL_LINE_ALPHA)
        AddStyledObject(group, line, r, g, b, FULL_LINE_ALPHA, DIM_LINE_ALPHA)
    end
end

local function DrawLeadingGap(group, gap, endPt, X, Y, logarithmic, r, g, b)
    local x, y = X(endPt.level), Y(endPt.seconds)
    local lineCountBefore = #Core.graphLines
    local texCountBefore = #Core.graphTextures
    if logarithmic then
        local samples = Logic.SampleLeadingGapCurve(gap, endPt, nil, currentLogAxisYMin)
        local screenPoints = {}
        for _, sample in ipairs(samples) do
            screenPoints[#screenPoints + 1] = {
                x = X(sample.level),
                y = Y(sample.seconds),
            }
        end
        Core.CreateDashedPolyline(graphFrame, screenPoints, DASH_THICKNESS, r, g, b, FULL_DASH_ALPHA)
    else
        local gx1, gy1 = X(gap.fromLevel), Y(0)
        Core.CreateDashedLine(graphFrame, gx1, gy1, x, y, DASH_THICKNESS, r, g, b, FULL_DASH_ALPHA)
    end
    TrackNewCoreObjects(group, r, g, b, FULL_DASH_ALPHA, DIM_DASH_ALPHA, lineCountBefore, texCountBefore)
end

local function PlotSeriesPoint(pt, X, Y, plotTopY)
    return Logic.PlotSeriesPoint(pt, X(pt.level), Y(pt.seconds), plotTopY)
end

local function DrawSeriesGroup(charData, X, Y, logarithmic, plotH)
    local group = {
        key = EntryKey(charData.entry),
        entry = charData.entry,
        objects = {},
        markerDots = {},
        markerHits = {},
    }
    local drawable = charData.drawable
    local drawPlan = charData.drawPlan
    local r, g, b = charData.r, charData.g, charData.b
    local entry = charData.entry
    local firstMarker = drawPlan.markers[1]
    local plotTopY = Logic.ComputePlotTopY(plotH, Core.PADDING)

    if drawable.leadingGap and firstMarker then
        DrawLeadingGap(group, drawable.leadingGap, firstMarker.pt, X, Y, logarithmic, r, g, b)
    end

    for _, seg in ipairs(drawPlan.segments) do
        local x1, y1 = PlotSeriesPoint(seg.from, X, Y, plotTopY)
        local x2, y2 = PlotSeriesPoint(seg.to, X, Y, plotTopY)
        DrawLineSegment(group, x1, y1, x2, y2, seg.style, r, g, b)
    end

    if not IsRollingAverage() then
        for _, marker in ipairs(drawPlan.markers) do
            local pt = marker.pt
            local x, y = PlotSeriesPoint(pt, X, Y, plotTopY)
            AddSegmentMarker(group, x, y, r, g, b, FULL_LINE_ALPHA, entry, pt)
        end
    end

    return group
end

local function AddHoveredSeries(entry)
    if not currentX or not currentY or not entry then return end

    local key = EntryKey(entry)
    if drawnKeys[key] then return end

    local series = LPD.GetSeriesForCharacter(entry.name, entry.realm)
    local drawable = LPD.PrepareDrawableSeries(series)
    if #drawable.usable < 1 then return end

    local charData = PrepareCharGraphData(entry, drawable)
    local _, plotH = Core.CalculatePlotDimensions(graphFrame)
    local group = DrawSeriesGroup(charData, currentX, currentY, IsLogarithmic(), plotH)
    drawnKeys[key] = true
    seriesGroups[#seriesGroups + 1] = group
end

ApplyHighlight = function()
    if #seriesGroups == 0 then return end

    local hoverKey = hoveredCompareEntry and EntryKey(hoveredCompareEntry) or nil
    local dimOthers = hoverKey ~= nil

    for _, group in ipairs(seriesGroups) do
        local isHovered = hoverKey and group.key == hoverKey
        for _, styled in ipairs(group.objects) do
            ApplyObjectAlpha(styled, dimOthers, isHovered)
        end
    end
end

RebuildGraph = function()
    if not Core or not LPD or not Logic then return end

    ReleaseAllSeriesGroups()
    Core.ClearObjects()

    currentX, currentY = nil, nil
    currentRawYMax = 0
    currentRawYMin = 0
    currentLogAxisYMin = nil

    local toDraw = GetCharactersToDraw()
    if #toDraw == 0 then
        graphHint:Show()
        UpdateEmptyGraphHint()
        return
    end

    local seriesByChar = {}
    local yMax = 0
    local yMin = math.huge

    for _, entry in ipairs(toDraw) do
        local series = LPD.GetSeriesForCharacter(entry.name, entry.realm)
        local drawable = LPD.PrepareDrawableSeries(series)
        if #drawable.usable >= 1 then
            local charData = PrepareCharGraphData(entry, drawable)
            seriesByChar[#seriesByChar + 1] = charData
            local scaleMin, scaleMax = Logic.GetSeriesScaleBounds(charData.markedPoints, true)
            if scaleMin > 0 and scaleMin < yMin then yMin = scaleMin end
            if scaleMax > yMax then yMax = scaleMax end
        end
    end

    if yMin == math.huge then
        yMin = 0
    end

    if #seriesByChar == 0 then
        graphHint:SetText("Selected characters have no\nusable level history.")
        graphHint:Show()
        return
    end

    graphHint:Hide()

    local xMin, _, xRange = LPD.GetAxisRange()

    currentRawYMax = yMax
    currentRawYMin = yMin
    local logarithmic = IsLogarithmic()
    local linearAxis = Logic.ComputeLinearYAxis(yMax)
    local logAxis = logarithmic and Logic.ComputeLogYAxis(yMax, yMin) or nil
    currentLogAxisYMin = logAxis and logAxis.yMin or nil

    local plotW, plotH = Core.CalculatePlotDimensions(graphFrame)
    if logarithmic and logAxis then
        currentX, currentY = Core.CreateTransformers(plotW, plotH, xMin, xRange, logAxis.yMin, 0, {
            yAxisMode = "log",
            logMin = logAxis.logMin,
            logMax = logAxis.logMax,
        })
    else
        currentX, currentY = Core.CreateTransformers(plotW, plotH, xMin, xRange, linearAxis.yMin, linearAxis.yRange)
    end

    local gridOpts = {
        xInterval = X_LEVEL_LABEL_INTERVAL,
        xMin = xMin,
        xRange = xRange,
    }
    if logarithmic and logAxis then
        gridOpts.logYTicks = logAxis.gridTicks
        gridOpts.logMin = logAxis.logMin
        gridOpts.logMax = logAxis.logMax
    end

    Core.RenderGridLines(graphFrame, plotW, plotH, gridOpts)
    Core.RenderAxes(graphFrame, plotW, plotH)
    Core.RenderYLabels(graphFrame, plotH, linearAxis.yMin, linearAxis.yRange, function(v)
        return Core.FormatDuration(v)
    end, logarithmic and logAxis and gridOpts or nil)
    Core.RenderXLabelsAtInterval(graphFrame, plotW, xMin, xRange, X_LEVEL_LABEL_INTERVAL, function(v)
        return tostring(math.floor(v + 0.5))
    end)

    for _, charData in ipairs(seriesByChar) do
        local group = DrawSeriesGroup(charData, currentX, currentY, logarithmic, plotH)
        drawnKeys[group.key] = true
        seriesGroups[#seriesGroups + 1] = group
    end

    ApplyHighlight()
end

HandleCompareRowEnter = function(row, entry)
    SetRowHoverHighlight(row, true)

    if row.suppressHoverPreview then
        return
    end

    hoveredCompareEntry = entry

    local key = EntryKey(entry)
    if drawnKeys[key] then
        ApplyHighlight()
        return
    end

    if #seriesGroups == 0 then
        RebuildGraph()
        return
    end

    local minSec, maxSec = GetSeriesSecondsBounds(entry)
    if Logic.HoverNeedsRebuild(key, drawnKeys, maxSec, currentRawYMax, minSec, currentRawYMin, IsLogarithmic()) then
        RebuildGraph()
        return
    end

    AddHoveredSeries(entry)
    ApplyHighlight()
end

HandleCompareRowLeave = function(row, entry)
    row.suppressHoverPreview = false
    hoveredCompareEntry = nil
    SetRowHoverHighlight(row, false)

    if IsSelected(entry.realm, entry.name) then
        ApplyHighlight()
        return
    end

    RebuildGraph()
end

local function FormatCharacterLabel(entry, showRealmSuffix)
    local labelText = entry.name or "?"
    if showRealmSuffix and entry.realm and entry.realm ~= "" then
        labelText = labelText .. "-" .. entry.realm
    end
    return labelText
end

local function RefreshSelector()
    if not LPD or not LPD.GetCharactersWithHistory then return end
    local list = ApplyRealmFilter(LPD.GetCharactersWithHistory())
    local insufficientList = {}
    if LPD.GetCharactersWithInsufficientHistory then
        insufficientList = ApplyRealmFilter(LPD.GetCharactersWithInsufficientHistory())
    end

    for _, row in ipairs(selectorRows) do
        row:Hide()
    end
    for _, row in ipairs(insufficientRows) do
        row:Hide()
    end
    insufficientHeader:Hide()
    UpdateSelectorLayout(#list > 0)

    local scrollW = selectorScroll:GetWidth() or SELECTOR_WIDTH - 12
    selectorChild:SetWidth(scrollW)

    local realmFilter = GetRealmFilterValue()
    local combinedForRealmCheck = {}
    for _, entry in ipairs(list) do combinedForRealmCheck[#combinedForRealmCheck + 1] = entry end
    for _, entry in ipairs(insufficientList) do combinedForRealmCheck[#combinedForRealmCheck + 1] = entry end
    local showRealmSuffix = (realmFilter == "all")
        and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(combinedForRealmCheck)

    local yOffset = 0
    if Logic.ShouldShowCompareSelectAll(#list) then
        local allRow = EnsureSelectAllRow()
        PositionListRow(allRow, yOffset)
        allRow:Show()
        allRow.check:SetChecked(AreAllCompareSelected())
        yOffset = yOffset + ROW_HEIGHT
    elseif selectAllRow then
        selectAllRow:Hide()
    end

    for i, entry in ipairs(list) do
        local row = GetSelectorRow(i)
        PositionListRow(row, yOffset)
        row:Show()
        row.entry = entry

        local r, g, b = LPD.GetClassColor(entry.classFile)
        row.swatch:SetVertexColor(r, g, b, 1)
        row.label:SetText(FormatCharacterLabel(entry, showRealmSuffix))
        row.label:SetTextColor(r, g, b, 1)

        row.check:SetChecked(IsSelected(entry.realm, entry.name))
        row.check:SetScript("OnClick", function(self)
            local wasChecked = IsSelected(entry.realm, entry.name)
            local nowChecked = self:GetChecked() and true or false
            SetSelected(entry.realm, entry.name, nowChecked)
            if wasChecked and not nowChecked then
                OnCompareRowUnchecked(row, entry)
            end
            UpdateSelectAllCheckbox()
            RebuildGraph()
        end)
        row.nameButton:SetScript("OnClick", function()
            ToggleCompareSelection(row, entry)
        end)
        BindCompareRowHover(row, entry)
        SetRowHoverHighlight(row, hoveredCompareEntry and EntryKey(hoveredCompareEntry) == EntryKey(entry))

        yOffset = yOffset + ROW_HEIGHT
    end

    if #insufficientList > 0 then
        if #list > 0 then
            yOffset = yOffset + INSUFFICIENT_SECTION_GAP
        end
        insufficientHeader:ClearAllPoints()
        insufficientHeader:SetPoint("TOPLEFT", selectorChild, "TOPLEFT", 4, -yOffset)
        insufficientHeader:Show()
        yOffset = yOffset + SECTION_HEADER_HEIGHT

        for i, entry in ipairs(insufficientList) do
            local row = GetInsufficientRow(i)
            PositionListRow(row, yOffset)
            row:Show()

            local r, g, b = LPD.GetClassColor(entry.classFile)
            row.swatch:SetVertexColor(r, g, b, 0.45)
            row.label:SetText(FormatCharacterLabel(entry, showRealmSuffix))
            row.label:SetTextColor(r, g, b, 0.55)

            yOffset = yOffset + ROW_HEIGHT
        end
    end

    selectorChild:SetHeight(math.max(1, yOffset))
    UpdateSelectorScrollbar()

    if LPD.DebugLogSelectorEligibility then
        LPD.DebugLogSelectorEligibility()
    end
end

function frame:Redraw()
    RebuildGraph()
end

local function WireOptionLabelClick(row, onEnter, onLeave)
    local check = row.check
    local label = row.label
    local hit = CreateFrame("Button", nil, check)
    hit:SetFrameLevel((check:GetFrameLevel() or 0) + 5)
    hit:EnableMouse(true)
    hit:RegisterForClicks("LeftButtonUp")
    hit:SetScript("OnClick", function()
        if check:IsEnabled() then
            check:Click()
        end
    end)
    hit:SetScript("OnEnter", onEnter)
    hit:SetScript("OnLeave", onLeave)
    hit:SetPoint("TOPLEFT", label, "TOPLEFT", -6, 6)
    hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 6, -6)
end

local function BindOptionRowHover(row, setPreview, getSuppress, clearSuppress, onHoverExtra)
    local function onEnter()
        SetRowHoverHighlight(row, true)
        if onHoverExtra then onHoverExtra(true) end
        if not getSuppress() then
            setPreview(true)
            RebuildGraph()
        end
    end

    local function onLeave()
        setPreview(false)
        clearSuppress()
        SetRowHoverHighlight(row, false)
        if onHoverExtra then onHoverExtra(false) end
        RebuildGraph()
    end

    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    row.check:SetScript("OnEnter", onEnter)
    row.check:SetScript("OnLeave", onLeave)
    WireOptionLabelClick(row, onEnter, onLeave)
end

BindOptionRowHover(logRow, function(on)
    hoveredLogarithmicPreview = on
end, function()
    return suppressLogarithmicHoverPreview
end, function()
    suppressLogarithmicHoverPreview = false
end)
BindOptionRowHover(outlierRow, function(on)
    hoveredOutliersPreview = on
end, function()
    return suppressOutliersHoverPreview
end, function()
    suppressOutliersHoverPreview = false
end, function(show)
    if show then
        ShowOutlierOptionTooltip(outlierRow)
    else
        HideOutlierOptionTooltip()
    end
end)
BindOptionRowHover(rollingAverageRow, function(on)
    hoveredRollingAveragePreview = on
end, function()
    return suppressRollingAverageHoverPreview
end, function()
    suppressRollingAverageHoverPreview = false
end)

frame:SetScript("OnHide", function()
    hoveredCompareEntry = nil
    hoveredLogarithmicPreview = false
    hoveredOutliersPreview = false
    hoveredRollingAveragePreview = false
    suppressLogarithmicHoverPreview = false
    suppressOutliersHoverPreview = false
    suppressRollingAverageHoverPreview = false
    for _, row in ipairs(selectorRows) do
        row.suppressHoverPreview = false
    end
    SetRowHoverHighlight(logRow, false)
    SetRowHoverHighlight(outlierRow, false)
    SetRowHoverHighlight(rollingAverageRow, false)
    HideOutlierOptionTooltip()
end)

frame:SetScript("OnShow", function()
    logRow.check:SetChecked(EnsureSettings().logarithmic == true)
    outlierRow.check:SetChecked(EnsureSettings().ignoreOutliers == true)
    rollingAverageRow.check:SetChecked(EnsureSettings().rollingAverage == true)
    RefreshSelector()
    frame:Redraw()
end)
