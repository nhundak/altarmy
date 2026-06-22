-- AltArmy TBC — Gear upgrade options (Interface > AddOns > AltArmy > Gear Upgrades tab).
-- Loaded after UI/Options.lua.

if not AltArmy then return end

local Theme = AltArmy.Theme
local LEFT_INSET = 0
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()
local SETTINGS_ROW_HEIGHT = Theme.OPTIONS_DROPDOWN_ROW_HEIGHT or 24

local function createReadOnlyUrlEdit(parent, relativeTo, relativePoint, y)
    local edit = CreateFrame("EditBox", nil, parent)
    edit:SetHeight(SETTINGS_ROW_HEIGHT)
    edit:SetPoint("TOPLEFT", relativeTo, relativePoint or "BOTTOMLEFT", 0, y or -4)
    edit:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetAutoFocus(false)
    edit:SetTextInsets(4, 4, 0, 0)
    Theme.ApplyInputTextures(edit)
    edit:SetScript("OnEditFocusGained", function(box)
        box:HighlightText()
    end)
    edit:SetScript("OnEditFocusLost", function(box)
        box:HighlightText(0, 0)
    end)
    edit:SetScript("OnMouseUp", function(box)
        box:SetFocus()
        box:HighlightText()
    end)
    edit:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
    end)
    edit:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
    end)
    return edit
end

local function hookHostShow(panel)
    local host = panel and panel.tabGearUpgradesHost
    if not host or host.gearUpgradeShowHooked then return end
    host.gearUpgradeShowHooked = true
    host:HookScript("OnShow", function()
        if AltArmy.BuildGearUpgradeOptionsUI then
            AltArmy.BuildGearUpgradeOptionsUI(panel)
        end
        if panel.UpdateGearUpgradeScrollRange then
            panel.UpdateGearUpgradeScrollRange()
        end
        if panel.RefreshGearUpgradeOptionsFromVars then
            panel.RefreshGearUpgradeOptionsFromVars()
        end
    end)
end

function AltArmy.BuildGearUpgradeOptionsUI(panel)
    panel = panel or AltArmy.OptionsPanel
    if not panel or not panel.tabGearUpgradesHost then return false end
    local host = panel.tabGearUpgradesHost
    if host.gearUpgradeUiBuilt then return true end

    local GU = AltArmy.GearUpgrade
    if not GU then
        local msg = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        msg:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        msg:SetWidth(520)
        msg:SetJustifyH("LEFT")
        msg:SetText("Gear upgrade options are unavailable.")
        host.gearUpgradeUiBuilt = true
        return false
    end

    host.gearUpgradeUiBuilt = true

    local viewport = Theme.CreateVerticalScrollViewport({
        name = "AltArmyTBC_GearUpgradeOptionsScroll",
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
    local scrollChild = viewport.child

    local enabledRow = Theme.CreateLabeledCheckbox(scrollChild, {
        point = "TOPLEFT",
        relativeTo = scrollChild,
        relativePoint = "TOPLEFT",
        x = 0,
        y = 0,
        text = "Enable gear upgrade notifications",
        fullWidthHover = true,
        onClick = function(checked)
            GU.EnsureGearUpgradeOptions().enabled = checked
        end,
    })
    local enabledChk = enabledRow.check

    local techniqueLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    techniqueLabel:SetPoint("TOPLEFT", enabledRow, "BOTTOMLEFT", 0, -14)
    techniqueLabel:SetText("Comparison technique")

    local updateInfoPanel
    local layoutInfoSection
    local techniqueDrop = Theme.CreateSingleSelectDropdown({
        parent = scrollChild,
        point = "TOPLEFT",
        relativeTo = techniqueLabel,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -4,
        width = 320,
        dropdownParent = scrollChild,
        getEntries = function()
            local providers = GU.GetProviders()
            local out = {}
            for i = 1, #providers do
                local p = providers[i]
                out[i] = {
                    id = p.id,
                    label = GU.GetProviderDisplayLabel and GU.GetProviderDisplayLabel(p) or p.label,
                }
            end
            return out
        end,
        getSelectedId = function()
            return GU.GetOptions().technique or "custom"
        end,
        onSelect = function(id)
            GU.EnsureGearUpgradeOptions().technique = id
            if updateInfoPanel then
                updateInfoPanel(id)
            end
        end,
    })

    local warningText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warningText:SetWidth(520)
    warningText:SetJustifyH("LEFT")
    warningText:SetTextColor(1, 0.4, 0.3, 1)
    warningText:Hide()

    local installPanel = CreateFrame("Frame", nil, scrollChild)
    installPanel:SetWidth(520)
    installPanel:Hide()

    local installLabel = installPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    installLabel:SetPoint("TOPLEFT", installPanel, "TOPLEFT", 0, 0)
    installLabel:SetJustifyH("LEFT")
    installLabel:SetText("Install from CurseForge")
    if Theme.SetLabelColor then
        Theme.SetLabelColor(installLabel)
    end

    local installUrlEdit = createReadOnlyUrlEdit(installPanel, installLabel, "BOTTOMLEFT", -4)
    installPanel:SetHeight(14 + SETTINGS_ROW_HEIGHT + 4)

    local levelsLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    levelsLabel:SetText("Consider items equippable within this many levels")

    local levelsEdit = CreateFrame("EditBox", nil, scrollChild)
    levelsEdit:SetPoint("TOPLEFT", levelsLabel, "BOTTOMLEFT", 0, -4)
    levelsEdit:SetSize(44, 20)
    levelsEdit:SetFontObject("GameFontHighlightSmall")
    levelsEdit:SetAutoFocus(false)
    levelsEdit:SetNumeric(true)
    levelsEdit:SetJustifyH("CENTER")
    Theme.ApplyInputTextures(levelsEdit)

    local function saveLevelsAhead()
        local n = tonumber(levelsEdit:GetText()) or 0
        GU.EnsureGearUpgradeOptions().levelsAhead = math.max(0, math.floor(n))
    end

    levelsEdit:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
        saveLevelsAhead()
    end)
    levelsEdit:SetScript("OnEditFocusLost", saveLevelsAhead)

    updateInfoPanel = function(providerId)
        local provider = GU.GetProvider(providerId)
        warningText:Hide()
        installPanel:Hide()

        if provider and provider.warningSpecAgnostic then
            warningText:SetText(
                "This comparison ignores character spec and may recommend items that are useless for you.")
            warningText:Show()
        end

        if provider and provider.isAddon and provider.installInfo
            and provider.IsAvailable and not provider.IsAvailable() then
            local info = provider.installInfo
            local url = info.url or ""
            installUrlEdit.urlLocked = url
            installUrlEdit:SetText(url)
            installUrlEdit:SetScript("OnChar", function() end)
            installUrlEdit:SetScript("OnTextChanged", function(box)
                if box.urlLocked and box:GetText() ~= box.urlLocked then
                    box:SetText(box.urlLocked)
                end
            end)
            installPanel:Show()
        end

        if layoutInfoSection then
            layoutInfoSection()
        end
    end

    layoutInfoSection = function()
        local anchor = techniqueDrop.button
        local gap = -12

        warningText:ClearAllPoints()
        if warningText:IsShown() then
            warningText:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
            anchor = warningText
            gap = -8
        end

        installPanel:ClearAllPoints()
        if installPanel:IsShown() then
            installPanel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
            anchor = installPanel
            gap = -12
        end

        levelsLabel:ClearAllPoints()
        levelsLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
    end

    scrollChild:SetHeight(280)

    local function UpdateGearUpgradeScrollRange()
        viewport:UpdateRange()
    end

    local function RefreshGearUpgradeOptionsFromVars()
        GU.EnsureGearUpgradeOptions()
        local opts = GU.GetOptions()
        enabledChk:SetChecked(opts.enabled ~= false)
        if techniqueDrop and techniqueDrop.Update then
            techniqueDrop:Update()
        end
        levelsEdit:SetText(tostring(opts.levelsAhead))
        updateInfoPanel(opts.technique or "custom")
        UpdateGearUpgradeScrollRange()
    end

    panel.RefreshGearUpgradeOptionsFromVars = RefreshGearUpgradeOptionsFromVars
    panel.UpdateGearUpgradeScrollRange = UpdateGearUpgradeScrollRange

    RefreshGearUpgradeOptionsFromVars()
    hookHostShow(panel)
    return true
end

if AltArmy.OptionsPanel then
    AltArmy.BuildGearUpgradeOptionsUI(AltArmy.OptionsPanel)
    hookHostShow(AltArmy.OptionsPanel)
end
