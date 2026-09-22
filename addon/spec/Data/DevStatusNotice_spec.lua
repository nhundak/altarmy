--[[ Unit tests for DevStatusNotice.lua — run: npm test ]]

describe("DevStatusNotice", function()
    local DSN

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["DevStatusNotice"] = nil
        require("DevStatusNotice")
        DSN = AltArmy.DevStatusNotice
        assert.truthy(DSN)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        _G.AltArmy.DataStore = { IsWowForever = true }
    end)

    it("ShouldPrompt is true when never shown and on WoW Forever", function()
        assert.is_true(DSN.ShouldPrompt())
    end)

    it("ShouldPrompt is false once dismissed", function()
        AltArmyTBC_Options.devStatusNoticeShown = true
        assert.is_false(DSN.ShouldPrompt())
    end)

    it("ShouldPrompt is false when not on WoW Forever", function()
        _G.AltArmy.DataStore = { IsWowForever = false }
        assert.is_false(DSN.ShouldPrompt())
    end)

    it("ShouldPrompt is false when DataStore is unavailable", function()
        _G.AltArmy.DataStore = nil
        assert.is_false(DSN.ShouldPrompt())
    end)

    it("Dismiss marks the notice as shown", function()
        DSN.Dismiss()
        assert.is_true(AltArmyTBC_Options.devStatusNoticeShown)
        assert.is_false(DSN.ShouldPrompt())
    end)

    it("IsDismissed reflects the saved flag", function()
        assert.is_false(DSN.IsDismissed())
        DSN.Dismiss()
        assert.is_true(DSN.IsDismissed())
    end)

    it("RegisterOnboardingProvider registers ahead of every other provider", function()
        local ODQ = { registered = nil }
        function ODQ.Register(provider)
            ODQ.registered = provider
        end
        _G.AltArmy.OnboardingDialogQueue = ODQ
        _G.AltArmy.DevStatusNoticeDialog = { Show = function() end }

        DSN.RegisterOnboardingProvider()

        assert.truthy(ODQ.registered)
        assert.are.equal("devStatusNotice", ODQ.registered.id)
        assert.are.equal(0, ODQ.registered.priority)

        _G.AltArmy.OnboardingDialogQueue = nil
        _G.AltArmy.DevStatusNoticeDialog = nil
    end)
end)
