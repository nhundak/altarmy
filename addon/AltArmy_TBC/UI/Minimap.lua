-- AltArmy TBC — Minimap button: circular, draggable (like Open-Sesame/LibDBIcon).
-- Left-click toggles main window. Drag to reposition; position is saved.
-- Following Open-Sesame: init minimap only on PLAYER_LOGIN so SavedVariables are ready.

if not AltArmy or not AltArmy.MainFrame then return end

local MINIMAP_RADIUS = 80
-- LibDBIcon-style layout: 31x31 button, 53x53 border overlay (TOPLEFT at button TOPLEFT), icon 17x17 inset
local BUTTON_SIZE = 31
local OVERLAY_SIZE = 53
local ICON_SIZE = 17
local ICON_INSET_X = 7
local ICON_INSET_Y = 6
local DEFAULT_ANGLE = 90  -- degrees: 0 = right, 90 = top, 180 = left, 270 = bottom

-- Position (x, y) from angle in degrees (0 = right, 90 = top, clockwise).
local function angleToPosition(angleDeg)
    local rad = angleDeg * (math.pi / 180)
    return math.cos(rad) * MINIMAP_RADIUS, math.sin(rad) * MINIMAP_RADIUS
end

-- Angle in degrees from position (x, y) relative to minimap center.
local function positionToAngle(x, y)
    local angle = math.deg(math.atan2(y, x))
    if angle < 0 then angle = angle + 360 end
    return angle
end

local btn
local function applyPosition()
    if not btn then return end
    local opts = AltArmyTBC_Options
    local angle = (opts and opts.minimapAngle ~= nil) and opts.minimapAngle or DEFAULT_ANGLE
    local x, y = angleToPosition(angle)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function setMinimapAngle(angle)
    if not AltArmyTBC_Options then AltArmyTBC_Options = {} end
    AltArmyTBC_Options.minimapAngle = angle
end

local function initMinimap()
    -- Ensure SavedVariables table and minimap defaults (Open-Sesame pattern: do this on PLAYER_LOGIN).
    AltArmyTBC_Options = AltArmyTBC_Options or {}
    if AltArmyTBC_Options.minimapAngle == nil then
        AltArmyTBC_Options.minimapAngle = DEFAULT_ANGLE
    end

    btn = CreateFrame("Button", "AltArmyTBC_MinimapButton", Minimap)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    applyPosition()

    -- Layout from LibDBIcon-1.0 (Classic path): overlay TOPLEFT at button TOPLEFT so the ring surrounds the button
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(OVERLAY_SIZE, OVERLAY_SIZE)
    overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    overlay:SetTexture("Interface\\Minimap\\Minimap-TrackingBorder")

    local background = btn:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", btn, "TOPLEFT", ICON_INSET_X, -5)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", ICON_INSET_X, -ICON_INSET_Y)
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local dragging = false
    local justDragged = false

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
        dragging = true
        justDragged = false
    end)
    btn:SetScript("OnDragStop", function()
        if dragging then justDragged = true end
        dragging = false
    end)

    btn:SetScript("OnUpdate", function()
        if not dragging then return end
        local scale = Minimap:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        cursorX = cursorX / scale
        cursorY = cursorY / scale
        local mx, my = Minimap:GetCenter()
        local dx = cursorX - mx
        local dy = cursorY - my
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 1 then
            dx = dx * (MINIMAP_RADIUS / dist)
            dy = dy * (MINIMAP_RADIUS / dist)
        end
        setMinimapAngle(positionToAngle(dx, dy))
        applyPosition()
    end)

    btn:SetScript("OnClick", function(_, mouseButton)
        if justDragged then
            justDragged = false
            return
        end
        if mouseButton == "LeftButton" then
            local main = AltArmy.MainFrame
            if main:IsShown() then main:Hide() else main:Show() end
        end
    end)

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText("AltArmy TBC")
        GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    AltArmy.MinimapButton = btn
    -- SetMinimapButtonShown already defined at load; now btn exists so it will work.

    if AltArmyTBC_Options.showMinimapButton == false then
        btn:Hide()
    end
end

-- So Options.lua can call this before PLAYER_LOGIN without error; button is nil until initMinimap.
AltArmy.SetMinimapButtonShown = function(show)
    if AltArmy.MinimapButton then
        AltArmy.MinimapButton:SetShown(show)
    end
end

-- Defer all minimap setup to PLAYER_LOGIN so SavedVariables are loaded (Open-Sesame pattern).
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        frame:UnregisterEvent("PLAYER_LOGIN")
        initMinimap()
    end
end)
