-- Migration from legacy minimapAngle / showMinimapButton to LibDBIcon minimap table.

describe("AltArmy.MigrateMinimapSavedVars", function()
    local migrate

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
        package.loaded["MinimapSavedVars"] = nil
        require("MinimapSavedVars")
        migrate = AltArmy.MigrateMinimapSavedVars
    end)
    it("creates minimap subtable with LibDBIcon defaults", function()
        local m = migrate({})
        assert.are.same({ hide = false, minimapPos = 90 }, m)
    end)

    it("maps minimapAngle to minimapPos", function()
        local m = migrate({ minimapAngle = 180 })
        assert.are.equal(180, m.minimapPos)
    end)

    it("maps showMinimapButton false to hide", function()
        local m = migrate({ showMinimapButton = false })
        assert.is_true(m.hide)
    end)

    it("preserves existing minimap subtable fields", function()
        local m = migrate({
            minimap = { hide = true, minimapPos = 45 },
        })
        assert.is_true(m.hide)
        assert.are.equal(45, m.minimapPos)
    end)

    it("does not overwrite minimapPos when already set", function()
        local m = migrate({
            minimapAngle = 10,
            minimap = { minimapPos = 200 },
        })
        assert.are.equal(200, m.minimapPos)
    end)
end)
