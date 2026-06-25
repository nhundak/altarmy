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
            [13] = { "Newer Helm", nil, 3, 32, 32, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [12] = { "Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [50] = { "Sparkling Wand", nil, 2, 25, 25, "Weapon", "Wand", nil, "INVTYPE_RANGEDRIGHT" },
            [80] = { "Heal Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [81] = { "Dmg Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
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
        if id == 13 then
            return { ["ITEM_MOD_INTELLECT_SHORT"] = 17, ["ITEM_MOD_STAMINA_SHORT"] = 8 }
        end
        if id == 50 then
            return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 15.5, ["ITEM_MOD_INTELLECT_SHORT"] = 5 }
        end
        if id == 51 then
            return { ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 12.0, ["ITEM_MOD_INTELLECT_SHORT"] = 5 }
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
        _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
            SHAMAN = { r = 0, g = 0.44, b = 0.87 },
            MAGE = { r = 0.41, g = 0.8, b = 0.94 },
        }
        package.loaded["ClassColor"] = nil
        require("ClassColor")
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
        GU = AltArmy.GearUpgrade
    end)

    it("ScoreItemCustom sums stat weights", function()
        local score = GU.ScoreItemCustom("|Hitem:11:0|h[New Helm]|h", "MAGE", "frost")
        assert.is_true(score > 0)
    end)

    it("FormatCompareSpecWarningText describes assumed spec with class-colored name", function()
        local text = GU.FormatCompareSpecWarningText("Totem", "Enhancement", "SHAMAN")
        assert.is_true(text:find("|cff", 1, true) ~= nil)
        assert.is_true(text:find("Totem", 1, true) ~= nil)
        assert.matches("spec is unknown%. Assuming Enhancement", text)
    end)

    it("GetCompareSpecWarning when talent data is missing", function()
        AltArmy.SummaryData = {
            GetTalentSpecMissingInfo = function(name)
                if name == "NoTalents" then
                    return { hasMissing = true, instructions = { "* Log in with this character" } }
                end
                return { hasMissing = false, instructions = {} }
            end,
        }
        local char = { classFile = "SHAMAN" }
        local entry = {
            name = "NoTalents",
            realm = "TestRealm",
            classFile = "SHAMAN",
            level = 60,
        }
        local warning = GU.GetCompareSpecWarning(entry, char)
        assert.is_truthy(warning)
        assert.are.equal("missing_spec", warning.kind)
        assert.matches("NoTalents", warning.text)
        assert.matches("spec is unknown", warning.text)
        assert.matches("Enhancement", warning.text)
        assert.are.equal("Enhancement", warning.assumedSpec)
    end)

    it("GetCompareSpecWarning is nil when talent data shows a picked spec", function()
        AltArmy.SummaryData = {
            GetTalentSpecMissingInfo = function()
                return { hasMissing = false, instructions = {} }
            end,
        }
        local char = {
            classFile = "MAGE",
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        assert.is_nil(GU.GetCompareSpecWarning(entry, char))
    end)

    it("GetCompareSpecWarning uses unpicked message when talents scanned but no points spent", function()
        AltArmy.SummaryData = {
            GetTalentSpecMissingInfo = function()
                return { hasMissing = false, instructions = {} }
            end,
        }
        local char = {
            classFile = "SHAMAN",
            talents = { tabs = { 0, 0, 0 }, primary = nil, specKey = nil },
        }
        local entry = {
            name = "FreshSixty",
            realm = "TestRealm",
            classFile = "SHAMAN",
            level = 60,
        }
        local warning = GU.GetCompareSpecWarning(entry, char)
        assert.is_truthy(warning)
        assert.are.equal("unpicked_spec", warning.kind)
        assert.matches("hasn't picked a spec yet", warning.text)
        assert.is_nil(warning.text:match("spec is unknown"))
        assert.matches("FreshSixty", warning.text)
        assert.matches("Enhancement", warning.text)
    end)

    it("GetCompareSpecWarning uses unpicked message for low-level characters with talent data", function()
        local char = {
            classFile = "MAGE",
            talents = { tabs = { 0, 0, 0 }, primary = nil, specKey = nil },
        }
        local entry = { name = "Lowbie", realm = "TestRealm", classFile = "MAGE", level = 8 }
        local warning = GU.GetCompareSpecWarning(entry, char)
        assert.are.equal("unpicked_spec", warning.kind)
        assert.matches("hasn't picked a spec yet", warning.text)
    end)

    it("ScoreItemCustom weights wand ranged_dps for hunters", function()
        local better = GU.ScoreItemCustom("|Hitem:50:0|h[Sparkling Wand]|h", "HUNTER", "beast")
        local worse = GU.ScoreItemCustom("|Hitem:51:0|h[Old Wand]|h", "HUNTER", "beast")
        assert.is_true(better > worse)
        assert.is_true(GU.CompareItems(
            "|Hitem:50:0|h[Sparkling Wand]|h",
            "|Hitem:51:0|h[Old Wand]|h",
            "custom",
            "HUNTER",
            "beast"))
    end)

    it("ScoreItemCustom values hunter ranged_dps heavily", function()
        local bowLink = "|Hitem:70:0|h[Bow]|h"
        local weakBowLink = "|Hitem:71:0|h[Weak Bow]|h"
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 70 then
                return "Strong Bow", bowLink, 3, 60, 60, "Weapon", "Bow", nil, "INVTYPE_RANGED"
            end
            if id == 71 then
                return "Weak Bow", weakBowLink, 2, 40, 40, "Weapon", "Bow", nil, "INVTYPE_RANGED"
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 70 then
                return { ["ITEM_MOD_AGILITY_SHORT"] = 10, ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 50 }
            end
            if id == 71 then
                return { ["ITEM_MOD_AGILITY_SHORT"] = 10, ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 40 }
            end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local strong = GU.ScoreItemCustom(bowLink, "HUNTER", "beast")
        local weak = GU.ScoreItemCustom(weakBowLink, "HUNTER", "beast")
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
        assert.is_true(strong > weak)
        assert.is_true((strong - weak) > 20)
    end)

    it("ScoreItemCustom scores priest holy healing not spell damage", function()
        local healItem = "|Hitem:80:0|h[Heal Ring]|h"
        local dmgItem = "|Hitem:81:0|h[Dmg Ring]|h"
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 80 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 10, ["ITEM_MOD_SPELL_HEALING_DONE"] = 50 }
            end
            if id == 81 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 10, ["ITEM_MOD_SPELL_DAMAGE_DONE"] = 50 }
            end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local healScore = GU.ScoreItemCustom(healItem, "PRIEST", "holy")
        local dmgScore = GU.ScoreItemCustom(dmgItem, "PRIEST", "holy")
        _G.GetItemStats = oldGetItemStats
        assert.is_true(healScore > dmgScore)
    end)

    it("ScoreItemCustom scores fire mage fire spell damage", function()
        local fireItem = "|Hitem:82:0|h[Fire Staff]|h"
        local frostItem = "|Hitem:83:0|h[Frost Staff]|h"
        local oldGetItemStats = _G.GetItemStats
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    GetRegions = function() return end,
                    NumLines = function() return 0 end,
                    GetName = function() return "AltArmyTBC_ItemStatsScanTooltip" end,
                }
            end
            if frameType == "Frame" then
                return { RegisterEvent = function() end, SetScript = function() end }
            end
            return {}
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 82 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 10 }
            end
            if id == 83 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 10 }
            end
            return {}
        end
        package.loaded["ItemStats"] = nil
        require("ItemStats")
        AltArmy.ItemStats.ClearCache()
        local IS = AltArmy.ItemStats
        local oldGetNormalized = IS.GetNormalized
        IS.GetNormalized = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 82 then return { int = 10, fire_sp = 40, sp = 10 } end
            if id == 83 then return { int = 10, frost_sp = 40, sp = 10 } end
            return oldGetNormalized(link)
        end
        local fireScore = GU.ScoreItemCustom(fireItem, "MAGE", "fire")
        local frostScore = GU.ScoreItemCustom(frostItem, "MAGE", "fire")
        IS.GetNormalized = oldGetNormalized
        _G.GetItemStats = oldGetItemStats
        assert.is_true(fireScore > frostScore)
    end)

    it("GetWeights returns weebly-derived weights for all classes", function()
        local classes = {
            "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
            "SHAMAN", "MAGE", "WARLOCK", "DRUID",
        }
        for i = 1, #classes do
            local classFile = classes[i]
            local w = GU.GetWeights(classFile, "unknown")
            assert.is_truthy(w, classFile .. " should have leveling weights")
            assert.is_true(next(w) ~= nil)
        end
        local hunter = GU.GetWeights("HUNTER", "beast")
        assert.are.equal(2.4, hunter.ranged_dps)
        assert.are.equal(1, hunter.agi)
    end)

    it("GetNormalizedItemStats delegates to ItemStats", function()
        local link = "|Hitem:11:0|h[New Helm]|h"
        local stats = GU.GetNormalizedItemStats(link)
        assert.are.equal(20, stats.int)
        assert.are.equal(10, stats.sta)
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

    it("EvaluateForAllAlts matches gear tab: only in-range clear upgrades", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 28,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.SidegradeAlt = {
            name = "SidegradeAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
                [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
                [13] = { "Newer Helm", nil, 3, 32, 32, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            }
            local info = items[id]
            if not info then return oldGetItemInfo(item) end
            local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
            return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
        end
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 20, ["ITEM_MOD_STAMINA_SHORT"] = 10 }
            end
            if id == 13 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 17, ["ITEM_MOD_STAMINA_SHORT"] = 8 }
            end
            if id == 10 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 5, ["ITEM_MOD_STAMINA_SHORT"] = 5 }
            end
            return oldGetItemStats(link)
        end
        local matches = GU.EvaluateForAllAlts("|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
            levelsAhead = 5,
        })
        assert.are.equal(2, #matches)
        local names = {}
        for i = 1, #matches do names[i] = matches[i].name end
        assert.are.equal("MageAlt", names[1])
        assert.are.equal("SidegradeAlt", names[2])
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("EvaluateForAllAlts sorts matches in gear tab focus order", function()
        _G.AltArmyTBC_Data.Characters.TestRealm = {
            MageAlt = {
                name = "MageAlt",
                realm = "TestRealm",
                classFile = "MAGE",
                level = 60,
                Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
            },
            SmallUpgrader = {
                name = "SmallUpgrader",
                realm = "TestRealm",
                classFile = "MAGE",
                level = 60,
                Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
                talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
            },
            BigUpgrader = {
                name = "BigUpgrader",
                realm = "TestRealm",
                classFile = "MAGE",
                level = 60,
                Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
            },
        }
        local matches = GU.EvaluateForAllAlts("|Hitem:11:0|h[New Helm]|h", {
            technique = "ilvl",
            levelsAhead = 0,
        })
        local names = {}
        for i = 1, #matches do names[i] = matches[i].name end
        assert.are.equal(3, #names)
        assert.are.equal("BigUpgrader", names[1])
        assert.are.equal("MageAlt", names[2])
        assert.are.equal("SmallUpgrader", names[3])
    end)

    it("EvaluateForCharacter uses opts.level override for level-up scans", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local link = "|Hitem:11:0|h[New Helm]|h"
        local opts = { technique = "ilvl", levelsAhead = 0 }
        assert.is_true(GU.EvaluateForCharacter(char, link, { technique = "ilvl", levelsAhead = 0, level = 60 }))
        assert.is_false(GU.EvaluateForCharacter(char, link, { technique = "ilvl", levelsAhead = 0, level = 28 }))
        assert.is_true(GU.EvaluateForCharacter(char, link, opts))
    end)

    it("EnsureGearUpgradeOptions applies defaults", function()
        _G.AltArmyTBC_Options = {}
        local opts = GU.EnsureGearUpgradeOptions()
        assert.is_true(opts.enabled)
        assert.are.equal("custom", opts.technique)
        assert.are.equal(5, opts.levelsAhead)
        assert.are.equal(10, opts.upgradeThresholdPercent)
    end)

    it("GetUpgradeHighlightKind uses upgradeThresholdPercent from opts", function()
        assert.are.equal("minor", GU.GetUpgradeHighlightKind(3, 15, { upgradeThresholdPercent = 50 }))
        assert.are.equal("clear", GU.GetUpgradeHighlightKind(3, 15, { upgradeThresholdPercent = 10 }))
    end)

    it("GetWeightedChangeColor uses threshold bands and smooth blends", function()
        local opts = { upgradeThresholdPercent = 10 }
        local gr, gg, gb = GU.GetWeightedChangeColor(10, opts)
        assert.are.equal(0.2, gr)
        assert.are.equal(1, gg)
        assert.are.equal(0.2, gb)
        local rr, rg, rb = GU.GetWeightedChangeColor(-10, opts)
        assert.are.equal(1, rr)
        assert.are.equal(0.4, rg)
        assert.are.equal(0.3, rb)
        local yr, yg, yb = GU.GetWeightedChangeColor(0, opts)
        assert.are.equal(1, yr)
        assert.are.equal(0.82, yg)
        assert.are.equal(0, yb)
        local midUpR, midUpG, midUpB = GU.GetWeightedChangeColor(5, opts)
        assert.is_true(math.abs(0.6 - midUpR) < 0.001)
        assert.is_true(math.abs(0.91 - midUpG) < 0.001)
        assert.is_true(math.abs(0.1 - midUpB) < 0.001)
        local midDownR, midDownG, midDownB = GU.GetWeightedChangeColor(-5, opts)
        assert.is_true(math.abs(1 - midDownR) < 0.001)
        assert.is_true(math.abs(0.61 - midDownG) < 0.001)
        assert.is_true(math.abs(0.15 - midDownB) < 0.001)
    end)

    it("ResolveUpgradeThresholdPercent clamps to 0-100", function()
        assert.are.equal(10, GU.ResolveUpgradeThresholdPercent(nil))
        assert.are.equal(0, GU.ResolveUpgradeThresholdPercent(-10))
        assert.are.equal(100, GU.ResolveUpgradeThresholdPercent(150))
    end)

    it("EnsureGearUpgradeOptions preserves enabled and levelsAhead", function()
        _G.AltArmyTBC_Options = {
            gearUpgrades = { enabled = false, technique = "ilvl", levelsAhead = 0 },
        }
        local opts = GU.EnsureGearUpgradeOptions()
        assert.is_false(opts.enabled)
        assert.are.equal("custom", opts.technique)
        assert.are.equal(0, opts.levelsAhead)
    end)

    it("GetProviders lists techniques in display order", function()
        local providers = GU.GetProviders()
        assert.are.equal("custom", providers[1].id)
        assert.are.equal("ilvl", providers[2].id)
        assert.are.equal("gearscore", providers[3].id)
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

    it("GetProviders lists all techniques", function()
        local providers = GU.GetProviders()
        local ids = {}
        for i = 1, #providers do ids[providers[i].id] = true end
        assert.is_true(ids.ilvl)
        assert.is_true(ids.custom)
        assert.is_true(ids.gearscore)
    end)

    it("GetEffectiveTechnique migrates removed pawn and sgj to custom", function()
        assert.are.equal("custom", GU.GetEffectiveTechnique("pawn"))
        assert.are.equal("custom", GU.GetEffectiveTechnique("sgj"))
    end)

    it("EnsureGearUpgradeOptions always uses custom comparison technique", function()
        _G.AltArmyTBC_Options = {
            gearUpgrades = { enabled = true, technique = "pawn", levelsAhead = 5 },
        }
        local opts = GU.EnsureGearUpgradeOptions()
        assert.are.equal("custom", opts.technique)
        _G.AltArmyTBC_Options.gearUpgrades.technique = "sgj"
        opts = GU.EnsureGearUpgradeOptions()
        assert.are.equal("custom", opts.technique)
        _G.AltArmyTBC_Options.gearUpgrades.technique = "ilvl"
        opts = GU.EnsureGearUpgradeOptions()
        assert.are.equal("custom", opts.technique)
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

    it("GetSlotCompareDelta is negative for downgrades", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local worseLink = "|Hitem:10:0|h[Old Helm]|h"
        local delta = GU.GetSlotCompareDelta(char, worseLink, 1, { technique = "ilvl" })
        assert.is_true(delta < 0)
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
    end)

    it("GetSlotCompareDelta treats zero-score item vs equipped gear as downgrade", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 99 then
                return "Useless Helm", "|Hitem:99:0|h[Useless Helm]|h", 0, 1, 1,
                    "Armor", "Cloth", nil, "INVTYPE_HEAD"
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 99 then return {} end
            return oldGetItemStats(link)
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local uselessLink = "|Hitem:99:0|h[Useless Helm]|h"
        local delta = GU.GetSlotCompareDelta(char, uselessLink, 1, { technique = "custom" })
        assert.is_true(delta < 0)
        local verdict = GU.GetFocusVerdictForSlot(entry, char, uselessLink, 1, {
            technique = "custom",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("Downgrade", verdict.label)
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("GetSlotCompareDelta uses entry classFile and enhancement weights for shamans", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 98 then
                return "Monkey Greaves", "|Hitem:98:0|h[Monkey Greaves]|h", 0, 15, 15,
                    "Armor", "Mail", nil, "INVTYPE_FEET"
            end
            if id == 97 then
                return "Veteran Boots", "|Hitem:97:0|h[Veteran Boots]|h", 3, 45, 45,
                    "Armor", "Mail", nil, "INVTYPE_FEET"
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 98 then
                return {
                    ["ITEM_MOD_AGILITY_SHORT"] = 8,
                    ["ITEM_MOD_STAMINA_SHORT"] = 8,
                }
            end
            if id == 97 then
                return {
                    ["ITEM_MOD_AGILITY_SHORT"] = 12,
                    ["ITEM_MOD_STAMINA_SHORT"] = 12,
                }
            end
            return oldGetItemStats(link)
        end
        local char = {
            classFile = "",
            Inventory = { [8] = "|Hitem:97:0|h[Veteran Boots]|h" },
        }
        local entry = {
            name = "Totem",
            realm = "TestRealm",
            classFile = "SHAMAN",
            level = 60,
        }
        local classFile, specKey = GU.ResolveCompareContext(char, entry)
        assert.are.equal("SHAMAN", classFile)
        assert.are.equal("enhancement", specKey)
        local monkeyLink = "|Hitem:98:0|h[Monkey Greaves]|h"
        local delta = GU.GetSlotCompareDelta(char, monkeyLink, 8, { technique = "custom" }, entry)
        assert.is_true(delta < 0)
        local verdict = GU.GetFocusVerdictForSlot(entry, char, monkeyLink, 8, {
            technique = "custom",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("Downgrade", verdict.label)
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("GetFocusCellBadgeKind returns unusable for equippable worse item", function()
        local oldGetItemInfo = _G.GetItemInfo
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 98 then
                return "Crappy Boots", "|Hitem:98:0|h[Crappy Boots]|h", 0, 30, 30,
                    "Armor", "Cloth", nil, "INVTYPE_FEET"
            end
            if id == 97 then
                return "Veteran Boots", "|Hitem:97:0|h[Veteran Boots]|h", 0, 30, 30,
                    "Armor", "Cloth", nil, "INVTYPE_FEET"
            end
            return oldGetItemInfo(item)
        end
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 98 or id == 97 then return {} end
            return oldGetItemStats(link)
        end
        if AltArmy.ItemStats and AltArmy.ItemStats.ClearCache then
            AltArmy.ItemStats.ClearCache()
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[8] = "|Hitem:97:0|h[Veteran Boots]|h"
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 20 }
        local crappyLink = "|Hitem:98:0|h[Crappy Boots]|h"
        local info = GU.ClassifyFocusSlot(entry, char, crappyLink, 8, {
            technique = "custom",
            levelsAhead = 5,
        }, 15)
        assert.are.equal(GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND, info.category)
        local verdict = GU.GetFocusVerdictForSlot(entry, char, crappyLink, 8, {
            technique = "custom",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("Eventual sidegrade", verdict.label)
        char.Inventory[8] = nil
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("GetFocusCellBadgeKind returns unusable for equippable worse item", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local worseLink = "|Hitem:10:0|h[Old Helm]|h"
        local kind = GU.GetFocusCellBadgeKind(entry, char, worseLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
        assert.are.equal("unusable", kind)
    end)

    it("GetFocusCellBadgeKind returns white plus when upgrade is beyond level threshold", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 28,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local char = DS:GetCharacter("LowLevel", "TestRealm")
        local entry = { name = "LowLevel", realm = "TestRealm", classFile = "MAGE", level = 28 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local kind = GU.GetFocusCellBadgeKind(entry, char, newLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("upgradeFuture", kind)
    end)

    it("GetFocusCellBadgeKind returns upgrade for equippable clear upgrades", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local kind = GU.GetFocusCellBadgeKind(entry, char, newLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("upgrade", kind)
    end)

    it("HasAnyFocusUpgradeOrEventual is true when a character has a clear upgrade", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 },
        }
        assert.is_true(GU.HasAnyFocusUpgradeOrEventual(entries, itemLink, {
            technique = "ilvl",
            levelsAhead = 5,
        }))
    end)

    it("HasAnyFocusUpgradeOrEventual is true for eventual upgrades", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 28,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "LowLevel", realm = "TestRealm", classFile = "MAGE", level = 28 },
        }
        assert.is_true(GU.HasAnyFocusUpgradeOrEventual(entries, itemLink, {
            technique = "ilvl",
            levelsAhead = 5,
        }))
    end)

    it("HasAnyFocusUpgradeOrEventual is true for in-range sidegrades", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 },
        }
        assert.is_true(GU.HasAnyFocusUpgradeOrEventual(entries, itemLink, {
            technique = "ilvl",
            levelsAhead = 5,
        }))
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
    end)

    it("HasAnyFocusUpgradeOrEventual is false when no character has a comparable focus result", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local itemLink = "|Hitem:10:0|h[Old Helm]|h"
        local entries = {
            { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 },
        }
        assert.is_false(GU.HasAnyFocusUpgradeOrEventual(entries, itemLink, {
            technique = "ilvl",
            levelsAhead = 5,
        }))
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
    end)

    it("GetFocusVerdictForSlot returns colored verdict labels", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local verdict = GU.GetFocusVerdictForSlot(entry, char, newLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        assert.are.equal("Upgrade", verdict.label)
        assert.are.equal(0.2, verdict.r)
    end)

    it("GetFocusVerdictForSlot returns Downgrade for worse items", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local worseLink = "|Hitem:10:0|h[Old Helm]|h"
        local verdict = GU.GetFocusVerdictForSlot(entry, char, worseLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15)
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
        assert.are.equal("Downgrade", verdict.label)
    end)

    it("GetFocusVerdictForSlot returns Sidegrade for minor weighted downgrades", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        char.Inventory[1] = "|Hitem:11:0|h[New Helm]|h"
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local slightlyWorseLink = "|Hitem:13:0|h[Newer Helm]|h"
        local verdict = GU.GetFocusVerdictForSlot(entry, char, slightlyWorseLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 100)
        char.Inventory[1] = "|Hitem:10:0|h[Old Helm]|h"
        assert.are.equal("Sidegrade", verdict.label)
    end)

    it("GetWeightedChangePercent matches compare panel formula", function()
        assert.are.equal(-3, GU.GetWeightedChangePercent(-3, 35, 100))
        assert.are.equal(-20, GU.GetWeightedChangePercent(-3, 35, 15))
        assert.are.equal(-100, GU.GetWeightedChangePercent(-35, 35, nil))
    end)

    it("BuildFocusSlotDebugLines reports classification and delta", function()
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local lines = GU.BuildFocusSlotDebugLines(entry, char, newLink, 1, {
            technique = "ilvl",
            levelsAhead = 5,
        }, 15, { sessionTechnique = "custom" })
        local text = table.concat(lines, "\n")
        assert.matches("Focus compare selection", text)
        assert.matches("Grid scores:", text)
        assert.matches("ClassifyFocusSlot:", text)
        assert.matches("MISMATCH", text)
        assert.matches("Verdict:", text)
    end)

    it("GetFocusCellBadgeKind returns unusable for never-equip classes", function()
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 99 then
                return "Plate Helm", "|Hitem:99:0|h[Plate Helm]|h", 3, 60, 60,
                    "Armor", "Plate", nil, "INVTYPE_HEAD"
            end
            return oldGetItemInfo(item)
        end
        local char = DS:GetCharacter("MageAlt", "TestRealm")
        local entry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local plateLink = "|Hitem:99:0|h[Plate Helm]|h"
        local info = GU.ClassifyFocusSlot(entry, char, plateLink, 1, { technique = "ilvl" }, 15)
        _G.GetItemInfo = oldGetItemInfo
        assert.are.equal("unusable", info.badge)
        assert.are.equal(GU.FOCUS_CATEGORY.NEVER, info.category)
        assert.is_true(info.dimmed)
    end)

    it("focus sort tier ranks eventual upgrades before in-range sidegrades", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 28,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.SidegradeAlt = {
            name = "SidegradeAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            local items = {
                [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
                [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
                [13] = { "Newer Helm", nil, 3, 32, 32, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            }
            local info = items[id]
            if not info then return oldGetItemInfo(item) end
            local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
            return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
        end
        local oldGetItemStats = _G.GetItemStats
        _G.GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id == 11 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 20, ["ITEM_MOD_STAMINA_SHORT"] = 10 }
            end
            if id == 13 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 17, ["ITEM_MOD_STAMINA_SHORT"] = 8 }
            end
            if id == 10 then
                return { ["ITEM_MOD_INTELLECT_SHORT"] = 5, ["ITEM_MOD_STAMINA_SHORT"] = 5 }
            end
            return oldGetItemStats(link)
        end
        local opts = { technique = "ilvl", levelsAhead = 5 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local eventualEntry = { name = "LowLevel", realm = "TestRealm", classFile = "MAGE", level = 28 }
        local sidegradeEntry = { name = "SidegradeAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local eventualTier = GU.GetFocusTier(
            eventualEntry, DS:GetCharacter("LowLevel", "TestRealm"), newLink, opts, 15)
        local sidegradeTier = GU.GetFocusTier(
            sidegradeEntry, DS:GetCharacter("SidegradeAlt", "TestRealm"), newLink, opts, 15)
        assert.is_true(sidegradeTier < eventualTier)
        assert.are.equal(GU.FOCUS_CATEGORY.UPGRADE_BEYOND,
            GU.SummarizeFocusEntry(eventualEntry, DS:GetCharacter("LowLevel", "TestRealm"), newLink, opts, 15).category)
        assert.are.equal(GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE,
            GU.SummarizeFocusEntry(sidegradeEntry, DS:GetCharacter("SidegradeAlt", "TestRealm"), newLink, opts, 15).category)
        _G.GetItemInfo = oldGetItemInfo
        _G.GetItemStats = oldGetItemStats
    end)

    it("CompareFocusEntries ranks sidegrades before eventual upgrades", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.LowLevel = {
            name = "LowLevel",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 10,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.SidegradeAlt = {
            name = "SidegradeAlt",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:11:0|h[New Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local opts = { technique = "ilvl", levelsAhead = 0 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local eventualEntry = { name = "LowLevel", realm = "TestRealm", classFile = "MAGE", level = 10 }
        local sidegradeEntry = { name = "SidegradeAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local eventualChar = DS:GetCharacter("LowLevel", "TestRealm")
        local sidegradeChar = DS:GetCharacter("SidegradeAlt", "TestRealm")
        assert.is_true(GU.CompareFocusEntries(
            sidegradeEntry, eventualEntry, sidegradeChar, eventualChar, newLink, opts, 15))
        assert.are.equal(2, GU.GetFocusCompareSortTier(sidegradeEntry, sidegradeChar, newLink, opts, 15))
        assert.are.equal(3, GU.GetFocusCompareSortTier(eventualEntry, eventualChar, newLink, opts, 15))
    end)

    it("CompareFocusEntries ranks downgrades before unusable", function()
        local oldGetItemInfo = _G.GetItemInfo
        _G.GetItemInfo = function(item)
            local id = type(item) == "number" and item
                or tonumber(tostring(item):match("item:(%d+)"))
            if id == 99 then
                return "Plate Helm", "|Hitem:99:0|h[Plate Helm]|h", 3, 50, 50,
                    "Armor", "Plate", nil, "INVTYPE_HEAD"
            end
            if id == 100 then
                return "Better Plate Helm", "|Hitem:100:0|h[Better Plate Helm]|h", 3, 60, 60,
                    "Armor", "Plate", nil, "INVTYPE_HEAD"
            end
            return oldGetItemInfo(item)
        end
        _G.AltArmyTBC_Data.Characters.TestRealm.WarriorAlt = {
            name = "WarriorAlt",
            realm = "TestRealm",
            classFile = "WARRIOR",
            level = 60,
            Inventory = { [1] = "|Hitem:100:0|h[Better Plate Helm]|h" },
            talents = { tabs = { 0, 21, 0 }, primary = 2, specKey = "fury" },
        }
        local opts = { technique = "ilvl", levelsAhead = 0 }
        local plateLink = "|Hitem:99:0|h[Plate Helm]|h"
        local downgradeEntry = { name = "WarriorAlt", realm = "TestRealm", classFile = "WARRIOR", level = 60 }
        local unusableEntry = { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local downgradeChar = DS:GetCharacter("WarriorAlt", "TestRealm")
        local unusableChar = DS:GetCharacter("MageAlt", "TestRealm")
        assert.is_true(GU.CompareFocusEntries(
            downgradeEntry, unusableEntry, downgradeChar, unusableChar, plateLink, opts, 10))
        assert.are.equal(5, GU.GetFocusCompareSortTier(
            downgradeEntry, downgradeChar, plateLink, opts, 10))
        assert.are.equal(6, GU.GetFocusCompareSortTier(
            unusableEntry, unusableChar, plateLink, opts, 10))
        _G.GetItemInfo = oldGetItemInfo
    end)

    it("CompareFocusEntries puts sub-max-level before max-level within same tier", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.SubMax = {
            name = "SubMax",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.AtMax = {
            name = "AtMax",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 70,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local opts = { technique = "ilvl", levelsAhead = 0 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local subMax = { name = "SubMax", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local maxLevel = { name = "AtMax", realm = "TestRealm", classFile = "MAGE", level = 70 }
        assert.is_true(GU.CompareFocusEntries(
            subMax, maxLevel,
            DS:GetCharacter("SubMax", "TestRealm"),
            DS:GetCharacter("AtMax", "TestRealm"),
            newLink, opts, 15))
        assert.is_true(GU.IsMaxLevelCharacter(maxLevel, DS:GetCharacter("AtMax", "TestRealm")))
        assert.is_false(GU.IsMaxLevelCharacter(subMax, DS:GetCharacter("SubMax", "TestRealm")))
    end)

    it("CompareFocusEntries sorts by upgrade percent then levels until equippable", function()
        _G.AltArmyTBC_Data.Characters.TestRealm.BigUpgrader = {
            name = "BigUpgrader",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        _G.AltArmyTBC_Data.Characters.TestRealm.SmallUpgrader = {
            name = "SmallUpgrader",
            realm = "TestRealm",
            classFile = "MAGE",
            level = 60,
            Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
            talents = { tabs = { 0, 0, 21 }, primary = 3, specKey = "frost" },
        }
        local opts = { technique = "ilvl", levelsAhead = 0 }
        local newLink = "|Hitem:11:0|h[New Helm]|h"
        local big = { name = "BigUpgrader", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local small = { name = "SmallUpgrader", realm = "TestRealm", classFile = "MAGE", level = 60 }
        assert.is_true(GU.CompareFocusEntries(
            big, small,
            DS:GetCharacter("BigUpgrader", "TestRealm"),
            DS:GetCharacter("SmallUpgrader", "TestRealm"),
            newLink, opts, 15))
        assert.is_true(GU.GetFocusUpgradePercent(
            big, DS:GetCharacter("BigUpgrader", "TestRealm"), newLink, opts, 15) >
            GU.GetFocusUpgradePercent(
                small, DS:GetCharacter("SmallUpgrader", "TestRealm"), newLink, opts, 15))
    end)

    it("SummarizeFocusCharacter uses best ring slot for sort tier", function()
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
        local entry = { name = "RingAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
        local ringLink = "|Hitem:20:0|h[New Ring]|h"
        local summary = GU.SummarizeFocusEntry(entry, char, ringLink, { technique = "ilvl" }, 20)
        _G.GetItemInfo = oldGetItemInfo
        assert.are.equal(1, summary.sortTier)
        assert.are.equal(20, summary.sortDelta)
        assert.is_false(summary.dimmed)
    end)
end)
