-- AltArmy TBC — One-time development-status notice dialog.
-- luacheck: globals UISpecialFrames UIParent

if not AltArmy then return end

local Theme = AltArmy.Theme
local DSN = AltArmy.DevStatusNotice

local ADDON_NAME = "Alt Army"
local CONTENT_INSET = 8
local HEADER_SECTION_GAP = 4
local HEADER_PANEL_HEIGHT = 28
local PARAGRAPH_GAP = 14
local BUTTON_TOP_GAP = 18
local BUTTON_HEIGHT = 24
local BUTTON_WIDTH = 140
local DIALOG_WIDTH = 460
local DIALOG_HEIGHT = 255

local dialog = Theme.CreatePanel(UIParent, "window", "AltArmyTBC_DevStatusNoticeDialog")
dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
dialog:Hide()
dialog:SetFrameStrata("DIALOG")
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:SetClampedToScreen(true)

UISpecialFrames = UISpecialFrames or {}
tinsert(UISpecialFrames, "AltArmyTBC_DevStatusNoticeDialog")

local headerPanel = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
headerPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
headerPanel:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
headerPanel:SetHeight(HEADER_PANEL_HEIGHT)
headerPanel:EnableMouse(true)
headerPanel:RegisterForDrag("LeftButton")
headerPanel:SetScript("OnDragStart", function()
    dialog:StartMoving()
end)
headerPanel:SetScript("OnDragStop", function()
    dialog:StopMovingOrSizing()
end)
Theme.ApplyBackdrop(headerPanel, "section")

local headerTitle = headerPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
headerTitle:SetPoint("LEFT", headerPanel, "LEFT", Theme.TAB_CONTENT_PADDING, 0)
headerTitle:SetText(ADDON_NAME)
Theme.SetTitleColor(headerTitle)

local bodyPanel = Theme.CreateTabContentPanel(dialog)
bodyPanel:SetPoint(
    "TOPLEFT",
    dialog,
    "TOPLEFT",
    CONTENT_INSET,
    -(CONTENT_INSET + HEADER_PANEL_HEIGHT + HEADER_SECTION_GAP))
bodyPanel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)

local bodyInner = Theme.CreatePanelInnerContent(bodyPanel)

local progressText = bodyInner:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
progressText:SetPoint("TOPLEFT", bodyInner, "TOPLEFT", 0, 0)
progressText:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
progressText:SetJustifyH("LEFT")
progressText:SetWordWrap(true)
progressText:SetTextColor(1, 1, 1, 1)
progressText:SetText("Alt Army has mostly been updated to work with Forever!")

local savedVarsText = bodyInner:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
savedVarsText:SetPoint("TOPLEFT", progressText, "BOTTOMLEFT", 0, -PARAGRAPH_GAP)
savedVarsText:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
savedVarsText:SetJustifyH("LEFT")
savedVarsText:SetWordWrap(true)
savedVarsText:SetTextColor(0.75, 0.75, 0.75, 1)
savedVarsText:SetText(
    "However, one critical issue remains. When the game boots up, Blizzard is not loading"
    .. " SavedVariables. As a result, any addon that needs to remember data from a previous"
    .. " session cannot do so. This has a big impact on Alt Army, since it's all about recalling"
    .. " data from previous sessions.")

local hopefulText = bodyInner:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
hopefulText:SetPoint("TOPLEFT", savedVarsText, "BOTTOMLEFT", 0, -PARAGRAPH_GAP)
hopefulText:SetPoint("RIGHT", bodyInner, "RIGHT", 0, 0)
hopefulText:SetJustifyH("LEFT")
hopefulText:SetWordWrap(true)
hopefulText:SetTextColor(0.75, 0.75, 0.75, 1)
hopefulText:SetText("Blizzard should hopefully fix this soon, and then you won't see this message any more.")

local btnGotIt = CreateFrame("Button", nil, bodyInner, "UIPanelButtonTemplate")
btnGotIt:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
btnGotIt:SetPoint("TOP", hopefulText, "BOTTOM", 0, -BUTTON_TOP_GAP)
btnGotIt:SetText("Got it")
Theme.SkinButton(btnGotIt)

local onDismissCallback

local function hideDialog()
    dialog:Hide()
    local callback = onDismissCallback
    onDismissCallback = nil
    if callback then
        callback()
    end
end

local function onGotIt()
    if DSN and DSN.Dismiss then
        DSN.Dismiss()
    end
    local ODQ = AltArmy.OnboardingDialogQueue
    if ODQ and ODQ.SuppressForSession then
        ODQ.SuppressForSession()
    end
    hideDialog()
end

btnGotIt:SetScript("OnClick", onGotIt)

AltArmy.DevStatusNoticeDialog = AltArmy.DevStatusNoticeDialog or {}

function AltArmy.DevStatusNoticeDialog.Show(onDismiss)
    onDismissCallback = onDismiss
    dialog:Show()
end

function AltArmy.DevStatusNoticeDialog.ShowDebug()
    AltArmy.DevStatusNoticeDialog.Show()
    return true
end

function AltArmy.DevStatusNoticeDialog.Hide()
    hideDialog()
end

if DSN and DSN.RegisterOnboardingProvider then
    DSN.RegisterOnboardingProvider()
end
