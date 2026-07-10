-- AltArmy TBC — Cooldown options (Interface > AddOns > AltArmy > Cooldowns tab).
-- Loaded after UI/Options.lua (see .toc); parents to AltArmy.OptionsPanel.tabCooldownsHost.

if not AltArmy then return end

local panel = AltArmy.OptionsPanel
local host = panel and panel.tabCooldownsHost
if not host then return end

local CD = AltArmy.CooldownData
if not CD then return end

local Theme = AltArmy.Theme

local LEFT_INSET = 0
local BLOCK_GAP = 18

local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()

local cooldownViewport = Theme.CreateVerticalScrollViewport({
    name = "AltArmyTBC_CooldownOptionsScroll",
    parent = host,
    gutterEdge = panel,
    anchorTop = { "TOPLEFT", host, "TOPLEFT", LEFT_INSET, -4 },
    anchorBottom = { "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SCROLL_GUTTER, 4 },
    wheelStep = 40,
    valueStep = 20,
    wheelOnChild = false,
    wheelSource = "slider",
    minScrollToShow = 1,
})
local scrollChild = cooldownViewport.child

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

--- Dim checkbox caption when the control is disabled (WoW does not gray companion text automatically).
local function SetCheckboxCaptionMuted(fs, muted)
    if not fs then return end
    if muted then
        fs:SetTextColor(0.5, 0.5, 0.5)
    else
        fs:SetTextColor(1, 1, 1)
    end
end

local function SetLabeledCheckboxEnabled(row, enabled)
    if not row then return end
    if enabled then
        row.check:Enable()
        if row.hoverRegion then row.hoverRegion:EnableMouse(true) end
        SetCheckboxCaptionMuted(row.label, false)
    else
        row.check:Disable()
        if row.hoverRegion then row.hoverRegion:EnableMouse(false) end
        SetCheckboxCaptionMuted(row.label, true)
    end
end

local function SaveCategory(key)
    CD.EnsureCooldownOptions()
    local cat = AltArmyTBC_Options.cooldowns.categories[key]
    local w = panel.cooldownWidgets[key]
    if not cat or not w then return end
    cat.showInUI = w.showRow.check:GetChecked() ~= false
    if w.showSpecRow then
        cat.showOnlyIfSpecialization = w.showSpecRow.check:GetChecked() == true
    end
    cat.alertWhenAvailable = w.alertRow.check:GetChecked() ~= false
    if w.alertSpecRow then
        cat.alertOnlyIfSpecialization = w.alertSpecRow.check:GetChecked() == true
    end
end

local function RefreshDependentEnabled(key)
    local w = panel.cooldownWidgets[key]
    if not w then return end
    local showOn = w.showRow.check:GetChecked() == true
    local alertOn = w.alertRow.check:GetChecked() == true
    if w.showSpecRow then
        SetLabeledCheckboxEnabled(w.showSpecRow, showOn)
        if not showOn then w.showSpecRow.check:SetChecked(false) end
    end
    if w.alertSpecRow then
        SetLabeledCheckboxEnabled(w.alertSpecRow, alertOn)
        if not alertOn then w.alertSpecRow.check:SetChecked(false) end
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

    local showRow = Theme.CreateLabeledCheckbox(block, {
        point = "TOPLEFT",
        relativeTo = titleFs,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -8,
        text = "Show in UI",
        onClick = function()
            SaveCategory(key)
            RefreshDependentEnabled(key)
        end,
    })

    local showSpecRow
    if CategoryHasSpecRow(key) then
        showSpecRow = Theme.CreateLabeledCheckbox(block, {
            point = "TOPLEFT",
            relativeTo = showRow,
            relativePoint = "TOPLEFT",
            x = 200,
            y = 0,
            text = SPEC_LABEL[key],
            onClick = function()
                SaveCategory(key)
            end,
        })
    end

    local alertRow = Theme.CreateLabeledCheckbox(block, {
        point = "TOPLEFT",
        relativeTo = showRow,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -6,
        text = "Alert when available",
        onClick = function()
            SaveCategory(key)
            RefreshDependentEnabled(key)
        end,
    })

    local alertSpecRow
    if CategoryHasSpecRow(key) then
        alertSpecRow = Theme.CreateLabeledCheckbox(block, {
            point = "TOPLEFT",
            relativeTo = alertRow,
            relativePoint = "TOPLEFT",
            x = 200,
            y = 0,
            text = SPEC_LABEL[key],
            onClick = function()
                SaveCategory(key)
            end,
        })
    end

    local blockH = 88
    block:SetHeight(blockH)
    if not prevBlock then
        block:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    else
        block:SetPoint("TOPLEFT", prevBlock, "BOTTOMLEFT", 0, -BLOCK_GAP)
    end
    totalHeight = totalHeight + blockH + BLOCK_GAP

    prevBlock = block

    panel.cooldownWidgets[key] = {
        showRow = showRow,
        showSpecRow = showSpecRow,
        alertRow = alertRow,
        alertSpecRow = alertSpecRow,
    }
end

scrollChild:SetHeight(math.max(totalHeight + 24, 120))

local function UpdateCooldownScrollRange()
    cooldownViewport:UpdateRange()
end

local function RefreshCooldownOptionsFromVars()
    CD.EnsureCooldownOptions()
    for key, w in pairs(panel.cooldownWidgets) do
        local cat = AltArmyTBC_Options.cooldowns.categories[key]
        if cat and w.showRow then
            w.showRow.check:SetChecked(cat.showInUI ~= false)
            if w.showSpecRow then
                w.showSpecRow.check:SetChecked(cat.showOnlyIfSpecialization == true)
            end
            w.alertRow.check:SetChecked(cat.alertWhenAvailable ~= false)
            if w.alertSpecRow then
                w.alertSpecRow.check:SetChecked(cat.alertOnlyIfSpecialization == true)
            end
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
