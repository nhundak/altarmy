-- AltArmy TBC — Cooldown options (Interface > AddOns > AltArmy > Cooldowns tab).
-- Loaded after UI/Options.lua (see .toc); parents to AltArmy.OptionsPanel.tabCooldownsHost.
-- luacheck: globals UIDropDownMenu_EnableDropDown UIDropDownMenu_DisableDropDown

if not AltArmy then return end

local panel = AltArmy.OptionsPanel
local host = panel and panel.tabCooldownsHost
if not host then return end

local CD = AltArmy.CooldownData
if not CD then return end

local LEFT_INSET = 0
local BLOCK_GAP = 18

local scroll = CreateFrame("ScrollFrame", "AltArmyTBC_CooldownOptionsScroll", host)
scroll:SetPoint("TOPLEFT", host, "TOPLEFT", LEFT_INSET, -4)
scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -LEFT_INSET, 4)

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

local SPEC_LABEL = {
    transmute = "Only if Master of Transmutation",
    spellcloth = "Only if Spellfire Tailor",
    shadowcloth = "Only if Shadoweave Tailor",
    primal_mooncloth = "Only if Mooncloth Tailor",
}

local function CategoryHasSpecRow(key)
    return SPEC_LABEL[key] ~= nil
end

local ALERT_TYPE_LABELS = {
    chat = "Chat message",
    -- Internal value remains "raidWarning"; uses RaidWarningFrame text only, not raid chat.
    raidWarning = "Center screen alert",
    both = "Chat + center screen",
}

--- Dim checkbox caption when the control is disabled (WoW does not gray companion text automatically).
local function SetCheckboxCaptionMuted(fs, muted)
    if not fs then return end
    if muted then
        fs:SetTextColor(0.5, 0.5, 0.5)
    else
        fs:SetTextColor(1, 1, 1)
    end
end

local function SaveCategory(key)
    CD.EnsureCooldownOptions()
    local cat = AltArmyTBC_Options.cooldowns.categories[key]
    local w = panel.cooldownWidgets[key]
    if not cat or not w then return end
    cat.showInUI = w.showChk:GetChecked() ~= false
    if w.showSpecChk then
        cat.showOnlyIfSpecialization = w.showSpecChk:GetChecked() == true
    end
    cat.alertWhenAvailable = w.alertChk:GetChecked() ~= false
    if w.alertSpecChk then
        cat.alertOnlyIfSpecialization = w.alertSpecChk:GetChecked() == true
    end
    cat.remindMe = w.remindChk:GetChecked() == true
    local mins = tonumber(w.remindEdit:GetText())
    cat.remindEveryMinutes = mins or 30
end

local function RefreshDependentEnabled(key)
    local w = panel.cooldownWidgets[key]
    if not w then return end
    local showOn = w.showChk:GetChecked() == true
    local alertOn = w.alertChk:GetChecked() == true
    if w.showSpecChk then
        if showOn then w.showSpecChk:Enable() else w.showSpecChk:Disable() end
        if not showOn then w.showSpecChk:SetChecked(false) end
        SetCheckboxCaptionMuted(w.showSpecLbl, not showOn)
    end
    if w.alertSpecChk then
        if alertOn then w.alertSpecChk:Enable() else w.alertSpecChk:Disable() end
        if not alertOn then w.alertSpecChk:SetChecked(false) end
        SetCheckboxCaptionMuted(w.alertSpecLbl, not alertOn)
    end
    if w.typeDrop then
        if alertOn and UIDropDownMenu_EnableDropDown then
            UIDropDownMenu_EnableDropDown(w.typeDrop)
        elseif not alertOn and UIDropDownMenu_DisableDropDown then
            UIDropDownMenu_DisableDropDown(w.typeDrop)
        end
    end
    if w.typeLabel then
        SetCheckboxCaptionMuted(w.typeLabel, not alertOn)
    end
    if alertOn then w.remindChk:Enable() else w.remindChk:Disable() end
    SetCheckboxCaptionMuted(w.remindLbl, not alertOn)
    SetCheckboxCaptionMuted(w.remindSuffixFs, not alertOn)
    if alertOn and w.remindChk:GetChecked() == true then
        w.remindEdit:Enable()
    else
        w.remindEdit:Disable()
    end
    if not alertOn then
        w.remindChk:SetChecked(false)
    end
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

    local showChk = CreateFrame("CheckButton", nil, block, "InterfaceOptionsCheckButtonTemplate")
    showChk:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -8)
    showChk:SetScript("OnClick", function()
        SaveCategory(key)
        RefreshDependentEnabled(key)
    end)
    local showLbl = showChk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    showLbl:SetPoint("LEFT", showChk, "RIGHT", 4, 0)
    showLbl:SetText("Show in UI")

    local showSpecChk
    local showSpecLbl
    if CategoryHasSpecRow(key) then
        showSpecChk = CreateFrame("CheckButton", nil, block, "InterfaceOptionsCheckButtonTemplate")
        showSpecChk:SetPoint("LEFT", showChk, "RIGHT", 200, 0)
        showSpecChk:SetScript("OnClick", function()
            SaveCategory(key)
        end)
        showSpecLbl = showSpecChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        showSpecLbl:SetPoint("LEFT", showSpecChk, "RIGHT", 4, 0)
        showSpecLbl:SetText(SPEC_LABEL[key])
    end

    local alertChk = CreateFrame("CheckButton", nil, block, "InterfaceOptionsCheckButtonTemplate")
    alertChk:SetPoint("TOPLEFT", showChk, "BOTTOMLEFT", 0, -6)
    alertChk:SetScript("OnClick", function()
        SaveCategory(key)
        RefreshDependentEnabled(key)
    end)
    local alertLbl = alertChk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    alertLbl:SetPoint("LEFT", alertChk, "RIGHT", 4, 0)
    alertLbl:SetText("Alert when available")

    local alertSpecChk
    local alertSpecLbl
    if CategoryHasSpecRow(key) then
        alertSpecChk = CreateFrame("CheckButton", nil, block, "InterfaceOptionsCheckButtonTemplate")
        alertSpecChk:SetPoint("LEFT", alertChk, "RIGHT", 200, 0)
        alertSpecChk:SetScript("OnClick", function()
            SaveCategory(key)
        end)
        alertSpecLbl = alertSpecChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        alertSpecLbl:SetPoint("LEFT", alertSpecChk, "RIGHT", 4, 0)
        alertSpecLbl:SetText(SPEC_LABEL[key])
    end

    local typeLabel = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    typeLabel:SetPoint("TOPLEFT", alertChk, "BOTTOMLEFT", 24, -8)
    typeLabel:SetText("Alert type")

    local typeDrop = CreateFrame("Frame", "AltArmyTBC_CDAlertType_" .. key, block, "UIDropDownMenuTemplate")
    typeDrop:SetPoint("LEFT", typeLabel, "RIGHT", 12, -4)
    UIDropDownMenu_SetWidth(typeDrop, 160)
    UIDropDownMenu_Initialize(typeDrop, function()
        if UIDropDownMenu_ClearMenu then
            UIDropDownMenu_ClearMenu(typeDrop)
        end
        for _, opt in ipairs({ "chat", "raidWarning", "both" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = ALERT_TYPE_LABELS[opt] or opt
            info.func = function()
                AltArmyTBC_Options.cooldowns.categories[key].alertType = opt
                UIDropDownMenu_SetText(typeDrop, ALERT_TYPE_LABELS[opt] or opt)
                SaveCategory(key)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local remindChk = CreateFrame("CheckButton", nil, block, "InterfaceOptionsCheckButtonTemplate")
    remindChk:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", -24, -10)
    remindChk:SetScript("OnClick", function()
        SaveCategory(key)
        RefreshDependentEnabled(key)
    end)
    local remindLbl = remindChk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    remindLbl:SetPoint("LEFT", remindChk, "RIGHT", 4, 0)
    remindLbl:SetText("Remind me every")

    local remindEdit = CreateFrame("EditBox", nil, block)
    remindEdit:SetSize(44, 20)
    remindEdit:SetFontObject("GameFontHighlightSmall")
    remindEdit:SetAutoFocus(false)
    remindEdit:SetNumeric(true)
    remindEdit:SetJustifyH("CENTER")
    remindEdit:SetPoint("LEFT", remindLbl, "RIGHT", 8, 0)
    local remindBg = remindEdit:CreateTexture(nil, "BACKGROUND")
    remindBg:SetAllPoints(remindEdit)
    remindBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    remindEdit:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
        SaveCategory(key)
    end)
    remindEdit:SetScript("OnEditFocusLost", function()
        SaveCategory(key)
    end)

    local remindSuffix = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    remindSuffix:SetPoint("LEFT", remindEdit, "RIGHT", 6, 0)
    remindSuffix:SetText("minutes (while ready)")

    if AltArmy.WireCheckboxLabelClick then
        AltArmy.WireCheckboxLabelClick(showChk, showLbl)
        AltArmy.WireCheckboxLabelClick(alertChk, alertLbl)
        AltArmy.WireCheckboxLabelClick(remindChk, remindLbl)
        AltArmy.WireCheckboxLabelClick(remindChk, remindSuffix)
        if showSpecChk and showSpecLbl then
            AltArmy.WireCheckboxLabelClick(showSpecChk, showSpecLbl)
        end
        if alertSpecChk and alertSpecLbl then
            AltArmy.WireCheckboxLabelClick(alertSpecChk, alertSpecLbl)
        end
    end

    local blockH = 168
    block:SetHeight(blockH)
    if not prevBlock then
        block:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    else
        block:SetPoint("TOPLEFT", prevBlock, "BOTTOMLEFT", 0, -BLOCK_GAP)
    end
    totalHeight = totalHeight + blockH + BLOCK_GAP

    prevBlock = block

    panel.cooldownWidgets[key] = {
        showChk = showChk,
        showSpecChk = showSpecChk,
        showSpecLbl = showSpecLbl,
        alertChk = alertChk,
        alertSpecChk = alertSpecChk,
        alertSpecLbl = alertSpecLbl,
        typeDrop = typeDrop,
        typeLabel = typeLabel,
        remindChk = remindChk,
        remindLbl = remindLbl,
        remindSuffixFs = remindSuffix,
        remindEdit = remindEdit,
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
        if cat and w.showChk then
            w.showChk:SetChecked(cat.showInUI ~= false)
            if w.showSpecChk then
                w.showSpecChk:SetChecked(cat.showOnlyIfSpecialization == true)
            end
            w.alertChk:SetChecked(cat.alertWhenAvailable ~= false)
            if w.alertSpecChk then
                w.alertSpecChk:SetChecked(cat.alertOnlyIfSpecialization == true)
            end
            local at = cat.alertType or "chat"
            if UIDropDownMenu_SetText and w.typeDrop then
                UIDropDownMenu_SetText(w.typeDrop, ALERT_TYPE_LABELS[at] or ALERT_TYPE_LABELS.chat)
            end
            w.remindChk:SetChecked(cat.remindMe == true)
            w.remindEdit:SetText(tostring(cat.remindEveryMinutes or 30))
            RefreshDependentEnabled(key)
        end
    end
end

panel.RefreshCooldownOptionsFromVars = RefreshCooldownOptionsFromVars
RefreshCooldownOptionsFromVars()
UpdateCooldownScrollRange()

host:HookScript("OnShow", function()
    RefreshCooldownOptionsFromVars()
    UpdateCooldownScrollRange()
end)
