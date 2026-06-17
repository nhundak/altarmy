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
        assert.is_false(AltArmyTBC_Options.debug.enabled)
        assert.is_false(AltArmyTBC_Options.debug.search)
        assert.is_false(AltArmyTBC_Options.debug.cooldowns)
        assert.is_false(AltArmyTBC_Options.debug.levelHistory)
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
end)
