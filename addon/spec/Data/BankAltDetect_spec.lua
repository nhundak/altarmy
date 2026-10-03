--[[ Unit tests for BankAltDetect.lua — run: npm test ]]

describe("BankAltDetect", function()
    local BD

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Options = {}
        _G.CreateFrame = _G.CreateFrame or function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
            }
        end
        _G.UIParent = _G.UIParent or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("CharKey")
        package.loaded["BankAlt"] = nil
        require("BankAlt")
        package.loaded["BankAltDetect"] = nil
        require("BankAltDetect")
        BD = AltArmy.BankAltDetect
        assert.truthy(BD)
    end)

    before_each(function()
        _G.AltArmyTBC_Options = {}
        AltArmy.BankAlt.Ensure()
        BD.EnsureDismiss()
    end)

    describe("formulas", function()
        it("NormalLevelTimeSeconds is 15 min at level 1", function()
            assert.are.equal(900, BD.NormalLevelTimeSeconds(1))
        end)

        it("NormalLevelTimeSeconds is 35 min at level 5", function()
            assert.are.equal(2100, BD.NormalLevelTimeSeconds(5))
        end)

        it("StagnationThresholdSeconds at level 1 is 2 hours", function()
            assert.are.equal(7200, BD.StagnationThresholdSeconds(1))
        end)

        it("StagnationThresholdSeconds at level 5 is 3h 20m", function()
            assert.are.equal(12000, BD.StagnationThresholdSeconds(5))
        end)
    end)

    describe("wealth", function()
        it("IsWealthy is false below 200g", function()
            assert.is_false(BD.IsWealthy(199 * 10000))
        end)

        it("IsWealthy is true at 200g", function()
            assert.is_true(BD.IsWealthy(200 * 10000))
        end)

        it("GetTotalWealthCopper sums on-hand and mail", function()
            local char = {}
            local ds = {
                GetMoney = function() return 100 * 10000 end,
                GetMailMoneyTotal = function() return 100 * 10000 end,
            }
            assert.are.equal(200 * 10000, BD.GetTotalWealthCopper(char, ds))
        end)
    end)

    describe("stagnation", function()
        it("IsStagnant is false one second below threshold at level 1", function()
            assert.is_false(BD.IsStagnant(1, 7199))
        end)

        it("IsStagnant is true at threshold at level 1", function()
            assert.is_true(BD.IsStagnant(1, 7200))
        end)
    end)

    local function mockDS(overrides)
        overrides = overrides or {}
        return {
            GetCharacterName = function(_, c) return c.name end,
            GetCharacterLevel = function(_, c) return c.level end,
            GetMoney = function(_, c) return c.money or 0 end,
            GetMailMoneyTotal = overrides.getMailMoneyTotal or function() return 0 end,
            GetPlayTime = function(_, c) return c.played or 0 end,
            GetDerivedPlayedTotal = overrides.getDerivedPlayedTotal,
        }
    end

    describe("Evaluate", function()
        it("prompts when wealthy and stagnant at level 5", function()
            local char = {
                name = "Banker",
                realm = "RealmA",
                level = 5,
                money = 200 * 10000,
                playedThisLevel = 12000,
            }
            local result = BD.Evaluate(char, mockDS(), { isCurrent = true })
            assert.is_true(result.shouldPrompt)
            assert.is_true(result.wealthy)
            assert.is_true(result.stagnant)
        end)

        it("does not prompt when wealthy but not stagnant", function()
            local char = {
                name = "Banker",
                realm = "RealmA",
                level = 1,
                money = 300 * 10000,
                playedThisLevel = 1000,
            }
            local result = BD.Evaluate(char, mockDS(), { isCurrent = true })
            assert.is_false(result.shouldPrompt)
            assert.is_true(result.wealthy)
            assert.is_false(result.stagnant)
        end)

        it("does not prompt when stagnant but not wealthy", function()
            local char = {
                name = "Banker",
                realm = "RealmA",
                level = 1,
                money = 50 * 10000,
                playedThisLevel = 8000,
            }
            local result = BD.Evaluate(char, mockDS(), { isCurrent = true })
            assert.is_false(result.shouldPrompt)
            assert.is_false(result.wealthy)
            assert.is_true(result.stagnant)
        end)

        it("does not prompt at level 6", function()
            local char = {
                name = "Banker",
                realm = "RealmA",
                level = 6,
                money = 300 * 10000,
                playedThisLevel = 99999,
            }
            local result = BD.Evaluate(char, mockDS(), { isCurrent = true })
            assert.is_false(result.shouldPrompt)
            assert.is_false(result.eligible)
        end)

        it("does not prompt when already marked bank alt", function()
            AltArmy.BankAlt.Set("Banker", "RealmA", true)
            local char = {
                name = "Banker",
                realm = "RealmA",
                level = 3,
                money = 300 * 10000,
                playedThisLevel = 8000,
            }
            local result = BD.Evaluate(char, mockDS(), { isCurrent = true })
            assert.is_false(result.shouldPrompt)
        end)

        it("does not prompt when dismissed", function()
            BD.Dismiss("Banker", "RealmA", "declined")
            local char = {
                name = "Banker",
                realm = "RealmA",
                level = 3,
                money = 300 * 10000,
                playedThisLevel = 8000,
            }
            local result = BD.Evaluate(char, mockDS(), { isCurrent = true })
            assert.is_false(result.shouldPrompt)
        end)

        it("uses milestone delta when playedThisLevel is absent", function()
            local char = {
                name = "Banker",
                realm = "RealmA",
                level = 3,
                money = 250 * 10000,
                played = 10000,
                levelHistory = {
                    milestones = {
                        [3] = { playedTotal = 2000 },
                    },
                },
            }
            local result = BD.Evaluate(char, mockDS(), { isCurrent = false })
            assert.are.equal(8000, result.timeAtLevelSeconds)
        end)
    end)
end)
