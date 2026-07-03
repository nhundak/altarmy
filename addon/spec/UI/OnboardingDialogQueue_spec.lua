--[[ Unit tests for OnboardingDialogQueue.lua — run: npm test ]]

describe("OnboardingDialogQueue", function()
    local ODQ

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.C_Timer = _G.C_Timer or {
            After = function(_, _, fn)
                if fn then fn() end
            end,
        }
        _G.CreateFrame = _G.CreateFrame or function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
            }
        end
        package.path = package.path .. ";AltArmy_TBC/UI/?.lua"
        package.loaded["OnboardingDialogQueue"] = nil
        require("OnboardingDialogQueue")
        ODQ = AltArmy.OnboardingDialogQueue
        assert.truthy(ODQ)
    end)

    before_each(function()
        ODQ._ResetForTests()
    end)

    it("shows only one provider at a time", function()
        local order = {}
        ODQ.Register({
            id = "first",
            priority = 1,
            shouldPrompt = function() return true end,
            show = function(onDismiss)
                order[#order + 1] = "show-first"
                onDismiss()
            end,
        })
        ODQ.Register({
            id = "second",
            priority = 2,
            shouldPrompt = function() return true end,
            show = function(onDismiss)
                order[#order + 1] = "show-second"
                onDismiss()
            end,
        })
        ODQ.Process()
        assert.are.same({ "show-first", "show-second" }, order)
    end)

    it("skips providers where shouldPrompt is false", function()
        local shown = false
        ODQ.Register({
            id = "skip",
            priority = 1,
            shouldPrompt = function() return false end,
            show = function()
                shown = true
            end,
        })
        ODQ.Register({
            id = "run",
            priority = 2,
            shouldPrompt = function() return true end,
            show = function(onDismiss)
                shown = true
                onDismiss()
            end,
        })
        ODQ.Process()
        assert.is_true(shown)
    end)

    it("does not start a second dialog while one is showing", function()
        local active = 0
        local maxActive = 0
        ODQ.Register({
            id = "slow",
            priority = 1,
            shouldPrompt = function() return true end,
            show = function(onDismiss)
                active = active + 1
                maxActive = math.max(maxActive, active)
                active = active - 1
                onDismiss()
            end,
        })
        ODQ.Process()
        assert.are.equal(1, maxActive)
    end)

    it("orders providers by ascending priority", function()
        local order = {}
        ODQ.Register({
            id = "late",
            priority = 10,
            shouldPrompt = function() return true end,
            show = function(onDismiss)
                order[#order + 1] = "late"
                onDismiss()
            end,
        })
        ODQ.Register({
            id = "early",
            priority = 5,
            shouldPrompt = function() return true end,
            show = function(onDismiss)
                order[#order + 1] = "early"
                onDismiss()
            end,
        })
        ODQ.Process()
        assert.are.same({ "early", "late" }, order)
    end)
end)
