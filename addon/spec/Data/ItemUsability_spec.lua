--[[
  Unit tests for ItemUsability.lua.
  Run from project root: npm test
]]

describe("ItemUsability", function()
    local IU
    local CC

    local function coloredName(name, classFile)
        return CC.wrapName(name, classFile)
    end

    local function mockGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [1] = { "Cloth Hood", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [2] = { "Plate Helm", nil, 3, 35, 35, "Armor", "Plate", nil, "INVTYPE_HEAD" },
            [3] = { "Mail Vest", nil, 3, 30, 30, "Armor", "Mail", nil, "INVTYPE_CHEST" },
            [4] = { "Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [5] = { "Sword", nil, 3, 10, 10, "Weapon", "One-Handed Swords", nil, "INVTYPE_WEAPONMAINHAND" },
            [6] = { "Wand", nil, 2, 5, 5, "Weapon", "Wands", nil, "INVTYPE_RANGEDRIGHT" },
            [7] = { "Shield", nil, 2, 10, 10, "Armor", "Shields", nil, "INVTYPE_SHIELD" },
            [8] = { "Health Potion", nil, 1, 1, 1, "Consumable", nil, nil, nil },
        }
        local info = items[id]
        if not info then return end
        local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
        return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
            PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
            MAGE = { r = 0.41, g = 0.8, b = 0.94 },
        }
        _G.GetItemInfo = mockGetItemInfo
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["ClassColor"] = nil
        require("ClassColor")
        CC = AltArmy.ClassColor
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        IU = AltArmy.ItemUsability
    end)

    it("maps INVTYPE_FINGER to finger slots", function()
        local slots = IU.GetInventorySlotsForItem("|Hitem:4:0|h[Ring]|h")
        assert.are.same({ 11, 12 }, slots)
    end)

    it("maps INVTYPE_WEAPONMAINHAND to slot 16", function()
        local slots = IU.GetInventorySlotsForItem("|Hitem:5:0|h[Sword]|h")
        assert.are.same({ 16 }, slots)
    end)

    it("CanClassEverUseArmor blocks mage from leather", function()
        assert.is_false(IU.CanClassEverUseArmor("MAGE", "Leather"))
        assert.is_true(IU.CanClassEverUseArmor("MAGE", "Cloth"))
    end)

    it("CanClassEverUseArmor allows paladin plate eventually", function()
        assert.is_true(IU.CanClassEverUseArmor("PALADIN", "Plate"))
    end)

    it("CanClassEverUseWeapon blocks warrior from wands", function()
        assert.is_false(IU.CanClassEverUseWeapon("WARRIOR", "Wands"))
        assert.is_true(IU.CanClassEverUseWeapon("MAGE", "Wands"))
    end)

    it("MinLevelToTrainProficiency returns 40 for paladin plate", function()
        assert.are.equal(40, IU.MinLevelToTrainProficiency("PALADIN", "Plate", "Armor"))
    end)

    it("MinLevelToTrainProficiency returns 40 for hunter mail", function()
        assert.are.equal(40, IU.MinLevelToTrainProficiency("HUNTER", "Mail", "Armor"))
    end)

    it("MinLevelToTrainProficiency returns 1 for cloth on any class", function()
        assert.are.equal(1, IU.MinLevelToTrainProficiency("MAGE", "Cloth", "Armor"))
    end)

    it("EffectiveRequiredLevel uses max of reqLevel and train level", function()
        -- Plate helm req 35, paladin trains plate at 40
        local eff = IU.EffectiveRequiredLevel("PALADIN", "|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(40, eff)
        -- Cloth hood req 20
        local eff2 = IU.EffectiveRequiredLevel("MAGE", "|Hitem:1:0|h[Cloth Hood]|h")
        assert.are.equal(20, eff2)
    end)

    it("IsEquippableWithin allows item within levelsAhead", function()
        local ok, inLevels = IU.IsEquippableWithin(
            "MAGE", 18, "|Hitem:1:0|h[Cloth Hood]|h", 5)
        assert.is_true(ok)
        assert.are.equal(2, inLevels)
    end)

    it("IsEquippableWithin rejects class that can never use armor", function()
        local ok = IU.IsEquippableWithin(
            "MAGE", 60, "|Hitem:2:0|h[Plate Helm]|h", 0)
        assert.is_false(ok)
    end)

    it("GetItemUseInfo returns reqLevel and armor subclass", function()
        local req, armor, weapon = IU.GetItemUseInfo("|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(35, req)
        assert.are.equal("Plate", armor)
        assert.is_nil(weapon)
    end)

    it("GetProficiencySkillName maps plate armor", function()
        assert.are.equal("Plate Armor", IU.GetProficiencySkillName("Armor", "Plate"))
    end)

    it("GetProficiencySkillName maps one-handed swords", function()
        assert.are.equal("One-Handed Swords", IU.GetProficiencySkillName("Weapon", "One-Handed Swords"))
    end)

    it("ValidateItemCheckDrop accepts equippable non-soulbound items", function()
        local ok, err = IU.ValidateItemCheckDrop("|Hitem:1:0|h[Cloth Hood]|h")
        assert.is_true(ok)
        assert.is_nil(err)
    end)

    it("ValidateItemCheckDrop rejects non-equippable items", function()
        local ok, err = IU.ValidateItemCheckDrop("|Hitem:8:0|h[Health Potion]|h")
        assert.is_false(ok)
        assert.are.equal("This item cannot be equipped.", err)
    end)

    it("ValidateItemCheckDrop accepts soulbound equippable items", function()
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Soulbound" end,
        }
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local ok, err = iu.ValidateItemCheckDrop("|Hitem:1:0|h[Cloth Hood]|h")
        assert.is_true(ok)
        assert.is_nil(err)
    end)

    it("GetEquipWarnings includes soulbound message", function()
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Binds when picked up" end,
        }
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local warnings = iu.GetEquipWarnings("MAGE", 60, "Alt", "|Hitem:1:0|h[Cloth Hood]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal("This item is soulbound", warnings[1])
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
    end)

    it("RequiresTrainerProficiency is true only for plate and class mail", function()
        assert.is_true(IU.RequiresTrainerProficiency("PALADIN", "Plate", "Armor"))
        assert.is_true(IU.RequiresTrainerProficiency("HUNTER", "Mail", "Armor"))
        assert.is_false(IU.RequiresTrainerProficiency("PALADIN", "Mail", "Armor"))
        assert.is_false(IU.RequiresTrainerProficiency("MAGE", "Cloth", "Armor"))
    end)

    it("GetEquipWarnings includes level requirement for selected character", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings("PALADIN", 35, "Tome", "|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Tome", "PALADIN") .. " must reach level 40 to equip this",
            warnings[1])
    end)

    it("GetEquipWarnings includes proficiency training when skill is missing", function()
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
        _G.IsUsableItem = function() return false end
        local warnings = IU.GetEquipWarnings("PALADIN", 60, "Tome", "|Hitem:2:0|h[Plate Helm]|h", nil)
        _G.IsUsableItem = nil
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Tome", "PALADIN") .. " must train Plate Armor to equip this",
            warnings[1])
    end)

    it("GetEquipWarnings omits training when current character can use the item", function()
        _G.IsUsableItem = function() return true end
        _G.UnitName = function() return "Tome" end
        _G.UnitClass = function() return "Paladin", "PALADIN" end
        local warnings = IU.GetEquipWarnings(
            "PALADIN",
            60,
            "Tome",
            "|Hitem:2:0|h[Plate Helm]|h",
            { name = "Tome", classFile = "PALADIN" })
        _G.IsUsableItem = nil
        _G.UnitName = nil
        _G.UnitClass = nil
        assert.are.equal(0, #warnings)
    end)

    it("GetEquipWarnings omits training when alt wears that armor type", function()
        local charData = {
            name = "Tome",
            classFile = "PALADIN",
            Inventory = { [1] = "|Hitem:2:0|h[Plate Helm]|h" },
        }
        local warnings = IU.GetEquipWarnings(
            "PALADIN", 60, "Tome", "|Hitem:2:0|h[Plate Helm]|h", charData)
        assert.are.equal(0, #warnings)
    end)

    it("GetEquipWarnings never shows training for cloth armor", function()
        _G.IsUsableItem = function() return false end
        local warnings = IU.GetEquipWarnings("MAGE", 60, "Merlin", "|Hitem:1:0|h[Cloth Hood]|h", nil)
        _G.IsUsableItem = nil
        assert.are.equal(0, #warnings)
    end)

    it("GetEquipWarnings reports class proficiency the character can never learn", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings("MAGE", 60, "Merlin", "|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Merlin", "MAGE") .. " can never equip this (Plate Armor)",
            warnings[1])
    end)

    it("GetEquipWarnings omits level warnings when the character can never equip", function()
        _G.IsUsableItem = nil
        local warnings = IU.GetEquipWarnings("MAGE", 10, "Merlin", "|Hitem:2:0|h[Plate Helm]|h")
        assert.are.equal(1, #warnings)
        assert.are.equal(
            coloredName("Merlin", "MAGE") .. " can never equip this (Plate Armor)",
            warnings[1])
    end)

    it("GetEquipWarnings can return soulbound and never-equip messages together", function()
        _G.IsUsableItem = nil
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Soulbound" end,
        }
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local warnings = iu.GetEquipWarnings("MAGE", 60, "Merlin", "|Hitem:2:0|h[Plate Helm]|h")
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
        assert.are.equal(2, #warnings)
        assert.are.equal("This item is soulbound", warnings[1])
        assert.are.equal(
            coloredName("Merlin", "MAGE") .. " can never equip this (Plate Armor)",
            warnings[2])
    end)

    it("GetEquipWarnings can return multiple messages", function()
        _G.IsUsableItem = function() return false end
        _G.CreateFrame = function(frameType)
            if frameType == "GameTooltip" then
                return {
                    SetOwner = function() end,
                    ClearLines = function() end,
                    SetHyperlink = function() end,
                    NumLines = function() return 1 end,
                }
            end
            return {}
        end
        _G.UIParent = _G.UIParent or {}
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "Soulbound" end,
        }
        package.loaded["ItemUsability"] = nil
        require("ItemUsability")
        local iu = AltArmy.ItemUsability
        local warnings = iu.GetEquipWarnings("PALADIN", 35, "Tome", "|Hitem:2:0|h[Plate Helm]|h")
        _G.IsUsableItem = nil
        _G.AltArmyTBC_ItemUsabilityScanTooltipTextLeft1 = {
            GetText = function() return "" end,
        }
        assert.are.equal(2, #warnings)
        assert.are.equal("This item is soulbound", warnings[1])
        assert.are.equal(
            coloredName("Tome", "PALADIN") .. " must reach level 40 to equip this",
            warnings[2])
    end)
end)
