--[[ Unit tests for the generated WaylaidCrates.lua (Economy tab) — run: npm test ]]

describe("WaylaidCrates", function()
    local C

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.loaded["WaylaidCrates"] = nil
        require("WaylaidCrates")
        C = AltArmy.WaylaidCrates
        assert.truthy(C)
    end)

    local TIERS = { Apprentice = true, Journeyman = true, Expert = true, Artisan = true }

    it("lists the 30 shipments and the unread crate", function()
        local shipments = 0
        for _, crate in ipairs(C.LIST) do
            if not crate.random then
                shipments = shipments + 1
            end
        end
        assert.equals(30, shipments)
        assert.equals(31, #C.LIST)
        assert.is_true(C.ById[C.GENERIC].random)
    end)

    it("gives every shipment a tier, a kind and its bundles", function()
        for _, crate in ipairs(C.LIST) do
            assert.equals(crate, C.ById[crate.id])
            assert.is_string(crate.name)
            assert.is_string(crate.short)
            if not crate.random then
                assert.is_true(TIERS[crate.tier], crate.name)
                assert.truthy(crate.kind == "Gathered" or crate.kind == "Crafted", crate.name)
                assert.is_true(#crate.bundles >= 2, crate.name)
                for _, b in ipairs(crate.bundles) do
                    assert.is_true(b.item > 0 and b.count > 0, crate.name)
                    assert.is_string(b.name)
                end
            end
        end
    end)

    it("matches the game's Apprentice Ore crate", function()
        local ore = C.ById[248683]
        assert.equals("Waylaid Crate: Apprentice Ore", ore.name)
        assert.equals("Apprentice Ore", ore.short)
        assert.same({ { item = 2770, count = 20, name = "Copper Ore" }, { item = 2771, count = 20, name = "Tin Ore" } },
            ore.bundles)
    end)

    it("uses the tradeable Dark Iron Ore", function()
        local found
        for _, b in ipairs(C.ById[248697].bundles) do
            if b.name == "Dark Iron Ore" then
                found = b.item
            end
        end
        assert.equals(11370, found)
    end)

    it("tells gathered goods from crafted goods", function()
        assert.equals("Crafted", C.ById[248703].kind)
        assert.equals("Gathered", C.ById[248682].kind)
    end)
end)
