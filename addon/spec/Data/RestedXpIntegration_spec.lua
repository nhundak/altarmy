--[[ Unit tests for RestedXpIntegration.lua — run: npm test ]]

describe("RestedXpIntegration", function()
    local RXI

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.CreateFrame = _G.CreateFrame or function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
            }
        end
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["RestedXpIntegration"] = nil
        require("RestedXpIntegration")
        RXI = AltArmy.RestedXpIntegration
        assert.truthy(RXI)
    end)

    before_each(function()
        _G.RXPGuides = nil
        _G.RXPSettings = nil
        _G.RXPCSettings = nil
        _G.LibStub = nil
        _G.C_AddOns = nil
        _G.IsAddOnLoaded = nil
        RXI._ResetPromptRecheckForTests()
    end)

    it("IsLoaded is false when RXP is absent", function()
        assert.is_false(RXI.IsLoaded())
    end)

    it("IsLoaded is true when ace addon is available", function()
        _G.RXPGuides = { settings = { profile = {} } }
        assert.is_true(RXI.IsLoaded())
    end)

    it("IsLoaded is false when only the RXPGuides namespace table exists", function()
        _G.RXPGuides = {}
        _G.C_AddOns = {
            IsAddOnLoaded = function()
                return false
            end,
        }
        assert.is_false(RXI.IsLoaded())
    end)

    it("reads profile from ace addon via LibStub", function()
        _G.RXPGuides = nil
        _G.LibStub = function(library)
            if library == "AceAddon-3.0" then
                return {
                    GetAddon = function(_, name)
                        if name == "RXPGuides" then
                            return {
                                settings = {
                                    profile = { enableQuestChoiceRecommendation = true },
                                },
                            }
                        end
                    end,
                }
            end
        end
        assert.is_true(RXI.IsQuestRewardUpgradeRecommendationEnabled())
    end)

    it("IsLoaded checks C_AddOns for RXPGuides_TBC", function()
        _G.C_AddOns = {
            IsAddOnLoaded = function(name)
                return name == "RXPGuides_TBC"
            end,
        }
        assert.is_true(RXI.IsLoaded())
    end)

    it("reads upgrade recommendation from RXP profile", function()
        _G.RXPGuides = {
            settings = {
                profile = { enableQuestChoiceRecommendation = true },
            },
        }
        assert.is_true(RXI.IsQuestRewardUpgradeRecommendationEnabled())
        _G.RXPGuides.settings.profile.enableQuestChoiceRecommendation = false
        assert.is_false(RXI.IsQuestRewardUpgradeRecommendationEnabled())
    end)

    it("treats nil upgrade recommendation as enabled", function()
        _G.RXPGuides = {
            settings = { profile = {} },
        }
        assert.is_true(RXI.IsQuestRewardUpgradeRecommendationEnabled())
    end)

    it("reads profile from RXPSettings when RXPGuides profile is unavailable", function()
        _G.C_AddOns = {
            IsAddOnLoaded = function(name)
                return name == "RXPGuides_TBC"
            end,
        }
        _G.RXPSettings = {
            profile = { enableQuestChoiceRecommendation = true },
        }
        assert.is_true(RXI.IsQuestRewardUpgradeRecommendationEnabled())
    end)

    it("returns nil when loaded but settings are not ready", function()
        _G.C_AddOns = {
            IsAddOnLoaded = function(name)
                return name == "RXPGuides_TBC"
            end,
        }
        assert.is_nil(RXI.IsQuestRewardUpgradeRecommendationEnabled())
    end)

    it("defaults nil recommendation flag to enabled once profile exists", function()
        _G.RXPSettings = {
            profile = {},
        }
        assert.is_true(RXI.IsQuestRewardUpgradeRecommendationEnabled())
    end)

    it("reads profile from RXPCSettings.profile", function()
        _G.RXPCSettings = {
            profile = { enableQuestChoiceRecommendation = true },
        }
        assert.is_true(RXI.IsQuestRewardUpgradeRecommendationEnabled())
    end)

    it("writes upgrade recommendation to RXP profile", function()
        _G.RXPGuides = {
            settings = {
                profile = { enableQuestChoiceRecommendation = true },
            },
        }
        RXI.SetQuestRewardUpgradeRecommendationEnabled(false)
        assert.is_false(_G.RXPGuides.settings.profile.enableQuestChoiceRecommendation)
    end)

    it("writes gold recommendation to RXP profile", function()
        _G.RXPGuides = {
            settings = {
                profile = { enableQuestChoiceGoldRecommendation = true },
            },
        }
        RXI.SetQuestRewardGoldRecommendationEnabled(false)
        assert.is_false(_G.RXPGuides.settings.profile.enableQuestChoiceGoldRecommendation)
    end)

    it("SetQuestRewardRecommendationsOnAllProfiles updates every RXPSettings profile", function()
        local activeProfile = {
            enableQuestChoiceRecommendation = true,
            enableQuestChoiceGoldRecommendation = true,
        }
        _G.RXPGuides = {
            settings = { profile = activeProfile },
        }
        _G.RXPSettings = {
            profiles = {
                Default = activeProfile,
                ["Alt - Realm"] = {
                    enableQuestChoiceRecommendation = true,
                    enableQuestChoiceGoldRecommendation = nil,
                },
            },
        }
        _G.RXPData = {
            defaultProfile = {
                profile = {
                    enableQuestChoiceRecommendation = nil,
                    enableQuestChoiceGoldRecommendation = true,
                },
            },
        }
        assert.is_true(RXI.SetQuestRewardRecommendationsOnAllProfiles(false))
        assert.is_false(_G.RXPSettings.profiles.Default.enableQuestChoiceRecommendation)
        assert.is_false(_G.RXPSettings.profiles.Default.enableQuestChoiceGoldRecommendation)
        assert.is_false(_G.RXPSettings.profiles["Alt - Realm"].enableQuestChoiceRecommendation)
        assert.is_false(_G.RXPSettings.profiles["Alt - Realm"].enableQuestChoiceGoldRecommendation)
        assert.is_false(_G.RXPData.defaultProfile.profile.enableQuestChoiceRecommendation)
        assert.is_false(_G.RXPData.defaultProfile.profile.enableQuestChoiceGoldRecommendation)
    end)

    it("GetLogoTexturePath prefers loaded addon name", function()
        _G.C_AddOns = {
            IsAddOnLoaded = function(name)
                return name == "RXPGuides_TBC"
            end,
        }
        assert.are.equal(
            "Interface/AddOns/RXPGuides_TBC/Textures/rxp_logo-64",
            RXI.GetLogoTexturePath())
    end)

    it("GetLogoTexturePath returns nil when RXP is not loaded", function()
        assert.is_nil(RXI.GetLogoTexturePath())
    end)
end)
