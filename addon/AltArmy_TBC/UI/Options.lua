-- AltArmy TBC — Options in WoW's Interface Options (AddOns list).
-- SavedVariables: AltArmyTBC_Options (debug, showMinimapButton).

-- Apply defaults and current option state
local function ensureDefaults()
    if not AltArmyTBC_Options then
        AltArmyTBC_Options = {}
        AltArmy.firstRun = true
        AltArmyTBC_Options.debug = true  -- on first run, show logs so user sees addon loaded
    end
    if AltArmyTBC_Options.showMinimapButton == nil then
        AltArmyTBC_Options.showMinimapButton = true
    end
    if AltArmyTBC_Options.minimapAngle == nil then
        AltArmyTBC_Options.minimapAngle = 90  -- degrees; 90 = top
    end
    if AltArmyTBC_Options.debug == nil then
        AltArmyTBC_Options.debug = true
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

-- Blizzard Interface Options panel (shows under Interface > AddOns > AltArmy TBC)
local panel = CreateFrame("Frame")
panel.name = "AltArmy"
panel.okay = function()
    ensureDefaults()
    applyMinimapOption()
end
panel.cancel = function()
    ensureDefaults()
    applyMinimapOption()
end
panel.default = function()
    AltArmyTBC_Options.showMinimapButton = true
    AltArmyTBC_Options.debug = false
    applyMinimapOption()
    if panel.debugCheckbox then
        panel.debugCheckbox:SetChecked(false)
    end
end
panel.refresh = function()
    ensureDefaults()
    if panel.debugCheckbox then
        panel.debugCheckbox:SetChecked(AltArmyTBC_Options.debug)
    end
end

-- Checkbox: Enable debug logging (only option on this page for now)
local debugCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
debugCheckbox:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
debugCheckbox:SetScript("OnClick", function()
    AltArmyTBC_Options.debug = debugCheckbox:GetChecked()
end)
panel.debugCheckbox = debugCheckbox

local debugLabel = debugCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
debugLabel:SetPoint("LEFT", debugCheckbox, "RIGHT", 4, 0)
debugLabel:SetText("Enable debug logging")

-- Register with WoW's options when the UI is ready. Support both:
-- 1) New Settings API (Dragonflight-style): Esc → Settings → AddOns → AltArmy
-- 2) Old Interface Options: Interface → AddOns → AltArmy (when still available)
local function registerOptionsPanel()
    -- New Settings UI (Interface 20502 / modern Classic clients)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "AltArmy")
        Settings.RegisterAddOnCategory(category)
    end
    -- Old Interface Options (when present)
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        if InterfaceAddOnsList_Update then
            InterfaceAddOnsList_Update()
        end
    end
end

local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_LOGIN")
reg:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        reg:UnregisterEvent("PLAYER_LOGIN")
        registerOptionsPanel()
    end
end)

-- Slash command: open the main AltArmy UI
SLASH_ALTARMY1 = "/altarmy"
SlashCmdList.ALTARMY = function(_msg)
    if AltArmy and AltArmy.MainFrame then
        AltArmy.MainFrame:Show()
    end
end
