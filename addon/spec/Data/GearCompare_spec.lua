--[[
  Unit tests for GearCompare.lua.
  Run from project root: npm test
]]

describe("GearCompare", function()
    local GC
    local DS

    local function mockGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [20] = { "New Ring", nil, 3, 50, 50, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [21] = { "Ring Two", nil, 2, 30, 30, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [22] = { "Ring One", nil, 2, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
        }
        local info = items[id]
        if not info then return end
        local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
        return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
    end

    local function mockGetItemStats(link)
        local id = tonumber(tostring(link):match("item:(%d+)"))
        if id == 11 then
            return { ["ITEM_MOD_INTELLECT_SHORT"] = 20, ["ITEM_MOD_STAMINA_SHORT"] = 10 }
        end
        if id == 10 then
            return { ["ITEM_MOD_INTELLECT_SHORT"] = 5, ["ITEM_MOD_STAMINA_SHORT"] = 5 }
        end
        return {}
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = {
            Characters = {
                TestRealm = {
                    MageAlt = {
                        name = "MageAlt",
                        realm = "TestRealm",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                        talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
                    },
                    EmptyHead = {
                        name = "EmptyHead",
                        realm = "TestRealm",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = {},
                        talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
                    },
                    RingAlt = {
                        name = "RingAlt",
                        realm = "TestRealm",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = {
                            [11] = "|Hitem:22:0|h[Ring One]|h",
                            [12] = "|Hitem:21:0|h[Ring Two]|h",
                        },
                        talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
                    },
                },
            },
        }
        _G.AltArmy.DB = _G.AltArmyTBC_Data
        _G.GetItemInfo = mockGetItemInfo
        _G.GetItemStats = mockGetItemStats
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        package.loaded["DataStore"] = nil
        package.loaded["ItemUsability"] = nil
        require("DataStore")
        require("DataStoreEquipment")
        DS = AltArmy.DataStore
        DS.accountData = _G.AltArmyTBC_Data
        require("ItemUsability")
        package.loaded["DataStoreTalents"] = nil
        require("DataStoreTalents")
        package.loaded["GearUpgrade"] = nil
        require("GearUpgrade")
        package.loaded["GearCompare"] = nil
        require("GearCompare")
        GC = AltArmy.GearCompare
    end)

    it("GetEquippedCompareItem returns equipped item in best slot", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local link, slot = GC.GetEquippedCompareItem(char, "|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
        })
        assert.are.equal("|Hitem:10:0|h[Old Helm]|h", link)
        assert.are.equal(1, slot)
    end)

    it("GetEquippedCompareItem honors explicit inventory slot", function()
        local char = DS:GetCharacter("RingAlt", "TestRealm")
        local link, slot = GC.GetEquippedCompareItem(char, "|Hitem:20:0|h[New Ring]|h", {
            technique = "ilvl",
            slot = 12,
        })
        assert.are.equal("|Hitem:21:0|h[Ring Two]|h", link)
        assert.are.equal(12, slot)
    end)

    it("GetEquippedCompareItem returns nil link for empty slot", function()
        local char = DS:GetCharacter("EmptyHead", "TestRealm")
        local link, slot = GC.GetEquippedCompareItem(char, "|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
        })
        assert.is_nil(link)
        assert.are.equal(1, slot)
    end)

    it("BuildComparison custom includes weighted stat rows and summary", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local focused = "|Hitem:11:0|h[New Helm]|h"
        local equipped = "|Hitem:10:0|h[Old Helm]|h"
        local result = GC.BuildComparison(focused, equipped, "custom", char)
        assert.are.equal("New Helm", result.focusedName)
        assert.are.equal("Old Helm", result.equippedName)
        assert.are.equal("custom", result.techniqueId)
        assert.is_true(result.summary.delta > 0)
        assert.is_true(#result.sections >= 1)
        local rows = result.sections[1].rows
        assert.is_true(#rows >= 1)
    end)

    it("BuildComparison ilvl returns item level summary", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "ilvl",
            char)
        assert.are.equal(35, result.summary.newTotal)
        assert.are.equal(20, result.summary.oldTotal)
        assert.are.equal(15, result.summary.delta)
    end)

    it("BuildComparison empty equipped shows (empty) name", function()
        local char = DS:GetCharacter("EmptyHead", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            nil,
            "custom",
            char)
        assert.are.equal("(empty)", result.equippedName)
    end)

    it("GetAvailableComparisonTechniques includes custom but excludes ilvl and gearscore", function()
        local techniques = GC.GetAvailableComparisonTechniques()
        local ids = {}
        for i = 1, #techniques do ids[techniques[i].id] = true end
        assert.is_true(ids.custom)
        assert.is_nil(ids.ilvl)
        assert.is_nil(ids.gearscore)
    end)

    it("BuildItemComparisonDebugReport lists all providers and character summaries", function()
        local lines = GC.BuildItemComparisonDebugReport("|Hitem:11:0|h[New Helm]|h")
        assert.is_true(#lines > 0)
        local text = table.concat(lines, "\n")
        assert.matches("New Helm", text)
        assert.matches("%[Alt Army%]", text)
        assert.matches("%[Item Level%]", text)
        assert.matches("MageAlt", text)
        assert.matches("upgrade", text)
        assert.matches("Intellect", text)
    end)
end)
