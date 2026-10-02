-- AltArmy TBC — the auction house's Alt Army scan button (AuctionScan.lua does the scanning).
-- Sits above the auction house frame, clear of its tabs and of other addons' buttons inside it.
-- luacheck: globals AuctionHouseFrame AuctionFrame

if not AltArmy then return end

AltArmy.AuctionScanButton = AltArmy.AuctionScanButton or {}
local Btn = AltArmy.AuctionScanButton

local button

--- The button's text and whether it can be clicked.
function Btn.Label(state, progress, cooldown)
    if state == "waiting" then
        return "Scanning...", false
    end
    if state == "reading" then
        return string.format("Scanning %d%%", math.floor(progress * 100)), false
    end
    if cooldown > 0 then
        return string.format("Scan in %d:%02d", math.floor(cooldown / 60), cooldown % 60), false
    end
    return "Alt Army scan", true
end

--- Open Alt Army's options on the automatic scan checkbox (General tab, Auction House section).
function Btn.OpenSettings()
    if AltArmy.OpenInterfaceOptions then
        AltArmy.OpenInterfaceOptions("general", { flash = "autoScan" })
    end
end

local function refresh()
    local S = AltArmy.AuctionScan
    if not button or not S then return end
    local text, enabled = Btn.Label(S.State(), S.Progress(), S.CooldownLeft())
    button:SetText(text)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

local function create()
    local S = AltArmy.AuctionScan
    local parent = AuctionHouseFrame or AuctionFrame
    if button or not parent or not S or not S.HasApi() then return end
    button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(130, 22)
    button:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 60, 0)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", function()
        S.Start()
        refresh()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Alt Army scan")
        local desc = "Reads every listing so Alt Army can make price calculations."
        if AltArmy.FeatureFlags and AltArmy.FeatureFlags.economySupplyChain then
            desc = desc .. " For greatest effect, use this in combination with the crafting tools on alt-army.com"
        end
        GameTooltip:AddLine(desc, 1, 1, 1, true)
        GameTooltip:AddLine("The game allows one full scan every 15 minutes.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local elapsed = 0
    button:SetScript("OnUpdate", function(_, dt) -- the cooldown's countdown
        elapsed = elapsed + dt
        if elapsed >= 1 then
            elapsed = 0
            refresh()
        end
    end)
    S.OnChange(refresh)

    -- Settings icon to the right: opens Options on the automatic scan checkbox.
    local settings = CreateFrame("Button", nil, parent)
    settings:SetSize(22, 22)
    settings:SetPoint("LEFT", button, "RIGHT", 4, 0)
    local icon = settings:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(settings)
    icon:SetTexture("Interface\\Icons\\Trade_Engineering") -- the main window's settings button art
    local highlight = settings:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(settings)
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    settings:SetHighlightTexture(highlight)
    settings:SetScript("OnClick", Btn.OpenSettings)
    Btn.settingsButton = settings
end

local frame = CreateFrame and CreateFrame("Frame")
if frame then
    frame:RegisterEvent("AUCTION_HOUSE_SHOW")
    frame:SetScript("OnEvent", function()
        create()
        refresh()
    end)
end
