-- AltArmy TBC — Minimal minimap button (left-click toggles main window)

if not AltArmy or not AltArmy.MainFrame then return end

local MINIMAP_RADIUS = 80
local BUTTON_SIZE = 24

local function getMinimapButtonPosition()
    -- Fixed angle for minimal version; Options can add angle/radius later
    local angle = 270 * (math.pi / 180) -- top of minimap
    local x = math.cos(angle) * MINIMAP_RADIUS
    local y = math.sin(angle) * MINIMAP_RADIUS
    return x, y
end

local btn = CreateFrame("Button", "AltArmyTBC_MinimapButton", Minimap)
btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
local x, y = getMinimapButtonPosition()
btn:SetPoint("CENTER", Minimap, "CENTER", x, y)

local icon = btn:CreateTexture(nil, "BACKGROUND")
icon:SetAllPoints(btn)
icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
btn:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "LeftButton" then
        if AltArmy.DebugLog then
            AltArmy.DebugLog("Minimap button clicked")
        end
        print("[AltArmy] Minimap button clicked")
        local main = AltArmy.MainFrame
        if main:IsShown() then
            main:Hide()
        else
            main:Show()
        end
    end
end)
btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:SetText("AltArmy TBC")
    GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Allow Options to show/hide the button
AltArmy.MinimapButton = btn
AltArmy.SetMinimapButtonShown = function(show)
    if AltArmy.MinimapButton then
        AltArmy.MinimapButton:SetShown(show)
    end
end

-- Respect saved option on load (Options.lua sets defaults and calls SetMinimapButtonShown after load)
if AltArmyTBC_Options ~= nil and AltArmyTBC_Options.showMinimapButton == false then
    btn:Hide()
end
