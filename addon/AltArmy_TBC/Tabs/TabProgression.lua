-- AltArmy TBC — Progression tab: time-per-level multi-character line graph.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Progression
if not frame then return end

local LPD = AltArmy.LevelProgressData
local Core = AltArmy.GraphCore

local SELECTOR_WIDTH = 150
local ROW_HEIGHT = 20
local SECTION_HEADER_HEIGHT = 18
local INSUFFICIENT_SECTION_GAP = 10
local LINE_THICKNESS = 2
local DASH_THICKNESS = 1
local MARKER_HIT_SIZE = 18
local MARKER_DOT_SIZE = 4

AltArmyTBC_ProgressionSettings = AltArmyTBC_ProgressionSettings or {}

local hoverFrames = {}
local markerDots = {}
local tooltipFrame = nil

local function CharKey(realm, name)
    return (realm or "") .. "\\" .. (name or "")
end

local function EnsureSettings()
    AltArmyTBC_ProgressionSettings.selected = AltArmyTBC_ProgressionSettings.selected or {}
    return AltArmyTBC_ProgressionSettings
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
    local RF = AltArmy.RealmFilter
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

-- Layout: graph (left) + selector (right)
local graphFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
graphFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
graphFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
graphFrame:SetPoint("RIGHT", frame, "RIGHT", -SELECTOR_WIDTH - 4, 0)
graphFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
graphFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
graphFrame:SetBackdropBorderColor(0.45, 0.38, 0.22, 0.9)
graphFrame:EnableMouse(false)

local graphHint = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
graphHint:SetPoint("CENTER", graphFrame, "CENTER", 0, 0)
graphHint:SetWidth(graphFrame:GetWidth() - 40)
graphHint:SetText("Select one or more characters on the right\nto compare time per level.")
graphHint:SetJustifyH("CENTER")

local axisTitleY = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
axisTitleY:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", 4, -6)
axisTitleY:SetText("Time")

local axisTitleX = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
axisTitleX:SetPoint("BOTTOMRIGHT", graphFrame, "BOTTOMRIGHT", -8, 6)
axisTitleX:SetText("Level")

-- Selector panel
local selectorPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
selectorPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
selectorPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
selectorPanel:SetWidth(SELECTOR_WIDTH)
selectorPanel:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
selectorPanel:SetBackdropColor(0.10, 0.10, 0.12, 0.95)
selectorPanel:SetBackdropBorderColor(0.45, 0.38, 0.22, 0.9)

local selectorTitle = selectorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
selectorTitle:SetPoint("TOPLEFT", selectorPanel, "TOPLEFT", 8, -8)
selectorTitle:SetText("Compare")

local selectorScroll = CreateFrame("ScrollFrame", nil, selectorPanel)
selectorScroll:SetPoint("TOPLEFT", selectorTitle, "BOTTOMLEFT", 0, -6)
selectorScroll:SetPoint("BOTTOMRIGHT", selectorPanel, "BOTTOMRIGHT", -4, 4)
selectorScroll:EnableMouse(true)

local selectorChild = CreateFrame("Frame", nil, selectorScroll)
selectorChild:SetPoint("TOPLEFT", selectorScroll, "TOPLEFT", 0, 0)
selectorChild:SetWidth(1)
selectorScroll:SetScrollChild(selectorChild)

selectorScroll:SetScript("OnMouseWheel", function(_, delta)
    local scrollVal = selectorScroll:GetVerticalScroll()
    local newScroll = scrollVal - delta * ROW_HEIGHT * 2
    local maxScroll = math.max(0, selectorChild:GetHeight() - selectorScroll:GetHeight())
    newScroll = math.max(0, math.min(maxScroll, newScroll))
    selectorScroll:SetVerticalScroll(newScroll)
end)

local selectorRows = {}
local insufficientRows = {}

local insufficientHeader = selectorChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
insufficientHeader:SetText("Not enough data:")
insufficientHeader:Hide()

local function PositionListRow(row, yOffset)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", selectorChild, "TOPLEFT", 0, -yOffset)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("RIGHT", selectorChild, "RIGHT", 0, 0)
end

local function GetSelectorRow(i)
    if not selectorRows[i] then
        local row = CreateFrame("Frame", nil, selectorChild)

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

local function GetTooltipFrame()
    if tooltipFrame then return tooltipFrame end
    tooltipFrame = Core.CreateTooltipBase(graphFrame, 175, 72)

    local padding = 12
    local timeText = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeText:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", padding, -padding)
    timeText:SetTextColor(Core.COLORS.headerText[1], Core.COLORS.headerText[2], Core.COLORS.headerText[3])
    tooltipFrame.charText = timeText

    local levelLabel = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelLabel:SetPoint("TOPLEFT", timeText, "BOTTOMLEFT", 0, -6)
    levelLabel:SetTextColor(Core.COLORS.labelText[1], Core.COLORS.labelText[2], Core.COLORS.labelText[3])
    levelLabel:SetText("Level")
    levelLabel:SetWidth(42)
    levelLabel:SetJustifyH("LEFT")
    tooltipFrame.levelLabel = levelLabel

    local levelValue = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelValue:SetPoint("LEFT", levelLabel, "RIGHT", 4, 0)
    levelValue:SetTextColor(Core.COLORS.valueText[1], Core.COLORS.valueText[2], Core.COLORS.valueText[3])
    tooltipFrame.levelValue = levelValue

    local timeLabel = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeLabel:SetPoint("TOPLEFT", levelLabel, "BOTTOMLEFT", 0, -4)
    timeLabel:SetTextColor(Core.COLORS.labelText[1], Core.COLORS.labelText[2], Core.COLORS.labelText[3])
    timeLabel:SetText("Time")
    timeLabel:SetWidth(42)
    timeLabel:SetJustifyH("LEFT")
    tooltipFrame.timeLabel = timeLabel

    local timeValue = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeValue:SetPoint("LEFT", timeLabel, "RIGHT", 4, 0)
    timeValue:SetTextColor(Core.COLORS.valueText[1], Core.COLORS.valueText[2], Core.COLORS.valueText[3])
    tooltipFrame.timeValue = timeValue

    return tooltipFrame
end

local function FormatDurationLong(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    if seconds < 60 then
        return seconds == 1 and "1 second" or string.format("%d seconds", seconds)
    elseif seconds < 3600 then
        local minutes = math.floor(seconds / 60 + 0.5)
        return minutes == 1 and "1 minute" or string.format("%d minutes", minutes)
    elseif seconds < 86400 then
        local hours = math.floor(seconds / 3600 + 0.5)
        return hours == 1 and "1 hour" or string.format("%d hours", hours)
    end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    if hours > 0 then
        local dayLabel = days == 1 and "1 day" or string.format("%d days", days)
        local hourLabel = hours == 1 and "1 hour" or string.format("%d hours", hours)
        return dayLabel .. " " .. hourLabel
    end
    return days == 1 and "1 day" or string.format("%d days", days)
end

local function ShowSegmentTooltip(tooltip, charLabel, fromLevel, toLevel, seconds, showCharName)
    local header = string.format("Level %d-%d", fromLevel, toLevel)
    if showCharName and charLabel and charLabel ~= "" and charLabel ~= "?" then
        header = header .. " (" .. charLabel .. ")"
    end
    tooltip.charText:SetText(header)
    if tooltip.levelLabel then tooltip.levelLabel:SetText("") end
    tooltip.levelValue:SetText("")
    if tooltip.timeLabel then tooltip.timeLabel:SetText("") end
    tooltip.timeValue:SetText(FormatDurationLong(seconds))
    tooltip:Show()
end

local function ClearHoverFrames()
    for _, hf in ipairs(hoverFrames) do
        if hf then
            hf:Hide()
            hf:SetParent(nil)
        end
    end
    wipe(hoverFrames)

    for _, dot in ipairs(markerDots) do
        if dot then
            dot:Hide()
            dot:SetParent(nil)
        end
    end
    wipe(markerDots)

    if tooltipFrame then tooltipFrame:Hide() end
end

local function AddSegmentMarker(px, py, r, g, b, onEnter, onLeave)
    local dot = graphFrame:CreateTexture(nil, "OVERLAY")
    dot:SetColorTexture(r, g, b, 1)
    dot:SetSize(MARKER_DOT_SIZE, MARKER_DOT_SIZE)
    dot:SetPoint("CENTER", graphFrame, "BOTTOMLEFT", px, py)
    markerDots[#markerDots + 1] = dot

    local hf = CreateFrame("Frame", nil, graphFrame)
    hf:SetSize(MARKER_HIT_SIZE, MARKER_HIT_SIZE)
    hf:SetPoint("CENTER", graphFrame, "BOTTOMLEFT", px, py)
    hf:SetFrameLevel(graphFrame:GetFrameLevel() + 50)
    hf:EnableMouse(true)

    hf:SetScript("OnEnter", function()
        dot:SetSize(MARKER_DOT_SIZE + 3, MARKER_DOT_SIZE + 3)
        if onEnter then onEnter() end
    end)
    hf:SetScript("OnLeave", function()
        dot:SetSize(MARKER_DOT_SIZE, MARKER_DOT_SIZE)
        if onLeave then onLeave() end
    end)

    hoverFrames[#hoverFrames + 1] = hf
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

    local scrollW = selectorScroll:GetWidth() or SELECTOR_WIDTH - 12
    selectorChild:SetWidth(scrollW)

    local RF = AltArmy.RealmFilter
    local realmFilter = GetRealmFilterValue()
    local combinedForRealmCheck = {}
    for _, entry in ipairs(list) do combinedForRealmCheck[#combinedForRealmCheck + 1] = entry end
    for _, entry in ipairs(insufficientList) do combinedForRealmCheck[#combinedForRealmCheck + 1] = entry end
    local showRealmSuffix = (realmFilter == "all")
        and RF and RF.hasMultipleRealms and RF.hasMultipleRealms(combinedForRealmCheck)

    local yOffset = 0
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
        row.check:SetScript("OnClick", function()
            local checked = row.check:GetChecked()
            SetSelected(entry.realm, entry.name, checked)
            frame:Redraw()
        end)

        yOffset = yOffset + ROW_HEIGHT
    end

    if #insufficientList > 0 then
        yOffset = yOffset + INSUFFICIENT_SECTION_GAP
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

    if #list == 0 and #insufficientList == 0 then
        graphHint:SetText("No level history yet.\nLevel up characters while\nlevel history is enabled.")
    end

    if LPD.DebugLogSelectorEligibility then
        LPD.DebugLogSelectorEligibility()
    end
end

function frame:Redraw()
    if not Core or not LPD then return end

    Core.ClearObjects()
    ClearHoverFrames()

    local selected = GetSelectedCharacters()
    if #selected == 0 then
        graphHint:Show()
        if LPD.GetCharactersWithHistory and #ApplyRealmFilter(LPD.GetCharactersWithHistory()) > 0 then
            graphHint:SetText("Select one or more characters on the right\nto compare time per level.")
        end
        return
    end

    local seriesByChar = {}
    local yMax = 0

    for _, entry in ipairs(selected) do
        local series = LPD.GetSeriesForCharacter(entry.name, entry.realm)
        local drawable = LPD.PrepareDrawableSeries(series)
        if #drawable.usable >= 1 then
            local cr, cg, cb = LPD.GetClassColor(entry.classFile)
            seriesByChar[#seriesByChar + 1] = {
                entry = entry,
                drawable = drawable,
                r = cr,
                g = cg,
                b = cb,
            }
            for _, pt in ipairs(drawable.usable) do
                if pt.seconds > yMax then yMax = pt.seconds end
            end
        end
    end

    if #seriesByChar == 0 then
        graphHint:SetText("Selected characters have no\nusable level history.")
        graphHint:Show()
        return
    end

    graphHint:Hide()

    local xMin, _, xRange = LPD.GetAxisRange()

    local yPad = math.max(1, math.floor(yMax * 0.08))
    local yMin = 0
    yMax = yMax + yPad
    local yRange = math.max(1, yMax - yMin)

    local plotW, plotH = Core.CalculatePlotDimensions(graphFrame)
    local X, Y = Core.CreateTransformers(plotW, plotH, xMin, xRange, yMin, yRange)

    Core.RenderGridLines(graphFrame, plotW, plotH)
    Core.RenderAxes(graphFrame, plotW, plotH)
    Core.RenderYLabels(graphFrame, plotH, yMin, yRange, function(v)
        return Core.FormatDuration(v)
    end)
    Core.RenderXLabelsAtInterval(graphFrame, plotW, xMin, xRange, 10, function(v)
        return tostring(math.floor(v + 0.5))
    end)

    local tooltip = GetTooltipFrame()
    local showCharName = #seriesByChar > 1

    for _, charData in ipairs(seriesByChar) do
        local drawable = charData.drawable
        local series = drawable.usable
        local r, g, b = charData.r, charData.g, charData.b
        local entry = charData.entry
        local charLabel = entry.name or "?"

        for i, pt in ipairs(series) do
            local x, y = X(pt.level), Y(pt.seconds)

            if drawable.leadingGap and i == 1 then
                local gap = drawable.leadingGap
                local gx1, gy1 = X(gap.fromLevel), Y(0)
                Core.CreateDashedLine(graphFrame, gx1, gy1, x, y, DASH_THICKNESS, r, g, b, 0.55)
            elseif i > 1 then
                local prev = series[i - 1]
                local x1, y1 = X(prev.level), Y(prev.seconds)
                Core.CreateLine(graphFrame, x1, y1, x, y, LINE_THICKNESS, r, g, b, 0.9)
            end

            AddSegmentMarker(x, y, r, g, b, function()
                tooltip:ClearAllPoints()
                tooltip:SetPoint("BOTTOMLEFT", graphFrame, "BOTTOMLEFT", x + 10, y + 10)
                ShowSegmentTooltip(
                    tooltip,
                    charLabel,
                    pt.fromLevel,
                    pt.toLevel,
                    pt.totalSeconds,
                    showCharName
                )
            end, function()
                tooltip:Hide()
            end)
        end
    end
end

frame:SetScript("OnShow", function()
    RefreshSelector()
    frame:Redraw()
end)
