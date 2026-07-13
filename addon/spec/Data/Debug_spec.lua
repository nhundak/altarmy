--[[ Unit tests for Debug.lua — run: npm test ]]

describe("AltArmy.Debug", function()
    local D

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["Debug"] = nil
        require("Debug")
        D = AltArmy.Debug
        assert.truthy(D)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        D.Ensure()
    end)

    it("Ensure defaults enabled, search, and cooldowns to false", function()
        assert.is_false(D.IsEnabled())
        assert.is_false(D.IsSearchEnabled())
        assert.is_false(D.IsCooldownsEnabled())
        assert.is_false(D.IsLevelHistoryEnabled())
        assert.is_false(D.IsItemComparisonEnabled())
        assert.is_false(D.IsGuildShareEnabled())
        assert.is_false(AltArmyTBC_Options.debug.enabled)
        assert.is_false(AltArmyTBC_Options.debug.search)
        assert.is_false(AltArmyTBC_Options.debug.cooldowns)
        assert.is_false(AltArmyTBC_Options.debug.levelHistory)
        assert.is_false(AltArmyTBC_Options.debug.itemComparison)
        assert.is_false(AltArmyTBC_Options.debug.itemStats)
        assert.is_false(AltArmyTBC_Options.debug.guildShare)
        assert.is_false(D.IsPretendCraftLibNotInstalled())
    end)

    it("IsGuildShareEnabled returns the raw flag, NOT requiring master enabled", function()
        -- Unlike the other debug flags, guild share is a standalone feature flag:
        -- it must be true when guildShare is set even if the master debug switch is off.
        assert.is_false(D.IsEnabled())
        D.SetGuildShareEnabled(true)
        assert.is_true(D.IsGuildShareEnabled())
        assert.is_true(AltArmyTBC_Options.debug.guildShare)
    end)

    it("SetGuildShareEnabled(false) turns the flag off", function()
        D.SetGuildShareEnabled(true)
        assert.is_true(D.IsGuildShareEnabled())
        D.SetGuildShareEnabled(false)
        assert.is_false(D.IsGuildShareEnabled())
        assert.is_false(AltArmyTBC_Options.debug.guildShare)
    end)

    it("guildShareVerbose defaults false and is standalone (not requiring master enabled)", function()
        assert.is_false(D.IsGuildShareVerbose())
        assert.is_false(AltArmyTBC_Options.debug.guildShareVerbose)
        D.SetGuildShareVerbose(true)
        assert.is_true(D.IsGuildShareVerbose())
        D.SetGuildShareVerbose(false)
        assert.is_false(D.IsGuildShareVerbose())
    end)

    it("LogGuildShare only emits to chat when verbose is on", function()
        local messages = {}
        local original = D.NotifyChat
        D.NotifyChat = function(m) messages[#messages + 1] = m end

        D.SetGuildShareVerbose(false)
        D.LogGuildShare("hidden")
        assert.are.equal(0, #messages)

        D.SetGuildShareVerbose(true)
        D.LogGuildShare("visible")
        assert.are.equal(1, #messages)
        assert.matches("visible", messages[1])
        assert.matches("GuildShare", messages[1])

        D.NotifyChat = original
    end)

    it("IsSearchEnabled is false when search is on but master is off", function()
        AltArmyTBC_Options.debug.search = true
        assert.is_false(D.IsSearchEnabled())
    end)

    it("IsSearchEnabled is true when master and search are on", function()
        D.SetEnabled(true)
        D.SetSearchEnabled(true)
        assert.is_true(D.IsSearchEnabled())
    end)

    it("LogSearch only emits when master and search are on", function()
        local messages = {}
        local oldNotify = D.NotifyChat
        D.NotifyChat = function(msg)
            messages[#messages + 1] = msg
        end
        D.LogSearch("hidden")
        assert.are.equal(0, #messages)
        D.SetEnabled(true)
        D.SetSearchEnabled(true)
        D.LogSearch("visible")
        D.NotifyChat = oldNotify
        assert.are.equal(1, #messages)
        assert.matches("visible", messages[1])
    end)

    it("IsCooldownsEnabled is false when cooldowns is on but master is off", function()
        AltArmyTBC_Options.debug.cooldowns = true
        assert.is_false(D.IsCooldownsEnabled())
    end)

    it("IsCooldownsEnabled is true when master and cooldowns are on", function()
        D.SetEnabled(true)
        D.SetCooldownsEnabled(true)
        assert.is_true(D.IsCooldownsEnabled())
    end)

    it("IsLevelHistoryEnabled is false when levelHistory is on but master is off", function()
        AltArmyTBC_Options.debug.levelHistory = true
        assert.is_false(D.IsLevelHistoryEnabled())
    end)

    it("IsLevelHistoryEnabled is true when master and levelHistory are on", function()
        D.SetEnabled(true)
        D.SetLevelHistoryEnabled(true)
        assert.is_true(D.IsLevelHistoryEnabled())
    end)

    it("IsItemComparisonEnabled is true when master and itemComparison are on", function()
        D.SetEnabled(true)
        D.SetItemComparisonEnabled(true)
        assert.is_true(D.IsItemComparisonEnabled())
    end)

    it("LogItemComparison only emits when master and itemComparison are on", function()
        local messages = {}
        local oldNotify = D.NotifyChat
        D.NotifyChat = function(msg)
            messages[#messages + 1] = msg
        end
        D.LogItemComparison({ "hidden" })
        assert.are.equal(0, #messages)
        D.SetEnabled(true)
        D.SetItemComparisonEnabled(true)
        D.LogItemComparison({ "visible" })
        D.NotifyChat = oldNotify
        assert.are.equal(1, #messages)
        assert.matches("visible", messages[1])
        assert.matches("Compare", messages[1])
    end)

    it("IsItemStatsEnabled is true when master and itemStats are on", function()
        D.SetEnabled(true)
        D.SetItemStatsEnabled(true)
        assert.is_true(D.IsItemStatsEnabled())
    end)

    it("LogItemStats only emits when master and itemStats are on", function()
        local messages = {}
        local oldNotify = D.NotifyChat
        D.NotifyChat = function(msg)
            messages[#messages + 1] = msg
        end
        D.LogItemStats({ "hidden" })
        assert.are.equal(0, #messages)
        D.SetEnabled(true)
        D.SetItemStatsEnabled(true)
        D.LogItemStats({ "visible" })
        D.NotifyChat = oldNotify
        assert.are.equal(1, #messages)
        assert.matches("visible", messages[1])
        assert.matches("ItemStats", messages[1])
    end)

    it("SetEnabled(false) does not clear search or cooldowns flags", function()
        D.SetEnabled(true)
        D.SetSearchEnabled(true)
        D.SetCooldownsEnabled(true)
        D.SetEnabled(false)
        assert.is_false(D.IsEnabled())
        assert.is_true(AltArmyTBC_Options.debug.search)
        assert.is_true(AltArmyTBC_Options.debug.cooldowns)
    end)

    it("mutations persist in AltArmyTBC_Options.debug", function()
        D.SetEnabled(true)
        D.SetSearchEnabled(true)
        assert.is_true(AltArmyTBC_Options.debug.enabled)
        assert.is_true(AltArmyTBC_Options.debug.search)
    end)

    it("AppendComparePanelDump stores payloads in comparePanelDumps", function()
        local payload = { version = 1, character = { name = "MageAlt" } }
        local index = D.AppendComparePanelDump(payload)
        assert.are.equal(1, index)
        assert.are.same(payload, AltArmyTBC_Options.debug.comparePanelDumps[1])
    end)

    it("IsPretendCraftLibNotInstalled is standalone (not requiring master enabled)", function()
        assert.is_false(D.IsEnabled())
        D.SetPretendCraftLibNotInstalled(true)
        assert.is_true(D.IsPretendCraftLibNotInstalled())
        D.SetPretendCraftLibNotInstalled(false)
        assert.is_false(D.IsPretendCraftLibNotInstalled())
    end)

    it("TogglePretendCraftLibNotInstalled flips the saved flag", function()
        assert.is_true(D.TogglePretendCraftLibNotInstalled())
        assert.is_true(D.IsPretendCraftLibNotInstalled())
        assert.is_false(D.TogglePretendCraftLibNotInstalled())
        assert.is_false(D.IsPretendCraftLibNotInstalled())
    end)

    it("AppendComparePanelDump keeps only the newest MAX_COMPARE_PANEL_DUMPS entries", function()
        for i = 1, D.MAX_COMPARE_PANEL_DUMPS + 3 do
            D.AppendComparePanelDump({ version = 1, index = i })
        end
        local dumps = AltArmyTBC_Options.debug.comparePanelDumps
        assert.are.equal(D.MAX_COMPARE_PANEL_DUMPS, #dumps)
        assert.are.equal(4, dumps[1].index)
        assert.are.equal(D.MAX_COMPARE_PANEL_DUMPS + 3, dumps[#dumps].index)
    end)
end)
