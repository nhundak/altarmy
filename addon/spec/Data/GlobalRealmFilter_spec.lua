--[[ Unit tests for GlobalRealmFilter.lua — run: npm test ]]

describe("GlobalRealmFilter", function()
    local G

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("GlobalRealmFilter")
        G = AltArmy.GlobalRealmFilter
        assert.truthy(G)
    end)

    it("ResolveFromLegacyValues returns all only when all four are explicitly all", function()
        assert.are.equal("all", G.ResolveFromLegacyValues("all", "all", "all", "all"))
    end)

    it("ResolveFromLegacyValues returns currentRealm when any legacy value is nil", function()
        assert.are.equal("currentRealm", G.ResolveFromLegacyValues(nil, "all", "all", "all"))
        assert.are.equal("currentRealm", G.ResolveFromLegacyValues("all", nil, "all", "all"))
    end)

    it("ResolveFromLegacyValues returns currentRealm when any tab is currentRealm", function()
        assert.are.equal("currentRealm", G.ResolveFromLegacyValues("all", "all", "all", "currentRealm"))
    end)
end)
