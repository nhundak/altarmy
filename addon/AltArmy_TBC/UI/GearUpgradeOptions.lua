-- AltArmy TBC — Gear upgrade options (Interface > AddOns > AltArmy > Gear Upgrades tab).
-- Loaded after UI/Options.lua.

if not AltArmy then return end

local Theme = AltArmy.Theme
local LEFT_INSET = 0
local SCROLL_GUTTER = Theme.VerticalScrollBarGutter()

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

    local currentCharRow = Theme.CreateLabeledCheckbox(scrollChild, {
        point = "TOPLEFT",
        relativeTo = scrollChild,
        relativePoint = "TOPLEFT",
        x = 0,
        y = 0,
        text = "Upgrade notifications for current character",
        fullWidthHover = true,
        onClick = function(checked)
            GU.EnsureGearUpgradeOptions().notifyCurrentCharacter = checked
        end,
    })
    local currentCharChk = currentCharRow.check

    local otherCharRow = Theme.CreateLabeledCheckbox(scrollChild, {
        point = "TOPLEFT",
        relativeTo = currentCharRow,
        relativePoint = "BOTTOMLEFT",
        x = 0,
        y = -8,
        text = "Upgrade notification for other characters",
        fullWidthHover = true,
        onClick = function(checked)
            GU.EnsureGearUpgradeOptions().notifyOtherCharacters = checked
        end,
    })
    local otherCharChk = otherCharRow.check

    local levelsLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    levelsLabel:SetPoint("TOPLEFT", otherCharRow, "BOTTOMLEFT", 0, -14)
    levelsLabel:SetText("Level look-ahead")

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

    local thresholdLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    thresholdLabel:SetPoint("TOPLEFT", levelsEdit, "BOTTOMLEFT", 0, -14)
    thresholdLabel:SetText("Upgrade threshold (%)")

    local thresholdEdit = CreateFrame("EditBox", nil, scrollChild)
    thresholdEdit:SetPoint("TOPLEFT", thresholdLabel, "BOTTOMLEFT", 0, -4)
    thresholdEdit:SetSize(44, 20)
    thresholdEdit:SetFontObject("GameFontHighlightSmall")
    thresholdEdit:SetAutoFocus(false)
    thresholdEdit:SetNumeric(true)
    thresholdEdit:SetJustifyH("CENTER")
    Theme.ApplyInputTextures(thresholdEdit)

    local function saveUpgradeThreshold()
        local n = tonumber(thresholdEdit:GetText()) or 0
        GU.EnsureGearUpgradeOptions().upgradeThresholdPercent =
            GU.ResolveUpgradeThresholdPercent(n)
        thresholdEdit:SetText(tostring(GU.GetOptions().upgradeThresholdPercent))
    end

    thresholdEdit:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
        saveUpgradeThreshold()
    end)
    thresholdEdit:SetScript("OnEditFocusLost", saveUpgradeThreshold)

    scrollChild:SetHeight(188)

    local function UpdateGearUpgradeScrollRange()
        viewport:UpdateRange()
    end

    local function RefreshGearUpgradeOptionsFromVars()
        GU.EnsureGearUpgradeOptions()
        local opts = GU.GetOptions()
        currentCharChk:SetChecked(opts.notifyCurrentCharacter ~= false)
        otherCharChk:SetChecked(opts.notifyOtherCharacters ~= false)
        levelsEdit:SetText(tostring(opts.levelsAhead))
        thresholdEdit:SetText(tostring(opts.upgradeThresholdPercent))
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
