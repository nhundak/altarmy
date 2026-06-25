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
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
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
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        package.loaded["PawnScale"] = nil
        require("PawnScale")
        package.loaded["PawnScales"] = nil
        require("PawnScales")
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

    it("BuildComparison custom uses Stat comparison section with changing stats", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local focused = "|Hitem:11:0|h[New Helm]|h"
        local equipped = "|Hitem:10:0|h[Old Helm]|h"
        local result = GC.BuildComparison(focused, equipped, "custom", char)
        assert.are.equal("New Helm", result.focusedName)
        assert.are.equal("Old Helm", result.equippedName)
        assert.are.equal("custom", result.techniqueId)
        assert.is_true(result.summary.delta > 0)
        assert.are.equal("Stat comparison", result.sections[1].title)
        local rows = result.sections[1].rows
        assert.are.equal(4, #rows)
        assert.are.equal("Stamina", rows[1].label)
        assert.is_false(rows[1].unimportant)
        assert.are.equal(0.5, rows[1].weight)
        assert.are.equal("Intellect", rows[2].label)
        assert.is_false(rows[2].unimportant)
        assert.are.equal(0.37, rows[2].weight)
        assert.are.equal("Weighted sum", rows[3].label)
        assert.are.equal(result.summary.delta, rows[3].delta)
        assert.is_true(rows[3].hideWeight)
        assert.are.equal("Weighted percent", rows[4].label)
        assert.is_true(rows[4].formatAsPercent)
        assert.is_true(rows[4].hideWeight)
        local expectedPercent = result.summary.delta / result.summary.oldTotal * 100
        assert.are.equal(expectedPercent, rows[4].delta)
    end)

    it("BuildComparison weighted percent uses upgradeMaxDelta when provided", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local focused = "|Hitem:11:0|h[New Helm]|h"
        local equipped = "|Hitem:10:0|h[Old Helm]|h"
        local result = GC.BuildComparison(focused, equipped, "custom", char, nil, {
            upgradeMaxDelta = 15,
        })
        local rows = result.sections[1].rows
        assert.are.equal("Weighted percent", rows[#rows].label)
        assert.are.equal(result.summary.delta / 15 * 100, rows[#rows].delta)
    end)

    it("BuildComparison includes zero-weight changing stats marked unimportant", function()
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 20,
                    ["ITEM_MOD_STAMINA_SHORT"] = 10,
                    ["ITEM_MOD_STRENGTH_SHORT"] = 8,
                }
            end
            if id == 10 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 5,
                    ["ITEM_MOD_STAMINA_SHORT"] = 5,
                }
            end
            return {}
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "custom",
            char)
        _G.GetItemStats = oldGetItemStats
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local rows = result.sections[1].rows
        assert.are.equal(5, #rows)
        assert.are.equal("Stamina", rows[1].label)
        assert.are.equal("Intellect", rows[2].label)
        assert.are.equal("Strength", rows[3].label)
        assert.is_true(rows[3].unimportant)
        assert.are.equal(0, rows[3].weight)
        assert.are.equal("Weighted sum", rows[4].label)
        assert.are.equal(result.summary.delta, rows[4].delta)
        assert.is_true(rows[4].hideWeight)
        assert.are.equal("Weighted percent", rows[5].label)
        assert.is_true(rows[5].formatAsPercent)
    end)

    it("BuildComparison omits stats that do not change", function()
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 20,
                    ["ITEM_MOD_STAMINA_SHORT"] = 10,
                }
            end
            if id == 10 then
                return {
                    ["ITEM_MOD_INTELLECT_SHORT"] = 5,
                    ["ITEM_MOD_STAMINA_SHORT"] = 10,
                }
            end
            return {}
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local result = GC.BuildComparison(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "custom",
            char)
        _G.GetItemStats = oldGetItemStats
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        assert.are.equal(3, #result.sections[1].rows)
        assert.are.equal("Intellect", result.sections[1].rows[1].label)
        assert.are.equal("Weighted sum", result.sections[1].rows[2].label)
        assert.are.equal(result.summary.delta, result.sections[1].rows[2].delta)
        assert.are.equal("Weighted percent", result.sections[1].rows[3].label)
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

    it("BuildItemComparisonDebugReport lists all providers and character summaries", function()
        local lines = GC.BuildItemComparisonDebugReport("|Hitem:11:0|h[New Helm]|h")
        assert.is_true(#lines > 0)
        local text = table.concat(lines, "\n")
        assert.matches("New Helm", text)
        assert.matches("%[Alt Army%]", text)
        assert.matches("%[Item Level%]", text)
        assert.matches("MageAlt", text)
        assert.matches("upgrade", text)
        assert.matches("Stat comparison", text)
    end)
end)
