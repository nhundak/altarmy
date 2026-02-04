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
if headerSearchEdit.SetPlaceholderText then
    headerSearchEdit:SetPlaceholderText("Search for items or recipes")
else
    -- Fallback for clients without SetPlaceholderText (e.g. TBC Classic): gray hint label
    local searchPlaceholderHint = headerSearchEdit:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    searchPlaceholderHint:SetPoint("LEFT", headerSearchEdit, "LEFT", 6, 0)
    searchPlaceholderHint:SetPoint("RIGHT", headerSearchEdit, "RIGHT", -6, 0)
    searchPlaceholderHint:SetJustifyH("LEFT")
    searchPlaceholderHint:SetText("Search for items or recipes")
    searchPlaceholderHint:SetTextColor(0.5, 0.5, 0.5, 1)
    headerSearchEdit.searchPlaceholderHint = searchPlaceholderHint
end

local function updateSearchPlaceholderVisibility()
    local hint = headerSearchEdit.searchPlaceholderHint
    if not hint then return end
    local text = headerSearchEdit:GetText()
    local trimmed = text and text:match("^%s*(.-)%s*$") or ""
    local hasFocus = headerSearchEdit:HasFocus()
    if trimmed == "" and not hasFocus then
        hint:Show()
    else
        hint:Hide()
    end
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
headerSearchEdit:SetScript("OnEditFocusGained", updateSearchPlaceholderVisibility)
headerSearchEdit:SetScript("OnEditFocusLost", updateSearchPlaceholderVisibility)
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
    -- Update tab button highlights: background and label color by selected state
    for _, btn in pairs(tabStrip.buttons or {}) do
        local isSelected = (btn.tabName == tabName)
        if isSelected then
            -- Keep Gear tab enabled when active so clicking it can close settings and return to grid
            btn:SetEnabled(btn.tabName == "Gear" or false)
            if btn.selectedBg then btn.selectedBg:Show() end
            if btn.label then btn.label:SetTextColor(1, 0.82, 0, 1) end  -- yellow when selected
        else
            btn:SetEnabled(true)
            if btn.selectedBg then btn.selectedBg:Hide() end
            if btn.label then btn.label:SetTextColor(0.85, 0.85, 0.85, 1) end  -- gray when not selected
        end
    end
    -- Gear tab settings button: only visible when Gear tab is active and tab strip is shown
    if tabStrip.gearSettingsBtn then
        if tabName == "Gear" and tabStrip:IsShown() then
            tabStrip.gearSettingsBtn:Show()
        else
            tabStrip.gearSettingsBtn:Hide()
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
    local btnBg = btn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints(btn)
    btnBg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
    -- Selected state (shown for active tab)
    local selectedBg = btn:CreateTexture(nil, "BACKGROUND")
    selectedBg:SetAllPoints(btn)
    selectedBg:SetColorTexture(0.35, 0.35, 0.5, 0.8)
    btn.selectedBg = selectedBg
    selectedBg:Hide()
    -- Label (plain Button has no built-in text); color is set in setActiveTab for consistent selected look
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(tabName)
    btn.label = label
    btn:SetScript("OnClick", function()
        setActiveTab(tabName)
    end)
    prevBtn = btn
    tabStrip.buttons[tabName] = btn
end

-- Gear tab: clicking the tab again while settings are open switches back to the gear grid
tabStrip.buttons["Gear"]:SetScript("OnClick", function()
    if AltArmy.CurrentTab == "Gear"
        and AltArmy.TabFrames.Gear
        and AltArmy.TabFrames.Gear.IsGearSettingsShown
        and AltArmy.TabFrames.Gear:IsGearSettingsShown() then
        AltArmy.TabFrames.Gear:ToggleGearSettings()
    else
        setActiveTab("Gear")
    end
end)

-- Gear tab settings icon (top right of tab strip; visible only when Gear tab is active)
local gearSettingsBtn = CreateFrame("Button", nil, tabStrip)
gearSettingsBtn:SetPoint("TOPRIGHT", tabStrip, "TOPRIGHT", 0, 0)
gearSettingsBtn:SetSize(TAB_HEIGHT, TAB_HEIGHT)
gearSettingsBtn:Hide()
local gearSettingsIcon = gearSettingsBtn:CreateTexture(nil, "ARTWORK")
gearSettingsIcon:SetAllPoints(gearSettingsBtn)
gearSettingsIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
gearSettingsBtn:SetScript("OnClick", function()
    if AltArmy.TabFrames.Gear and AltArmy.TabFrames.Gear.ToggleGearSettings then
        AltArmy.TabFrames.Gear:ToggleGearSettings()
    end
end)
tabStrip.gearSettingsBtn = gearSettingsBtn

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

-- Search category filter checkboxes (replace tab strip when in search mode)
AltArmy.SearchCategories = AltArmy.SearchCategories or { Items = true, Recipes = true }
local searchResultsLabel = CreateFrame("Frame", nil, main)
searchResultsLabel:SetPoint("TOPLEFT", main, "TOPLEFT", CONTENT_INSET, -HEADER_TOTAL_OFFSET)
searchResultsLabel:SetPoint("TOPRIGHT", main, "TOPRIGHT", -CONTENT_INSET, -HEADER_TOTAL_OFFSET)
searchResultsLabel:SetHeight(TAB_HEIGHT)
searchResultsLabel:Hide()
local function refreshSearchIfActive()
    if AltArmy.TabFrames.Search and AltArmy.TabFrames.Search:IsShown() and headerSearchEdit then
        local query = headerSearchEdit:GetText()
        local trimmed = query and query:match("^%s*(.-)%s*$") or ""
        if trimmed ~= "" and AltArmy.TabFrames.Search.SearchWithQuery then
            AltArmy.TabFrames.Search:SearchWithQuery(trimmed)
        end
    end
end
local gap = 12
local itemsCheck = CreateFrame("CheckButton", nil, searchResultsLabel, "UICheckButtonTemplate")
itemsCheck:SetPoint("LEFT", searchResultsLabel, "LEFT", 0, 0)
itemsCheck:SetChecked(AltArmy.SearchCategories.Items)
itemsCheck:SetScript("OnClick", function()
    AltArmy.SearchCategories.Items = itemsCheck:GetChecked()
    refreshSearchIfActive()
end)
local itemsLabel = searchResultsLabel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
itemsLabel:SetPoint("LEFT", itemsCheck, "RIGHT", 2, 0)
itemsLabel:SetText("Items")
local recipesCheck = CreateFrame("CheckButton", nil, searchResultsLabel, "UICheckButtonTemplate")
recipesCheck:SetPoint("LEFT", itemsLabel, "RIGHT", gap, 0)
recipesCheck:SetChecked(AltArmy.SearchCategories.Recipes)
recipesCheck:SetScript("OnClick", function()
    AltArmy.SearchCategories.Recipes = recipesCheck:GetChecked()
    refreshSearchIfActive()
end)
local recipesLabel = searchResultsLabel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
recipesLabel:SetPoint("LEFT", recipesCheck, "RIGHT", 2, 0)
recipesLabel:SetText("Recipes")

local function enterSearchMode(trimmed)
    lastTab = AltArmy.CurrentTab
    tabStrip:Hide()
    searchResultsLabel:Show()
    if itemsCheck then itemsCheck:SetChecked(AltArmy.SearchCategories.Items) end
    if recipesCheck then recipesCheck:SetChecked(AltArmy.SearchCategories.Recipes) end
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
    updateSearchPlaceholderVisibility()
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
updateSearchPlaceholderVisibility()

main:SetScript("OnShow", function()
    lastTab = "Summary"
    if headerSearchEdit and headerSearchEdit.SetText then
        headerSearchEdit:SetText("")
    end
    exitSearchMode()
end)
