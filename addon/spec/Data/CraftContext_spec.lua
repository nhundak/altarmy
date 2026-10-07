--[[ Unit tests for CraftContext.lua (Economy tab: who crafts for Writs and Waylaid Crates) — run: npm test ]]

describe("CraftContext", function()
    local CX

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["CraftContext"] = nil
        require("CraftContext")
        CX = AltArmy.CraftContext
        assert.truthy(CX)
    end)

    local CHARS = {
        Smith = { name = "Smith", faction = "Alliance", classFile = "WARRIOR",
            legacyTalents = { spells = { [1225459] = 2 } }, Reputations = { [72] = { s = 6 } },
            profs = { { rank = 150, Recipes = { [500] = { color = 1 }, [501] = { primaryRecipeID = 502 } } } } },
        Novice = { name = "Novice", faction = "Alliance", classFile = "MAGE",
            profs = { { rank = 20, Recipes = { [500] = true } } } },
        Orc = { name = "Orc", faction = "Horde", profs = { { rank = 300, Recipes = { [500] = true } } } },
    }
    local DS = {
        GetCharacters = function() return CHARS end,
        GetProfessions = function(_, char) return char.profs end,
        GetCurrentPlayerName = function() return "Novice" end,
        GetTotalItemCount = function(_, char, item) return item == 7 and (char.name == "Smith" and 2 or 1) or 0 end,
    }
    local DATA = { ITEMS = {}, RECIPES = { [500] = {}, [501] = {} }, ByOutput = {} }

    it("names the highest-skilled character of the faction who knows a recipe", function()
        local ctx = CX.Build(DS, "Realm", "Alliance", {}, DATA)
        assert.equals("Smith", ctx.knownBy(500))
        assert.is_nil(ctx.knownBy(501)) -- an alias key, not the recipe itself
        assert.equals("Novice", ctx.current)
        assert.equals(DATA.RECIPES, ctx.recipes)
    end)

    it("gives each character's vendor discount and class", function()
        local ctx, classOf = CX.Build(DS, "Realm", "Alliance", {}, DATA)
        assert.is_true(math.abs(ctx.discountOf("Smith") - 0.2) < 1e-9) -- Bartering 2 ranks + Honored
        assert.equals(0, ctx.discountOf(nil)) -- the current character, Novice
        assert.equals("WARRIOR", classOf.Smith)
        assert.is_nil(classOf.Orc)
    end)

    it("counts what the faction's characters hold", function()
        local ctx = CX.Build(DS, "Realm", "Alliance", {}, DATA)
        assert.equals(3, ctx.heldBy(7))
    end)
end)
