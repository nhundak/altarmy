--[[
  Unit tests for DataStoreTalents.lua.
  Run from project root: npm test
]]

describe("DataStoreTalents", function()
    local DT

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
end)
