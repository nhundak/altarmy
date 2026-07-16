-- AltArmy TBC — Core: namespace, main frame, header, tabs, content frames

local ADDON_NAME = "Alt Army"
local ADDON_VERSION = "1.8.5"

-- Namespace
AltArmy = AltArmy or {}
AltArmy.Name = ADDON_NAME
AltArmy.Version = ADDON_VERSION
AltArmy.MainFrame = nil
AltArmy.TabFrames = {}
AltArmy.CurrentTab = "Summary"

AltArmyTBC_Options = AltArmyTBC_Options or {}

local Theme = AltArmy.Theme

local FRAME_WIDTH = 640
local FRAME_HEIGHT = 420
local TAB_HEIGHT = 22
local CONTENT_INSET = 8
local HEADER_TOTAL_OFFSET = 40  -- CONTENT_INSET + header section + gap before tab strip

local setActiveTab -- forward-declare so header search scripts can call it
local exitSearchMode -- forward-declare; OpenGearTabFocused uses it when frame already visible
local UpdateSettingsButtonGlow -- forward-declare; defined after settings buttons exist
local searchModeHandlers = {}  -- enterSearchMode impl registered later (avoids nil if load errors)
local function enterSearchMode(trimmed)
    local fn = searchModeHandlers.enterSearchMode
    if fn then fn(trimmed) end
end
local lastTab = "Summary"
local pendingOpenTab = nil
local pendingGearFocusLink = nil

-- Create main frame
local main = CreateFrame("Frame", "AltArmyTBC_MainFrame", UIParent)
main:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
main:SetPoint("CENTER", 0, 0)
main:SetFrameStrata("DIALOG")
main:SetFrameLevel(100)
if main.SetToplevel then
    main:SetToplevel(true)
end
main:SetMovable(true)
main:SetClampedToScreen(true)
main:EnableMouse(true)
main:HookScript("OnShow", function(f)
    if f.Raise then
        f:Raise()
    end
end)
Theme.ApplyBackdrop(main, "window")
main:Hide()

AltArmy.MainFrame = main

-- Dismiss UI when Escape is pressed (WoW closes topmost frame in UISpecialFrames)
UISpecialFrames = UISpecialFrames or {}
tinsert(UISpecialFrames, "AltArmyTBC_MainFrame")

-- Header section (title, search, close) — same nearly-opaque card + bronze border as tab panels
local HEADER_SECTION_GAP = 4
local HEADER_PANEL_HEIGHT = HEADER_TOTAL_OFFSET - CONTENT_INSET - HEADER_SECTION_GAP
local headerPanel = CreateFrame("Frame", nil, main, "BackdropTemplate")
headerPanel:SetPoint("TOPLEFT", main, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
headerPanel:SetPoint("TOPRIGHT", main, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
headerPanel:SetHeight(HEADER_PANEL_HEIGHT)
headerPanel:EnableMouse(true)
headerPanel:RegisterForDrag("LeftButton")
headerPanel:SetScript("OnDragStart", function()
    main:StartMoving()
end)
headerPanel:SetScript("OnDragStop", function()
    main:StopMovingOrSizing()
end)
Theme.ApplyBackdrop(headerPanel, "section")

-- Title (vertically centered in header)
local title = headerPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", headerPanel, "LEFT", Theme.TAB_CONTENT_PADDING, 0)
title:SetText(ADDON_NAME)
Theme.SetTitleColor(title)

-- Close button (vertically centered like title)
local closeBtn = CreateFrame("Button", nil, headerPanel, "UIPanelCloseButton")
closeBtn:SetPoint("RIGHT", headerPanel, "RIGHT", 2, 0)
_G.AltArmyTBC_HeaderCloseButton = closeBtn
closeBtn:SetScript("OnClick", function()
    main:Hide()
end)

-- Header search: EditBox to the left of close button (vertically centered in header)
local headerSearchEdit = CreateFrame("EditBox", "AltArmyTBC_HeaderSearchEdit", headerPanel)
headerSearchEdit:SetPoint("RIGHT", closeBtn, "LEFT", 2, 0)
headerSearchEdit:SetSize(288, 20)
headerSearchEdit:SetAutoFocus(false)
headerSearchEdit:SetFontObject("GameFontHighlight")
if headerSearchEdit.SetTextInsets then
    headerSearchEdit:SetTextInsets(6, 6, 0, 0)
end
Theme.SetupEditBoxPlaceholder(headerSearchEdit, "Search for items or recipes")

-- Clear (X) button at start of input; only visible when there is text
local headerSearchClearBtn = CreateFrame("Button", nil, headerPanel)
headerSearchClearBtn:SetPoint("RIGHT", headerSearchEdit, "LEFT", -2, 0)
headerSearchClearBtn:SetSize(18, 18)
headerSearchClearBtn:SetScript("OnClick", function()
    Theme.ClearEditBoxText(headerSearchEdit)
end)
headerSearchClearBtn:Hide()
local clearBtnLabel = headerSearchClearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
clearBtnLabel:SetPoint("CENTER", headerSearchClearBtn, "CENTER", 0, 0)
clearBtnLabel:SetText("X")
headerSearchClearBtn:SetHighlightFontObject("GameFontNormal")

Theme.ApplyInputTextures(headerSearchEdit)
headerSearchEdit:SetScript("OnEnterPressed", function(box)
    box:ClearFocus()
    local query = box:GetText()
    local trimmed = query and query:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" then
        if trimmed:lower() == "/reload" then
            ReloadUI()
            return
        end
        if enterSearchMode then
            enterSearchMode(trimmed)
        end
    end
end)
headerSearchEdit:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
end)
-- OnTextChanged registered below after enterSearchMode/exitSearchMode are defined

local function itemLinksReferToSameItem(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local function itemId(link)
        return tonumber(tostring(link):match("item:(%d+)"))
    end
    local idA, idB = itemId(a), itemId(b)
    return idA ~= nil and idA == idB
end

-- Expose for clearing header search and switching to Summary (e.g. from other code)
function AltArmy.OpenGearTabFocused(itemLink)
    pendingOpenTab = "Gear"
    pendingGearFocusLink = itemLink
    lastTab = "Gear"
    if not AltArmy.MainFrame or not AltArmy.MainFrame.Show then return end
    if AltArmy.MainFrame.IsShown and AltArmy.MainFrame:IsShown() then
        local gearFrame = AltArmy.TabFrames and AltArmy.TabFrames.Gear
        if AltArmy.CurrentTab == "Gear"
            and gearFrame
            and gearFrame.GetFocusedItemLink
            and itemLink
            and itemLinksReferToSameItem(gearFrame:GetFocusedItemLink(), itemLink) then
            pendingOpenTab = nil
            pendingGearFocusLink = nil
            AltArmy.MainFrame:Hide()
            return
        end
        pendingOpenTab = nil
        pendingGearFocusLink = nil
        if headerSearchEdit and headerSearchEdit.SetText then
            headerSearchEdit:SetText("")
        end
        exitSearchMode()
        setActiveTab("Gear")
        if gearFrame and gearFrame.FocusItem and itemLink then
            gearFrame:FocusItem(itemLink)
        end
        return
    end
    AltArmy.MainFrame:Show()
end

function AltArmy.SwitchToSummaryTab()
    lastTab = "Summary"
    if headerSearchEdit and headerSearchEdit.SetText then
        headerSearchEdit:SetText("")
    end
end

-- Tab button strip (below header; leave clear space so tabs don't overlap header)
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
            btn:SetEnabled(btn.tabName == "Gear" or btn.tabName == "Reputation" or false)
            if btn.SetSelected then btn:SetSelected(true) end
        else
            btn:SetEnabled(true)
            if btn.SetSelected then btn:SetSelected(false) end
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
    -- Summary tab settings button: only visible when Summary tab is active and tab strip is shown
    if tabStrip.summarySettingsBtn then
        if tabName == "Summary" and tabStrip:IsShown() then
            tabStrip.summarySettingsBtn:Show()
        else
            tabStrip.summarySettingsBtn:Hide()
        end
    end
    if tabStrip.reputationSettingsBtn then
        if tabName == "Reputation" and tabStrip:IsShown() then
            tabStrip.reputationSettingsBtn:Show()
        else
            tabStrip.reputationSettingsBtn:Hide()
        end
    end
    if tabStrip.cooldownSettingsBtn then
        if tabName == "Cooldowns" and tabStrip:IsShown() then
            tabStrip.cooldownSettingsBtn:Show()
        else
            tabStrip.cooldownSettingsBtn:Hide()
        end
    end
    if searchModeHandlers.searchSettingsBtn then
        searchModeHandlers.searchSettingsBtn:Hide()
    end
    UpdateSettingsButtonGlow()
end

local TAB_BTN_MIN_WIDTH = 72
-- "Guild" is always created but its button is only shown when the guildShare feature flag is on
-- and at least one character on the current realm is in a guild (see updateGuildTabVisibility).
-- It is kept last so hiding it never leaves a gap in the strip.
local tabNames = { "Summary", "Gear", "Reputation", "Cooldowns", "Graph", "Guild" }
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
    -- Label (plain Button has no built-in text)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(tabName == "Graph" and "Graphs" or tabName)
    btn.label = label
    Theme.SkinButton(btn, true)
    btn:SetScript("OnClick", function()
        setActiveTab(tabName)
    end)
    prevBtn = btn
    tabStrip.buttons[tabName] = btn
end

-- Guild tab: only visible when the guildShare feature flag is on and the current realm has at
-- least one guilded character. Debug.lua / DataStore load after Core, so we evaluate lazily (on
-- frame show / when the flag or guild membership changes) rather than at load.
local function updateGuildTabVisibility()
    local btn = tabStrip.buttons["Guild"]
    if not btn then return end
    local GTD = AltArmy.GuildTabData
    local on = GTD and GTD.CanShowGuildTab and GTD.CanShowGuildTab()
    btn:SetShown(on and true or false)
    if not on and AltArmy.CurrentTab == "Guild" then
        setActiveTab("Summary")
    end
end
AltArmy.UpdateGuildTabVisibility = updateGuildTabVisibility
updateGuildTabVisibility()

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

-- Reputation tab: same pattern as Gear (toggle settings when clicking tab again)
tabStrip.buttons["Reputation"]:SetScript("OnClick", function()
    if AltArmy.CurrentTab == "Reputation"
        and AltArmy.TabFrames.Reputation
        and AltArmy.TabFrames.Reputation.IsReputationSettingsShown
        and AltArmy.TabFrames.Reputation:IsReputationSettingsShown() then
        AltArmy.TabFrames.Reputation:ToggleReputationSettings()
    else
        setActiveTab("Reputation")
    end
end)

-- Glow texture for settings buttons when their panel is active (shown behind icon)
local function addSettingsButtonGlow(btn)
    Theme.InstallSettingsButtonGlow(btn, "glow")
end

UpdateSettingsButtonGlow = function()
    if tabStrip.gearSettingsBtn and tabStrip.gearSettingsBtn:IsShown() and tabStrip.gearSettingsBtn.glow then
        local active = AltArmy.TabFrames.Gear and AltArmy.TabFrames.Gear.IsGearSettingsShown
            and AltArmy.TabFrames.Gear:IsGearSettingsShown()
        tabStrip.gearSettingsBtn.glow:SetShown(active)
    end
    if tabStrip.summarySettingsBtn and tabStrip.summarySettingsBtn:IsShown() and tabStrip.summarySettingsBtn.glow then
        local active = AltArmy.TabFrames.Summary and AltArmy.TabFrames.Summary.IsSummarySettingsShown
            and AltArmy.TabFrames.Summary:IsSummarySettingsShown()
        tabStrip.summarySettingsBtn.glow:SetShown(active)
    end
    if tabStrip.reputationSettingsBtn and tabStrip.reputationSettingsBtn:IsShown()
        and tabStrip.reputationSettingsBtn.glow then
        local active = AltArmy.TabFrames.Reputation and AltArmy.TabFrames.Reputation.IsReputationSettingsShown
            and AltArmy.TabFrames.Reputation:IsReputationSettingsShown()
        tabStrip.reputationSettingsBtn.glow:SetShown(active)
    end
    if searchModeHandlers.searchSettingsBtn and searchModeHandlers.searchSettingsBtn:IsShown()
        and searchModeHandlers.searchSettingsBtn.glow then
        local settingsOpen = AltArmy.TabFrames.Search and AltArmy.TabFrames.Search.IsSearchSettingsShown
            and AltArmy.TabFrames.Search:IsSearchSettingsShown()
        local filterActive = false
        local SS = AltArmy.SearchSettings
        if SS and SS.IsAnyRecipeFilterActive then
            filterActive = SS.IsAnyRecipeFilterActive()
        end
        searchModeHandlers.searchSettingsBtn.glow:SetShown(settingsOpen or filterActive)
        if searchModeHandlers.searchFiltersActiveLabel then
            searchModeHandlers.searchFiltersActiveLabel:SetShown(filterActive)
        end
    elseif searchModeHandlers.searchFiltersActiveLabel then
        searchModeHandlers.searchFiltersActiveLabel:Hide()
    end
end

AltArmy.UpdateSearchSettingsButtonGlow = UpdateSettingsButtonGlow

local function createTabSettingsButton(onClick)
    local btn = CreateFrame("Button", nil, tabStrip)
    btn:SetPoint("TOPRIGHT", tabStrip, "TOPRIGHT", 0, 0)
    btn:SetSize(TAB_HEIGHT, TAB_HEIGHT)
    btn:Hide()
    addSettingsButtonGlow(btn)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexture("Interface\\Icons\\Trade_Engineering")
    Theme.SkinSettingsIconButton(btn)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- Gear tab settings icon (top right of tab strip; visible only when Gear tab is active)
local gearSettingsBtn = createTabSettingsButton(function()
    if AltArmy.TabFrames.Gear and AltArmy.TabFrames.Gear.ToggleGearSettings then
        AltArmy.TabFrames.Gear:ToggleGearSettings()
        UpdateSettingsButtonGlow()
    end
end)
tabStrip.gearSettingsBtn = gearSettingsBtn

-- Summary tab settings icon (same position as Gear; visible only when Summary tab is active)
local summarySettingsBtn = createTabSettingsButton(function()
    if AltArmy.TabFrames.Summary and AltArmy.TabFrames.Summary.ToggleSummarySettings then
        AltArmy.TabFrames.Summary:ToggleSummarySettings()
        UpdateSettingsButtonGlow()
    end
end)
tabStrip.summarySettingsBtn = summarySettingsBtn

-- Reputation tab settings icon (same position; visible only when Reputation tab is active)
local reputationSettingsBtn = createTabSettingsButton(function()
    if AltArmy.TabFrames.Reputation and AltArmy.TabFrames.Reputation.ToggleReputationSettings then
        AltArmy.TabFrames.Reputation:ToggleReputationSettings()
        UpdateSettingsButtonGlow()
    end
end)
tabStrip.reputationSettingsBtn = reputationSettingsBtn

-- Cooldowns tab settings icon — opens Interface > AddOns > AltArmy (same position as other tab gears).
local cooldownSettingsBtn = createTabSettingsButton(function()
    if AltArmy.OpenInterfaceOptions then
        AltArmy.OpenInterfaceOptions("cooldowns")
    end
end)
tabStrip.cooldownSettingsBtn = cooldownSettingsBtn

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

-- Register enterSearchMode handler early (before check buttons etc.) so it exists even if later UI errors.
-- Handler reads refs from searchModeHandlers as we fill them in below.
searchModeHandlers.tabStrip = tabStrip
searchModeHandlers.enterSearchMode = function(trimmed)
    local strip = searchModeHandlers.tabStrip
    local resultsLabel = searchModeHandlers.searchResultsLabel
    local itemsChk = searchModeHandlers.itemsCheck
    local recipesChk = searchModeHandlers.recipesCheck
    if not strip or not resultsLabel then
        return
    end
    lastTab = AltArmy.CurrentTab
    strip:Hide()
    resultsLabel:Show()
    local searchBtn = searchModeHandlers.searchSettingsBtn
    if searchBtn then
        searchBtn:Show()
    end
    if itemsChk then itemsChk:SetChecked(AltArmy.SearchCategories.Items) end
    if recipesChk then recipesChk:SetChecked(AltArmy.SearchCategories.Recipes) end
    if AltArmy.RefreshSearchCategoryBar then AltArmy.RefreshSearchCategoryBar() end
    for name, tabFrame in pairs(AltArmy.TabFrames) do
        if name ~= "Search" then
            tabFrame:Hide()
        end
    end
    if AltArmy.TabFrames.Search then
        AltArmy.TabFrames.Search:Show()
        if AltArmy.TabFrames.Search.SearchWithQuery then
            AltArmy.TabFrames.Search:SearchWithQuery(trimmed)
        end
    end
    UpdateSettingsButtonGlow()
end

-- Search category filter checkboxes (replace tab strip when in search mode)
AltArmy.SearchCategories = AltArmy.SearchCategories or { Items = true, Recipes = true }
local searchResultsLabel = CreateFrame("Frame", nil, main)
searchModeHandlers.searchResultsLabel = searchResultsLabel
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
local updateGuildmateRecipesControlEnabled
local itemsCheck = CreateFrame("CheckButton", nil, searchResultsLabel, "UICheckButtonTemplate")
searchModeHandlers.itemsCheck = itemsCheck
itemsCheck:SetScript("OnClick", function() end)  -- set before any GetScript("OnClick") from template
itemsCheck:SetPoint("LEFT", searchResultsLabel, "LEFT", 0, 0)
itemsCheck:SetChecked(AltArmy.SearchCategories.Items)
itemsCheck:SetScript("OnClick", function()
    AltArmy.SearchCategories.Items = itemsCheck:GetChecked()
    refreshSearchIfActive()
end)
local itemsLabelFrame = CreateFrame("Button", nil, searchResultsLabel)
itemsLabelFrame:SetPoint("LEFT", itemsCheck, "RIGHT", 2, 0)
itemsLabelFrame:SetSize(50, TAB_HEIGHT)
itemsLabelFrame:EnableMouse(true)
itemsLabelFrame:SetScript("OnClick", function()
    itemsCheck:Click()
end)
local itemsLabel = itemsLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
itemsLabel:SetPoint("LEFT", itemsLabelFrame, "LEFT", 0, 0)
itemsLabel:SetText("Items")
local recipesCheck = CreateFrame("CheckButton", nil, searchResultsLabel, "UICheckButtonTemplate")
searchModeHandlers.recipesCheck = recipesCheck
recipesCheck:SetScript("OnClick", function() end)  -- set before any GetScript("OnClick") from template
recipesCheck:SetPoint("LEFT", itemsLabelFrame, "RIGHT", gap, 0)
recipesCheck:SetChecked(AltArmy.SearchCategories.Recipes)
recipesCheck:SetScript("OnClick", function()
    AltArmy.SearchCategories.Recipes = recipesCheck:GetChecked()
    updateGuildmateRecipesControlEnabled()
    refreshSearchIfActive()
end)
local recipesLabelFrame = CreateFrame("Button", nil, searchResultsLabel)
recipesLabelFrame:SetPoint("LEFT", recipesCheck, "RIGHT", 2, 0)
recipesLabelFrame:SetSize(60, TAB_HEIGHT)
recipesLabelFrame:EnableMouse(true)
recipesLabelFrame:SetScript("OnClick", function()
    recipesCheck:Click()
end)
local recipesLabel = recipesLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
recipesLabel:SetPoint("LEFT", recipesLabelFrame, "LEFT", 0, 0)
recipesLabel:SetText("Recipes")

local includeGuildCheck = CreateFrame("CheckButton", nil, searchResultsLabel, "UICheckButtonTemplate")
searchModeHandlers.includeGuildCheck = includeGuildCheck
includeGuildCheck:SetScript("OnClick", function() end)
includeGuildCheck:SetPoint("LEFT", recipesLabelFrame, "RIGHT", gap, 0)
includeGuildCheck:SetScript("OnClick", function()
    local SS = AltArmy.SearchSettings
    if SS and SS.SetIncludeGuildmatesEnabled then
        SS.SetIncludeGuildmatesEnabled(includeGuildCheck:GetChecked())
    end
    refreshSearchIfActive()
end)
local includeGuildLabelFrame = CreateFrame("Button", nil, searchResultsLabel)
includeGuildLabelFrame:SetPoint("LEFT", includeGuildCheck, "RIGHT", 2, 0)
includeGuildLabelFrame:SetSize(130, TAB_HEIGHT)
includeGuildLabelFrame:EnableMouse(true)
includeGuildLabelFrame:SetScript("OnClick", function()
    includeGuildCheck:Click()
end)
local includeGuildLabel = includeGuildLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
includeGuildLabel:SetPoint("LEFT", includeGuildLabelFrame, "LEFT", 0, 0)
includeGuildLabel:SetText("Guildmate recipes")
includeGuildCheck:Hide()
includeGuildLabelFrame:Hide()

local function setGuildmateRecipesCaptionMuted(muted)
    if not includeGuildLabel then return end
    if muted then
        includeGuildLabel:SetTextColor(0.5, 0.5, 0.5)
    else
        includeGuildLabel:SetTextColor(1, 1, 1)
    end
end

updateGuildmateRecipesControlEnabled = function()
    if not includeGuildCheck or not includeGuildLabelFrame then return end
    local recipesEnabled = AltArmy.SearchCategories.Recipes and true or false
    if recipesEnabled then
        includeGuildCheck:Enable()
        includeGuildLabelFrame:EnableMouse(true)
        setGuildmateRecipesCaptionMuted(false)
    else
        includeGuildCheck:Disable()
        includeGuildLabelFrame:EnableMouse(false)
        setGuildmateRecipesCaptionMuted(true)
    end
end

local function refreshIncludeGuildmatesCheck()
    if not includeGuildCheck then return end
    local SS = AltArmy.SearchSettings
    local show = SS and SS.CanShowIncludeGuildmatesToggle and SS.CanShowIncludeGuildmatesToggle()
    includeGuildCheck:SetShown(show)
    includeGuildLabelFrame:SetShown(show)
    if show and SS.IsIncludeGuildmatesEnabled then
        includeGuildCheck:SetChecked(SS.IsIncludeGuildmatesEnabled())
    end
    updateGuildmateRecipesControlEnabled()
end

function AltArmy.RefreshSearchCategoryBar()
    refreshIncludeGuildmatesCheck()
end

local searchSettingsBtn = CreateFrame("Button", nil, searchResultsLabel)
searchSettingsBtn:SetPoint("TOPRIGHT", searchResultsLabel, "TOPRIGHT", 0, 0)
searchSettingsBtn:SetSize(TAB_HEIGHT, TAB_HEIGHT)
searchSettingsBtn:Hide()
Theme.InstallSettingsButtonGlow(searchSettingsBtn, "glow")
local searchSettingsIcon = searchSettingsBtn:CreateTexture(nil, "ARTWORK")
searchSettingsIcon:SetAllPoints(searchSettingsBtn)
searchSettingsIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
Theme.SkinSettingsIconButton(searchSettingsBtn)
searchSettingsBtn:SetScript("OnClick", function()
    if AltArmy.TabFrames.Search and AltArmy.TabFrames.Search.ToggleSearchSettings then
        AltArmy.TabFrames.Search:ToggleSearchSettings()
        UpdateSettingsButtonGlow()
    end
end)
searchModeHandlers.searchSettingsBtn = searchSettingsBtn

local searchFiltersActiveLabel = searchResultsLabel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
searchFiltersActiveLabel:SetPoint("RIGHT", searchSettingsBtn, "LEFT", -6, 0)
searchFiltersActiveLabel:SetJustifyH("RIGHT")
searchFiltersActiveLabel:SetText("Filters Active")
if Theme.SetTitleColor then
    Theme.SetTitleColor(searchFiltersActiveLabel)
end
searchFiltersActiveLabel:Hide()
searchModeHandlers.searchFiltersActiveLabel = searchFiltersActiveLabel

exitSearchMode = function()
    searchResultsLabel:Hide()
    if searchSettingsBtn then
        searchSettingsBtn:Hide()
    end
    if AltArmy.TabFrames.Search
        and AltArmy.TabFrames.Search.IsSearchSettingsShown
        and AltArmy.TabFrames.Search:IsSearchSettingsShown()
        and AltArmy.TabFrames.Search.ToggleSearchSettings then
        AltArmy.TabFrames.Search:ToggleSearchSettings()
    end
    tabStrip:Show()
    if AltArmy.TabFrames.Search then AltArmy.TabFrames.Search:Hide() end
    if AltArmy.TabFrames[lastTab] then AltArmy.TabFrames[lastTab]:Show() end
    setActiveTab(lastTab)
end

--- Show Guild character recipe view from a search recipe row; Back returns to search.
--- Optional professionKey/professionName select the matching profession tab.
--- Optional recipeID focuses/scrolls to that recipe row.
function AltArmy.OpenGuildCharacterFromSearch(characterName, realm, professionKey, professionName, recipeID)
    local Nav = AltArmy.SearchGuildNav
    if not Nav or not Nav.ResolveGuildMember then return false end
    local entry = Nav.ResolveGuildMember(characterName, realm)
    if not entry then return false end
    local guildFrame = AltArmy.TabFrames and AltArmy.TabFrames.Guild
    if not guildFrame or not guildFrame.ShowCharacterFromSearch then return false end

    Nav.Begin()
    searchResultsLabel:Hide()
    if searchSettingsBtn then
        searchSettingsBtn:Hide()
    end
    if AltArmy.TabFrames.Search then
        AltArmy.TabFrames.Search:Hide()
    end
    guildFrame:ShowCharacterFromSearch(entry, professionKey, professionName, recipeID)
    return true
end

--- Called by Guild Back when the character view was opened from search.
function AltArmy.ReturnToSearchFromGuildCharacter()
    local Nav = AltArmy.SearchGuildNav
    if Nav then Nav.End() end
    local guildFrame = AltArmy.TabFrames and AltArmy.TabFrames.Guild
    if guildFrame and guildFrame.ClearSearchDrillIn then
        guildFrame:ClearSearchDrillIn()
    elseif guildFrame then
        guildFrame:Hide()
    end
    local query = headerSearchEdit and headerSearchEdit:GetText() or ""
    local trimmed = query:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then
        exitSearchMode()
        if headerSearchClearBtn then headerSearchClearBtn:Hide() end
    else
        if headerSearchClearBtn then headerSearchClearBtn:Show() end
        enterSearchMode(trimmed)
    end
end

local function applySearchBoxState()
    local query = headerSearchEdit:GetText()
    local trimmed = query and query:match("^%s*(.-)%s*$") or ""
    Theme.UpdateEditBoxPlaceholderVisibility(headerSearchEdit)

    local Nav = AltArmy.SearchGuildNav
    local navAction = Nav and Nav.OnHeaderSearchTextChanged and Nav.OnHeaderSearchTextChanged(trimmed) or "ignore"
    if navAction ~= "ignore" then
        local guildFrame = AltArmy.TabFrames and AltArmy.TabFrames.Guild
        if guildFrame and guildFrame.ClearSearchDrillIn then
            guildFrame:ClearSearchDrillIn()
        elseif guildFrame then
            guildFrame:Hide()
        end
    end

    if trimmed == "" then
        exitSearchMode()
        headerSearchClearBtn:Hide()
    else
        headerSearchClearBtn:Show()
        enterSearchMode(trimmed)  -- switch to search results on any character
    end
end

headerSearchEdit:SetScript("OnTextChanged", applySearchBoxState)
headerSearchEdit:SetScript("OnEditFocusGained", function(self)
    Theme.UpdateEditBoxPlaceholderVisibility(self)
end)
headerSearchEdit:SetScript("OnEditFocusLost", function(self)
    Theme.UpdateEditBoxPlaceholderVisibility(self)
end)
Theme.UpdateEditBoxPlaceholderVisibility(headerSearchEdit)

main:SetScript("OnShow", function()
    updateGuildTabVisibility()
    local openTab = pendingOpenTab or "Summary"
    pendingOpenTab = nil
    lastTab = openTab
    if headerSearchEdit and headerSearchEdit.SetText then
        headerSearchEdit:SetText("")
    end
    exitSearchMode()
    if openTab == "Gear" then
        setActiveTab("Gear")
    end
    if openTab == "Gear" and pendingGearFocusLink then
        local gearFrame = AltArmy.TabFrames and AltArmy.TabFrames.Gear
        local link = pendingGearFocusLink
        pendingGearFocusLink = nil
        if gearFrame and gearFrame.FocusItem then
            gearFrame:FocusItem(link)
        end
    end
end)
