-- AltArmy TBC — Search tab column layout (item and recipe result tables).

AltArmy.SearchColumns = AltArmy.SearchColumns or {}

local SC = AltArmy.SearchColumns

SC.ITEM_COLUMN_ORDER = { "Item", "Character", "Total" }
SC.RECIPE_COLUMN_ORDER = { "Recipe", "Character", "Skill" }

-- Closed-settings total (354+170+72=596) matches listViewport width on the 640px main frame
-- (624 content − 8 inner pad − 20 scroll gutter).
SC.ITEM_COLUMN_WIDTHS = { Item = 354, Character = 170, Total = 72 }
SC.RECIPE_COLUMN_WIDTHS = { Recipe = 354, Character = 170, Skill = 72 }

--- Pixels to subtract from Item/Recipe when the search settings panel is open.
SC.SETTINGS_FIRST_COLUMN_SHRINK = 179
--- Pixels to subtract from Character when the search settings panel is open.
SC.SETTINGS_CHARACTER_COLUMN_SHRINK = 12

local DEFAULT_COL_WIDTH = 80

local function CopyWidths(widths)
    local out = {}
    for k, v in pairs(widths) do
        out[k] = v
    end
    return out
end

function SC.GetItemColumnWidths(settingsOpen)
    if not settingsOpen then
        return CopyWidths(SC.ITEM_COLUMN_WIDTHS)
    end
    return {
        Item = SC.ITEM_COLUMN_WIDTHS.Item - SC.SETTINGS_FIRST_COLUMN_SHRINK,
        Character = SC.ITEM_COLUMN_WIDTHS.Character - SC.SETTINGS_CHARACTER_COLUMN_SHRINK,
        Total = SC.ITEM_COLUMN_WIDTHS.Total,
    }
end

function SC.GetRecipeColumnWidths(settingsOpen)
    if not settingsOpen then
        return CopyWidths(SC.RECIPE_COLUMN_WIDTHS)
    end
    return {
        Recipe = SC.RECIPE_COLUMN_WIDTHS.Recipe - SC.SETTINGS_FIRST_COLUMN_SHRINK,
        Character = SC.RECIPE_COLUMN_WIDTHS.Character - SC.SETTINGS_CHARACTER_COLUMN_SHRINK,
        Skill = SC.RECIPE_COLUMN_WIDTHS.Skill,
    }
end

--- Sum of column widths for a table layout.
function SC.GetTableWidth(order, widths)
    local w = 0
    for _, colName in ipairs(order) do
        w = w + (widths[colName] or DEFAULT_COL_WIDTH)
    end
    return w
end

--- Left edge (x offset) of a column within a table layout.
function SC.GetColumnOffset(order, widths, colName)
    local x = 0
    for _, name in ipairs(order) do
        if name == colName then
            return x
        end
        x = x + (widths[name] or DEFAULT_COL_WIDTH)
    end
    return nil
end

--- Item and recipe result columns share the same horizontal positions (default layout).
function SC.AreResultColumnsAligned()
    return SC.AreResultColumnsAlignedForSettings(false)
end

--- Item and recipe result columns share the same horizontal positions for a layout mode.
function SC.AreResultColumnsAlignedForSettings(settingsOpen)
    local itemWidths = SC.GetItemColumnWidths(settingsOpen)
    local recipeWidths = SC.GetRecipeColumnWidths(settingsOpen)
    local pairs = {
        { "Item", "Recipe" },
        { "Character", "Character" },
        { "Total", "Skill" },
    }
    for _, pair in ipairs(pairs) do
        local itemCol, recipeCol = pair[1], pair[2]
        local itemOffset = SC.GetColumnOffset(SC.ITEM_COLUMN_ORDER, itemWidths, itemCol)
        local recipeOffset = SC.GetColumnOffset(SC.RECIPE_COLUMN_ORDER, recipeWidths, recipeCol)
        if itemOffset ~= recipeOffset then
            return false
        end
        if itemWidths[itemCol] ~= recipeWidths[recipeCol] then
            return false
        end
    end
    return true
end

function SC.GetItemTableWidth(settingsOpen)
    local widths = settingsOpen and SC.GetItemColumnWidths(true) or SC.ITEM_COLUMN_WIDTHS
    return SC.GetTableWidth(SC.ITEM_COLUMN_ORDER, widths)
end

function SC.GetRecipeTableWidth(settingsOpen)
    local widths = settingsOpen and SC.GetRecipeColumnWidths(true) or SC.RECIPE_COLUMN_WIDTHS
    return SC.GetTableWidth(SC.RECIPE_COLUMN_ORDER, widths)
end

function SC.GetResultsTableWidth(settingsOpen)
    if settingsOpen then
        return math.max(
            SC.GetTableWidth(SC.ITEM_COLUMN_ORDER, SC.GetItemColumnWidths(true)),
            SC.GetTableWidth(SC.RECIPE_COLUMN_ORDER, SC.GetRecipeColumnWidths(true))
        )
    end
    return math.max(SC.GetItemTableWidth(), SC.GetRecipeTableWidth())
end
