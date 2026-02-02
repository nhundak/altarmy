-- AltArmy TBC — Core: namespace, main frame, header, tabs, content frames

local ADDON_NAME = "AltArmy"
local ADDON_VERSION = "0.0.1"

-- Namespace
AltArmy = AltArmy or {}
AltArmy.Name = ADDON_NAME
AltArmy.Version = ADDON_VERSION
AltArmy.MainFrame = nil
AltArmy.TabFrames = {}
AltArmy.CurrentTab = "Summary"

-- Debug logging: only prints when options.debug is true; output is local (current player only)
function AltArmy.DebugLog(msg)
    if AltArmyTBC_Options and AltArmyTBC_Options.debug then
        print("[AltArmy] " .. tostring(msg))
    end
end

local FRAME_WIDTH = 600
local FRAME_HEIGHT = 400
local HEADER_HEIGHT = 24
local TAB_HEIGHT = 22
local CONTENT_INSET = 8

local setActiveTab -- forward-declare so header search scripts can call it

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
title:SetPoint("LEFT", headerBg, "LEFT", 16, 0)
title:SetText(ADDON_NAME)

-- Close button
local closeBtn = CreateFrame("Button", nil, main, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", main, "TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
    main:Hide()
end)

-- Header search: icon button (right) + EditBox (left of icon), vertically centered in header
local headerSearchBtn = CreateFrame("Button", nil, main)
headerSearchBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
headerSearchBtn:SetSize(24, 24)
headerSearchBtn:RegisterForClicks("LeftButtonUp")
local searchIcon = headerSearchBtn:CreateTexture(nil, "ARTWORK")
searchIcon:SetAllPoints(headerSearchBtn)
searchIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
searchIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
headerSearchBtn:SetScript("OnClick", function()
    local query = ""
    if headerSearchEdit then
        query = headerSearchEdit:GetText()
    end
    setActiveTab("Search")
    if AltArmy.TabFrames and AltArmy.TabFrames.Search and AltArmy.TabFrames.Search.SearchWithQuery then
        AltArmy.TabFrames.Search:SearchWithQuery(query)
    end
end)
headerSearchBtn:SetScript("OnEnter", function(self)
    searchIcon:SetAlpha(0.8)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Search")
end)
headerSearchBtn:SetScript("OnLeave", function()
    searchIcon:SetAlpha(1)
    GameTooltip:Hide()
end)

local headerSearchEdit = CreateFrame("EditBox", "AltArmyTBC_HeaderSearchEdit", main)
headerSearchEdit:SetPoint("RIGHT", headerSearchBtn, "LEFT", -4, 0)
headerSearchEdit:SetSize(280, 20)
headerSearchEdit:SetAutoFocus(false)
headerSearchEdit:SetFontObject("GameFontHighlight")
if headerSearchEdit.SetTextInsets then
    headerSearchEdit:SetTextInsets(6, 6, 0, 0)
end
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
    setActiveTab("Search")
    if AltArmy.TabFrames and AltArmy.TabFrames.Search and AltArmy.TabFrames.Search.SearchWithQuery then
        AltArmy.TabFrames.Search:SearchWithQuery(query)
    end
end)
headerSearchEdit:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
end)

-- Tab button strip (below header)
local tabStrip = CreateFrame("Frame", nil, main)
tabStrip:SetPoint("TOPLEFT", main, "TOPLEFT", CONTENT_INSET, -HEADER_HEIGHT - 4)
tabStrip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -CONTENT_INSET, -HEADER_HEIGHT - 4)
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

local tabNames = { "Summary", "Characters", "Search" }
tabStrip.buttons = {}
local prevBtn = nil
for _, tabName in ipairs(tabNames) do
    local btn = CreateFrame("Button", nil, tabStrip)
    btn.tabName = tabName
    btn:SetHeight(TAB_HEIGHT)
    btn:SetNormalFontObject("GameFontHighlight")
    btn:SetHighlightFontObject("GameFontNormal")
    btn:SetDisabledFontObject("GameFontNormal")
    btn:SetText(tabName)
    if prevBtn then
        btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    else
        btn:SetPoint("LEFT", tabStrip, "LEFT", 0, 0)
    end
    local selectedBg = btn:CreateTexture(nil, "BACKGROUND")
    selectedBg:SetAllPoints(btn)
    selectedBg:SetColorTexture(0.3, 0.3, 0.5, 0.6)
    btn.selectedBg = selectedBg
    selectedBg:Hide()
    btn:SetScript("OnClick", function()
        setActiveTab(tabName)
    end)
    prevBtn = btn
    tabStrip.buttons[tabName] = btn
end
setActiveTab("Summary")

-- Content area: one frame per tab
local contentArea = CreateFrame("Frame", nil, main)
contentArea:SetPoint("TOPLEFT", main, "TOPLEFT", CONTENT_INSET, -HEADER_HEIGHT - TAB_HEIGHT - 8)
contentArea:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)

for _, tabName in ipairs(tabNames) do
    local cf = CreateFrame("Frame", nil, contentArea)
    cf:SetAllPoints(contentArea)
    cf:SetShown(tabName == "Summary")
    AltArmy.TabFrames[tabName] = cf
end

-- Log when addon has finished loading (and optionally first run / new user)
main:RegisterEvent("ADDON_LOADED")
main:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "AltArmy_TBC" then
        AltArmy.DebugLog("Addon loaded")
        if AltArmy.firstRun then
            AltArmy.DebugLog("First run (new user): defaults applied")
        end
    end
end)

-- Fallback: run "loaded" log when main frame is first shown (in case ADDON_LOADED fires before chat is ready)
local loadedLogged = false
main:SetScript("OnShow", function()
    if not loadedLogged then
        loadedLogged = true
        print("[AltArmy] Addon ready (first open)")
        if AltArmy.DebugLog then
            AltArmy.DebugLog("Addon ready (first open)")
        end
    end
end)
