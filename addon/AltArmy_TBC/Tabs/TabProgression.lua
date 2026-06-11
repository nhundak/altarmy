-- AltArmy TBC — Progression tab: time-per-level multi-character line graph.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Progression
if not frame then return end

local LPD = AltArmy.LevelProgressData
local Core = AltArmy.GraphCore
local Logic = AltArmy.ProgressionGraphLogic

local SELECTOR_WIDTH = 150
local ROW_HEIGHT = 20
local SECTION_HEADER_HEIGHT = 18
local INSUFFICIENT_SECTION_GAP = 10
local LINE_THICKNESS = 2
local DASH_THICKNESS = 1
local MARKER_HIT_SIZE = 18
local MARKER_DOT_SIZE = 4
local ROW_HOVER_BG = "Interface\\Tooltips\\UI-Tooltip-Background"
local ROW_HOVER_TINT = 0.22

local FULL_LINE_ALPHA = Logic.FULL_LINE_ALPHA
local FULL_DASH_ALPHA = Logic.FULL_DASH_ALPHA
local FULL_MARKER_ALPHA = Logic.FULL_MARKER_ALPHA
local DIM_LINE_ALPHA = Logic.DIM_LINE_ALPHA
local DIM_DASH_ALPHA = Logic.DIM_DASH_ALPHA
local DIM_MARKER_ALPHA = Logic.DIM_MARKER_ALPHA

AltArmyTBC_ProgressionSettings = AltArmyTBC_ProgressionSettings or {}

local RF = AltArmy.RealmFilter
local hoveredCompareEntry = nil

local currentX, currentY = nil, nil
local currentRawYMax = 0
local drawnKeys = {}
local seriesGroups = {}

local markerDotPool = { free = {} }
local markerHitPool = { free = {} }

local RebuildGraph
local ApplyHighlight
local HandleCompareRowEnter
local HandleCompareRowLeave

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
    local tint = row and row.hoverTint
    if tint then
        tint:SetVertexColor(1, 1, 1, on and ROW_HOVER_TINT or 0)
    end
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

local function ToggleCompareSelection(row, entry)
    local checked = not IsSelected(entry.realm, entry.name)
    row.check:SetChecked(checked)
    SetSelected(entry.realm, entry.name, checked)
    RebuildGraph()
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
        row:EnableMouse(true)

        row.hoverTint = row:CreateTexture(nil, "BACKGROUND")
        row.hoverTint:SetTexture(ROW_HOVER_BG)
        row.hoverTint:SetAllPoints(true)
        row.hoverTint:SetVertexColor(1, 1, 1, 0)

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

local function AddStyledObject(group, obj, r, g, b, fullAlpha, dimAlpha)
    group.objects[#group.objects + 1] = {
        obj = obj,
        r = r,
        g = g,
        b = b,
        fullAlpha = fullAlpha,
        dimAlpha = dimAlpha,
    }
end

local function ApplyObjectAlpha(styled, dimOthers, isHovered)
    local alpha = dimOthers and (isHovered and styled.fullAlpha or styled.dimAlpha) or styled.fullAlpha
    styled.obj:SetVertexColor(styled.r, styled.g, styled.b, alpha)
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
    AddStyledObject(group, dot, r, g, b, FULL_MARKER_ALPHA, DIM_MARKER_ALPHA)

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

local function GetSeriesMaxSeconds(entry)
    if not LPD or not entry then return 0 end
    local series = LPD.GetSeriesForCharacter(entry.name, entry.realm)
    local drawable = LPD.PrepareDrawableSeries(series)
    local maxSeconds = 0
    for _, pt in ipairs(drawable.usable) do
        if pt.seconds > maxSeconds then
            maxSeconds = pt.seconds
        end
    end
    return maxSeconds
end

local function DrawSeriesGroup(charData, X, Y)
    local group = {
        key = EntryKey(charData.entry),
        entry = charData.entry,
        objects = {},
        markerDots = {},
        markerHits = {},
    }
    local drawable = charData.drawable
    local series = drawable.usable
    local r, g, b = charData.r, charData.g, charData.b
    local entry = charData.entry

    for i, pt in ipairs(series) do
        local x, y = X(pt.level), Y(pt.seconds)

        if drawable.leadingGap and i == 1 then
            local gap = drawable.leadingGap
            local gx1, gy1 = X(gap.fromLevel), Y(0)
            local lineCountBefore = #Core.graphLines
            local texCountBefore = #Core.graphTextures
            Core.CreateDashedLine(graphFrame, gx1, gy1, x, y, DASH_THICKNESS, r, g, b, FULL_DASH_ALPHA)
            TrackNewCoreObjects(group, r, g, b, FULL_DASH_ALPHA, DIM_DASH_ALPHA, lineCountBefore, texCountBefore)
        elseif i > 1 then
            local prev = series[i - 1]
            local x1, y1 = X(prev.level), Y(prev.seconds)
            local line = Core.CreateLine(graphFrame, x1, y1, x, y, LINE_THICKNESS, r, g, b, FULL_LINE_ALPHA)
            AddStyledObject(group, line, r, g, b, FULL_LINE_ALPHA, DIM_LINE_ALPHA)
        end

        AddSegmentMarker(group, x, y, r, g, b, FULL_MARKER_ALPHA, entry, pt)
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

    local cr, cg, cb = LPD.GetClassColor(entry.classFile)
    local charData = {
        entry = entry,
        drawable = drawable,
        r = cr,
        g = cg,
        b = cb,
    }
    local group = DrawSeriesGroup(charData, currentX, currentY)
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

    local toDraw = GetCharactersToDraw()
    if #toDraw == 0 then
        graphHint:Show()
        if LPD.GetCharactersWithHistory and #ApplyRealmFilter(LPD.GetCharactersWithHistory()) > 0 then
            graphHint:SetText("Select one or more characters on the right\nto compare time per level.")
        end
        return
    end

    local seriesByChar = {}
    local yMax = 0

    for _, entry in ipairs(toDraw) do
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

    currentRawYMax = yMax
    local yPad = math.max(1, math.floor(yMax * 0.08))
    local yMin = 0
    local paddedYMax = yMax + yPad
    local yRange = math.max(1, paddedYMax - yMin)

    local plotW, plotH = Core.CalculatePlotDimensions(graphFrame)
    currentX, currentY = Core.CreateTransformers(plotW, plotH, xMin, xRange, yMin, yRange)

    Core.RenderGridLines(graphFrame, plotW, plotH)
    Core.RenderAxes(graphFrame, plotW, plotH)
    Core.RenderYLabels(graphFrame, plotH, yMin, yRange, function(v)
        return Core.FormatDuration(v)
    end)
    Core.RenderXLabelsAtInterval(graphFrame, plotW, xMin, xRange, 10, function(v)
        return tostring(math.floor(v + 0.5))
    end)

    for _, charData in ipairs(seriesByChar) do
        local group = DrawSeriesGroup(charData, currentX, currentY)
        drawnKeys[group.key] = true
        seriesGroups[#seriesGroups + 1] = group
    end

    ApplyHighlight()
end

HandleCompareRowEnter = function(row, entry)
    hoveredCompareEntry = entry
    SetRowHoverHighlight(row, true)

    local key = EntryKey(entry)
    if drawnKeys[key] then
        ApplyHighlight()
        return
    end

    if #seriesGroups == 0 then
        RebuildGraph()
        return
    end

    local maxSec = GetSeriesMaxSeconds(entry)
    if Logic.HoverNeedsRebuild(key, drawnKeys, maxSec, currentRawYMax) then
        RebuildGraph()
        return
    end

    AddHoveredSeries(entry)
    ApplyHighlight()
end

HandleCompareRowLeave = function(row, entry)
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

    local scrollW = selectorScroll:GetWidth() or SELECTOR_WIDTH - 12
    selectorChild:SetWidth(scrollW)

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
            SetSelected(entry.realm, entry.name, row.check:GetChecked())
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
    RebuildGraph()
end

frame:SetScript("OnShow", function()
    RefreshSelector()
    frame:Redraw()
end)
