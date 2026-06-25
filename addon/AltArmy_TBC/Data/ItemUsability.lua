-- AltArmy TBC — Item usability: class armor/weapon rules, equip slots, effective level.
-- luacheck: globals GetItemInfo

AltArmy = AltArmy or {}
AltArmy.ItemUsability = AltArmy.ItemUsability or {}

local IU = AltArmy.ItemUsability

local ARMOR_SPEC_LEVEL = 40

-- TBC class weapon proficiencies (subclass strings normalized to lowercase).
local WEAPON_PROFICIENCIES = {
    WARRIOR = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
        ["one-handed swords"] = true, ["two-handed swords"] = true,
        ["daggers"] = true, ["fist weapons"] = true, ["polearms"] = true, ["staves"] = true,
        ["bows"] = true, ["crossbows"] = true, ["guns"] = true, ["thrown"] = true,
    },
    PALADIN = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
        ["one-handed swords"] = true, ["two-handed swords"] = true,
    },
    HUNTER = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed swords"] = true, ["two-handed swords"] = true,
        ["polearms"] = true, ["staves"] = true, ["daggers"] = true,
        ["bows"] = true, ["crossbows"] = true, ["guns"] = true,
    },
    ROGUE = {
        ["daggers"] = true, ["fist weapons"] = true,
        ["one-handed swords"] = true, ["one-handed maces"] = true,
        ["bows"] = true, ["crossbows"] = true, ["guns"] = true, ["thrown"] = true,
    },
    DRUID = {
        ["daggers"] = true, ["fist weapons"] = true, ["staves"] = true, ["one-handed maces"] = true,
    },
    SHAMAN = {
        ["one-handed axes"] = true, ["two-handed axes"] = true,
        ["one-handed maces"] = true, ["two-handed maces"] = true,
        ["daggers"] = true, ["fist weapons"] = true, ["staves"] = true,
    },
    MAGE = {
        ["daggers"] = true, ["one-handed swords"] = true, ["staves"] = true, ["wands"] = true,
    },
    PRIEST = {
        ["daggers"] = true, ["one-handed maces"] = true, ["staves"] = true, ["wands"] = true,
    },
    WARLOCK = {
        ["daggers"] = true, ["one-handed swords"] = true, ["staves"] = true, ["wands"] = true,
    },
}

-- WoW equip location -> inventory slot IDs (1-19).
local INVTYPE_TO_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_RELIC = { 18 },
    INVTYPE_TABARD = { 19 },
}

-- Weapon types that show both main-hand and off-hand grid rows in focus mode.
local WEAPON_PAIR_DISPLAY_TYPES = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONOFFHAND = true,
}

local MAIN_AND_OFF_HAND_SLOTS = { 16, 17 }

local function normalizeClassFile(classFile)
    return (classFile or ""):upper()
end

--- Parse GetItemInfo: returns itemLevel (iLvl), minLevel (required to equip).
local function getItemInfoLevels(link)
    if not link or not GetItemInfo then return nil, nil end
    local name, _, _, itemLevel, minLevel = GetItemInfo(link)
    if not name then return nil, nil end
    return tonumber(itemLevel) or 0, tonumber(minLevel) or 0
end

--- Required character level to equip (item min level, not iLvl).
function IU.GetItemMinLevel(link)
    local _, minLevel = getItemInfoLevels(link)
    return minLevel
end

--- True if this class can ever wear this armor subclass.
function IU.CanClassEverUseArmor(classFile, subclass)
    if not subclass or subclass == "" then return true end
    classFile = normalizeClassFile(classFile)
    subclass = subclass:lower()
    if subclass == "cloth" then return true end
    if subclass == "leather" then
        return classFile ~= "MAGE" and classFile ~= "PRIEST" and classFile ~= "WARLOCK"
    end
    if subclass == "mail" then
        return classFile == "HUNTER" or classFile == "SHAMAN"
            or classFile == "WARRIOR" or classFile == "PALADIN"
    end
    if subclass == "plate" then
        return classFile == "WARRIOR" or classFile == "PALADIN"
    end
    return true
end

--- True if this class can ever use this weapon subclass.
function IU.CanClassEverUseWeapon(classFile, weaponSubclass)
    if not weaponSubclass or weaponSubclass == "" then return true end
    local key = weaponSubclass:lower()
    if key == "fishing pole" then return true end
    classFile = normalizeClassFile(classFile)
    local prof = WEAPON_PROFICIENCIES[classFile]
    if not prof then return true end
    return prof[key] == true
end

--- Parse item link for reqLevel, armor subclass, weapon subclass.
function IU.GetItemUseInfo(link)
    if not link or not GetItemInfo then return nil, nil, nil end
    local name, _, _, _, minLevel, itemClass, subclass = GetItemInfo(link)
    if not name then return nil, nil, nil end
    local reqLevel = tonumber(minLevel) or 0
    local ic = itemClass and itemClass:lower() or ""
    if ic == "armor" or ic == "armour" then
        if subclass == "Shields" then
            return reqLevel, nil, subclass
        end
        return reqLevel, subclass, nil
    end
    if ic == "weapon" then
        return reqLevel, nil, subclass
    end
    return reqLevel, subclass, nil
end

--- Inventory slot IDs for an item link, or empty table.
function IU.GetInventorySlotsForItem(link)
    if not link or not GetItemInfo then return {} end
    local name = GetItemInfo(link)
    if not name then return {} end
    local equipLoc = select(9, GetItemInfo(link))
    if not equipLoc then return {} end
    local slots = INVTYPE_TO_SLOTS[equipLoc]
    if not slots then return {} end
    local out = {}
    for i = 1, #slots do
        out[i] = slots[i]
    end
    return out
end

--- Inventory slots to show in the gear grid when an item is focused (may be wider than equip slots).
function IU.GetFocusDisplaySlotsForItem(link)
    local slots = IU.GetInventorySlotsForItem(link)
    if not slots or #slots == 0 then return {} end
    if not link or not GetItemInfo then return slots end
    local equipLoc = select(9, GetItemInfo(link))
    if WEAPON_PAIR_DISPLAY_TYPES[equipLoc] then
        return { MAIN_AND_OFF_HAND_SLOTS[1], MAIN_AND_OFF_HAND_SLOTS[2] }
    end
    return slots
end

--- Level at which the class can train this armor/weapon proficiency.
function IU.MinLevelToTrainProficiency(classFile, subclass, itemClass)
    if not subclass or subclass == "" then return 1 end
    classFile = normalizeClassFile(classFile)
    local ic = (itemClass or ""):lower()
    if ic == "armor" or ic == "armour" then
        local sub = subclass:lower()
        if sub == "plate" then
            if classFile == "WARRIOR" or classFile == "PALADIN" then
                return ARMOR_SPEC_LEVEL
            end
            return 999
        end
        if sub == "mail" then
            if classFile == "HUNTER" or classFile == "SHAMAN" then
                return ARMOR_SPEC_LEVEL
            end
            if classFile == "WARRIOR" or classFile == "PALADIN" then
                return 1
            end
            return 999
        end
        return 1
    end
    if ic == "weapon" then
        if IU.CanClassEverUseWeapon(classFile, subclass) then
            return 1
        end
        return 999
    end
    return 1
end

--- max(item reqLevel, proficiency train level).
function IU.EffectiveRequiredLevel(classFile, link)
    if not link or not GetItemInfo then return 999 end
    local name, _, _, _, minLevel, itemClass, subclass = GetItemInfo(link)
    if not name then return 999 end
    local reqLevel = tonumber(minLevel) or 0
    classFile = normalizeClassFile(classFile)
    local ic = itemClass and itemClass:lower() or ""
    if ic == "armor" or ic == "armour" then
        if subclass == "Shields" then
            if not IU.CanClassEverUseWeapon(classFile, "Shields") then
                return 999
            end
            return reqLevel
        end
        if not IU.CanClassEverUseArmor(classFile, subclass) then
            return 999
        end
        local train = IU.MinLevelToTrainProficiency(classFile, subclass, itemClass)
        return math.max(reqLevel, train)
    end
    if ic == "weapon" then
        if not IU.CanClassEverUseWeapon(classFile, subclass) then
            return 999
        end
        return reqLevel
    end
    return reqLevel
end

--- Whether character can equip within levelsAhead levels.
--- Returns equippable (bool), levelsUntil (number or 0), reason (string or nil).
function IU.IsEquippableWithin(classFile, level, link, levelsAhead)
    levelsAhead = tonumber(levelsAhead) or 0
    level = math.floor(tonumber(level) or 0)
    if not link then return false, 0, "no_item" end

    local reqLevel, armorSubclass, weaponSubclass = IU.GetItemUseInfo(link)
    if reqLevel == nil then return false, 0, "unknown_item" end

    classFile = normalizeClassFile(classFile)
    if armorSubclass and armorSubclass ~= "" and armorSubclass ~= "Shields" then
        if not IU.CanClassEverUseArmor(classFile, armorSubclass) then
            return false, 0, "armor"
        end
    end
    if weaponSubclass and weaponSubclass ~= "" then
        if not IU.CanClassEverUseWeapon(classFile, weaponSubclass) then
            return false, 0, "weapon"
        end
    end

    local effective = IU.EffectiveRequiredLevel(classFile, link)
    if effective >= 999 then
        return false, 0, "never"
    end

    if level + levelsAhead < effective then
        return false, effective - level, "level"
    end

    local equippableNow = level >= effective
    local levelsUntil = equippableNow and 0 or (effective - level)
    return true, levelsUntil, nil
end

--- Human-readable skill name for trainer message.
function IU.GetProficiencySkillName(itemClass, subclass)
    if not subclass or subclass == "" then return "the required skill" end
    local ic = (itemClass or ""):lower()
    if ic == "armor" or ic == "armour" then
        local sub = subclass:lower()
        if sub == "plate" then return "Plate Armor" end
        if sub == "mail" then return "Mail Armor" end
        if sub == "leather" then return "Leather Armor" end
        if sub == "cloth" then return "Cloth Armor" end
        if sub == "shields" then return "Shields" end
    end
    return subclass
end

--- True when this armor type must be learned from a trainer (plate/mail at 40).
function IU.RequiresTrainerProficiency(classFile, subclass, itemClass)
    if not subclass or subclass == "" then return false end
    return IU.MinLevelToTrainProficiency(classFile, subclass, itemClass) == ARMOR_SPEC_LEVEL
end

--- True if character has any equipped item of this armor subclass.
function IU.CharHasEquippedArmorSubclass(charData, subclass)
    if not charData or not charData.Inventory or not subclass or not GetItemInfo then
        return false
    end
    local target = subclass:lower()
    for _, item in pairs(charData.Inventory) do
        if type(item) == "string" then
            local name, _, _, _, _, itemClass, itemSubclass = GetItemInfo(item)
            if name then
                local ic = itemClass and itemClass:lower() or ""
                if (ic == "armor" or ic == "armour")
                    and itemSubclass
                    and itemSubclass:lower() == target then
                    return true
                end
            end
        end
    end
    return false
end

local function isCurrentCharacter(classFile, charData)
    if not charData or not UnitClass or not UnitName then return false end
    local playerName = UnitName("player")
    if not playerName or playerName ~= charData.name then return false end
    local _, currentClass = UnitClass("player")
    return normalizeClassFile(classFile) == normalizeClassFile(currentClass)
end

--- True when character already knows an armor proficiency that requires training.
function IU.HasLearnedArmorProficiency(classFile, subclass, itemClass, charData, link)
    if not IU.RequiresTrainerProficiency(classFile, subclass, itemClass) then
        return true
    end
    if IU.CharHasEquippedArmorSubclass(charData, subclass) then
        return true
    end
    if isCurrentCharacter(classFile, charData) and link and _G.IsUsableItem then
        return _G.IsUsableItem(link) == true
    end
    return false
end

--- True when character is high enough to train but has not learned armor proficiency.
function IU.NeedsProficiencyTraining(classFile, charLevel, link, charData)
    if not link or not GetItemInfo then return false end
    local name, _, _, _, minLevel, itemClass, subclass = GetItemInfo(link)
    if not name then return false end
    local reqLevel = tonumber(minLevel) or 0
    classFile = normalizeClassFile(classFile)
    charLevel = math.floor(tonumber(charLevel) or 0)
    local ic = itemClass and itemClass:lower() or ""
    if ic ~= "armor" and ic ~= "armour" then return false end
    if not subclass or subclass == "" or subclass == "Shields" then return false end
    if not IU.CanClassEverUseArmor(classFile, subclass) then return false end
    if not IU.RequiresTrainerProficiency(classFile, subclass, itemClass) then return false end

    local trainLevel = IU.MinLevelToTrainProficiency(classFile, subclass, itemClass)
    if charLevel < trainLevel or charLevel < reqLevel then return false end

    return not IU.HasLearnedArmorProficiency(classFile, subclass, itemClass, charData, link)
end

local function formatWarningCharName(name, classFile)
    local CC = AltArmy.ClassColor
    if CC and CC.wrapName then
        return CC.wrapName(name, classFile)
    end
    return name or "?"
end

local function formatLevelsToGainPhrase(count)
    count = math.floor(tonumber(count) or 0)
    if count == 1 then return "1 level" end
    return tostring(count) .. " levels"
end

local function formatLevelRequirementWarning(coloredName, charLevel, effective)
    local levelsToGain = effective - charLevel
    return coloredName .. " must gain " .. formatLevelsToGainPhrase(levelsToGain)
        .. " to equip this"
end

--- Skill name for items the class can never equip (armor/weapon proficiency).
function IU.GetNeverEquipSkillName(classFile, link)
    if not link or not GetItemInfo then return "the required skill" end
    local _, armorSubclass, weaponSubclass = IU.GetItemUseInfo(link)
    local _, _, _, _, _, itemClass, subclass = GetItemInfo(link)
    classFile = normalizeClassFile(classFile)
    if armorSubclass and armorSubclass ~= "" and armorSubclass ~= "Shields" then
        if not IU.CanClassEverUseArmor(classFile, armorSubclass) then
            return IU.GetProficiencySkillName(itemClass or "Armor", armorSubclass)
        end
    end
    if weaponSubclass and weaponSubclass ~= "" then
        if not IU.CanClassEverUseWeapon(classFile, weaponSubclass) then
            return IU.GetProficiencySkillName(itemClass or "Weapon", weaponSubclass)
        end
    end
    return IU.GetProficiencySkillName(itemClass, subclass)
end

IU.EQUIP_WARNING_KIND = {
    SOULBOUND = "soulbound",
    NEVER = "never",
    LEVEL = "level",
    TRAINING = "training",
}

local function addEquipWarning(warnings, text, kind)
    warnings[#warnings + 1] = { text = text, kind = kind }
end

function IU.GetEquipWarningText(warning)
    if type(warning) == "table" then return warning.text end
    return warning
end

function IU.GetEquipWarningKind(warning)
    if type(warning) == "table" then return warning.kind end
    return nil
end

--- Warning lines for compare panel (soulbound, level, proficiency).
function IU.GetEquipWarnings(classFile, charLevel, charName, link, charData)
    local warnings = {}
    if not link then return warnings end
    charName = charName or "?"
    charLevel = math.floor(tonumber(charLevel) or 0)
    classFile = normalizeClassFile(classFile)

    if IU.IsBindOnPickup(link) then
        addEquipWarning(warnings, "This item is soulbound", IU.EQUIP_WARNING_KIND.SOULBOUND)
    end

    if IU.CanNeverUseItem(classFile, link) then
        local skill = IU.GetNeverEquipSkillName(classFile, link)
        local coloredName = formatWarningCharName(charName, classFile)
        addEquipWarning(
            warnings,
            coloredName .. " can never equip this (" .. skill .. ")",
            IU.EQUIP_WARNING_KIND.NEVER)
        return warnings
    end

    local effective = IU.EffectiveRequiredLevel(classFile, link)
    if effective < 999 and charLevel < effective then
        local coloredName = formatWarningCharName(charName, classFile)
        addEquipWarning(
            warnings,
            formatLevelRequirementWarning(coloredName, charLevel, effective),
            IU.EQUIP_WARNING_KIND.LEVEL)
    end

    if IU.NeedsProficiencyTraining(classFile, charLevel, link, charData) then
        local _, _, _, _, _, itemClass, subclass = GetItemInfo(link)
        local skill = IU.GetProficiencySkillName(itemClass, subclass)
        local coloredName = formatWarningCharName(charName, classFile)
        addEquipWarning(
            warnings,
            coloredName .. " must train " .. skill .. " to equip this",
            IU.EQUIP_WARNING_KIND.TRAINING)
    end

    return warnings
end

--- Whether class can never equip the item (for graying columns).
function IU.CanNeverUseItem(classFile, link)
    if not link then return false end
    local _, armorSubclass, weaponSubclass = IU.GetItemUseInfo(link)
    classFile = normalizeClassFile(classFile)
    if armorSubclass and armorSubclass ~= "" and armorSubclass ~= "Shields" then
        if not IU.CanClassEverUseArmor(classFile, armorSubclass) then
            return true
        end
    end
    if weaponSubclass and weaponSubclass ~= "" then
        if not IU.CanClassEverUseWeapon(classFile, weaponSubclass) then
            return true
        end
    end
    local eff = IU.EffectiveRequiredLevel(classFile, link)
    if eff >= 999 then return true end
    return false
end

local scanTooltip

local function getScanTooltip()
    if scanTooltip then return scanTooltip end
    if not CreateFrame then return nil end
    scanTooltip = CreateFrame("GameTooltip", "AltArmyTBC_ItemUsabilityScanTooltip", UIParent, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTooltip
end

--- True when tooltip shows bind-on-pickup or quest item (not valid for item check / loot alerts).
function IU.IsBindOnPickup(link)
    if not link then return false end
    local tip = getScanTooltip()
    if not tip or not tip.SetHyperlink then return false end
    tip:ClearLines()
    tip:SetHyperlink(link)
    for i = 1, tip:NumLines() do
        local line = _G["AltArmyTBC_ItemUsabilityScanTooltipTextLeft" .. i]
        if line and line.GetText then
            local text = line:GetText() or ""
            if text:find("Binds when picked up") or text:find("Quest Item") or text:find("Soulbound") then
                return true
            end
        end
    end
    return false
end

--- Whether an item may be dropped on Item Check; returns ok, errorMessage.
function IU.ValidateItemCheckDrop(link)
    if not link or link == "" then
        return false, "Drop an item to check."
    end
    if not GetItemInfo then
        return false, "Unknown item."
    end
    local name = GetItemInfo(link)
    if not name then
        return false, "Unknown item."
    end
    local slots = IU.GetInventorySlotsForItem(link)
    if not slots or #slots == 0 then
        return false, "This item cannot be equipped."
    end
    return true, nil
end
