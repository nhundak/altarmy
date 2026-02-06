-- AltArmy TBC — Options in WoW's Interface Options (AddOns list).
-- SavedVariables: AltArmyTBC_Options (showMinimapButton, minimapAngle).

-- Apply defaults and current option state
local function ensureDefaults()
    if not AltArmyTBC_Options then
        AltArmyTBC_Options = {}
        AltArmy.firstRun = true
    end
    if AltArmyTBC_Options.showMinimapButton == nil then
        AltArmyTBC_Options.showMinimapButton = true
    end
    if AltArmyTBC_Options.minimapAngle == nil then
        AltArmyTBC_Options.minimapAngle = 90  -- degrees; 90 = top
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
    applyMinimapOption()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(true)
    end
end
panel.refresh = function()
    ensureDefaults()
    if panel.minimapCheckbox then
        panel.minimapCheckbox:SetChecked(AltArmyTBC_Options.showMinimapButton)
    end
end

-- Checkbox: Show Minimap Button (default on)
local minimapCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
minimapCheckbox:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
minimapCheckbox:SetScript("OnClick", function()
    AltArmyTBC_Options.showMinimapButton = minimapCheckbox:GetChecked()
    applyMinimapOption()
end)
panel.minimapCheckbox = minimapCheckbox

local minimapLabel = minimapCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
minimapLabel:SetPoint("LEFT", minimapCheckbox, "RIGHT", 4, 0)
minimapLabel:SetText("Show Minimap Button")

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
