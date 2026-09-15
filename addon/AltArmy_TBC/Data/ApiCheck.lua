-- AltArmy TBC — Blizzard API existence check.
-- Manual diagnostic only: /altarmy debug apicheck. Never runs on its own (no
-- login hook, no event registration) — defining this file costs nothing.
-- Full per-entry results go to AltArmyTBC_Options.debug.apiCheckSnapshot
-- (read it from the SavedVariables .lua file after /reload); chat only gets
-- a one-line status.

if not AltArmy then return end

AltArmy.ApiCheck = AltArmy.ApiCheck or {}
local AC = AltArmy.ApiCheck

-- Each entry is ONE logical capability the addon depends on somewhere in its
-- code. `candidates` are dotted-path strings tried in order; the first one
-- that resolves wins. A fallback pair (old global vs. new namespaced API,
-- e.g. GetContainerItemInfo / C_Container.GetContainerItemInfo) is modeled
-- as a single entry with two candidates, not two independent checks — the
-- addon's own code already falls back the same way, so that's not a break.
AC.MANIFEST = {
    -- Bags/Containers
    { area = "Bags/Containers", label = "GetContainerNumSlots",
      candidates = { "C_Container.GetContainerNumSlots", "GetContainerNumSlots" } },
    { area = "Bags/Containers", label = "GetContainerItemInfo",
      candidates = { "C_Container.GetContainerItemInfo", "GetContainerItemInfo" } },
    { area = "Bags/Containers", label = "GetContainerItemLink",
      candidates = { "C_Container.GetContainerItemLink", "GetContainerItemLink" } },
    { area = "Bags/Containers", label = "ContainerIDToInventoryID",
      candidates = { "C_Container.ContainerIDToInventoryID", "ContainerIDToInventoryID" } },
    { area = "Bags/Containers", label = "GetContainerNumFreeSlots",
      candidates = { "C_Container.GetContainerNumFreeSlots", "GetContainerNumFreeSlots" } },
    { area = "Bags/Containers", label = "UseContainerItem",
      candidates = { "C_Container.UseContainerItem", "UseContainerItem" } },
    { area = "Bags/Containers", label = "SplitContainerItem",
      candidates = { "C_Container.SplitContainerItem", "SplitContainerItem" } },
    { area = "Bags/Containers", label = "PickupContainerItem",
      candidates = { "C_Container.PickupContainerItem", "PickupContainerItem" } },

    -- Inventory/Equipment
    { area = "Inventory/Equipment", label = "GetInventorySlotInfo", candidates = { "GetInventorySlotInfo" } },
    { area = "Inventory/Equipment", label = "GetInventoryItemLink", candidates = { "GetInventoryItemLink" } },
    { area = "Inventory/Equipment", label = "GetInventoryItemID", candidates = { "GetInventoryItemID" } },

    -- Item/Spell Info
    { area = "Item Info", label = "GetItemInfo", candidates = { "GetItemInfo" } },
    { area = "Item Info", label = "GetItemInfoInstant", candidates = { "GetItemInfoInstant" } },
    { area = "Item Info", label = "GetItemStats", candidates = { "GetItemStats" } },
    { area = "Item Info", label = "IsUsableItem", candidates = { "IsUsableItem" } },
    { area = "Item Info", label = "GetItemQualityColor", candidates = { "GetItemQualityColor" } },
    { area = "Item Info", label = "GetSpellInfo", candidates = { "GetSpellInfo" } },
    { area = "Item Info", label = "GetSpellLink", candidates = { "GetSpellLink" } },

    -- Professions/Tradeskills
    { area = "Professions", label = "GetNumTradeSkills", candidates = { "GetNumTradeSkills" } },
    { area = "Professions", label = "GetTradeSkillInfo", candidates = { "GetTradeSkillInfo" } },
    { area = "Professions", label = "GetTradeSkillLine", candidates = { "GetTradeSkillLine" } },
    { area = "Professions", label = "GetTradeSkillItemLink", candidates = { "GetTradeSkillItemLink" } },
    { area = "Professions", label = "GetTradeSkillRecipeLink", candidates = { "GetTradeSkillRecipeLink" } },
    { area = "Professions", label = "ExpandTradeSkillSubClass", candidates = { "ExpandTradeSkillSubClass" } },
    { area = "Professions", label = "GetTradeSkillNumReagents", candidates = { "GetTradeSkillNumReagents" } },
    { area = "Professions", label = "GetTradeSkillReagentItemLink", candidates = { "GetTradeSkillReagentItemLink" } },
    { area = "Professions", label = "GetTradeSkillReagentInfo", candidates = { "GetTradeSkillReagentInfo" } },
    { area = "Professions", label = "GetNumSkillLines", candidates = { "GetNumSkillLines" } },
    { area = "Professions", label = "GetSkillLineInfo", candidates = { "GetSkillLineInfo" } },
    { area = "Professions", label = "GetMacroInfo", candidates = { "GetMacroInfo" } },

    -- Crafting (old-style profession UI; some TBC-era professions still use this)
    { area = "Crafting", label = "GetCraftSkillLine", candidates = { "GetCraftSkillLine" } },
    { area = "Crafting", label = "GetNumCrafts", candidates = { "GetNumCrafts" } },
    { area = "Crafting", label = "GetCraftInfo", candidates = { "GetCraftInfo" } },
    { area = "Crafting", label = "GetCraftRecipeLink", candidates = { "GetCraftRecipeLink" } },
    { area = "Crafting", label = "GetCraftNumReagents", candidates = { "GetCraftNumReagents" } },
    { area = "Crafting", label = "GetCraftReagentInfo", candidates = { "GetCraftReagentInfo" } },

    -- Reputations
    { area = "Reputations", label = "GetNumFactions", candidates = { "GetNumFactions" } },
    { area = "Reputations", label = "GetFactionInfo", candidates = { "GetFactionInfo" } },
    { area = "Reputations", label = "GetFactionInfoByID", candidates = { "GetFactionInfoByID" } },
    { area = "Reputations", label = "ExpandFactionHeader", candidates = { "ExpandFactionHeader" } },

    -- Mail
    { area = "Mail", label = "GetInboxNumItems", candidates = { "GetInboxNumItems" } },
    { area = "Mail", label = "GetInboxHeaderInfo", candidates = { "GetInboxHeaderInfo" } },
    { area = "Mail", label = "GetInboxItem", candidates = { "GetInboxItem" } },
    { area = "Mail", label = "GetInboxItemLink", candidates = { "GetInboxItemLink" } },
    { area = "Mail", label = "SendMail", candidates = { "SendMail" } },
    { area = "Mail", label = "ReturnInboxItem", candidates = { "ReturnInboxItem" } },

    -- Auctions
    { area = "Auctions", label = "GetNumAuctionItems", candidates = { "GetNumAuctionItems" } },
    { area = "Auctions", label = "GetAuctionItemInfo", candidates = { "GetAuctionItemInfo" } },
    { area = "Auctions", label = "GetAuctionItemLink", candidates = { "GetAuctionItemLink" } },

    -- Talents
    { area = "Talents", label = "GetNumTalentTabs", candidates = { "GetNumTalentTabs" } },
    { area = "Talents", label = "GetTalentTabInfo", candidates = { "GetTalentTabInfo" } },

    -- Lockouts/Raids
    { area = "Lockouts", label = "RequestRaidInfo", candidates = { "RequestRaidInfo" } },
    { area = "Lockouts", label = "GetNumSavedInstances", candidates = { "GetNumSavedInstances" } },
    { area = "Lockouts", label = "GetSavedInstanceInfo", candidates = { "GetSavedInstanceInfo" } },

    -- Guild
    { area = "Guild", label = "GetGuildInfo", candidates = { "GetGuildInfo" } },
    { area = "Guild", label = "IsInGuild", candidates = { "IsInGuild" } },
    { area = "Guild", label = "GetNumGuildMembers", candidates = { "GetNumGuildMembers" } },
    { area = "Guild", label = "GetGuildRosterInfo", candidates = { "GetGuildRosterInfo" } },
    { area = "Guild", label = "GuildRoster", candidates = { "GuildRoster" } },
    { area = "Guild", label = "GetGuildTabardInfo", candidates = { "C_GuildInfo.GetGuildTabardInfo" } },

    -- Addon/Timer/Chat infra
    { area = "Addon Infra", label = "IsAddOnLoaded",
      candidates = { "C_AddOns.IsAddOnLoaded", "IsAddOnLoaded" } },
    { area = "Addon Infra", label = "GetAddOnMetadata",
      candidates = { "C_AddOns.GetAddOnMetadata", "GetAddOnMetadata" } },
    { area = "Addon Infra", label = "C_Timer.After", candidates = { "C_Timer.After" } },
    { area = "Addon Infra", label = "RegisterAddonMessagePrefix",
      candidates = { "C_ChatInfo.RegisterAddonMessagePrefix" } },
    { area = "Addon Infra", label = "SendAddonMessage",
      candidates = { "C_ChatInfo.SendAddonMessage", "SendAddonMessage" } },
    { area = "Addon Infra", label = "SendChatMessage", candidates = { "SendChatMessage" } },
    { area = "Addon Infra", label = "hooksecurefunc", candidates = { "hooksecurefunc" } },
    { area = "Addon Infra", label = "GetBuildInfo", candidates = { "GetBuildInfo" } },

    -- Unit/Player Info
    { area = "Unit Info", label = "UnitName", candidates = { "UnitName" } },
    { area = "Unit Info", label = "UnitLevel", candidates = { "UnitLevel" } },
    { area = "Unit Info", label = "UnitClass", candidates = { "UnitClass" } },
    { area = "Unit Info", label = "UnitRace", candidates = { "UnitRace" } },
    { area = "Unit Info", label = "UnitFactionGroup", candidates = { "UnitFactionGroup" } },
    { area = "Unit Info", label = "UnitGUID", candidates = { "UnitGUID" } },
    { area = "Unit Info", label = "UnitXPMax", candidates = { "UnitXPMax" } },
    { area = "Unit Info", label = "GetMaxPlayerLevel", candidates = { "GetMaxPlayerLevel" } },
    { area = "Unit Info", label = "GetRealmName", candidates = { "GetRealmName" } },
    { area = "Unit Info", label = "GetMoney", candidates = { "GetMoney" } },
    { area = "Unit Info", label = "GetXPExhaustion", candidates = { "GetXPExhaustion" } },
    { area = "Unit Info", label = "GetRealZoneText", candidates = { "GetRealZoneText" } },
    { area = "Unit Info", label = "RequestTimePlayed", candidates = { "RequestTimePlayed" } },
    { area = "Unit Info", label = "ChatFrame_DisplayTimePlayed", candidates = { "ChatFrame_DisplayTimePlayed" } },
    { area = "Unit Info", label = "CombatLogGetCurrentEventInfo", candidates = { "CombatLogGetCurrentEventInfo" } },

    -- Quests
    { area = "Quests", label = "GetNumQuestChoices", candidates = { "GetNumQuestChoices" } },
    { area = "Quests", label = "GetNumQuestRewards", candidates = { "GetNumQuestRewards" } },
    { area = "Quests", label = "SelectQuestLogEntry", candidates = { "SelectQuestLogEntry" } },

    -- Misc UI
    { area = "Misc UI", label = "CreateFrame", candidates = { "CreateFrame" } },
    { area = "Misc UI", label = "GetCursorPosition", candidates = { "GetCursorPosition" } },
    { area = "Misc UI", label = "GetCursorInfo", candidates = { "GetCursorInfo" } },
    { area = "Misc UI", label = "ChatFrame_AddMessageEventFilter", candidates = { "ChatFrame_AddMessageEventFilter" } },
    { area = "Misc UI", label = "ChatFrame_OnHyperlinkClick", candidates = { "ChatFrame_OnHyperlinkClick" } },
    { area = "Misc UI", label = "SetItemRef", candidates = { "SetItemRef" } },
    { area = "Misc UI", label = "DEFAULT_CHAT_FRAME", candidates = { "DEFAULT_CHAT_FRAME" } },
    { area = "Misc UI", label = "GameTooltip.SetOwner", candidates = { "GameTooltip.SetOwner" } },
}

--- Walks `root` (defaults to _G) along a dotted path (e.g. "C_Container.GetContainerItemInfo").
--- Returns (value, true) if found, or (nil, false) if any segment is missing/not a table.
--- Side-effect-free — never calls the resolved function.
function AC.Resolve(path, root)
    root = root or _G
    local node = root
    for part in tostring(path):gmatch("[^%.]+") do
        if type(node) ~= "table" then
            return nil, false
        end
        node = node[part]
    end
    if node == nil then
        return nil, false
    end
    return node, true
end

--- Checks one manifest entry against `root`. Returns "ok" (first/preferred
--- candidate resolved), "fallback" (a later candidate resolved), or
--- "missing" (none resolved), plus the matched candidate path (or nil).
function AC.CheckEntry(entry, root)
    for i, candidate in ipairs(entry.candidates) do
        local _, found = AC.Resolve(candidate, root)
        if found then
            return (i == 1) and "ok" or "fallback", candidate
        end
    end
    return "missing", nil
end

--- Runs `manifest` (defaults to AC.MANIFEST) against `root` (defaults to _G).
--- Returns (results, counts). results[i] = { area, label, status, matched, candidates }.
function AC.Run(manifest, root)
    manifest = manifest or AC.MANIFEST
    local results, counts = {}, { total = 0, ok = 0, fallback = 0, missing = 0 }
    for _, entry in ipairs(manifest) do
        local status, matched = AC.CheckEntry(entry, root)
        counts.total = counts.total + 1
        counts[status] = counts[status] + 1
        results[#results + 1] = {
            area = entry.area,
            label = entry.label,
            status = status,
            matched = matched,
            candidates = entry.candidates,
        }
    end
    return results, counts
end

function AC.BuildSnapshot(root)
    local results, counts = AC.Run(AC.MANIFEST, root)
    return {
        version = 1,
        timestamp = time and time() or 0,
        interface = GetBuildInfo and select(4, GetBuildInfo()) or nil,
        results = results,
        counts = counts,
    }
end

--- Prints a single terse status line — no per-entry/per-area detail. The
--- snapshot itself (saved separately) carries the detail for offline review.
function AC.ReportToChat(snapshot)
    local D = AltArmy.Debug
    if not D or not D.NotifyChat then
        return
    end
    local c = snapshot.counts
    if c.missing == 0 then
        D.NotifyChat(string.format(
            "|cff00ccff[Alt Army:ApiCheck]|r Checked %d API(s). No issues detected.", c.total))
    else
        D.NotifyChat(string.format(
            "|cff00ccff[Alt Army:ApiCheck]|r Checked %d API(s). %d issue(s) found — see the dump. "
                .. "/reload, then open WTF/.../SavedVariables/AltArmy_TBC.lua and look for debug.apiCheckSnapshot.",
            c.total, c.missing))
    end
end

--- Entry point for the /altarmy debug apicheck slash command. Never called
--- automatically — no login hook, no event registration anywhere in this file.
function AC.RunAndReport()
    local snapshot = AC.BuildSnapshot(_G)
    local D = AltArmy.Debug
    if D and D.SaveApiCheckSnapshot then
        D.SaveApiCheckSnapshot(snapshot)
    end
    AC.ReportToChat(snapshot)
    return snapshot
end
