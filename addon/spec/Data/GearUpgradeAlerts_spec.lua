--[[
  Unit tests for GearUpgradeAlerts.lua.
  Run from project root: npm test
]]

describe("GearUpgradeAlerts", function()
    local GA
    local openedLink

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        openedLink = nil
        AltArmy.OpenGearTabFocused = function(itemLink)
            openedLink = itemLink
        end
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 11 then
                return "New Helm", "|Hitem:11:0|h[New Helm]|h"
            end
            return nil
        end
        _G.CreateFrame = _G.CreateFrame or function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
                HookScript = function() end,
            }
        end
        _G.SetItemRef = function() end
        _G.UIParent = _G.UIParent or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["GearUpgradeAlerts"] = nil
        require("GearUpgradeAlerts")
        GA = AltArmy.GearUpgradeAlerts
    end)

    it("HandleSetItemRef opens gear tab for altarmy upgrade links", function()
        local ok = GA.HandleSetItemRef("altarmy:upgrade:11", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)
    end)

    it("HandleSetItemRef accepts mixed-case link types", function()
        local ok = GA.HandleSetItemRef("AltArmy:upgrade:11", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)
    end)

    it("HandleSetItemRef falls back to bare item id when item is uncached", function()
        local ok = GA.HandleSetItemRef("altarmy:upgrade:99999", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("item:99999", openedLink)
    end)

    it("HandleSetItemRef ignores non-upgrade links", function()
        openedLink = nil
        assert.is_false(GA.HandleSetItemRef("item:11", "LeftButton"))
        assert.is_nil(openedLink)
    end)

    it("SetItemRef wrapper intercepts altarmy links before inner handler", function()
        local innerCalled = false
        _G.SetItemRef = function()
            innerCalled = true
        end
        package.loaded["GearUpgradeAlerts"] = nil
        require("GearUpgradeAlerts")
        GA = AltArmy.GearUpgradeAlerts
        openedLink = nil
        SetItemRef("altarmy:upgrade:11", "View upgrade", "LeftButton")
        assert.is_false(innerCalled)
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)

        SetItemRef("item:11", "item", "LeftButton")
        assert.is_true(innerCalled)
    end)
end)
