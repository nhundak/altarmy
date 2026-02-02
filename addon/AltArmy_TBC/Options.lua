-- AltArmy TBC — Minimal options (SavedVariables + show minimap button)

-- Apply defaults and current option state
local function ensureDefaults()
    if not AltArmyTBC_Options then
        AltArmyTBC_Options = {}
    end
    if AltArmyTBC_Options.showMinimapButton == nil then
        AltArmyTBC_Options.showMinimapButton = true
    end
end

local function applyMinimapOption()
    ensureDefaults()
    if AltArmy.SetMinimapButtonShown then
        AltArmy.SetMinimapButtonShown(AltArmyTBC_Options.showMinimapButton)
    end
end

-- Run after addon load so SavedVariables and Minimap are ready
ensureDefaults()
applyMinimapOption()

-- Blizzard Interface Options panel
local panel = CreateFrame("Frame")
panel.name = "AltArmy TBC"
panel.okay = function()
    ensureDefaults()
    -- Checkbox state is already saved on click; just reapply if needed
    applyMinimapOption()
end
panel.cancel = function()
    ensureDefaults()
    applyMinimapOption()
end
panel.default = function()
    AltArmyTBC_Options.showMinimapButton = true
    applyMinimapOption()
    if panel.checkbox then
        panel.checkbox:SetChecked(true)
    end
end
panel.refresh = function()
    ensureDefaults()
    if panel.checkbox then
        panel.checkbox:SetChecked(AltArmyTBC_Options.showMinimapButton)
    end
end

-- Checkbox: Show minimap button
local checkbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
checkbox:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
checkbox:SetScript("OnClick", function()
    AltArmyTBC_Options.showMinimapButton = checkbox:GetChecked()
    applyMinimapOption()
end)
panel.checkbox = checkbox

local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
label:SetText("Show minimap button")

-- InterfaceOptions_AddCategory was added in a later patch; not available in all TBC Classic builds
if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end
