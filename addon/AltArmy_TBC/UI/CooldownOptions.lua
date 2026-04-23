-- AltArmy TBC — Cooldown subsection for Interface > AddOns > AltArmy.
-- Loaded after UI/Options.lua (see .toc); uses AltArmy.OptionsPanel.

if not AltArmy then return end

local panel = AltArmy.OptionsPanel
if not panel then return end

local CD = AltArmy.CooldownData
if not CD then return end

local LEFT_INSET = 16
local BLOCK_GAP = 12

local cooldownHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
cooldownHeader:SetPoint("TOPLEFT", panel.minimapCheckbox, "BOTTOMLEFT", 0, -14)
cooldownHeader:SetText("Cooldown")

local scroll = CreateFrame("ScrollFrame", "AltArmyTBC_CooldownOptionsScroll", panel)
scroll:SetPoint("TOPLEFT", cooldownHeader, "BOTTOMLEFT", 0, -6)
scroll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", LEFT_INSET, 12)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -LEFT_INSET, 12)

local scrollBar = CreateFrame("Slider", nil, scroll)
scrollBar:SetOrientation("VERTICAL")
scrollBar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
scrollBar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
scrollBar:SetWidth(14)
scrollBar:SetMinMaxValues(0, 0)
scrollBar:SetValue(0)
scrollBar:SetValueStep(20)

local sbThumb = scrollBar:CreateTexture(nil, "OVERLAY")
sbThumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
sbThumb:SetSize(18, 24)
scrollBar:SetThumbTexture(sbThumb)

local scrollChild = CreateFrame("Frame", nil, scroll)
scroll:SetScrollChild(scrollChild)

scrollBar:SetScript("OnValueChanged", function(_, v)
    scroll:SetVerticalScroll(v)
end)

scroll:SetScript("OnMouseWheel", function(_, delta)
    local cur = scrollBar:GetValue()
    local lo, hi = scrollBar:GetMinMaxValues()
    scrollBar:SetValue(math.max(lo, math.min(hi, cur - delta * 40)))
end)

scroll:SetScript("OnSizeChanged", function(s, w)
    scrollChild:SetWidth(math.max(1, (w or s:GetWidth()) - 18))
end)

panel.cooldownWidgets = {}

local function SaveCategory(key)
    CD.EnsureCooldownOptions()
    local cat = AltArmyTBC_Options.cooldowns.categories[key]
    local w = panel.cooldownWidgets[key]
    if not cat or not w then return end
    cat.hide = w.hideChk:GetChecked() == true
    cat.alertWhenAvailable = w.alertChk:GetChecked() ~= false
    cat.alertMinutesBefore = w.minChk:GetChecked() == true
    local mins = tonumber(w.minEdit:GetText())
    cat.alertMinutesBeforeMinutes = mins or 15
end

local totalHeight = 0
local prevBlock = nil

for _, key in ipairs(CD.CATEGORY_ORDER) do
    local catDef = CD.CATEGORIES[key]
    local title = catDef and catDef.title or key
    local block = CreateFrame("Frame", nil, scrollChild)
    block:SetWidth(520)

    local titleFs = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    titleFs:SetText(title)

    local hideChk = CreateFrame("CheckButton", nil, block, "InterfaceOptionsCheckButtonTemplate")
    hideChk:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
    hideChk:SetScript("OnClick", function() SaveCategory(key) end)

    local hideLbl = hideChk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hideLbl:SetPoint("LEFT", hideChk, "RIGHT", 4, 0)
    hideLbl:SetText("Hide")

    local alertChk = CreateFrame("CheckButton", nil, block, "InterfaceOptionsCheckButtonTemplate")
    alertChk:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -6)
    alertChk:SetScript("OnClick", function() SaveCategory(key) end)

    local alertLbl = alertChk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    alertLbl:SetPoint("LEFT", alertChk, "RIGHT", 4, 0)
    alertLbl:SetText("Alert when available")

    local minChk = CreateFrame("CheckButton", nil, block, "InterfaceOptionsCheckButtonTemplate")
    minChk:SetPoint("TOPLEFT", alertChk, "BOTTOMLEFT", 0, -4)
    minChk:SetScript("OnClick", function() SaveCategory(key) end)

    local minLbl = minChk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    minLbl:SetPoint("LEFT", minChk, "RIGHT", 4, 0)
    minLbl:SetText("Alert minutes before")

    local minEdit = CreateFrame("EditBox", nil, block)
    minEdit:SetSize(44, 20)
    minEdit:SetFontObject("GameFontHighlightSmall")
    minEdit:SetAutoFocus(false)
    minEdit:SetNumeric(true)
    minEdit:SetPoint("LEFT", minLbl, "RIGHT", 8, 0)
    local minBg = minEdit:CreateTexture(nil, "BACKGROUND")
    minBg:SetAllPoints(minEdit)
    minBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    minEdit:SetScript("OnEnterPressed", function(box) box:ClearFocus() SaveCategory(key) end)
    minEdit:SetScript("OnEditFocusLost", function() SaveCategory(key) end)

    local blockH = 82

    block:SetHeight(blockH)
    if not prevBlock then
        block:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    else
        block:SetPoint("TOPLEFT", prevBlock, "BOTTOMLEFT", 0, -BLOCK_GAP)
    end
    totalHeight = totalHeight + blockH + BLOCK_GAP

    prevBlock = block

    panel.cooldownWidgets[key] = {
        hideChk = hideChk,
        alertChk = alertChk,
        minChk = minChk,
        minEdit = minEdit,
    }
end

scrollChild:SetHeight(math.max(totalHeight + 24, 120))

local function UpdateCooldownScrollRange()
    local viewH = scroll:GetHeight()
    local contentH = scrollChild:GetHeight()
    if viewH <= 0 then return end
    local maxScroll = math.max(0, contentH - viewH)
    scrollBar:SetMinMaxValues(0, maxScroll)
    scrollBar:SetShown(maxScroll > 1)
end

scroll:HookScript("OnSizeChanged", function()
    UpdateCooldownScrollRange()
end)

local function RefreshCooldownOptionsFromVars()
    CD.EnsureCooldownOptions()
    for key, w in pairs(panel.cooldownWidgets) do
        local cat = AltArmyTBC_Options.cooldowns.categories[key]
        if cat and w.hideChk then
            w.hideChk:SetChecked(cat.hide == true)
            w.alertChk:SetChecked(cat.alertWhenAvailable ~= false)
            w.minChk:SetChecked(cat.alertMinutesBefore == true)
            w.minEdit:SetText(tostring(cat.alertMinutesBeforeMinutes or 15))
        end
    end
end

panel.RefreshCooldownOptionsFromVars = RefreshCooldownOptionsFromVars
RefreshCooldownOptionsFromVars()
UpdateCooldownScrollRange()

panel:HookScript("OnShow", function()
    RefreshCooldownOptionsFromVars()
    UpdateCooldownScrollRange()
end)
