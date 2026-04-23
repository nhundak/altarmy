-- AltArmy TBC — Cooldown availability alerts (chat + sound). Uses CooldownData.EvaluateAlerts.

if not AltArmy then return end

AltArmy.CooldownAlerts = AltArmy.CooldownAlerts or {}
local CA = AltArmy.CooldownAlerts

local alertState = {
    availAnnounced = {},
    soonAnnounced = {},
}

local TICK_INTERVAL = 30
local LOGIN_DELAY = 5
local elapsed = TICK_INTERVAL

local alertFrame = CreateFrame("Frame", "AltArmyTBC_CooldownAlertFrame", UIParent)

local function categoryTitle(key)
    local CD = AltArmy.CooldownData
    local c = CD and CD.CATEGORIES and CD.CATEGORIES[key]
    return (c and c.title) or key or "?"
end

local function announceBatch(alerts)
    if not alerts or #alerts == 0 then return end
    local chat = _G.DEFAULT_CHAT_FRAME
    for _, r in ipairs(alerts) do
        local cat = categoryTitle(r.categoryKey)
        local kindLabel = r.kind == "soon" and "soon" or "ready"
        local realm = r.realm and r.realm ~= "" and (" (" .. r.realm .. ")") or ""
        local msg = string.format("|cfffecc00AltArmy|r %s — %s%s [%s]", cat, r.name or "?", realm, kindLabel)
        if chat and chat.AddMessage then
            chat:AddMessage(msg)
        end
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
    announceBatch(alerts)
end

function CA.ResetAnnouncementState()
    alertState.availAnnounced = {}
    alertState.soonAnnounced = {}
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
