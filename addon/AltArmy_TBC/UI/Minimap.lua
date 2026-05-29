-- AltArmy TBC — Minimap button via LibDBIcon-1.0 (square/circular via GetMinimapShape).
-- Left-click toggles main window. Drag to reposition; position saved in AltArmyTBC_Options.minimap.

if not AltArmy or not AltArmy.MainFrame then return end

local LDB_ICON_NAME = "AltArmyTBC"

local ldb = LibStub("LibDataBroker-1.1", true)
local icon = LibStub("LibDBIcon-1.0", true)
if not ldb or not icon then return end

local broker = ldb:NewDataObject(LDB_ICON_NAME, {
    type = "data source",
    text = "Alt Army",
    icon = "Interface\\Icons\\INV_Misc_GroupLooking",
    OnClick = function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        local main = AltArmy.MainFrame
        if main:IsShown() then main:Hide() else main:Show() end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Alt Army")
        tooltip:AddLine("Left-click: open / close", 1, 1, 1)
        tooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
    end,
})

local function initMinimap()
    AltArmyTBC_Options = AltArmyTBC_Options or {}
    local m = AltArmy.MigrateMinimapSavedVars(AltArmyTBC_Options)

    if not icon:IsRegistered(LDB_ICON_NAME) then
        icon:Register(LDB_ICON_NAME, broker, m)
    else
        icon:Refresh(LDB_ICON_NAME, m)
    end

    AltArmy.MinimapButton = icon:GetMinimapButton(LDB_ICON_NAME)

    if m.hide then
        icon:Hide(LDB_ICON_NAME)
    else
        icon:Show(LDB_ICON_NAME)
    end
end

AltArmy.SetMinimapButtonShown = function(show)
    AltArmyTBC_Options = AltArmyTBC_Options or {}
    local m = AltArmy.MigrateMinimapSavedVars(AltArmyTBC_Options)
    m.hide = not show
    if not icon:IsRegistered(LDB_ICON_NAME) then return end
    if show then
        icon:Show(LDB_ICON_NAME)
    else
        icon:Hide(LDB_ICON_NAME)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        frame:UnregisterEvent("PLAYER_LOGIN")
        initMinimap()
    end
end)
