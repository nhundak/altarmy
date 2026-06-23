-- AltArmy TBC — Item comparison for Gear tab character selection.
-- luacheck: globals GetItemInfo GetItemStats PawnGetItemValue PawnGetItemData PawnGetSingleValueFromItem PawnCommon

AltArmy = AltArmy or {}
AltArmy.GearCompare = AltArmy.GearCompare or {}

local GC = AltArmy.GearCompare
local GU = AltArmy.GearUpgrade

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

local STAT_LABELS = {
    str = "Strength",
    agi = "Agility",
    sta = "Stamina",
    int = "Intellect",
    spi = "Spirit",
    sp = "Spell Damage",
    heal = "Healing",
    hit = "Hit Rating",
    crit = "Crit Rating",
    ap = "Attack Power",
    rap = "Ranged AP",
    def = "Defense",
    dodge = "Dodge",
    parry = "Parry",
    block = "Block",
    blockval = "Block Value",
    mp5 = "Mana Regen",
}

local function IU()
    return AltArmy.ItemUsability
end

local function getItemName(link)
    if not link or not GetItemInfo then return "?" end
    local name = GetItemInfo(link)
    return name or "?"
end

local function normalizeStats(stats)
    local out = {}
    if not stats then return out end
    for statKey, value in pairs(stats) do
        local short = STAT_ALIASES[statKey] or statKey
        out[short] = (out[short] or 0) + (tonumber(value) or 0)
    end
    return out
end

local function getRawStats(link)
    if not link or not GetItemStats then return {} end
    return normalizeStats(GetItemStats(link))
end

local function buildSummary(newLink, oldLink, technique, classFile, specKey)
    local newTotal = GU.ScoreItem(newLink, technique, classFile, specKey) or 0
    local oldTotal = oldLink and (GU.ScoreItem(oldLink, technique, classFile, specKey) or 0) or 0
    return {
        newTotal = newTotal,
        oldTotal = oldTotal,
        delta = newTotal - oldTotal,
    }
end

local function buildWeightedRows(newLink, oldLink, classFile, specKey)
    local weights = GU.GetWeights and GU.GetWeights(classFile, specKey)
    if not weights then return {} end
    local newStats = getRawStats(newLink)
    local oldStats = oldLink and getRawStats(oldLink) or {}
    local seen = {}
    local keys = {}
    for k in pairs(newStats) do
        if weights[k] then
            seen[k] = true
            keys[#keys + 1] = k
        end
    end
    for k in pairs(oldStats) do
        if weights[k] and not seen[k] then
            seen[k] = true
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    local rows = {}
    for i = 1, #keys do
        local key = keys[i]
        local newVal = newStats[key] or 0
        local oldVal = oldStats[key] or 0
        local w = weights[key] or 0
        rows[#rows + 1] = {
            label = STAT_LABELS[key] or key,
            newValue = newVal,
            oldValue = oldVal,
            delta = newVal - oldVal,
            weightedDelta = (newVal - oldVal) * w,
        }
    end
    return rows
end

local function buildRawStatRows(newLink, oldLink)
    local newStats = getRawStats(newLink)
    local oldStats = oldLink and getRawStats(oldLink) or {}
    local seen = {}
    local keys = {}
    for k in pairs(newStats) do
        seen[k] = true
        keys[#keys + 1] = k
    end
    for k in pairs(oldStats) do
        if not seen[k] then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    local rows = {}
    for i = 1, #keys do
        local key = keys[i]
        local newVal = newStats[key] or 0
        local oldVal = oldStats[key] or 0
        rows[#rows + 1] = {
            label = STAT_LABELS[key] or key,
            newValue = newVal,
            oldValue = oldVal,
            delta = newVal - oldVal,
        }
    end
    return rows
end

local function buildCustomComparison(newLink, oldLink, classFile, specKey)
    local sections = {
        {
            title = "Weighted stats",
            rows = buildWeightedRows(newLink, oldLink, classFile, specKey),
        },
    }
    return sections
end

local function buildPawnComparison(newLink, oldLink, classFile, specKey)
    if type(_G.PawnGetItemData) == "function" and type(_G.PawnGetSingleValueFromItem) == "function" then
        local newItem = _G.PawnGetItemData(newLink)
        local oldItem = oldLink and _G.PawnGetItemData(oldLink) or nil
        if newItem and newItem.Stats and (not oldLink or (oldItem and oldItem.Stats)) then
            local scaleName
            if type(_G.PawnGetScaleName) == "function" then
                scaleName = _G.PawnGetScaleName()
            end
            if scaleName and _G.PawnCommon and _G.PawnCommon.Scales and _G.PawnCommon.Scales[scaleName] then
                local scaleValues = _G.PawnCommon.Scales[scaleName].Values or {}
                local newStats = newItem.Stats or {}
                local oldStats = oldItem and oldItem.Stats or {}
                local keys = {}
                for statName, weight in pairs(scaleValues) do
                    if tonumber(weight) and weight > 0 and (newStats[statName] or oldStats[statName]) then
                        keys[#keys + 1] = statName
                    end
                end
                table.sort(keys)
                if #keys > 0 then
                    local rows = {}
                    for i = 1, #keys do
                        local statName = keys[i]
                        local newVal = newStats[statName] or 0
                        local oldVal = oldStats[statName] or 0
                        local w = scaleValues[statName] or 0
                        rows[#rows + 1] = {
                            label = statName,
                            newValue = newVal,
                            oldValue = oldVal,
                            delta = newVal - oldVal,
                            weightedDelta = (newVal - oldVal) * w,
                        }
                    end
                    return {
                        {
                            title = "Pawn weighted stats",
                            rows = rows,
                        },
                    }
                end
            end
        end
    end
    local sections = buildCustomComparison(newLink, oldLink, classFile, specKey)
    if sections[1] then
        sections[1].title = "Weighted stats (Pawn unavailable; Alt Army fallback)"
    end
    return sections
end

local function buildScoreOnlyComparison(newLink, oldLink, classFile, specKey, technique)
    local sections = {}
    local rawRows = buildRawStatRows(newLink, oldLink)
    if #rawRows > 0 then
        sections[#sections + 1] = {
            title = "Raw stats",
            rows = rawRows,
        }
    end
    if technique == "ilvl" then
        sections[#sections + 1] = {
            title = "Item level",
            rows = {
                {
                    label = "Item Level",
                    newValue = GU.ScoreItem(newLink, "ilvl", classFile, specKey),
                    oldValue = oldLink and GU.ScoreItem(oldLink, "ilvl", classFile, specKey) or 0,
                    delta = buildSummary(newLink, oldLink, "ilvl", classFile, specKey).delta,
                },
            },
        }
    end
    return sections
end

function GC.GetEquippedCompareItem(char, focusedLink, opts)
    opts = opts or {}
    if not char or not focusedLink then return nil, nil end
    local slots = IU() and IU().GetInventorySlotsForItem(focusedLink) or {}
    if #slots == 0 then return nil, nil end

    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local classFile = char.classFile or ""
    local specKey = GU.GetSpecKey(char)
    local DS = AltArmy.DataStore
    if not DS or not DS.GetInventoryItem then return nil, slots[1] end

    local newScore = GU.ScoreItem(focusedLink, technique, classFile, specKey)
    local bestSlot = slots[1]
    local bestLink = nil
    local bestDelta = -math.huge
    local hasEquipped = false

    for i = 1, #slots do
        local slot = slots[i]
        local equipped = DS:GetInventoryItem(char, slot)
        local eqLink = GU.ResolveItemLink(equipped)
        if eqLink then
            hasEquipped = true
            local oldScore = GU.ScoreItem(eqLink, technique, classFile, specKey)
            local delta = newScore - oldScore
            if delta > bestDelta then
                bestDelta = delta
                bestLink = eqLink
                bestSlot = slot
            end
        end
    end

    if not hasEquipped then
        return nil, bestSlot
    end
    return bestLink, bestSlot
end

local COMPARE_DROPDOWN_EXCLUDED = {
    ilvl = true,
    gearscore = true,
}

function GC.GetAvailableComparisonTechniques()
    local out = {}
    local providers = GU.GetProviders()
    for i = 1, #providers do
        local p = providers[i]
        if not COMPARE_DROPDOWN_EXCLUDED[p.id]
            and p.IsAvailable and p.IsAvailable() then
            out[#out + 1] = p
        end
    end
    return out
end

function GC.BuildComparison(focusedLink, equippedLink, technique, charData)
    if not focusedLink then return nil end
    technique = GU.GetEffectiveTechnique(technique or "custom")
    local classFile = charData and charData.classFile or ""
    local specKey = charData and GU.GetSpecKey(charData) or "unknown"
    local provider = GU.GetProvider(technique)
    local sections

    if technique == "custom" then
        sections = buildCustomComparison(focusedLink, equippedLink, classFile, specKey)
    elseif technique == "pawn" then
        sections = buildPawnComparison(focusedLink, equippedLink, classFile, specKey)
    elseif technique == "ilvl" or technique == "sgj" or technique == "gearscore" then
        sections = buildScoreOnlyComparison(focusedLink, equippedLink, classFile, specKey, technique)
    else
        sections = buildCustomComparison(focusedLink, equippedLink, classFile, specKey)
    end

    return {
        focusedName = getItemName(focusedLink),
        equippedName = equippedLink and getItemName(equippedLink) or "(empty)",
        techniqueId = technique,
        techniqueLabel = provider and GU.GetProviderDisplayLabel(provider) or technique,
        summary = buildSummary(focusedLink, equippedLink, technique, classFile, specKey),
        sections = sections,
    }
end
