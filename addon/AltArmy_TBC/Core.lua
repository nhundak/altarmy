-- AltArmy TBC — Core: namespace, main frame, header, tabs, content frames

local ADDON_NAME = "Alt Army"
local ADDON_VERSION = "0.0.1"

-- Namespace
AltArmy = AltArmy or {}
AltArmy.Name = ADDON_NAME
AltArmy.Version = ADDON_VERSION
AltArmy.MainFrame = nil
AltArmy.TabFrames = {}
AltArmy.CurrentTab = "Summary"

local FRAME_WIDTH = 600
local FRAME_HEIGHT = 400
local HEADER_HEIGHT = 24
local TAB_HEIGHT = 22
local CONTENT_INSET = 8

local setActiveTab -- forward-declare so header search scripts can call it
local lastTab = "Summary"

-- Create main frame
local main = CreateFrame("Frame", "AltArmyTBC_MainFrame", UIParent)
main:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
main:SetPoint("CENTER", 0, 0)
main:SetMovable(true)
main:SetClampedToScreen(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", function(f) f:StartMoving() end)
main:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
main:EnableMouse(true)
-- SetBackdrop is not available in all TBC Classic builds; use a simple background texture
local bg = main:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(main)
bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
bg:SetTexCoord(0, 1, 0, 1)
main:Hide()

AltArmy.MainFrame = main

-- Dismiss UI when Escape is pressed (WoW closes topmost frame in UISpecialFrames)
UISpecialFrames = UISpecialFrames or {}
tinsert(UISpecialFrames, "AltArmyTBC_MainFrame")

-- Header background
local headerBg = main:CreateTexture(nil, "ARTWORK")
headerBg:SetPoint("TOPLEFT", main, "TOPLEFT", 8, -8)
headerBg:SetPoint("TOPRIGHT", main, "TOPRIGHT", -8, -8)
headerBg:SetHeight(HEADER_HEIGHT)
headerBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)

-- Title (vertically centered in header)
local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", headerBg, "LEFT", 6, 0)
title:SetText(ADDON_NAME)

-- Close button
local closeBtn = CreateFrame("Button", nil, main, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", main, "TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
    main:Hide()
end)

-- Header search: EditBox to the left of close button
local headerSearchEdit = CreateFrame("EditBox", "AltArmyTBC_HeaderSearchEdit", main)
headerSearchEdit:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
headerSearchEdit:SetSize(280, 20)
headerSearchEdit:SetAutoFocus(false)
headerSearchEdit:SetFontObject("GameFontHighlight")
if headerSearchEdit.SetTextInsets then
    headerSearchEdit:SetTextInsets(6, 6, 0, 0)
end

-- Clear (X) button at start of input; only visible when there is text
local headerSearchClearBtn = CreateFrame("Button", nil, main)
headerSearchClearBtn:SetPoint("RIGHT", headerSearchEdit, "LEFT", -2, 0)
headerSearchClearBtn:SetSize(18, 18)
headerSearchClearBtn:SetScript("OnClick", function()
    headerSearchEdit:SetText("")
    headerSearchEdit:SetFocus()
end)
headerSearchClearBtn:Hide()
local clearBtnLabel = headerSearchClearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
clearBtnLabel:SetPoint("CENTER", headerSearchClearBtn, "CENTER", 0, 0)
clearBtnLabel:SetText("X")
headerSearchClearBtn:SetHighlightFontObject("GameFontNormal")

-- Visible input background
local searchEditBg = headerSearchEdit:CreateTexture(nil, "BACKGROUND")
searchEditBg:SetAllPoints(headerSearchEdit)
searchEditBg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
local searchEditBorder = headerSearchEdit:CreateTexture(nil, "BORDER")
searchEditBorder:SetPoint("TOPLEFT", headerSearchEdit, "TOPLEFT", -1, 1)
searchEditBorder:SetPoint("BOTTOMRIGHT", headerSearchEdit, "BOTTOMRIGHT", 1, -1)
searchEditBorder:SetColorTexture(0.4, 0.4, 0.4, 1)
headerSearchEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
    local query = box:GetText()
    local trimmed = query and query:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" then
        -- Debugging convenience: allow /reload from search box; remove before release.
        if trimmed:lower() == "/reload" then
            ReloadUI()
            return
        end
        if AltArmy.TabFrames.Search and AltArmy.TabFrames.Search.SearchWithQuery then
            AltArmy.TabFrames.Search:SearchWithQuery(trimmed)
        end
    end
end)
headerSearchEdit:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
end)
-- OnTextChanged registered below after enterSearchMode/exitSearchMode are defined

-- Expose for clearing header search and switching to Summary (e.g. from other code)
function AltArmy.SwitchToSummaryTab()
    lastTab = "Summary"
    if headerSearchEdit and headerSearchEdit.SetText then
        headerSearchEdit:SetText("")
    end
end

-- Tab button strip (below header; leave clear space so tabs don't overlap header)
local HEADER_TOTAL_OFFSET = 40  -- 8 (top inset) + header content + gap
local tabStrip = CreateFrame("Frame", nil, main)
tabStrip:SetPoint("TOPLEFT", main, "TOPLEFT", CONTENT_INSET, -HEADER_TOTAL_OFFSET)
tabStrip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -CONTENT_INSET, -HEADER_TOTAL_OFFSET)
tabStrip:SetHeight(TAB_HEIGHT)

setActiveTab = function(tabName)
    AltArmy.CurrentTab = tabName
    for name, frame in pairs(AltArmy.TabFrames) do
        frame:SetShown(name == tabName)
    end
    -- Update tab button highlights (handled in each button's refresh or we do it here)
    for _, btn in pairs(tabStrip.buttons or {}) do
        if btn.tabName == tabName then
            btn:SetEnabled(false)
            if btn.selectedBg then btn.selectedBg:Show() end
        else
            btn:SetEnabled(true)
            if btn.selectedBg then btn.selectedBg:Hide() end
        end
    end
end

local TAB_BTN_MIN_WIDTH = 72
local tabNames = { "Summary", "Gear" }
tabStrip.buttons = {}
local prevBtn = nil
for _, tabName in ipairs(tabNames) do
    local btn = CreateFrame("Button", nil, tabStrip)
    btn.tabName = tabName
    btn:SetHeight(TAB_HEIGHT)
    btn:SetWidth(TAB_BTN_MIN_WIDTH)
    if prevBtn then
        btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    else
        btn:SetPoint("LEFT", tabStrip, "LEFT", 0, 0)
    end
    -- Visible background so tab is clickable and visible
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
    -- Selected state (shown for active tab)
    local selectedBg = btn:CreateTexture(nil, "BACKGROUND")
    selectedBg:SetAllPoints(btn)
    selectedBg:SetColorTexture(0.35, 0.35, 0.5, 0.8)
    btn.selectedBg = selectedBg
    selectedBg:Hide()
    -- Label (plain Button has no built-in text)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(tabName)
    btn:SetScript("OnClick", function()
        setActiveTab(tabName)
    end)
    btn:SetScript("OnEnable", function(self)
        if label then label:SetTextColor(0.85, 0.85, 0.85, 1) end
    end)
    btn:SetScript("OnDisable", function(self)
        if label then label:SetTextColor(1, 0.82, 0, 1) end
    end)
    prevBtn = btn
    tabStrip.buttons[tabName] = btn
end
setActiveTab("Summary")

-- Content area: one frame per tab
local contentArea = CreateFrame("Frame", nil, main)
contentArea:SetPoint("TOPLEFT", main, "TOPLEFT", CONTENT_INSET, -HEADER_TOTAL_OFFSET - TAB_HEIGHT - 4)
contentArea:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)

for _, tabName in ipairs(tabNames) do
    local cf = CreateFrame("Frame", nil, contentArea)
    cf:SetAllPoints(contentArea)
    cf:SetShown(tabName == "Summary")
    AltArmy.TabFrames[tabName] = cf
end

-- Search content frame (no tab button; shown when search box has text)
local searchFrame = CreateFrame("Frame", nil, contentArea)
searchFrame:SetAllPoints(contentArea)
searchFrame:Hide()
AltArmy.TabFrames.Search = searchFrame

-- "Search Results" label (replaces tab strip when in search mode)
local searchResultsLabel = CreateFrame("Frame", nil, main)
searchResultsLabel:SetPoint("TOPLEFT", main, "TOPLEFT", CONTENT_INSET, -HEADER_TOTAL_OFFSET)
searchResultsLabel:SetPoint("TOPRIGHT", main, "TOPRIGHT", -CONTENT_INSET, -HEADER_TOTAL_OFFSET)
searchResultsLabel:SetHeight(TAB_HEIGHT)
searchResultsLabel:Hide()
local searchResultsText = searchResultsLabel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
searchResultsText:SetPoint("LEFT", searchResultsLabel, "LEFT", 0, 0)
searchResultsText:SetText("Search Results")

local function enterSearchMode(trimmed)
    lastTab = AltArmy.CurrentTab
    tabStrip:Hide()
    searchResultsLabel:Show()
    if AltArmy.TabFrames.Summary then AltArmy.TabFrames.Summary:Hide() end
    if AltArmy.TabFrames.Gear then AltArmy.TabFrames.Gear:Hide() end
    if AltArmy.TabFrames.Search then
        AltArmy.TabFrames.Search:Show()
        if AltArmy.TabFrames.Search.SearchWithQuery then
            AltArmy.TabFrames.Search:SearchWithQuery(trimmed)
        end
    end
end

local function exitSearchMode()
    searchResultsLabel:Hide()
    tabStrip:Show()
    if AltArmy.TabFrames.Search then AltArmy.TabFrames.Search:Hide() end
    if AltArmy.TabFrames[lastTab] then AltArmy.TabFrames[lastTab]:Show() end
    setActiveTab(lastTab)
end

local function applySearchBoxState()
    local query = headerSearchEdit:GetText()
    local trimmed = query and query:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        exitSearchMode()
        headerSearchClearBtn:Hide()
    else
        headerSearchClearBtn:Show()
        enterSearchMode(trimmed)
    end
end

headerSearchEdit:SetScript("OnTextChanged", applySearchBoxState)
headerSearchEdit:SetScript("OnChar", applySearchBoxState)

main:SetScript("OnShow", function()
    lastTab = "Summary"
    if headerSearchEdit and headerSearchEdit.SetText then
        headerSearchEdit:SetText("")
    end
    exitSearchMode()
end)
