--[[
  Unit tests for SearchColumns.lua (search result table column alignment).
]]

describe("SearchColumns", function()
    local SC

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("SearchColumns")
        SC = AltArmy.SearchColumns
    end)

    it("aligns item and recipe name columns", function()
        assert.are.equal(
            SC.GetColumnOffset(SC.ITEM_COLUMN_ORDER, SC.ITEM_COLUMN_WIDTHS, "Item"),
            SC.GetColumnOffset(SC.RECIPE_COLUMN_ORDER, SC.RECIPE_COLUMN_WIDTHS, "Recipe")
        )
        assert.are.equal(SC.ITEM_COLUMN_WIDTHS.Item, SC.RECIPE_COLUMN_WIDTHS.Recipe)
    end)

    it("aligns item and recipe character columns", function()
        assert.are.equal(
            SC.GetColumnOffset(SC.ITEM_COLUMN_ORDER, SC.ITEM_COLUMN_WIDTHS, "Character"),
            SC.GetColumnOffset(SC.RECIPE_COLUMN_ORDER, SC.RECIPE_COLUMN_WIDTHS, "Character")
        )
        assert.are.equal(SC.ITEM_COLUMN_WIDTHS.Character, SC.RECIPE_COLUMN_WIDTHS.Character)
    end)

    it("aligns item Total column with recipe Skill column", function()
        assert.are.equal(
            SC.GetColumnOffset(SC.ITEM_COLUMN_ORDER, SC.ITEM_COLUMN_WIDTHS, "Total"),
            SC.GetColumnOffset(SC.RECIPE_COLUMN_ORDER, SC.RECIPE_COLUMN_WIDTHS, "Skill")
        )
        assert.are.equal(SC.ITEM_COLUMN_WIDTHS.Total, SC.RECIPE_COLUMN_WIDTHS.Skill)
    end)

    it("reports aligned layouts via AreResultColumnsAligned", function()
        assert.is_true(SC.AreResultColumnsAligned())
    end)

    it("uses the same total width for item and recipe tables", function()
        assert.are.equal(SC.GetItemTableWidth(), SC.GetRecipeTableWidth())
    end)

    it("shrinks the first column when settings are open", function()
        assert.are.equal(175, SC.GetItemColumnWidths(true).Item)
        assert.are.equal(175, SC.GetRecipeColumnWidths(true).Recipe)
        assert.are.equal(150, SC.SETTINGS_FIRST_COLUMN_SHRINK)
    end)

    it("keeps columns aligned when settings are open", function()
        assert.is_true(SC.AreResultColumnsAlignedForSettings(true))
        assert.are.equal(SC.GetItemTableWidth(true), SC.GetRecipeTableWidth(true))
    end)
end)
