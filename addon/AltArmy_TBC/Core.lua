-- AltArmy TBC — Core: namespace, main frame, header, tabs, content frames

local ADDON_NAME = "AltArmy TBC"
local ADDON_VERSION = "1.0.0"

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

-- Create main frame
local main = CreateFrame("Frame", "AltArmyTBC_MainFrame", UIParent)
main:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
main:SetPoint("CENTER", 0, 0)
main:SetMovable(true)
main:SetClampedToScreen(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", function(f) f:StartMoving() end)
main:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
-- SetBackdrop is not available in all TBC Classic builds; use a simple background texture
local bg = main:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(main)
bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
bg:SetTexCoord(0, 1, 0, 1)
main:Hide()

AltArmy.MainFrame = main

-- Header background
local headerBg = main:CreateTexture(nil, "ARTWORK")
headerBg:SetPoint("TOPLEFT", main, "TOPLEFT", 8, -8)
headerBg:SetPoint("TOPRIGHT", main, "TOPRIGHT", -8, -8)
headerBg:SetHeight(HEADER_HEIGHT)
headerBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)

-- Title
local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", main, "TOPLEFT", 16, -HEADER_HEIGHT / 2 - 2)
title:SetText(ADDON_NAME)

-- Close button
local closeBtn = CreateFrame("Button", nil, main, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", main, "TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
    main:Hide()
end)

-- Optional: placeholder search box in header (no behavior yet)
local searchBox = CreateFrame("EditBox", nil, main)
searchBox:SetSize(140, 20)
searchBox:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
searchBox:SetAutoFocus(false)
searchBox:SetFontObject("GameFontHighlight")
searchBox:SetTextInsets(4, 4, 0, 0)
local searchBg = searchBox:CreateTexture(nil, "BACKGROUND")
searchBg:SetAllPoints(searchBox)
searchBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
searchBox:SetScript("OnEscapePressed", function() searchBox:ClearFocus() end)
AltArmy.HeaderSearchBox = searchBox

-- Tab button strip (below header)
local tabStrip = CreateFrame("Frame", nil, main)
tabStrip:SetPoint("TOPLEFT", main, "TOPLEFT", CONTENT_INSET, -HEADER_HEIGHT - 4)
tabStrip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -CONTENT_INSET, -HEADER_HEIGHT - 4)
tabStrip:SetHeight(TAB_HEIGHT)

local function setActiveTab(tabName)
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
