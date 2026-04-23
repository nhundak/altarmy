-- AltArmy TBC — Cooldown availability alerts (chat + optional on-screen banner + sound).
-- Uses CooldownData.EvaluateAlerts. Chat lines are prefixed with gold "AltArmy"; center-screen uses the body only.
-- "raidWarning" uses RaidNotice_AddMessage(RaidWarningFrame): local only, not raid/party chat.
-- luacheck: globals RaidWarningFrame RaidNotice_AddMessage GetRealmName RAID_CLASS_COLORS

if not AltArmy then return end

AltArmy.CooldownAlerts = AltArmy.CooldownAlerts or {}
local CA = AltArmy.CooldownAlerts

local alertState = {
    lastAvailAlertAt = {},
}

local TICK_INTERVAL = 30
local LOGIN_DELAY = 5
local elapsed = TICK_INTERVAL

local alertFrame = CreateFrame("Frame", "AltArmyTBC_CooldownAlertFrame", UIParent)

local ALTARMY_GOLD = "|cfffecc00"

local function categoryTitleFallback(key)
    local CD = AltArmy.CooldownData
    local c = CD and CD.CATEGORIES and CD.CATEGORIES[key]
    return (c and c.title) or key or "?"
end

local function classColorWrap(text, classFile)
    if not text or text == "" then
        text = "?"
    end
    local rc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if rc then
        local hex = string.format(
            "%02x%02x%02x",
            math.floor(rc.r * 255),
            math.floor(rc.g * 255),
            math.floor(rc.b * 255)
        )
        return "|cff" .. hex .. text .. "|r"
    end
    return text
end

--- Recipe / cooldown ready / name (and optional realm). No "AltArmy" prefix — used for center-screen.
--- @param r table alert row from CooldownData.EvaluateAlerts
--- @param showAllRealms boolean append (realm) when true
local function formatAlertBody(r, showAllRealms)
    local recipe = r.categoryTitle
    if not recipe or recipe == "" then
        recipe = categoryTitleFallback(r.categoryKey)
    end
    local namePart = classColorWrap(r.name, r.classFile)
    local msg = string.format("%s cooldown ready — %s", recipe, namePart)
    if showAllRealms and r.realm and r.realm ~= "" then
        msg = msg .. " (" .. r.realm .. ")"
    end
    return msg
end

--- Classic RaidNotice_AddMessage requires colorInfo; RaidNotice_SetSlot applies it after SetText.
--- Use white so |cff…|r segments (class-colored name) stay accurate.
local function raidNoticeBaseColor()
    return { r = 1, g = 1, b = 1 }
end

--- @param chatLine string|nil full line for DEFAULT_CHAT_FRAME (includes gold "AltArmy" when used)
--- @param raidLine string|nil line for RaidWarningFrame (body only; no "AltArmy")
local function sendCooldownAlert(chatLine, raidLine, alertType)
    local at = alertType or "chat"
    if at == "raidWarning" or at == "both" then
        if raidLine and raidLine ~= "" and RaidNotice_AddMessage and RaidWarningFrame then
            RaidNotice_AddMessage(RaidWarningFrame, raidLine, raidNoticeBaseColor())
        end
    end
    if at == "chat" or at == "both" then
        local chat = _G.DEFAULT_CHAT_FRAME
        if chatLine and chatLine ~= "" and chat and chat.AddMessage then
            chat:AddMessage(chatLine)
        end
    end
end

local function announceBatch(alerts, showAllRealms)
    if not alerts or #alerts == 0 then return end
    for _, r in ipairs(alerts) do
        local body = formatAlertBody(r, showAllRealms == true)
        local chatLine = ALTARMY_GOLD .. "AltArmy|r " .. body
        sendCooldownAlert(chatLine, body, r.alertType)
    end
    pcall(function()
        if PlaySound then
            PlaySound("TellMessage", "Master")
        end
    end)
end

function CA.RunEvaluateOnce()
    local DS = AltArmy.DataStore
    local CD = AltArmy.CooldownData
    if not DS or not CD or not CD.EvaluateAlerts or not CD.EnsureCooldownOptions then return end
    CD.EnsureCooldownOptions()
    local opts = AltArmyTBC_Options and AltArmyTBC_Options.cooldowns
    if not opts then return end
    local now = time and time() or 0
    local alerts = CD.EvaluateAlerts(DS, opts, now, alertState)
    local GRF = AltArmy.GlobalRealmFilter
    local showAllRealms = GRF and GRF.Get and GRF.Get() == "all"
    if GRF and GRF.Get and GRF.Get() == "currentRealm" then
        local curRealm = (GetRealmName and GetRealmName()) or ""
        local filtered = {}
        for i = 1, #alerts do
            local a = alerts[i]
            if a and a.realm == curRealm then
                filtered[#filtered + 1] = a
            end
        end
        alerts = filtered
    end
    announceBatch(alerts, showAllRealms)
end

function CA.ResetAnnouncementState()
    alertState.lastAvailAlertAt = {}
end

alertFrame:RegisterEvent("PLAYER_LOGIN")
alertFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        CA.ResetAnnouncementState()
        elapsed = TICK_INTERVAL
        alertFrame.loginSweepPending = true
        alertFrame.loginElapsed = 0
    end
end)

alertFrame:SetScript("OnUpdate", function(f, dt)
    if f.loginSweepPending then
        f.loginElapsed = (f.loginElapsed or 0) + dt
        if f.loginElapsed >= LOGIN_DELAY then
            f.loginSweepPending = false
            CA.RunEvaluateOnce()
            elapsed = 0
        end
        return
    end
    elapsed = elapsed + dt
    if elapsed >= TICK_INTERVAL then
        elapsed = 0
        CA.RunEvaluateOnce()
    end
end)
