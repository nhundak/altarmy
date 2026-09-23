-- AltArmy TBC — Search toolbar "Filter" dropdown entries (pure; rendered by Theme.CreateFilterDropdown).

AltArmy = AltArmy or {}
AltArmy.SearchFilterMenu = AltArmy.SearchFilterMenu or {}

local SFM = AltArmy.SearchFilterMenu

-- Silver cog (present on both TBC Anniversary and Forever).
SFM.ADVANCED_ICON = "Interface\\Buttons\\UI-OptionsButton"
SFM.ICON_SIZE = 14

--- Menu entries for the current state.
--- state: { items, recipes, showGuild, guild } (booleans).
--- Returns a list of { kind = "checkbox"|"divider"|"button", key, label, checked, enabled, icon }.
function SFM.BuildEntries(state)
    state = state or {}
    local recipes = state.recipes and true or false
    local entries = {
        { kind = "checkbox", key = "Items", label = "Items", checked = state.items and true or false, enabled = true },
        { kind = "checkbox", key = "Recipes", label = "Recipes", checked = recipes, enabled = true },
    }
    if state.showGuild then
        entries[#entries + 1] = {
            kind = "checkbox",
            key = "GuildRecipes",
            label = "Guild recipes",
            checked = state.guild and true or false,
            enabled = recipes,
        }
    end
    entries[#entries + 1] = { kind = "divider" }
    entries[#entries + 1] = { kind = "button", key = "Advanced", label = "Advanced", icon = SFM.ADVANCED_ICON }
    return entries
end

--- Display text for an entry; icons are inlined so native and fallback menus render them the same.
function SFM.FormatLabel(entry)
    if not entry then return "" end
    local label = entry.label or ""
    if entry.icon then
        return string.format("|T%s:%d:%d|t %s", entry.icon, SFM.ICON_SIZE, SFM.ICON_SIZE, label)
    end
    return label
end
