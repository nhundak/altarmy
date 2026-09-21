--[[
  Unit tests for DataStoreLegacy.lua (WoW Forever Legacy Talent capture + rest-XP multiplier).
  Run from project root: npm test
]]

describe("DataStoreLegacy", function()
    local DL
    local DS

    local savedGlobals = {}
    local function stashGlobal(name)
        savedGlobals[name] = _G[name]
    end
    local function restoreGlobal(name)
        _G[name] = savedGlobals[name]
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = _G.AltArmyTBC_Data or { Characters = {} }
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("DataStore")
        package.loaded["DataStoreLegacy"] = nil
        require("DataStoreLegacy")
        DL = AltArmy.DataStoreLegacy
        DS = AltArmy.DataStore
    end)

    before_each(function()
        stashGlobal("C_ClassTalents")
        stashGlobal("C_Traits")
        stashGlobal("GetSpellInfo")
        stashGlobal("C_Spell")
        stashGlobal("UnitName")
        stashGlobal("GetRealmName")
        AltArmyTBC_Data.Characters = {}
    end)

    after_each(function()
        restoreGlobal("C_ClassTalents")
        restoreGlobal("C_Traits")
        restoreGlobal("GetSpellInfo")
        restoreGlobal("C_Spell")
        restoreGlobal("UnitName")
        restoreGlobal("GetRealmName")
    end)

    describe("HasTraitsApi", function()
        it("false when C_Traits is absent", function()
            _G.C_Traits = nil
            assert.is_false(DL.HasTraitsApi())
        end)

        it("true when the required C_Traits functions exist", function()
            _G.C_Traits = { GetTreeNodes = function() end, GetNodeInfo = function() end }
            assert.is_true(DL.HasTraitsApi())
        end)
    end)

    describe("ScanActiveConfig", function()
        it("returns nil when the API is entirely absent (e.g. TBC Classic)", function()
            _G.C_Traits = nil
            _G.C_ClassTalents = nil
            assert.is_nil(DL.ScanActiveConfig())
        end)

        it("returns nil when no active config resolves", function()
            _G.C_Traits = { GetTreeNodes = function() end, GetNodeInfo = function() end }
            _G.C_ClassTalents = { GetActiveConfigID = function() return nil end }
            assert.is_nil(DL.ScanActiveConfig())
        end)

        it("captures per-node ranks and total ranks spent across all trees", function()
            _G.C_ClassTalents = { GetActiveConfigID = function() return 111 end }
            _G.C_Traits = {
                GetConfigInfo = function(configID)
                    assert.are.equal(111, configID)
                    return { treeIDs = { 1, 2 } }
                end,
                GetTreeNodes = function(treeID)
                    if treeID == 1 then return { 10, 11 } end
                    return { 20 }
                end,
                GetNodeInfo = function(_configID, nodeID)
                    local ranks = { [10] = 2, [11] = 0, [20] = 3 }
                    return { activeRank = ranks[nodeID], entryIDs = {} }
                end,
            }
            local result = DL.ScanActiveConfig()
            assert.is_not_nil(result)
            assert.are.equal(2, result.nodes[10])
            assert.is_nil(result.nodes[11]) -- zero-rank nodes are not recorded
            assert.are.equal(3, result.nodes[20])
            assert.are.equal(5, result.totalRanksSpent)
            assert.are.equal(0, result.restRank)
        end)

        it("identifies the rest-XP talent's rank by resolved name", function()
            _G.C_ClassTalents = { GetActiveConfigID = function() return 1 end }
            _G.C_Spell = { GetSpellInfo = function(spellID)
                if spellID == 999 then return { name = "Well Rested" } end
                return { name = "Something Else" }
            end }
            _G.C_Traits = {
                GetConfigInfo = function() return { treeIDs = { 1 } } end,
                GetTreeNodes = function() return { 5 } end,
                GetNodeInfo = function(_configID, nodeID)
                    if nodeID == 5 then return { activeRank = 3, entryIDs = { 500 } } end
                    return nil
                end,
                GetEntryInfo = function(_configID, entryID)
                    if entryID == 500 then return { definitionID = 700 } end
                    return nil
                end,
                GetDefinitionInfo = function(definitionID)
                    if definitionID == 700 then return { spellID = 999 } end
                    return nil
                end,
            }
            local result = DL.ScanActiveConfig()
            assert.are.equal(3, result.restRank)
        end)
    end)

    describe("GetRestXpMultiplier", function()
        it("returns 1 when char has no legacyTalents", function()
            assert.are.equal(1, DL.GetRestXpMultiplier({}))
        end)

        it("returns 1 when char is nil", function()
            assert.are.equal(1, DL.GetRestXpMultiplier(nil))
        end)

        it("returns 1 when restRank is 0", function()
            assert.are.equal(1, DL.GetRestXpMultiplier({ legacyTalents = { restRank = 0 } }))
        end)

        it("applies 4% per rank", function()
            assert.are.equal(1.12, DL.GetRestXpMultiplier({ legacyTalents = { restRank = 3 } }))
        end)

        it("clamps at the max rank (5 -> 20%)", function()
            assert.are.equal(1.2, DL.GetRestXpMultiplier({ legacyTalents = { restRank = 9 } }))
        end)
    end)

    describe("ScanLegacyTalents", function()
        before_each(function()
            _G.UnitName = function() return "Legacychar" end
            _G.GetRealmName = function() return "Faerlina" end
        end)

        it("does nothing when the API doesn't resolve", function()
            _G.C_Traits = nil
            _G.C_ClassTalents = nil
            DS:ScanLegacyTalents()
            local char = AltArmyTBC_Data.Characters.Faerlina and AltArmyTBC_Data.Characters.Faerlina.Legacychar
            assert.is_nil(char.legacyTalents)
        end)

        it("stores captured data and bumps dataVersions.legacyTalents", function()
            _G.C_ClassTalents = { GetActiveConfigID = function() return 1 end }
            _G.C_Traits = {
                GetConfigInfo = function() return { treeIDs = { 1 } } end,
                GetTreeNodes = function() return { 5 } end,
                GetNodeInfo = function() return { activeRank = 2, entryIDs = {} } end,
            }
            DS:ScanLegacyTalents()
            local char = AltArmyTBC_Data.Characters.Faerlina.Legacychar
            assert.are.equal(2, char.legacyTalents.nodes[5])
            assert.are.equal(2, char.legacyTalents.totalRanksSpent)
            assert.are.equal(1, char.dataVersions.legacyTalents)
        end)
    end)
end)
