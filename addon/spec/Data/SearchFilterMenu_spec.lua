--[[
  Unit tests for SearchFilterMenu.lua (toolbar "Filter" dropdown entries in search mode).
]]

describe("SearchFilterMenu", function()
    local SFM

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/Search/?.lua"
        require("SearchFilterMenu")
        SFM = AltArmy.SearchFilterMenu
    end)

    local function keysOf(entries)
        local out = {}
        for _, e in ipairs(entries) do
            out[#out + 1] = e.key or e.kind
        end
        return out
    end

    it("lists Items, Recipes, Guild recipes, then Advanced when guild sharing is on", function()
        local entries = SFM.BuildEntries({ items = true, recipes = true, showGuild = true, guild = false })
        assert.are.same({ "Items", "Recipes", "GuildRecipes", "divider", "Advanced" }, keysOf(entries))
        assert.are.equal("Guild recipes", entries[3].label)
        assert.is_false(entries[3].checked)
    end)

    it("hides Guild recipes when guild sharing is off", function()
        local entries = SFM.BuildEntries({ items = true, recipes = true, showGuild = false, guild = true })
        assert.are.same({ "Items", "Recipes", "divider", "Advanced" }, keysOf(entries))
    end)

    it("reflects checked state for Items and Recipes", function()
        local entries = SFM.BuildEntries({ items = false, recipes = true })
        assert.are.equal("checkbox", entries[1].kind)
        assert.is_false(entries[1].checked)
        assert.is_true(entries[2].checked)
    end)

    it("disables Guild recipes while Recipes is unchecked", function()
        local entries = SFM.BuildEntries({ items = true, recipes = false, showGuild = true, guild = true })
        assert.is_false(entries[3].enabled)
        entries = SFM.BuildEntries({ items = true, recipes = true, showGuild = true, guild = true })
        assert.is_true(entries[3].enabled)
    end)

    it("makes Advanced a button with the silver gear icon", function()
        local entries = SFM.BuildEntries({ items = true, recipes = true })
        local adv = entries[#entries]
        assert.are.equal("button", adv.kind)
        assert.are.equal(SFM.ADVANCED_ICON, adv.icon)
        local text = SFM.FormatLabel(adv)
        assert.truthy(text:find("|T" .. SFM.ADVANCED_ICON, 1, true))
        assert.truthy(text:find("Advanced", 1, true))
        assert.are.equal("Items", SFM.FormatLabel(entries[1]))
    end)
end)
