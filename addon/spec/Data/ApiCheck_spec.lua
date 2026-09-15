--[[ Unit tests for ApiCheck.lua — run: npm test ]]

describe("AltArmy.ApiCheck", function()
    local AC, D

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["Debug"] = nil
        package.loaded["ApiCheck"] = nil
        require("Debug")
        require("ApiCheck")
        D = AltArmy.Debug
        AC = AltArmy.ApiCheck
        assert.truthy(D)
        assert.truthy(AC)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        D.Ensure()
    end)

    describe("Resolve", function()
        it("finds a bare global present on the given root", function()
            local v, found = AC.Resolve("GetItemInfo", { GetItemInfo = function() end })
            assert.is_true(found)
            assert.is_function(v)
        end)

        it("finds a nested dotted path", function()
            local root = { C_Container = { GetContainerItemInfo = function() end } }
            local v, found = AC.Resolve("C_Container.GetContainerItemInfo", root)
            assert.is_true(found)
            assert.is_function(v)
        end)

        it("returns false when a namespace table is entirely missing", function()
            local _, found = AC.Resolve("C_Container.GetContainerItemInfo", {})
            assert.is_false(found)
        end)

        it("returns false when an intermediate segment exists but isn't a table", function()
            local _, found = AC.Resolve("C_Container.GetContainerItemInfo", { C_Container = "not a table" })
            assert.is_false(found)
        end)

        it("defaults root to _G when omitted", function()
            _G.AltArmyApiCheckSpecFakeGlobal = function() end
            local _, found = AC.Resolve("AltArmyApiCheckSpecFakeGlobal")
            assert.is_true(found)
            _G.AltArmyApiCheckSpecFakeGlobal = nil
        end)
    end)

    describe("CheckEntry", function()
        it("reports ok when the first (preferred) candidate resolves", function()
            local entry = { candidates = { "C_Container.GetContainerItemInfo", "GetContainerItemInfo" } }
            local root = { C_Container = { GetContainerItemInfo = function() end } }
            local status, matched = AC.CheckEntry(entry, root)
            assert.are.equal("ok", status)
            assert.are.equal("C_Container.GetContainerItemInfo", matched)
        end)

        it("reports fallback when only a later candidate resolves", function()
            local entry = { candidates = { "C_Container.GetContainerItemInfo", "GetContainerItemInfo" } }
            local root = { GetContainerItemInfo = function() end }
            local status, matched = AC.CheckEntry(entry, root)
            assert.are.equal("fallback", status)
            assert.are.equal("GetContainerItemInfo", matched)
        end)

        it("reports missing when no candidate resolves", function()
            local entry = { candidates = { "C_Container.GetContainerItemInfo", "GetContainerItemInfo" } }
            local status, matched = AC.CheckEntry(entry, {})
            assert.are.equal("missing", status)
            assert.is_nil(matched)
        end)
    end)

    describe("Run", function()
        it("counts ok/fallback/missing across a manifest", function()
            local manifest = {
                { area = "A", label = "one", candidates = { "Foo" } },
                { area = "A", label = "two", candidates = { "New.Bar", "Bar" } },
                { area = "B", label = "three", candidates = { "Missing" } },
            }
            local results, counts = AC.Run(manifest, { Foo = function() end, Bar = function() end })
            assert.are.equal(3, counts.total)
            assert.are.equal(1, counts.ok)
            assert.are.equal(1, counts.fallback)
            assert.are.equal(1, counts.missing)
            assert.are.equal(3, #results)
            assert.are.equal("ok", results[1].status)
            assert.are.equal("fallback", results[2].status)
            assert.are.equal("missing", results[3].status)
        end)
    end)

    describe("MANIFEST", function()
        it("is a non-empty table of well-formed entries", function()
            assert.is_table(AC.MANIFEST)
            assert.is_true(#AC.MANIFEST > 0)
            for _, entry in ipairs(AC.MANIFEST) do
                assert.is_string(entry.area)
                assert.is_string(entry.label)
                assert.is_table(entry.candidates)
                assert.is_true(#entry.candidates > 0)
            end
        end)
    end)

    describe("BuildSnapshot", function()
        it("returns a versioned table with counts and results sized to the real manifest", function()
            local snapshot = AC.BuildSnapshot(_G)
            assert.are.equal(1, snapshot.version)
            assert.is_table(snapshot.counts)
            assert.is_table(snapshot.results)
            assert.are.equal(#AC.MANIFEST, snapshot.counts.total)
            assert.are.equal(#AC.MANIFEST, #snapshot.results)
        end)
    end)

    describe("RunAndReport", function()
        it("saves a single overwritten snapshot under debug.apiCheckSnapshot", function()
            AC.RunAndReport()
            assert.is_table(AltArmyTBC_Options.debug.apiCheckSnapshot)
            AC.RunAndReport()
            assert.is_table(AltArmyTBC_Options.debug.apiCheckSnapshot)
            assert.is_nil(AltArmyTBC_Options.debug.apiCheckSnapshot[2])
        end)

        it("reports a clean status line when nothing is missing", function()
            local savedManifest = AC.MANIFEST
            AC.MANIFEST = { { area = "A", label = "one", candidates = { "type" } } } -- Lua base lib, always present
            local messages = {}
            local original = D.NotifyChat
            D.NotifyChat = function(m) messages[#messages + 1] = m end

            AC.RunAndReport()

            D.NotifyChat = original
            AC.MANIFEST = savedManifest
            assert.are.equal(1, #messages)
            assert.matches("ApiCheck", messages[1])
            assert.matches("No issues detected", messages[1])
        end)

        it("reports an issue-count status line, with no per-entry detail, when something is missing", function()
            local savedManifest = AC.MANIFEST
            AC.MANIFEST = { { area = "A", label = "one", candidates = { "AltArmyApiCheckSpecDefinitelyMissing" } } }
            local messages = {}
            local original = D.NotifyChat
            D.NotifyChat = function(m) messages[#messages + 1] = m end

            AC.RunAndReport()

            D.NotifyChat = original
            AC.MANIFEST = savedManifest
            assert.are.equal(1, #messages)
            assert.matches("ApiCheck", messages[1])
            assert.matches("1 issue", messages[1])
            assert.does_not_match("AltArmyApiCheckSpecDefinitelyMissing", messages[1])
        end)
    end)
end)
