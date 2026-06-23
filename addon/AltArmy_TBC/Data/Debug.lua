-- AltArmy TBC — Debug options (master switch + per-feature flags).
-- Saved under AltArmyTBC_Options.debug. Enable UI: /altarmy debug on

if not AltArmy then return end

AltArmy.Debug = AltArmy.Debug or {}
local D = AltArmy.Debug

local function debugTable()
    D.Ensure()
    return AltArmyTBC_Options.debug
end

function D.Ensure()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    local d = AltArmyTBC_Options.debug
    if type(d) ~= "table" then
        d = {}
        AltArmyTBC_Options.debug = d
    end
    if d.enabled == nil then
        d.enabled = false
    end
    if d.search == nil then
        d.search = false
    end
    if d.cooldowns == nil then
        d.cooldowns = false
    end
    if d.levelHistory == nil then
        d.levelHistory = false
    end
    if d.itemComparison == nil then
        d.itemComparison = false
    end
end

function D.IsEnabled()
    D.Ensure()
    return AltArmyTBC_Options.debug.enabled == true
end

function D.SetEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.enabled = on == true
end

function D.IsSearchEnabled()
    local d = debugTable()
    return d.enabled == true and d.search == true
end

function D.SetSearchEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.search = on == true
end

function D.LogSearch(msg)
    if not D.IsSearchEnabled() then
        return
    end
    D.NotifyChat("|cff00ccff[AltArmy:Search]|r " .. tostring(msg))
end

function D.IsCooldownsEnabled()
    local d = debugTable()
    return d.enabled == true and d.cooldowns == true
end

function D.SetCooldownsEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.cooldowns = on == true
end

function D.IsLevelHistoryEnabled()
    local d = debugTable()
    return d.enabled == true and d.levelHistory == true
end

function D.SetLevelHistoryEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.levelHistory = on == true
end

function D.IsItemComparisonEnabled()
    local d = debugTable()
    return d.enabled == true and d.itemComparison == true
end

function D.SetItemComparisonEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.itemComparison = on == true
end

function D.LogItemComparison(msgs)
    if not D.IsItemComparisonEnabled() then
        return
    end
    if type(msgs) == "string" then
        msgs = { msgs }
    end
    if type(msgs) ~= "table" then
        return
    end
    for i = 1, #msgs do
        D.NotifyChat("|cff00ccff[AltArmy:Compare]|r " .. tostring(msgs[i]))
    end
end

function D.NotifyChat(msg)
    local text = tostring(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

D.Ensure()
