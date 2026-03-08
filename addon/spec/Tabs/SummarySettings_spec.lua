--[[
  Unit tests for Summary tab sort persistence (GetSummarySettings sort fields).
  Tests the validation/defaulting logic for sortKey and sortAscending in the
  AltArmyTBC_SummarySettings saved variable.
  Run from project root: npm test
]]

describe("Summary sort settings persistence", function()
    local VALID_SORT_KEYS = {
        name = true, level = true, restXp = true,
        money = true, played = true, lastOnline = true,
    }

    -- Mirror the GetSummarySettings logic from TabSummary.lua so we can test
    -- the validation rules in isolation without loading WoW UI APIs.
    local function GetSummarySettings()
        _G.AltArmyTBC_SummarySettings = _G.AltArmyTBC_SummarySettings or {}
        local s = _G.AltArmyTBC_SummarySettings
        if s.realmFilter ~= "all" and s.realmFilter ~= "currentRealm" then
            s.realmFilter = "all"
        end
        if not VALID_SORT_KEYS[s.sortKey] then
            s.sortKey = "name"
        end
        if s.sortAscending == nil then
            s.sortAscending = true
        end
        s.characters = s.characters or {}
        return s
    end

    before_each(function()
        _G.AltArmyTBC_SummarySettings = nil
    end)

    describe("sortKey default", function()
        it("defaults to 'name' when settings are empty", function()
            local s = GetSummarySettings()
            assert.are.equal("name", s.sortKey)
        end)

        it("preserves a valid sortKey", function()
            _G.AltArmyTBC_SummarySettings = { sortKey = "money" }
            local s = GetSummarySettings()
            assert.are.equal("money", s.sortKey)
        end)

        it("resets an unrecognised sortKey to 'name'", function()
            _G.AltArmyTBC_SummarySettings = { sortKey = "bogusColumn" }
            local s = GetSummarySettings()
            assert.are.equal("name", s.sortKey)
        end)

        it("accepts all valid sort keys", function()
            for key in pairs(VALID_SORT_KEYS) do
                _G.AltArmyTBC_SummarySettings = { sortKey = key }
                local s = GetSummarySettings()
                assert.are.equal(key, s.sortKey)
            end
        end)
    end)

    describe("sortAscending default", function()
        it("defaults to true when settings are empty", function()
            local s = GetSummarySettings()
            assert.is_true(s.sortAscending)
        end)

        it("preserves false (descending)", function()
            _G.AltArmyTBC_SummarySettings = { sortKey = "level", sortAscending = false }
            local s = GetSummarySettings()
            assert.is_false(s.sortAscending)
        end)

        it("preserves true (ascending)", function()
            _G.AltArmyTBC_SummarySettings = { sortKey = "money", sortAscending = true }
            local s = GetSummarySettings()
            assert.is_true(s.sortAscending)
        end)
    end)

    describe("settings round-trip", function()
        it("persists sortKey and sortAscending written by OnClick logic", function()
            local s = GetSummarySettings()
            -- Simulate clicking the Money column header
            s.sortKey = "money"
            s.sortAscending = false

            -- On the next session, AltArmyTBC_SummarySettings retains those values
            -- (simulated by NOT clearing the global before re-calling)
            local s2 = GetSummarySettings()
            assert.are.equal("money", s2.sortKey)
            assert.is_false(s2.sortAscending)
        end)
    end)
end)
