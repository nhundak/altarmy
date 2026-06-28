--[[ Unit tests for BankAlt.lua — run: npm test ]]

describe("BankAlt", function()
    local B

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("CharKey")
        package.loaded["BankAlt"] = nil
        require("BankAlt")
        B = AltArmy.BankAlt
        assert.truthy(B)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        B.Ensure()
    end)

    it("Ensure initializes bankAlts table", function()
        B.Ensure()
        assert.is_table(AltArmyTBC_Options.bankAlts)
    end)

    it("Is returns false for unknown characters", function()
        assert.is_false(B.Is("Alice", "RealmA"))
    end)

    it("Set and Is round-trip", function()
        B.Set("Alice", "RealmA", true)
        assert.is_true(B.Is("Alice", "RealmA"))
        assert.is_false(B.Is("Bob", "RealmA"))
    end)

    it("Set false clears the flag", function()
        B.Set("Alice", "RealmA", true)
        B.Set("Alice", "RealmA", false)
        assert.is_false(B.Is("Alice", "RealmA"))
        assert.is_nil(AltArmyTBC_Options.bankAlts["RealmA\\Alice"])
    end)

    it("IconMarkup returns a texture escape", function()
        local markup = B.IconMarkup()
        assert.matches("|T.-|t", markup)
    end)
end)
