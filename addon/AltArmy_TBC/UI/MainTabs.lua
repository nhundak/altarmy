-- AltArmy TBC — Main window tab registry: order, labels, portrait/side-tab icons, settings routing.
-- Pure data; Core.lua builds the side tabs, title, portrait and toolbar settings button from it.

AltArmy = AltArmy or {}
AltArmy.MainTabs = AltArmy.MainTabs or {}

local MainTabs = AltArmy.MainTabs

local ADDON_TITLE = "Alt Army"
local ICON_PREFIX = "Interface\\Icons\\"

-- "Guild" stays last so hiding it (no guilded characters) never leaves a gap in the stack.
MainTabs.ORDER = { "Summary", "Gear", "Reputation", "Cooldowns", "Graph", "Guild" }

-- settings.toggle / settings.isShown: method names on AltArmy.TabFrames[name].
-- settings.optionsKey: opens Interface Options on that AltArmy section instead.
-- headerSearch: show the toolbar item/recipe search on this tab (always shown in search mode).
local DEFS = {
    Summary = {
        label = "Summary",
        icon = "INV_Misc_Book_09",
        headerSearch = true, -- toolbar item/recipe search; other tabs hide it
        settings = { toggle = "ToggleSummarySettings", isShown = "IsSummarySettingsShown" },
    },
    Gear = {
        label = "Gear",
        icon = "INV_Chest_Plate01",
        settings = { toggle = "ToggleGearSettings", isShown = "IsGearSettingsShown" },
    },
    Reputation = {
        label = "Reputation",
        nativeIcon = "INV_SideTab_Reputation2_c60", -- Forever CharacterFrame Reputation tab
        settings = { toggle = "ToggleReputationSettings", isShown = "IsReputationSettingsShown" },
    },
    Cooldowns = {
        label = "Cooldowns",
        icon = "INV_Misc_PocketWatch_01",
        settings = { optionsKey = "cooldowns" },
    },
    Graph = {
        label = "Graphs",
        nativeIcon = "INV_SideTab_Stats_c60", -- Forever CharacterFrame Statistics tab
    },
    Guild = {
        label = "Guild",
        icon = "INV_Shirt_GuildTabard_01", -- shown when the player has no guild crest
        guildCrest = true,
    },
    -- Header search results; no side tab.
    Search = {
        label = "Search",
        icon = "INV_Misc_Spyglass_02",
        settings = { toggle = "ToggleSearchSettings", isShown = "IsSearchSettingsShown" },
    },
}

-- nativeIcon: Forever's CharacterFrame side-tab icons (*_c60). They exist only in Forever's
-- game data, so TBC Anniversary uses byte-identical copies bundled under Textures/Icons
-- (extracted from Forever's CASC storage; see docs/UI_DESIGN.md). Forever keeps the game file
-- so its reskin applies.
local BUNDLED_ICON_PREFIX = "Interface\\AddOns\\AltArmy_TBC\\Textures\\Icons\\"
local isMainline = _G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1)

for name, def in pairs(DEFS) do
    def.name = name
    if def.nativeIcon then
        def.icon = (isMainline and ICON_PREFIX or BUNDLED_ICON_PREFIX) .. def.nativeIcon
    else
        def.icon = ICON_PREFIX .. def.icon
    end
    def.nativeIcon = nil
end

function MainTabs.Get(name)
    if name == nil then return nil end
    return DEFS[name]
end

--- Side-tab definitions in display order (excludes Search).
function MainTabs.List()
    local list = {}
    for i, name in ipairs(MainTabs.ORDER) do
        list[i] = DEFS[name]
    end
    return list
end

--- Window title for a tab, e.g. "Alt Army - Reputation".
function MainTabs.Title(name)
    local def = DEFS[name]
    if not def then return ADDON_TITLE end
    return ADDON_TITLE .. " - " .. def.label
end
