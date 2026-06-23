-- AltArmy TBC — Gear upgrade comparison engine.
-- Requires DataStore, ItemUsability, DataStoreTalents, GearScore (optional).
-- luacheck: globals GetItemInfo GetItemStats PawnGetItemValue PawnGetScaleName

AltArmy = AltArmy or {}
AltArmy.GearUpgrade = AltArmy.GearUpgrade or {}

local GU = AltArmy.GearUpgrade
local DT = AltArmy.DataStoreTalents

local function IU()
    return AltArmy.ItemUsability
end

local STAT_ALIASES = {
    ["ITEM_MOD_STRENGTH_SHORT"] = "str",
    ["ITEM_MOD_AGILITY_SHORT"] = "agi",
    ["ITEM_MOD_STAMINA_SHORT"] = "sta",
    ["ITEM_MOD_INTELLECT_SHORT"] = "int",
    ["ITEM_MOD_SPIRIT_SHORT"] = "spi",
    ["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] = "sp",
    ["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = "heal",
    ["ITEM_MOD_HIT_RATING_SHORT"] = "hit",
    ["ITEM_MOD_CRIT_RATING_SHORT"] = "crit",
    ["ITEM_MOD_ATTACK_POWER_SHORT"] = "ap",
    ["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = "rap",
    ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = "def",
    ["ITEM_MOD_DODGE_RATING_SHORT"] = "dodge",
    ["ITEM_MOD_PARRY_RATING_SHORT"] = "parry",
    ["ITEM_MOD_BLOCK_RATING_SHORT"] = "block",
    ["ITEM_MOD_BLOCK_VALUE_SHORT"] = "blockval",
    ["ITEM_MOD_MANA_REGENERATION_SHORT"] = "mp5",
}

-- Simplified TBC stat weights per class/spec (custom Pawn-style).
local WEIGHTS = {
    MAGE = {
        frost = { int = 1.0, spi = 0.5, sta = 0.3, sp = 0.8, crit = 0.6, hit = 0.7 },
        fire = { int = 1.0, spi = 0.4, sta = 0.3, sp = 0.9, crit = 0.7, hit = 0.7 },
        arcane = { int = 1.0, spi = 0.5, sta = 0.3, sp = 0.85, crit = 0.65, hit = 0.7 },
    },
    PRIEST = {
        shadow = { int = 1.0, spi = 0.6, sta = 0.4, sp = 0.9, crit = 0.5, hit = 0.7 },
        holy = { int = 0.8, spi = 1.0, sta = 0.5, heal = 1.0, mp5 = 0.8 },
        discipline = { int = 0.7, spi = 1.0, sta = 0.6, heal = 0.9, mp5 = 0.7 },
    },
    WARLOCK = {
        affliction = { int = 1.0, spi = 0.7, sta = 0.5, sp = 0.9, hit = 0.75, crit = 0.5 },
        demonology = { int = 1.0, spi = 0.6, sta = 0.6, sp = 0.85, hit = 0.7 },
        destruction = { int = 1.0, spi = 0.5, sta = 0.4, sp = 1.0, crit = 0.7, hit = 0.75 },
    },
    WARRIOR = {
        fury = { str = 1.0, agi = 0.3, sta = 0.5, ap = 0.9, crit = 0.6, hit = 0.7 },
        arms = { str = 1.0, agi = 0.2, sta = 0.5, ap = 0.85, crit = 0.65, hit = 0.75 },
        protection = { sta = 1.0, str = 0.5, agi = 0.2, def = 0.9, dodge = 0.7, parry = 0.7, block = 0.6 },
    },
    PALADIN = {
        retribution = { str = 1.0, sta = 0.5, sp = 0.4, crit = 0.6, hit = 0.7 },
        holy = { int = 0.8, spi = 1.0, sta = 0.5, heal = 1.0, mp5 = 0.8 },
        protection = { sta = 1.0, str = 0.4, def = 0.9, dodge = 0.7, block = 0.7 },
    },
    HUNTER = {
        beast = { agi = 1.0, sta = 0.5, ap = 0.8, rap = 0.9, crit = 0.7, hit = 0.75 },
        marksmanship = { agi = 1.0, sta = 0.5, rap = 1.0, crit = 0.75, hit = 0.8 },
        survival = { agi = 1.0, sta = 0.6, ap = 0.7, crit = 0.65, hit = 0.75 },
    },
    ROGUE = {
        combat = { agi = 1.0, str = 0.3, sta = 0.4, ap = 0.9, crit = 0.8, hit = 0.75 },
        assassination = { agi = 1.0, str = 0.2, sta = 0.4, ap = 0.85, crit = 0.75, hit = 0.75 },
        subtlety = { agi = 1.0, str = 0.25, sta = 0.4, ap = 0.8, crit = 0.7, hit = 0.7 },
    },
    SHAMAN = {
        elemental = { int = 1.0, spi = 0.5, sta = 0.4, sp = 0.9, hit = 0.75, crit = 0.6 },
        enhancement = { str = 0.8, agi = 0.6, sta = 0.5, ap = 0.9, crit = 0.7, hit = 0.75 },
        restoration = { int = 0.8, spi = 1.0, sta = 0.5, heal = 1.0, mp5 = 0.8 },
    },
    DRUID = {
        feral = { agi = 1.0, str = 0.6, sta = 0.5, ap = 0.85, crit = 0.7, hit = 0.7 },
        balance = { int = 1.0, spi = 0.5, sta = 0.4, sp = 0.9, hit = 0.75, crit = 0.6 },
        restoration = { int = 0.8, spi = 1.0, sta = 0.5, heal = 1.0, mp5 = 0.8 },
    },
}

local PROVIDERS = {
    {
        id = "custom",
        label = "Alt Army",
        isAddon = false,
        installInfo = nil,
        warningSpecAgnostic = false,
        IsAvailable = function() return true end,
    },
    {
        id = "pawn",
        label = "Pawn",
        isAddon = true,
        installInfo = {
            name = "Pawn",
            url = "https://www.curseforge.com/wow/addons/pawn",
            text = "Install Pawn from CurseForge to compare gear using its stat-weight scales.",
        },
        warningSpecAgnostic = false,
        IsAvailable = function()
            return type(_G.PawnGetItemValue) == "function"
        end,
    },
    {
        id = "sgj",
        label = "Sharpie's Gear Judge",
        isAddon = true,
        installInfo = {
            name = "Sharpie's Gear Judge",
            url = "https://www.curseforge.com/wow/addons/sharpies-gear-judge",
            text = "Install Sharpie's Gear Judge from CurseForge to compare gear using its scoring engine.",
        },
        warningSpecAgnostic = false,
        IsAvailable = function()
            return type(_G.SGJ_GetItemScore) == "function"
                or (type(_G.SGJ) == "table" and type(_G.SGJ.GetItemScore) == "function")
        end,
    },
    {
        id = "ilvl",
        label = "Item Level",
        notRecommended = true,
        isAddon = false,
        installInfo = nil,
        warningSpecAgnostic = true,
        IsAvailable = function() return true end,
    },
    {
        id = "gearscore",
        label = "Gear Score",
        notRecommended = true,
        isAddon = true,
        installInfo = {
            name = "GearScoreTBCClassic or TacoTip",
            url = "https://www.curseforge.com/wow/addons/gearscoretbcclassic",
            text = "Install GearScoreTBCClassic or TacoTip from CurseForge for gear score integration.",
        },
        warningSpecAgnostic = true,
        IsAvailable = function()
            local GS = AltArmy.GearScore
            if GS and GS.GetAvailableProviders then
                local list = GS.GetAvailableProviders()
                for i = 1, #list do
                    if list[i].id ~= "level" and list[i].id ~= "ilvl" and list[i].id ~= "played" then
                        return true
                    end
                end
            end
            return type(_G.TT_GS) == "table" and type(_G.TT_GS.GetItemScore) == "function"
        end,
    },
}

local providerById = {}
for i = 1, #PROVIDERS do
    providerById[PROVIDERS[i].id] = PROVIDERS[i]
end

function GU.GetProviders()
    local out = {}
    for i = 1, #PROVIDERS do
        out[i] = PROVIDERS[i]
    end
    return out
end

function GU.GetProvider(id)
    return providerById[id]
end

--- Rich-text dropdown label; suffixes use warning gray / not-recommended colors.
function GU.GetProviderDisplayLabel(provider)
    if not provider then return "" end
    local label = provider.label
    if provider.notRecommended then
        label = label .. " |cffFF664C(not recommended)|r"
    end
    if provider.isAddon and provider.IsAvailable and not provider.IsAvailable() then
        label = label .. " |cffaaaaaa(not installed)|r"
    end
    return label
end

function GU.GetEffectiveTechnique(requested)
    local p = providerById[requested]
    if p and p.IsAvailable() then
        return requested
    end
    if requested == "custom" or requested == "ilvl" then
        return requested
    end
    return "custom"
end

local function resolveItemLink(item)
    if type(item) == "string" and item:find("item:") then
        return item
    end
    if type(item) == "number" and GetItemInfo then
        local _, link = GetItemInfo(item)
        return link
    end
    return nil
end

local function getItemLevel(link)
    if not link or not GetItemInfo then return 0 end
    local _, _, _, iLevel = GetItemInfo(link)
    return tonumber(iLevel) or 0
end

local function getSpecKey(char)
    if DT and DT.ResolveSpecKey then
        return DT.ResolveSpecKey(char)
    end
    return "unknown", false
end

function GU.GetSpecKey(char)
    return getSpecKey(char)
end

local function getWeights(classFile, specKey)
    classFile = (classFile or ""):upper()
    local byClass = WEIGHTS[classFile]
    if not byClass then return nil end
    if byClass[specKey] then return byClass[specKey] end
    if DT and DT.GetLevelingSpecKey then
        return byClass[DT.GetLevelingSpecKey(classFile)]
    end
    return nil
end

function GU.GetWeights(classFile, specKey)
    return getWeights(classFile, specKey)
end

function GU.ScoreItemCustom(link, classFile, specKey)
    if not link or not GetItemStats then return 0 end
    local stats = GetItemStats(link)
    if not stats then return 0 end
    local weights = getWeights(classFile, specKey)
    if not weights then return 0 end
    local total = 0
    for statKey, value in pairs(stats) do
        local short = STAT_ALIASES[statKey] or statKey
        local w = weights[short]
        if w then
            total = total + (tonumber(value) or 0) * w
        end
    end
    return total
end

local function scoreItemPawn(link)
    if type(_G.PawnGetItemValue) ~= "function" then return nil end
    return tonumber(_G.PawnGetItemValue(link))
end

local function scoreItemSgj(link)
    if type(_G.SGJ_GetItemScore) == "function" then
        return tonumber(_G.SGJ_GetItemScore(link))
    end
    local sgj = _G.SGJ
    if type(sgj) == "table" and type(sgj.GetItemScore) == "function" then
        return tonumber(sgj.GetItemScore(link))
    end
    return nil
end

local function scoreItemGearScore(link)
    local TT = _G.TT_GS
    if TT and type(TT.GetItemScore) == "function" then
        return tonumber(TT.GetItemScore(link))
    end
    return nil
end

local function scoreItem(link, technique, classFile, specKey)
    if not link then return 0 end
    if technique == "ilvl" then
        return getItemLevel(link)
    end
    if technique == "custom" then
        return GU.ScoreItemCustom(link, classFile, specKey)
    end
    if technique == "pawn" then
        return scoreItemPawn(link) or GU.ScoreItemCustom(link, classFile, specKey)
    end
    if technique == "sgj" then
        return scoreItemSgj(link) or GU.ScoreItemCustom(link, classFile, specKey)
    end
    if technique == "gearscore" then
        return scoreItemGearScore(link) or getItemLevel(link)
    end
    return GU.ScoreItemCustom(link, classFile, specKey)
end

function GU.ResolveItemLink(item)
    return resolveItemLink(item)
end

function GU.ScoreItem(link, technique, classFile, specKey)
    return scoreItem(link, technique, classFile, specKey)
end

function GU.CompareItems(newLink, oldLink, technique, classFile, specKey)
    local newScore = scoreItem(newLink, technique, classFile, specKey)
    local oldScore = oldLink and scoreItem(oldLink, technique, classFile, specKey) or 0
    if not oldLink then
        return newScore > 0
    end
    return newScore > oldScore
end

local function upgradeDeltaInSlots(char, newLink, technique, classFile, specKey, slots)
    local DS = AltArmy.DataStore
    if not DS or not DS.GetInventoryItem then return 0 end
    local newScore = scoreItem(newLink, technique, classFile, specKey)
    if newScore <= 0 then return 0 end

    local bestDelta = 0
    local hasEquipped = false
    for i = 1, #slots do
        local slot = slots[i]
        local equipped = DS:GetInventoryItem(char, slot)
        local eqLink = resolveItemLink(equipped)
        if eqLink then
            hasEquipped = true
            local oldScore = scoreItem(eqLink, technique, classFile, specKey)
            local delta = newScore - oldScore
            if delta > bestDelta then
                bestDelta = delta
            end
        end
    end
    if not hasEquipped then
        return newScore
    end
    return bestDelta
end

local function bestUpgradeInSlots(char, newLink, technique, classFile, specKey, slots)
    return upgradeDeltaInSlots(char, newLink, technique, classFile, specKey, slots) > 0
end

local function charMatchesRealm(_char, realm, _name, realmFilter, currentRealm)
    if realmFilter == "currentRealm" and currentRealm and realm ~= currentRealm then
        return false
    end
    return true
end

local DEFAULT_LEVELS_AHEAD = 5

local function resolveLevelsAhead(value)
    local n = tonumber(value)
    if n == nil then return DEFAULT_LEVELS_AHEAD end
    return math.max(0, math.floor(n))
end

function GU.EvaluateForAllAlts(itemLink, opts)
    opts = opts or {}
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter or not itemLink then return {} end
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local levelsAhead = resolveLevelsAhead(opts.levelsAhead)
    local slots = IU() and IU().GetInventorySlotsForItem(itemLink) or {}
    if #slots == 0 then return {} end

    local realmFilter = "all"
    local GRF = AltArmy.GlobalRealmFilter
  if GRF and GRF.Get then realmFilter = GRF.Get() end
    local currentRealm = DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or ""

    local matches = {}
    DS:ForEachCharacter(function(realm, charName, charData)
        if not charMatchesRealm(charData, realm, charName, realmFilter, currentRealm) then
            return
        end
        local classFile = charData.classFile or ""
        local level = (DS.GetCharacterLevel and DS:GetCharacterLevel(charData))
            or tonumber(charData.level) or 0
        local equippable = IU() and IU().IsEquippableWithin(classFile, level, itemLink, levelsAhead)
        if not equippable then return end
        local equippableNow = level >= (IU().EffectiveRequiredLevel(classFile, itemLink) or 999)
        local specKey = getSpecKey(charData)
        local isUpgrade = bestUpgradeInSlots(charData, itemLink, technique, classFile, specKey, slots)
        if isUpgrade then
            matches[#matches + 1] = {
                name = charData.name or charName,
                realm = realm,
                classFile = classFile,
                isUpgrade = true,
                equippableNow = equippableNow,
            }
        end
    end)
    return matches
end

--- Evaluate upgrade for a single character (level-up scan, focus mode).
function GU.EvaluateForCharacter(char, itemLink, opts)
    opts = opts or {}
    if not char or not itemLink then return false end
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local classFile = char.classFile or ""
    local specKey = getSpecKey(char)
    local slots = IU() and IU().GetInventorySlotsForItem(itemLink) or {}
    if #slots == 0 then return false end
    return bestUpgradeInSlots(char, itemLink, technique, classFile, specKey, slots)
end

--- Raw upgrade magnitude for one character (technique-specific score delta).
function GU.GetCharacterUpgradeDelta(char, itemLink, opts)
    opts = opts or {}
    if not char or not itemLink then return 0 end
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local classFile = char.classFile or ""
    local specKey = getSpecKey(char)
    local slots = IU() and IU().GetInventorySlotsForItem(itemLink) or {}
    if #slots == 0 then return 0 end
    return upgradeDeltaInSlots(char, itemLink, technique, classFile, specKey, slots)
end

--- Upgrade magnitude for focus-mode sort and highlight (0 when not an upgrade).
function GU.GetFocusUpgradeDelta(entry, charData, itemLink, opts)
    if GU.GetFocusTier(entry, charData, itemLink, opts) ~= 1 then return 0 end
    return GU.GetCharacterUpgradeDelta(charData, itemLink, opts)
end

--- Tier for focus-mode column sort: 1=upgrade, 2=usable, 3=cannot use.
function GU.GetFocusTier(entry, charData, itemLink, opts)
    if not entry or not itemLink then return 3 end
    local classFile = entry.classFile or (charData and charData.classFile) or ""
    if IU() and IU().CanNeverUseItem(classFile, itemLink) then
        return 3
    end
    local level = entry.level or (charData and charData.level) or 0
    local levelsAhead = resolveLevelsAhead(opts and opts.levelsAhead)
    local ok = IU() and IU().IsEquippableWithin(classFile, level, itemLink, levelsAhead)
    if not ok then return 3 end
    if charData and GU.EvaluateForCharacter(charData, itemLink, opts) then
        return 1
    end
    return 2
end

function GU.EnsureGearUpgradeOptions()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    local root = _G.AltArmyTBC_Options
    root.gearUpgrades = root.gearUpgrades or {}
    local gu = root.gearUpgrades
    if gu.enabled == nil then gu.enabled = true end
    if gu.technique == nil then gu.technique = "custom" end
    gu.levelsAhead = resolveLevelsAhead(gu.levelsAhead)
    return gu
end

function GU.GetOptions()
    return GU.EnsureGearUpgradeOptions()
end
