-- AltArmy TBC — Cooldowns tab Raids view: per-character raid/heroic lockouts.

local frame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Cooldowns
if not frame or not frame.RaidsView then return end

local Theme = AltArmy.Theme
local PAD = 4
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 18
local HEADER_ROW_GAP = 3

local LD = AltArmy.LockoutData
local DS = AltArmy.DataStore
local RF = AltArmy.RealmFilter
if not LD or not DS then return end

local parent = frame.RaidsView
local inner = Theme.CreatePanelInnerContent(parent)

local UI = {
    -- Match TabCooldowns crafting list total (230+190+44+128 = 592).
    colWidths = {
        character = 190,
        instance = 274,
        time = 128,
    },
    sortKeys = { "instance", "character", "time" },
    sortLabels = {
        character = "Character",
        instance = "Instance",
        time = "Time Remaining",
    },
    sortJustify = {
        character = "LEFT",
        instance = "LEFT",
        time = "RIGHT",
    },
    currentSortKey = "time",
    sortAscending = true,
    headerButtons = {},
    rowPool = {},
    activeRows = {},
}

local function TotalColWidth()
    local w = UI.colWidths
    return w.character + w.instance + w.time
end

local function EnsureSortFromSaved()
    local opts = LD.EnsureLockoutListOptions()
    UI.currentSortKey = opts.lockoutListSortKey
    UI.sortAscending = opts.lockoutListSortAscending == true
end

local function PersistSort()
    local opts = LD.EnsureLockoutListOptions()
    opts.lockoutListSortKey = UI.currentSortKey
    opts.lockoutListSortAscending = UI.sortAscending
end

local function AccountHasMultipleRealms()
    local n = 0
    for _ in pairs(DS:GetRealms()) do
        n = n + 1
        if n > 1 then return true end
    end
    return false
end

local function GetCurrentRealm()
    if DS.GetCurrentPlayerIdentity then
        local _, realm = DS:GetCurrentPlayerIdentity()
        return realm
    end
    return (GetRealmName and GetRealmName()) or ""
end

local function UpdateHeaderSortIndicators()
    for _, sk in ipairs(UI.sortKeys) do
        local btn = UI.headerButtons[sk]
        if btn and btn.label then
            btn.label:SetText(Theme.FormatSortHeaderLabel(
                UI.sortLabels[sk],
                sk == UI.currentSortKey,
                UI.sortAscending
            ))
        end
    end
end

local function CompareLockoutRows(a, b)
    local key = UI.currentSortKey
    local asc = UI.sortAscending
    local function lessStr(x, y)
        if x == y then return nil end
        if asc then return x < y end
        return x > y
    end
    local function lessNum(x, y)
        x = tonumber(x) or 0
        y = tonumber(y) or 0
        if x == y then return nil end
        if asc then return x < y end
        return x > y
    end

    local r
    if key == "character" then
        r = lessStr(a.name or "", b.name or "")
        if r ~= nil then return r end
        r = lessStr(a.realm or "", b.realm or "")
        if r ~= nil then return r end
        r = lessStr(a.instanceLabel or "", b.instanceLabel or "")
        if r ~= nil then return r end
    elseif key == "instance" then
        r = lessStr(a.instanceLabel or "", b.instanceLabel or "")
        if r ~= nil then return r end
        r = lessStr(a.name or "", b.name or "")
        if r ~= nil then return r end
    else -- time
        r = lessNum(a.resetAtUnix, b.resetAtUnix)
        if r ~= nil then return r end
    end
    r = lessStr(a.name or "", b.name or "")
    if r ~= nil then return r end
    r = lessStr(a.instanceLabel or "", b.instanceLabel or "")
    if r ~= nil then return r end
    return false
end

local headerRow = CreateFrame("Frame", nil, inner)
headerRow:SetHeight(HEADER_HEIGHT)
headerRow:SetWidth(TotalColWidth())
headerRow:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
headerRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)

do
    local hx = 0
    for _, sk in ipairs(UI.sortKeys) do
        local btn = CreateFrame("Button", nil, headerRow)
        btn:SetPoint("TOPLEFT", headerRow, "TOPLEFT", hx, 0)
        btn:SetSize(UI.colWidths[sk], HEADER_HEIGHT)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")
        local sortKeyForClick = sk
        btn:SetScript("OnClick", function()
            if UI.currentSortKey == sortKeyForClick then
                UI.sortAscending = not UI.sortAscending
            else
                UI.currentSortKey = sortKeyForClick
                -- Default ascending (for time: soonest reset first).
                UI.sortAscending = true
            end
            PersistSort()
            UpdateHeaderSortIndicators()
            if frame.RefreshRaidsList then
                frame.RefreshRaidsList()
            end
        end)
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", btn, "LEFT", 0, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        label:SetHeight(HEADER_HEIGHT)
        label:SetJustifyH(UI.sortJustify[sk] or "LEFT")
        label:SetText(UI.sortLabels[sk])
        btn.label = label
        Theme.BindInteractableHover(btn)
        UI.headerButtons[sk] = btn
        hx = hx + UI.colWidths[sk]
    end
end

local listViewport = CreateFrame("Frame", nil, inner)
listViewport:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -PAD)
listViewport:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLL_GUTTER, PAD)

local rowParent = CreateFrame("Frame", nil, listViewport)
rowParent:SetPoint("TOPLEFT", listViewport, "TOPLEFT", 0, -(HEADER_HEIGHT + HEADER_ROW_GAP - PAD))
rowParent:SetPoint("BOTTOMRIGHT", listViewport, "BOTTOMRIGHT", 0, 0)

local viewport = Theme.CreateVerticalScrollViewport({
    parent = rowParent,
    gutterEdge = parent,
    anchorTop = { "TOPLEFT", rowParent, "TOPLEFT", 0, 0 },
    anchorBottom = { "BOTTOMRIGHT", rowParent, "BOTTOMRIGHT", 0, 0 },
    valueStep = ROW_HEIGHT,
    wheelStep = ROW_HEIGHT * 3,
    enableMouseWheel = true,
    childWidth = TotalColWidth(),
})

local scroll = viewport.scroll
local scrollChild = viewport.child
local scrollBar = viewport.scrollBar

headerRow:SetFrameLevel((inner:GetFrameLevel() or 0) + 10)
local headerFade = Theme.CreatePinnedHeaderScrollFade({
    headerFrame = headerRow,
    scrollFrame = scroll,
    scrollBar = scrollBar,
    headerBottomInset = 2,
})

do
    local prevOnValueChanged = scrollBar:GetScript("OnValueChanged")
    scrollBar:SetScript("OnValueChanged", function(self, value)
        if prevOnValueChanged then
            prevOnValueChanged(self, value)
        end
        if headerFade then
            headerFade:Update()
        end
    end)
end

local emptyLabel = inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
emptyLabel:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -HEADER_ROW_GAP - 4)
emptyLabel:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -HEADER_ROW_GAP - 4)
emptyLabel:SetJustifyH("LEFT")
emptyLabel:SetText("No active raid or heroic lockouts recorded. Log characters in to refresh.")
emptyLabel:Hide()

local function ReleaseRows()
    for i = #UI.activeRows, 1, -1 do
        local row = UI.activeRows[i]
        UI.activeRows[i] = nil
        row:Hide()
        UI.rowPool[#UI.rowPool + 1] = row
    end
end

local function PoolRow()
    local row = table.remove(UI.rowPool)
    if row then
        row:Show()
        return row
    end
    row = CreateFrame("Frame", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(false)

    local timeCell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timeCell:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    timeCell:SetWidth(UI.colWidths.time)
    timeCell:SetJustifyH("RIGHT")
    row.timeCell = timeCell

    local instanceCell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    instanceCell:SetPoint("LEFT", row, "LEFT", 0, 0)
    instanceCell:SetWidth(UI.colWidths.instance)
    instanceCell:SetJustifyH("LEFT")
    instanceCell:SetWordWrap(false)
    row.instanceCell = instanceCell

    local charCell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    charCell:SetPoint("LEFT", instanceCell, "RIGHT", 0, 0)
    charCell:SetPoint("RIGHT", timeCell, "LEFT", -4, 0)
    charCell:SetJustifyH("LEFT")
    charCell:SetWordWrap(false)
    row.charCell = charCell

    return row
end

local function RefreshRaidsList()
    ReleaseRows()
    EnsureSortFromSaved()
    UpdateHeaderSortIndicators()

    local now = time and time() or 0
    local rows = LD.BuildRows(DS, now)
    do
        local GRF = AltArmy.GlobalRealmFilter
        local rf = GRF and GRF.Get and GRF.Get() or "all"
        if rf == "currentRealm" then
            local curRealm = GetCurrentRealm()
            local filtered = {}
            for _, rd in ipairs(rows) do
                if rd.realm == curRealm then
                    filtered[#filtered + 1] = rd
                end
            end
            rows = filtered
        end
    end

    table.sort(rows, CompareLockoutRows)

    local totalW = TotalColWidth()
    local totalH = math.max(1, #rows) * ROW_HEIGHT
    scrollChild:SetSize(totalW, totalH)

    emptyLabel:SetShown(#rows == 0)

    local y = 0
    for _, rd in ipairs(rows) do
        local row = PoolRow()
        UI.activeRows[#UI.activeRows + 1] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        row:SetWidth(totalW)
        y = y - ROW_HEIGHT
        row.rowData = rd

        local showRealm = (AltArmy.GlobalRealmFilter and AltArmy.GlobalRealmFilter.Get() == "all")
            and AccountHasMultipleRealms()
            and rd.realm
            and rd.realm ~= ""
        local charText = RF and RF.formatColoredCharacterNameRealm
            and RF.formatColoredCharacterNameRealm(rd.name or "", rd.realm, showRealm, rd.classFile)
            or (rd.name or "")
        row.charCell:SetText(charText)
        local instanceText = rd.instanceLabel or rd.instanceName or "?"
        if rd.extended then
            instanceText = instanceText .. " *"
        end
        row.instanceCell:SetText(instanceText)
        row.timeCell:SetText(rd.timeText or "")
        row.timeCell:SetTextColor(1, 0.35, 0.35, 1)
    end

    if viewport.UpdateRange then
        viewport.UpdateRange()
    end
    if headerFade then
        headerFade:Update()
    end
end

frame.RefreshRaidsList = RefreshRaidsList

-- Refresh when lockout data arrives while the Raids view is visible.
if not frame._lockoutUpdateWatcher then
    local watcher = CreateFrame("Frame", nil, frame)
    watcher:RegisterEvent("UPDATE_INSTANCE_INFO")
    watcher:SetScript("OnEvent", function()
        if frame:IsShown() and frame.RaidsView and frame.RaidsView:IsShown() then
            RefreshRaidsList()
        end
    end)
    frame._lockoutUpdateWatcher = watcher
end
