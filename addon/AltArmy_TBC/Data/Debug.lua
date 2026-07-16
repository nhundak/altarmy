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
    if d.itemStats == nil then
        d.itemStats = false
    end
    if d.guildShareVerbose == nil then
        d.guildShareVerbose = false
    end
    -- Legacy SavedVariables key from when guild share was a debug toggle; no longer read.
    d.guildShare = nil
    if d.pretendCraftLibNotInstalled == nil then
        d.pretendCraftLibNotInstalled = false
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
    D.NotifyChat("|cff00ccff[Alt Army:Search]|r " .. tostring(msg))
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
        D.NotifyChat("|cff00ccff[Alt Army:Compare]|r " .. tostring(msgs[i]))
    end
end

function D.IsItemStatsEnabled()
    local d = debugTable()
    return d.enabled == true and d.itemStats == true
end

function D.SetItemStatsEnabled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.itemStats = on == true
end

function D.LogItemStats(msgs)
    if not D.IsItemStatsEnabled() then
        return
    end
    if type(msgs) == "string" then
        msgs = { msgs }
    end
    if type(msgs) ~= "table" then
        return
    end
    for i = 1, #msgs do
        D.NotifyChat("|cff00ccff[Alt Army:ItemStats]|r " .. tostring(msgs[i]))
    end
end

--- Guild data sharing is shipped on. Call sites and tests may still stub this for flag-off paths.
--- Gates RECEIVE + UI, and selects the opt-in SEND set (see GuildShareComm).
function D.IsGuildShareEnabled()
    return true
end

--- Verbose guild-share traffic logging. Standalone (does NOT require master enabled).
function D.IsGuildShareVerbose()
    D.Ensure()
    return AltArmyTBC_Options.debug.guildShareVerbose == true
end

function D.SetGuildShareVerbose(on)
    D.Ensure()
    AltArmyTBC_Options.debug.guildShareVerbose = on == true
end

function D.LogGuildShare(msg)
    if not D.IsGuildShareVerbose() then
        return
    end
    D.NotifyChat("|cff00ccff[Alt Army:GuildShare]|r " .. tostring(msg))
end

--- When true, RecipeCraftLib.IsAvailable() returns false so CraftLib-dependent UI behaves
--- as if CraftLib were not installed. Standalone flag (does not require master debug on).
function D.IsPretendCraftLibNotInstalled()
    D.Ensure()
    return AltArmyTBC_Options.debug.pretendCraftLibNotInstalled == true
end

function D.SetPretendCraftLibNotInstalled(on)
    D.Ensure()
    AltArmyTBC_Options.debug.pretendCraftLibNotInstalled = on == true
end

function D.TogglePretendCraftLibNotInstalled()
    D.SetPretendCraftLibNotInstalled(not D.IsPretendCraftLibNotInstalled())
    return D.IsPretendCraftLibNotInstalled()
end

function D.RefreshCraftLibDependentUi()
    if AltArmy.RefreshGuildTab then
        pcall(AltArmy.RefreshGuildTab)
    end
    local searchFrame = AltArmy and AltArmy.TabFrames and AltArmy.TabFrames.Search
    if searchFrame and searchFrame.DoSearch then
        pcall(function()
            searchFrame:DoSearch()
        end)
    end
end

function D.NotifyChat(msg)
    local text = tostring(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

D.MAX_COMPARE_PANEL_DUMPS = 1

local function ensureComparePanelDumps()
    D.Ensure()
    local d = AltArmyTBC_Options.debug
    if type(d.comparePanelDumps) ~= "table" then
        d.comparePanelDumps = {}
    end
    return d.comparePanelDumps
end

function D.AppendComparePanelDump(payload)
    if type(payload) ~= "table" then
        return nil
    end
    local dumps = ensureComparePanelDumps()
    dumps[#dumps + 1] = payload
    while #dumps > D.MAX_COMPARE_PANEL_DUMPS do
        table.remove(dumps, 1)
    end
    return #dumps
end

function D.NotifyCompareDumpSaved(index, total)
    D.NotifyChat(string.format(
        "|cff00ccff[Alt Army:Debug]|r Compare dump #%d saved (%d in buffer). "
            .. "/reload, then open WTF/.../SavedVariables/AltArmy_TBC.lua",
        tonumber(index) or 0,
        tonumber(total) or 0))
end

D.Ensure()
