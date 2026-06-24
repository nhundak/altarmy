--[[
  Unit tests for GearUpgradeAlerts.lua.
  Run from project root: npm test
]]

describe("GearUpgradeAlerts", function()
    local GA
    local openedLink

    local function defaultGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        if id == 11 then
            return "New Helm", "|Hitem:11:0|h[New Helm]|h"
        end
        return nil
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        openedLink = nil
        AltArmy.OpenGearTabFocused = function(itemLink)
            openedLink = itemLink
        end
        _G.GetItemInfo = defaultGetItemInfo
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

    before_each(function()
        _G.GetItemInfo = defaultGetItemInfo
        openedLink = nil
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

    it("HandleSetItemRef preserves random suffix item payload", function()
        _G.GetItemInfo = function(item)
            if type(item) == "string" and item:find("item:99:") then
                return "Greaves of the Boar", item
            end
            if item == 99 then
                return "Greaves", "|Hitem:99:0|h[Greaves]|h"
            end
            return nil
        end
        local ok = GA.HandleSetItemRef(
            "altarmy:upgrade:item:99:0:0:0:0:0:55:12345:0",
            "LeftButton")
        assert.is_true(ok)
        assert.matches("item:99:0:0:0:0:0:55:12345", openedLink)
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

    describe("AnnounceLootUpgrade", function()
        local chatLines

        local function loadWithMocks(evaluateFn)
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    return { enabled = true, technique = "custom", levelsAhead = 5 }
                end,
                GetEffectiveTechnique = function(technique)
                    return technique
                end,
                EvaluateForAllAlts = evaluateFn,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = function() return false end,
            }
            AltArmy.ClassColor = {
                wrapName = function(name) return name end,
            }
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
        end

        it("omits the item link and includes the view upgrade link", function()
            loadWithMocks(function()
                return { { name = "MageAlt", classFile = "MAGE" } }
            end)
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_true(ok)
            assert.matches("Upgrade for MageAlt:", chatLines[1])
            assert.matches("View upgrade:", chatLines[1])
            assert.is_nil(chatLines[1]:match("|Hitem:11:0|h%[New Helm%]|h"))
        end)

        it("lists every alt name when three or fewer match", function()
            loadWithMocks(function()
                return {
                    { name = "Alpha", classFile = "MAGE" },
                    { name = "Bravo", classFile = "PRIEST" },
                    { name = "Charlie", classFile = "WARLOCK" },
                }
            end)
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("Upgrade for Alpha, Bravo, Charlie:", chatLines[1])
        end)

        it("summarizes four or more alts as two names plus others", function()
            loadWithMocks(function()
                return {
                    { name = "Alpha", classFile = "MAGE" },
                    { name = "Bravo", classFile = "PRIEST" },
                    { name = "Charlie", classFile = "WARLOCK" },
                    { name = "Delta", classFile = "HUNTER" },
                    { name = "Echo", classFile = "ROGUE" },
                }
            end)
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("Upgrade for Alpha, Bravo, and 3 others:", chatLines[1])
        end)
    end)
end)
