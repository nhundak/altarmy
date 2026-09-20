--[[
  Unit tests for DataStoreTalents.lua.
  Run from project root: npm test
]]

describe("DataStoreTalents", function()
    local DT
    local DS

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("DataStore")
        package.loaded["DataStoreTalents"] = nil
        require("DataStoreTalents")
        DT = AltArmy.DataStoreTalents
        DS = AltArmy.DataStore
    end)

    it("DerivePrimaryTabIndex picks tab with most points", function()
        assert.are.equal(3, DT.DerivePrimaryTabIndex({ 5, 10, 25 }))
    end)

    it("DerivePrimaryTabIndex returns nil when all zero", function()
        assert.is_nil(DT.DerivePrimaryTabIndex({ 0, 0, 0 }))
    end)

    it("GetSpecKeyForTab returns shadow for priest tab 3", function()
        assert.are.equal("shadow", DT.GetSpecKeyForTab("PRIEST", 3))
    end)

    it("GetLevelingSpecKey returns fury for warrior", function()
        assert.are.equal("fury", DT.GetLevelingSpecKey("WARRIOR"))
    end)

    it("GetLevelingSpecKey returns retribution for paladin", function()
        assert.are.equal("retribution", DT.GetLevelingSpecKey("PALADIN"))
    end)

    it("ResolveSpecKey uses stored spec when known", function()
        local char = {
            classFile = "PRIEST",
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "shadow" },
        }
        local key, known = DT.ResolveSpecKey(char)
        assert.are.equal("shadow", key)
        assert.is_true(known)
    end)

    it("ResolveSpecKey falls back to leveling spec when unknown", function()
        local char = { classFile = "PRIEST" }
        local key, known = DT.ResolveSpecKey(char)
        assert.are.equal("shadow", key)
        assert.is_false(known)
    end)

    it("HasTalentData is false when talents never scanned", function()
        assert.is_false(DT.HasTalentData({ classFile = "MAGE" }))
    end)

    it("HasTalentData is true after scan stored", function()
        assert.is_true(DT.HasTalentData({
            classFile = "MAGE",
            talents = { tabs = { 10, 0, 0 }, primary = 1, specKey = "arcane" },
        }))
    end)

    it("IsTalentEligible is false below level 10", function()
        assert.is_false(DT.IsTalentEligible({ level = 9 }))
    end)

    it("IsTalentEligible is true at level 10", function()
        assert.is_true(DT.IsTalentEligible({ level = 10 }))
    end)

    it("IsTalentEligible is false when level is missing", function()
        assert.is_false(DT.IsTalentEligible({ classFile = "MAGE" }))
    end)

    it("GetSpecKeyForSpecId maps canonical spec IDs to keys", function()
        assert.are.equal("fury", DT.GetSpecKeyForSpecId("WARRIOR", 72))
        assert.are.equal("retribution", DT.GetSpecKeyForSpecId("PALADIN", 70))
    end)

    it("GetSpecKeyForSpecId collapses both Druid Feral/Guardian IDs onto 'feral'", function()
        assert.are.equal("feral", DT.GetSpecKeyForSpecId("DRUID", 103))
        assert.are.equal("feral", DT.GetSpecKeyForSpecId("DRUID", 104))
    end)

    it("GetSpecKeyForSpecId returns nil for an unrecognized spec ID", function()
        assert.is_nil(DT.GetSpecKeyForSpecId("WARRIOR", 999))
    end)

    describe("ScanTalents specialization-API fallback (e.g. WoW Forever)", function()
        local oldGetNumTalentTabs, oldGetTalentTabInfo
        local oldGetSpecialization, oldGetSpecializationInfo, oldCSpecInfo
        local oldGetRealmName, oldUnitName

        before_each(function()
            oldGetNumTalentTabs = _G.GetNumTalentTabs
            oldGetTalentTabInfo = _G.GetTalentTabInfo
            oldGetSpecialization = _G.GetSpecialization
            oldGetSpecializationInfo = _G.GetSpecializationInfo
            oldCSpecInfo = _G.C_SpecializationInfo
            oldGetRealmName = _G.GetRealmName
            oldUnitName = _G.UnitName

            -- Legacy talent-tab API absent, same as WoW Forever (confirmed via /altarmy debug
            -- apicheck — see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md).
            _G.GetNumTalentTabs = nil
            _G.GetTalentTabInfo = nil
            _G.GetSpecialization = nil
            _G.GetSpecializationInfo = nil
            _G.C_SpecializationInfo = nil

            _G.GetRealmName = function() return "TestRealm" end
            _G.UnitName = function() return "TestChar" end
            _G.AltArmyTBC_Data.Characters = { TestRealm = { TestChar = { classFile = "WARRIOR" } } }
        end)

        after_each(function()
            _G.GetNumTalentTabs = oldGetNumTalentTabs
            _G.GetTalentTabInfo = oldGetTalentTabInfo
            _G.GetSpecialization = oldGetSpecialization
            _G.GetSpecializationInfo = oldGetSpecializationInfo
            _G.C_SpecializationInfo = oldCSpecInfo
            _G.GetRealmName = oldGetRealmName
            _G.UnitName = oldUnitName
        end)

        it("does nothing when neither the legacy nor the specialization API exist", function()
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.is_nil(char.talents)
        end)

        it("resolves specKey via C_SpecializationInfo when legacy tabs are missing", function()
            _G.C_SpecializationInfo = {
                GetSpecialization = function() return 2 end,
                GetSpecializationInfo = function(specIndex)
                    assert.are.equal(2, specIndex)
                    return 72 -- Fury Warrior
                end,
            }
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.are.equal("fury", char.talents.specKey)
            assert.are.equal(2, char.talents.primary)
            assert.is_not_nil(char.talents.tabs)
            local key, known = DT.ResolveSpecKey(char)
            assert.are.equal("fury", key)
            assert.is_true(known)
        end)

        it("falls back to the bare GetSpecialization/GetSpecializationInfo globals", function()
            _G.GetSpecialization = function() return 3 end
            _G.GetSpecializationInfo = function() return 73 end -- Protection Warrior
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.are.equal("protection", char.talents.specKey)
            assert.are.equal(3, char.talents.primary)
        end)

        it("records a scan with no spec chosen yet when the API exists but returns nothing", function()
            _G.C_SpecializationInfo = {
                GetSpecialization = function() return nil end,
                GetSpecializationInfo = function() return nil end,
            }
            DS:ScanTalents()
            local char = _G.AltArmyTBC_Data.Characters.TestRealm.TestChar
            assert.is_not_nil(char.talents)
            assert.is_nil(char.talents.specKey)
            assert.is_true(DT.HasTalentData(char))
            local key, known = DT.ResolveSpecKey(char)
            assert.are.equal("fury", key) -- warrior leveling-spec fallback
            assert.is_false(known)
        end)
    end)
end)
