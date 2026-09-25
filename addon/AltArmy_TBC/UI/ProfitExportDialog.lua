-- AltArmy TBC — Export dialog: shows ProfitExport's string, selected, to copy with Ctrl+C and paste on the
-- altarmy-profit site's Upload tab. Opened only by `/altarmy export` (no button in the UI).
-- luacheck: globals UISpecialFrames UIParent

if not AltArmy then return end

local Theme = AltArmy.Theme

local UI = {
    INSET = 8,
    HEADER_GAP = 4,
    HEADER_HEIGHT = 28,
    GAP = 12,
    BUTTON_HEIGHT = 24,
    BUTTON_WIDTH = 120,
    WIDTH = 520,
    HEIGHT = 170,
}

local dialog = Theme.CreatePanel(UIParent, "window", "AltArmyTBC_ProfitExportDialog")
dialog:SetSize(UI.WIDTH, UI.HEIGHT)
dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
dialog:Hide()
dialog:SetFrameStrata("DIALOG")
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:SetClampedToScreen(true)

UISpecialFrames = UISpecialFrames or {}
tinsert(UISpecialFrames, "AltArmyTBC_ProfitExportDialog")

local header = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
header:SetPoint("TOPLEFT", dialog, "TOPLEFT", UI.INSET, -UI.INSET)
header:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -UI.INSET, -UI.INSET)
header:SetHeight(UI.HEADER_HEIGHT)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function()
    dialog:StartMoving()
end)
header:SetScript("OnDragStop", function()
    dialog:StopMovingOrSizing()
end)
Theme.ApplyBackdrop(header, "section")

local title = header:CreateFontString(nil, "OVERLAY", Theme.FONTS.title)
title:SetPoint("LEFT", header, "LEFT", Theme.TAB_CONTENT_PADDING, 0)
title:SetText("Export")
Theme.SetTitleColor(title)

local body = Theme.CreateTabContentPanel(dialog)
body:SetPoint("TOPLEFT", dialog, "TOPLEFT", UI.INSET, -(UI.INSET + UI.HEADER_HEIGHT + UI.HEADER_GAP))
body:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -UI.INSET, UI.INSET)
local inner = Theme.CreatePanelInnerContent(body)

local intro = inner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
intro:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
intro:SetPoint("RIGHT", inner, "RIGHT", 0, 0)
intro:SetJustifyH("LEFT")
intro:SetWordWrap(true)
intro:SetTextColor(0.85, 0.85, 0.85, 1)
intro:SetText("Copy this string into the alt army website to upload your data")

-- One line holds the whole string; it is selected on show, so Ctrl+C copies all of it.
local box = CreateFrame("EditBox", nil, inner, "InputBoxTemplate")
box:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 6, -UI.GAP)
box:SetPoint("RIGHT", inner, "RIGHT", -6, 0)
box:SetHeight(24)
box:SetAutoFocus(false)
box:SetMaxLetters(0)
box:SetScript("OnEscapePressed", function()
    dialog:Hide()
end)
-- Read-only: typing puts the export back; clicking selects it all again.
box:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self.export then
        self:SetText(self.export)
        self:HighlightText()
    end
end)
box:SetScript("OnMouseUp", function(self)
    self:HighlightText()
end)

local status = inner:CreateFontString(nil, "ARTWORK", Theme.FONTS.body)
status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -UI.GAP)
status:SetPoint("RIGHT", inner, "RIGHT", 0, 0)
status:SetJustifyH("LEFT")
status:SetWordWrap(true)
status:SetTextColor(0.6, 0.6, 0.6, 1)

local close = CreateFrame("Button", nil, inner, "UIPanelButtonTemplate")
close:SetSize(UI.BUTTON_WIDTH, UI.BUTTON_HEIGHT)
close:SetPoint("BOTTOM", inner, "BOTTOM", 0, 0)
close:SetText("Close")
Theme.SkinButton(close)
close:SetScript("OnClick", function()
    dialog:Hide()
end)

AltArmy.ProfitExportDialog = AltArmy.ProfitExportDialog or {}

--- Build a fresh export and show it, selected.
function AltArmy.ProfitExportDialog.Show()
    local PE = AltArmy.ProfitExport
    local export = PE and PE.Build and PE.Build()
    box.export = export
    if export then
        box:SetText(export)
        status:SetText("")
    else
        box:SetText("")
        status:SetText("The export needs the LibDeflate library, which failed to load.")
    end
    dialog:Show()
    box:SetFocus()
    box:HighlightText()
end

function AltArmy.ProfitExportDialog.Hide()
    dialog:Hide()
end
