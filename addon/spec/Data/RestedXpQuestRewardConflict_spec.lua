--[[ Unit tests for RestedXpQuestRewardConflict.lua — run: npm test ]]

describe("RestedXpQuestRewardConflict", function()
    local RC
    local RXI
    local GU

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        _G.CreateFrame = _G.CreateFrame or function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
            }
        end
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["GearUpgrade"] = nil
        package.loaded["RestedXpIntegration"] = nil
        package.loaded["RestedXpQuestRewardConflict"] = nil
        require("GearUpgrade")
        require("RestedXpIntegration")
        require("RestedXpQuestRewardConflict")
        RC = AltArmy.RestedXpQuestRewardConflict
        RXI = AltArmy.RestedXpIntegration
        GU = AltArmy.GearUpgrade
        assert.truthy(RC)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        _G.RXPGuides = {
            settings = {
                profile = {
                    enableQuestChoiceRecommendation = true,
                    enableQuestChoiceGoldRecommendation = true,
                },
            },
        }
        GU.EnsureGearUpgradeOptions()
    end)

    it("ShouldPrompt is false when dismissed", function()
        AltArmyTBC_Options.restedXpQuestRewardConflictDismissed = true
        assert.is_false(RC.ShouldPrompt())
    end)

    it("ShouldPrompt is false when our upgrade indicator is off", function()
        AltArmyTBC_Options.gearUpgrades.showQuestRewardUpgradeIndicator = false
        assert.is_false(RC.ShouldPrompt())
    end)

    it("ShouldPrompt is false when RXP upgrade recommendation is off", function()
        _G.RXPGuides.settings.profile.enableQuestChoiceRecommendation = false
        assert.is_false(RC.ShouldPrompt())
    end)

    it("ShouldPrompt defers when RXP settings are not ready", function()
        _G.RXPGuides = nil
        _G.C_AddOns = {
            IsAddOnLoaded = function(name)
                return name == "RXPGuides_TBC"
            end,
        }
        assert.is_false(RC.ShouldPrompt())
    end)

    it("ShouldPrompt is true when both indicators are on and not dismissed", function()
        assert.is_true(RC.ShouldPrompt())
    end)

    it("ChooseAltArmy disables RXP upgrade and price overlays and dismisses", function()
        RC.ChooseAltArmy()
        assert.is_false(_G.RXPGuides.settings.profile.enableQuestChoiceRecommendation)
        assert.is_false(_G.RXPGuides.settings.profile.enableQuestChoiceGoldRecommendation)
        assert.is_true(AltArmyTBC_Options.restedXpQuestRewardConflictDismissed)
        assert.is_not_false(AltArmyTBC_Options.gearUpgrades.showQuestRewardUpgradeIndicator)
        assert.is_not_false(AltArmyTBC_Options.gearUpgrades.showQuestRewardVendorIndicator)
    end)

    it("ChooseRestedXp disables our upgrade and price overlays and dismisses", function()
        RC.ChooseRestedXp()
        assert.is_false(AltArmyTBC_Options.gearUpgrades.showQuestRewardUpgradeIndicator)
        assert.is_false(AltArmyTBC_Options.gearUpgrades.showQuestRewardVendorIndicator)
        assert.is_true(AltArmyTBC_Options.restedXpQuestRewardConflictDismissed)
        assert.is_true(_G.RXPGuides.settings.profile.enableQuestChoiceRecommendation)
        assert.is_true(_G.RXPGuides.settings.profile.enableQuestChoiceGoldRecommendation)
    end)

    it("ShouldPrompt is false when only price indicators conflict", function()
        _G.RXPGuides.settings.profile.enableQuestChoiceRecommendation = false
        _G.RXPGuides.settings.profile.enableQuestChoiceGoldRecommendation = true
        AltArmyTBC_Options.gearUpgrades.showQuestRewardUpgradeIndicator = false
        AltArmyTBC_Options.gearUpgrades.showQuestRewardVendorIndicator = true
        assert.is_false(RC.ShouldPrompt())
    end)

    it("DismissWithoutChoice marks dismissed without changing settings", function()
        RC.DismissWithoutChoice()
        assert.is_true(AltArmyTBC_Options.restedXpQuestRewardConflictDismissed)
        assert.is_not_false(AltArmyTBC_Options.gearUpgrades.showQuestRewardUpgradeIndicator)
        assert.is_not_false(AltArmyTBC_Options.gearUpgrades.showQuestRewardVendorIndicator)
        assert.is_true(_G.RXPGuides.settings.profile.enableQuestChoiceRecommendation)
        assert.is_true(_G.RXPGuides.settings.profile.enableQuestChoiceGoldRecommendation)
    end)
end)
