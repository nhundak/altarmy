--[[
  Unit tests for GearUpgrade.lua.
  Run from project root: npm test
]]

describe("GearUpgrade", function()
    local GU
    local DS

    local function mockGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [12] = { "Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
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
                },
            },
        }
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmy.DB = _G.AltArmyTBC_Data
        _G.GetItemInfo = mockGetItemInfo
        _G.GetItemStats = mockGetItemStats
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_Options = { realmFilter = "all" }
        _G.AltArmy.GlobalRealmFilter = {
            Get = function() return "all" end,
        }
        package.loaded["DataStore"] = nil
        package.loaded["ItemUsability"] = nil
        require("DataStore")
        require("DataStoreEquipment")
        DS = AltArmy.DataStore
        DS.accountData = _G.AltArmyTBC_Data
        AltArmy.DB = _G.AltArmyTBC_Data
        DS.GetCurrentPlayerRealm = function() return "TestRealm" end
        require("ItemUsability")
        package.loaded["DataStoreTalents"] = nil
        require("DataStoreTalents")
        package.loaded["GearUpgrade"] = nil
        require("GearUpgrade")
        GU = AltArmy.GearUpgrade
    end)

    it("ScoreItemCustom sums stat weights", function()
        local score = GU.ScoreItemCustom("|Hitem:11:0|h[New Helm]|h", "MAGE", "frost")
        assert.is_true(score > 0)
    end)

    it("CompareItems ilvl detects upgrade", function()
        local isUp = GU.CompareItems(
            "|Hitem:11:0|h[New Helm]|h",
            "|Hitem:10:0|h[Old Helm]|h",
            "ilvl",
            "MAGE",
            "frost")
        assert.is_true(isUp)
    end)

    it("EvaluateForAllAlts finds upgrade for alt", function()
        local matches = GU.EvaluateForAllAlts("|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
            levelsAhead = 0,
        })
        assert.are.equal(1, #matches)
        assert.are.equal("MageAlt", matches[1].name)
        assert.is_true(matches[1].isUpgrade)
    end)

    it("EnsureGearUpgradeOptions applies defaults", function()
        _G.AltArmyTBC_Options = {}
        local opts = GU.EnsureGearUpgradeOptions()
        assert.is_true(opts.enabled)
        assert.are.equal("custom", opts.technique)
        assert.are.equal(5, opts.levelsAhead)
    end)

    it("EnsureGearUpgradeOptions preserves explicit values", function()
        _G.AltArmyTBC_Options = {
            gearUpgrades = { enabled = false, technique = "ilvl", levelsAhead = 0 },
        }
        local opts = GU.EnsureGearUpgradeOptions()
        assert.is_false(opts.enabled)
        assert.are.equal("ilvl", opts.technique)
        assert.are.equal(0, opts.levelsAhead)
    end)

    it("GetProviders lists techniques in display order", function()
        local providers = GU.GetProviders()
        assert.are.equal("custom", providers[1].id)
        assert.are.equal("pawn", providers[2].id)
        assert.are.equal("sgj", providers[3].id)
        assert.are.equal("ilvl", providers[4].id)
        assert.are.equal("gearscore", providers[5].id)
    end)

    it("GetProviderDisplayLabel marks not-recommended techniques", function()
        assert.are.equal("Alt Army", GU.GetProviderDisplayLabel(GU.GetProvider("custom")))
        assert.are.equal(
            "Item Level |cffFF664C(not recommended)|r",
            GU.GetProviderDisplayLabel(GU.GetProvider("ilvl")))
        assert.are.equal(
            "Gear Score |cffFF664C(not recommended)|r |cffaaaaaa(not installed)|r",
            GU.GetProviderDisplayLabel(GU.GetProvider("gearscore")))
    end)

    it("GetProviderDisplayLabel marks unavailable addon techniques as not installed", function()
        assert.are.equal(
            "Pawn |cffaaaaaa(not installed)|r",
            GU.GetProviderDisplayLabel(GU.GetProvider("pawn")))
        assert.are.equal(
            "Sharpie's Gear Judge |cffaaaaaa(not installed)|r",
            GU.GetProviderDisplayLabel(GU.GetProvider("sgj")))
    end)

    it("GetProviders lists all techniques", function()
        local providers = GU.GetProviders()
        local ids = {}
        for i = 1, #providers do ids[providers[i].id] = true end
        assert.is_true(ids.ilvl)
        assert.is_true(ids.custom)
        assert.is_true(ids.pawn)
    end)

    it("GetEffectiveTechnique falls back to custom when pawn unavailable", function()
        assert.are.equal("custom", GU.GetEffectiveTechnique("pawn"))
    end)

    it("GetCharacterUpgradeDelta returns score difference for ilvl technique", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local delta = GU.GetCharacterUpgradeDelta(char, "|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
        })
        assert.are.equal(15, delta)
    end)

    it("GetFocusUpgradeDelta is zero for non-upgrade characters", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local worseLink = "|Hitem:10:0|h[Old Helm]|h"
        local delta = GU.GetFocusUpgradeDelta(entry, char, worseLink, { technique = "ilvl" })
        assert.are.equal(0, delta)
    end)

    it("GetSlotUpgradeDelta compares one inventory slot at a time", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.RingAlt = {
            name = "RingAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = {
                [11] = "|Hitem:22:0|h[Ring One]|h",
                [12] = "|Hitem:21:0|h[Ring Two]|h",
            },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [20] = { "New Ring", nil, 3, 50, 50, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
                [21] = { "Ring Two", nil, 2, 30, 30, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
                [22] = { "Ring One", nil, 2, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            }
            local info = items[id]
            if not info then return oldGetItemInfo(item) end
            local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
            return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
        end
        local char = DS:GetCharacter("RingAlt", "TestRealm")
        local ringLink = "|Hitem:20:0|h[New Ring]|h"
        local slot11 = GU.GetSlotUpgradeDelta(char, ringLink, 11, { technique = "ilvl" })
        local slot12 = GU.GetSlotUpgradeDelta(char, ringLink, 12, { technique = "ilvl" })
        _G.GetItemInfo = oldGetItemInfo
        assert.are.equal(10, slot11)
        assert.are.equal(20, slot12)
    end)
end)
