--[[
  Unit tests for QuestRewardIndicators.lua.
  Run from project root: npm test
]]

describe("QuestRewardIndicators", function()
    local QRI

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.CreateFrame = _G.CreateFrame or function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
                HookScript = function() end,
            }
        end
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua;AltArmy_TBC/Data/?.lua"
        package.loaded["QuestRewardIndicators"] = nil
        package.loaded["GearUpgrade"] = nil
        require("GearUpgrade")
        require("QuestRewardIndicators")
        QRI = AltArmy.QuestRewardIndicators
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
    end)

    it("EvaluateRewardIndicators returns highlight kind for best upgrade", function()
        local result = QRI.EvaluateRewardIndicators({
            { unifiedIndex = 1, itemId = 100, sellPrice = 50, delta = 5, equippable = true, highlightKind = "minor" },
            { unifiedIndex = 2, itemId = 200, sellPrice = 200, delta = 10, equippable = true, highlightKind = "clear" },
        }, {
            showQuestRewardUpgradeIndicator = true,
            showQuestRewardVendorIndicator = true,
        })
        assert.are.equal(2, result.bestUpgradeUnifiedIndex)
        assert.are.equal("clear", result.bestUpgradeHighlightKind)
    end)

    it("ApplyUpgradeBadgeStyle uses tilde for minor upgrades", function()
        local badge = {
            text = "",
            color = {},
            SetText = function(self, text) self.text = text end,
            SetTextColor = function(self, r, g, b, a) self.color = { r, g, b, a } end,
        }
        QRI.ApplyUpgradeBadgeStyle(badge, "minor")
        assert.are.equal("~", badge.text)
        assert.are.equal(0.9, badge.color[1])
        assert.are.equal(0.78, badge.color[2])
        assert.are.equal(0.12, badge.color[3])

        QRI.ApplyUpgradeBadgeStyle(badge, "clear")
        assert.are.equal("+", badge.text)
        assert.are.equal(0.2, badge.color[1])
        assert.are.equal(1, badge.color[2])
        assert.are.equal(0.2, badge.color[3])
    end)

    it("EvaluateRewardIndicators picks best upgrade and vendor indices", function()
        local result = QRI.EvaluateRewardIndicators({
            { unifiedIndex = 1, itemId = 100, sellPrice = 50, delta = 5, equippable = true },
            { unifiedIndex = 2, itemId = 200, sellPrice = 200, delta = 10, equippable = true },
            { unifiedIndex = 3, itemId = 300, sellPrice = 150, delta = 0, equippable = true },
        }, {
            showQuestRewardUpgradeIndicator = true,
            showQuestRewardVendorIndicator = true,
        })
        assert.are.equal(2, result.bestUpgradeUnifiedIndex)
        assert.are.equal(2, result.bestVendorUnifiedIndex)
    end)

    it("EvaluateRewardIndicators tie-breaks by item id", function()
        local result = QRI.EvaluateRewardIndicators({
            { unifiedIndex = 1, itemId = 200, sellPrice = 100, delta = 10, equippable = true },
            { unifiedIndex = 2, itemId = 100, sellPrice = 100, delta = 10, equippable = true },
        }, {
            showQuestRewardUpgradeIndicator = true,
            showQuestRewardVendorIndicator = true,
        })
        assert.are.equal(2, result.bestUpgradeUnifiedIndex)
        assert.are.equal(2, result.bestVendorUnifiedIndex)
    end)

    it("EvaluateRewardIndicators ignores non-equippable upgrades", function()
        local result = QRI.EvaluateRewardIndicators({
            { unifiedIndex = 1, itemId = 100, sellPrice = 50, delta = 20, equippable = false },
            { unifiedIndex = 2, itemId = 200, sellPrice = 10, delta = 5, equippable = true },
        }, {
            showQuestRewardUpgradeIndicator = true,
            showQuestRewardVendorIndicator = true,
        })
        assert.are.equal(2, result.bestUpgradeUnifiedIndex)
    end)

    it("EvaluateRewardIndicators returns nil upgrade when no positive delta", function()
        local result = QRI.EvaluateRewardIndicators({
            { unifiedIndex = 1, itemId = 100, sellPrice = 50, delta = 0, equippable = true },
            { unifiedIndex = 2, itemId = 200, sellPrice = 10, delta = -5, equippable = true },
        }, {
            showQuestRewardUpgradeIndicator = true,
            showQuestRewardVendorIndicator = true,
        })
        assert.is_nil(result.bestUpgradeUnifiedIndex)
        assert.are.equal(1, result.bestVendorUnifiedIndex)
    end)

    it("EvaluateRewardIndicators honors indicator toggles", function()
        local entries = {
            { unifiedIndex = 1, itemId = 100, sellPrice = 50, delta = 5, equippable = true },
        }
        local offUpgrade = QRI.EvaluateRewardIndicators(entries, {
            showQuestRewardUpgradeIndicator = false,
            showQuestRewardVendorIndicator = true,
        })
        assert.is_nil(offUpgrade.bestUpgradeUnifiedIndex)
        assert.are.equal(1, offUpgrade.bestVendorUnifiedIndex)

        local offVendor = QRI.EvaluateRewardIndicators(entries, {
            showQuestRewardUpgradeIndicator = true,
            showQuestRewardVendorIndicator = false,
        })
        assert.are.equal(1, offVendor.bestUpgradeUnifiedIndex)
        assert.is_nil(offVendor.bestVendorUnifiedIndex)
    end)

    it("CollectTurnInRewardEntries builds unified indices for choices and rewards", function()
        _G.GetNumQuestChoices = function() return 2 end
        _G.GetNumQuestRewards = function() return 1 end
        _G.GetQuestItemLink = function(kind, index)
            if kind == "choice" then
                return "|Hitem:" .. tostring(100 + index) .. "|h[Choice " .. index .. "]|h"
            end
            if kind == "reward" then
                return "|Hitem:" .. tostring(200 + index) .. "|h[Reward " .. index .. "]|h"
            end
            return nil
        end
        _G.GetItemInfo = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            return "Item", nil, nil, nil, nil, nil, nil, nil, nil, nil, id * 10
        end

        local entries = QRI.CollectTurnInRewardEntries()
        assert.are.equal(3, #entries)
        assert.are.equal(1, entries[1].unifiedIndex)
        assert.are.equal(101, entries[1].itemId)
        assert.are.equal(2, entries[2].unifiedIndex)
        assert.are.equal(3, entries[3].unifiedIndex)
        assert.are.equal(201, entries[3].itemId)
        assert.are.equal(2010, entries[3].sellPrice)
    end)

    it("OpenGearComparisonForLink opens the gear tab focused on the item", function()
        local opened
        AltArmy.OpenGearTabFocused = function(itemLink)
            opened = itemLink
        end
        local link = "|Hitem:42|h[Test Item]|h"
        assert.is_true(QRI.OpenGearComparisonForLink(link))
        assert.are.equal(link, opened)
        assert.is_false(QRI.OpenGearComparisonForLink(""))
        assert.is_false(QRI.OpenGearComparisonForLink(nil))
    end)

    it("ShouldEvaluateForCurrentCharacter returns false for bank alts", function()
        AltArmy.DataStore = {
            GetCurrentCharacter = function()
                return { name = "Banker", realm = "Test", classFile = "WARRIOR", level = 70 }
            end,
            GetCurrentPlayerRealm = function() return "Test" end,
        }
        AltArmy.BankAlt = {
            Is = function(name, realm)
                return name == "Banker" and realm == "Test"
            end,
        }
        assert.is_false(QRI.ShouldEvaluateForCurrentCharacter())
    end)
end)
