-- Luacheck config for AltArmy TBC (WoW TBC Classic addon).
-- See https://luacheck.readthedocs.io/ and https://github.com/lunarmodules/luacheck

-- WoW uses Lua 5.1
std = "lua51"

-- Do not warn about unused implicit self argument in method (:) definitions.
self = false

-- Globals the addon reads and writes (SavedVariables, slash commands, etc.)
globals = {
    "AltArmy",
    "AltArmyTBC_Data",
    "AltArmyTBC_Options",
    "AltArmyTBC_GearSettings",
    "UISpecialFrames",
    "SLASH_ALTARMY1",
    "SlashCmdList",
}

-- WoW API and built-in globals (read-only from addon's perspective)
read_globals = {
    -- Frame & UI
    "CreateFrame",
    "UIParent",
    "tinsert",
    "GameFontNormal",
    "GameFontNormalLarge",
    "GameFontHighlight",
    "GameFontDisable",
    -- Unit & player
    "UnitName",
    "GetUnitName",
    "GetRealmName",
    "UnitLevel",
    "UnitClass",
    "UnitRace",
    "UnitFactionGroup",
    "UnitXP",
    "UnitXPMax",
    "GetXPExhaustion",
    "GetMoney",
    -- Time
    "time",
    -- Container / inventory (TBC)
    "GetContainerNumSlots",
    "GetContainerItemLink",
    "GetContainerItemInfo",
    "C_Container",
    "NUM_BAG_SLOTS",
    "BANK_CONTAINER",
    "MAX_PLAYER_LEVEL",
    -- Misc WoW
    "GetBuildInfo",
    "GetAddOnMetadata",
    "Interface",
    "LE_FRAME_TUTORIAL",
    -- WoW API (TBC / Classic)
    "ReloadUI",
    "wipe",
    "RequestTimePlayed",
    "GetNumSkillLines",
    "GetSkillLineInfo",
    "GetNumFactions",
    "GetFactionInfo",
    "GetInboxNumItems",
    "GetInboxHeaderInfo",
    "GetInboxItem",
    "GetInboxItemLink",
    "GetInboxText",
    "CheckInbox",
    "GetNumAuctionItems",
    "GetAuctionItemInfo",
    "GetAuctionItemTimeLeft",
    "GetAuctionItemLink",
    "GetContainerNumFreeSlots",
    "GetInventoryItemLink",
    "GetItemInfo",
    "GetTradeSkillLine",
    "GetNumTradeSkills",
    "SecondsToTime",
    "Minimap",
    "GameTooltip",
    "GetCursorPosition",
    "IsMouseButtonDown",
    "IsShiftKeyDown",
    "RAID_CLASS_COLORS",
    "ChatEdit_InsertLink",
    "GetCursorInfo",
    "ClearCursor",
    "Settings",
    "InterfaceOptions_AddCategory",
    "InterfaceAddOnsList_Update",
    -- Professions / tradeskill
    "GetTradeSkillInfo",
    "GetTradeSkillRecipeLink",
    "GetTradeSkillItemLink",
    "ExpandTradeSkillSubClass",
    "CollapseTradeSkillSubClass",
    "ExpandSkillHeader",
    "GetSpellInfo",
    -- Reputations
    "ExpandFactionHeader",
    "CollapseFactionHeader",
}
