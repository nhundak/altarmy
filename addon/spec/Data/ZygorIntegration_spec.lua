--[[ Unit tests for ZygorIntegration.lua — run: npm test ]]

describe("ZygorIntegration", function()
    local ZI

    local ALDOR_TITLE = "REPUTATIONS\\The Burning Crusade\\The Aldor"
    local STEAMWHEEDLE_TITLE = "REPUTATIONS\\Classic\\Steamwheedle Cartel"
    local CENTAUR_TITLE = "REPUTATIONS\\Classic\\Gelkis & Magram Centaur Clans"

    local function makeZgv(guides)
        return {
            DIR = "Interface\\AddOns\\ZygorGuidesViewerClassicTBCAnniv",
            registeredguides = guides or {},
            GetGuideByTitle = function(self, title)
                if not title then return nil end
                for _, g in ipairs(self.registeredguides) do
                    if g.title == title then
                        return g
                    end
                end
                return nil
            end,
            SetVisible = function() end,
            SetGuide = function() end,
        }
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        package.loaded["Debug"] = nil
        package.loaded["ZygorIntegration"] = nil
        require("Debug")
        require("ZygorIntegration")
        ZI = AltArmy.ZygorIntegration
        assert.truthy(ZI)
    end)

    before_each(function()
        _G.ZGV = nil
        _G.AltArmyTBC_Options = {}
        if AltArmy.Debug and AltArmy.Debug.Ensure then
            AltArmy.Debug.Ensure()
        end
        if ZI.SetDevShowMissingGuides then
            ZI.SetDevShowMissingGuides(false)
        end
    end)

    it("IsLoaded is false when ZGV is absent", function()
        assert.is_false(ZI.IsLoaded())
    end)

    it("IsLoaded is true when ZGV is present", function()
        _G.ZGV = makeZgv()
        assert.is_true(ZI.IsLoaded())
    end)

    it("GetGuideForFaction returns nil when Zygor is absent", function()
        assert.is_nil(ZI.GetGuideForFaction(932))
    end)

    it("GetGuideForFaction returns nil for unmapped faction IDs", function()
        _G.ZGV = makeZgv({
            { title = ALDOR_TITLE, missing = false },
        })
        assert.is_nil(ZI.GetGuideForFaction(99999))
    end)

    it("GetGuideForFaction returns title for a loadable guide", function()
        _G.ZGV = makeZgv({
            { title = ALDOR_TITLE, missing = false },
        })
        assert.are.equal(ALDOR_TITLE, ZI.GetGuideForFaction(932))
    end)

    it("GetGuideForFaction returns nil for a placeholder (missing) guide", function()
        _G.ZGV = makeZgv({
            { title = ALDOR_TITLE, missing = true },
        })
        assert.is_nil(ZI.GetGuideForFaction(932))
    end)

    it("GetGuideForFaction returns nil when mapped title is not registered", function()
        _G.ZGV = makeZgv({})
        assert.is_nil(ZI.GetGuideForFaction(932))
    end)

    it("maps Steamwheedle Cartel umbrella factions to one guide", function()
        _G.ZGV = makeZgv({
            { title = STEAMWHEEDLE_TITLE, missing = false },
        })
        -- Booty Bay, Everlook, Gadgetzan, Ratchet
        assert.are.equal(STEAMWHEEDLE_TITLE, ZI.GetGuideForFaction(21))
        assert.are.equal(STEAMWHEEDLE_TITLE, ZI.GetGuideForFaction(577))
        assert.are.equal(STEAMWHEEDLE_TITLE, ZI.GetGuideForFaction(369))
        assert.are.equal(STEAMWHEEDLE_TITLE, ZI.GetGuideForFaction(470))
    end)

    it("maps Gelkis and Magram Centaur to one guide", function()
        _G.ZGV = makeZgv({
            { title = CENTAUR_TITLE, missing = false },
        })
        assert.are.equal(CENTAUR_TITLE, ZI.GetGuideForFaction(92))
        assert.are.equal(CENTAUR_TITLE, ZI.GetGuideForFaction(93))
    end)

    it("OpenGuide shows viewer then loads the guide into a new tab", function()
        local visibleCalls = {}
        local loadTabCalls = {}
        local setGuideCalls = {}
        _G.ZGV = makeZgv({
            { title = ALDOR_TITLE, missing = false },
        })
        _G.ZGV.SetVisible = function(_, a, b)
            visibleCalls[#visibleCalls + 1] = { a, b }
        end
        _G.ZGV.Tabs = {
            LoadGuideToTab = function(_, title, step)
                loadTabCalls[#loadTabCalls + 1] = { title = title, step = step }
            end,
        }
        _G.ZGV.SetGuide = function(_, title)
            setGuideCalls[#setGuideCalls + 1] = title
        end

        assert.is_true(ZI.OpenGuide(ALDOR_TITLE))
        assert.are.equal(1, #visibleCalls)
        assert.is_nil(visibleCalls[1][1])
        assert.is_true(visibleCalls[1][2])
        assert.are.equal(1, #loadTabCalls)
        assert.are.equal(ALDOR_TITLE, loadTabCalls[1].title)
        assert.are.equal(1, loadTabCalls[1].step)
        assert.are.equal(0, #setGuideCalls)
    end)

    it("OpenGuide falls back to SetGuide when Tabs API is unavailable", function()
        local setGuideCalls = {}
        _G.ZGV = makeZgv()
        _G.ZGV.SetGuide = function(_, title)
            setGuideCalls[#setGuideCalls + 1] = title
        end

        assert.is_true(ZI.OpenGuide(ALDOR_TITLE))
        assert.are.equal(1, #setGuideCalls)
        assert.are.equal(ALDOR_TITLE, setGuideCalls[1])
    end)

    it("OpenGuide returns false when Zygor is absent", function()
        assert.is_false(ZI.OpenGuide(ALDOR_TITLE))
    end)

    it("OpenGuide returns false when title is nil", function()
        _G.ZGV = makeZgv()
        assert.is_false(ZI.OpenGuide(nil))
    end)

    it("SetDevShowMissingGuides allows placeholder titles", function()
        _G.ZGV = makeZgv({
            { title = ALDOR_TITLE, missing = true },
        })
        assert.is_nil(ZI.GetGuideForFaction(932))
        ZI.SetDevShowMissingGuides(true)
        assert.are.equal(ALDOR_TITLE, ZI.GetGuideForFaction(932))
        ZI.SetDevShowMissingGuides(false)
        assert.is_nil(ZI.GetGuideForFaction(932))
    end)

    it("GetIconTexturePath derives from ZGV.DIR", function()
        _G.ZGV = makeZgv()
        assert.are.equal(
            "Interface\\AddOns\\ZygorGuidesViewerClassicTBCAnniv\\Skins\\addon-icon",
            ZI.GetIconTexturePath())
    end)

    it("GetIconTexturePath returns nil when Zygor is absent", function()
        assert.is_nil(ZI.GetIconTexturePath())
    end)
end)
