-- AltArmy TBC — Item stat extraction for gear compare/scoring.
-- Priority: GetItemStats → tooltip regex parsing.
-- luacheck: globals GetItemInfo GetItemStats UIParent CreateFrame

AltArmy = AltArmy or {}
AltArmy.ItemStats = AltArmy.ItemStats or {}

local IS = AltArmy.ItemStats

IS.STAT_ALIASES = {
    -- Primary attributes
    ["ITEM_MOD_STRENGTH_SHORT"] = "str",
    ["ITEM_MOD_STRENGTH"] = "str",
    ["ITEM_MOD_AGILITY_SHORT"] = "agi",
    ["ITEM_MOD_AGILITY"] = "agi",
    ["ITEM_MOD_STAMINA_SHORT"] = "sta",
    ["ITEM_MOD_STAMINA"] = "sta",
    ["ITEM_MOD_INTELLECT_SHORT"] = "int",
    ["ITEM_MOD_INTELLECT"] = "int",
    ["ITEM_MOD_SPIRIT_SHORT"] = "spi",
    ["ITEM_MOD_SPIRIT"] = "spi",
    -- Armor and resistances (GetItemStats uses RESISTANCE*_NAME keys)
    ["RESISTANCE0_NAME"] = "armor",
    ["RESISTANCE1_NAME"] = "holy_res",
    ["RESISTANCE2_NAME"] = "fire_res",
    ["RESISTANCE3_NAME"] = "nature_res",
    ["RESISTANCE4_NAME"] = "frost_res",
    ["RESISTANCE5_NAME"] = "shadow_res",
    ["RESISTANCE6_NAME"] = "arcane_res",
    ["ITEM_MOD_EXTRA_ARMOR_SHORT"] = "bonus_armor",
    ["ITEM_MOD_EXTRA_ARMOR"] = "bonus_armor",
    -- Spell power / damage / healing
    ["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] = "sp",
    ["ITEM_MOD_SPELL_DAMAGE_DONE"] = "sp",
    ["ITEM_MOD_SPELL_DAMAGE"] = "sp",
    ["ITEM_MOD_SPELL_POWER_SHORT"] = "sp",
    ["ITEM_MOD_SPELL_POWER"] = "sp",
    ["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = "heal",
    ["ITEM_MOD_SPELL_HEALING_DONE"] = "heal",
    -- Hit / crit (physical vs spell)
    ["ITEM_MOD_HIT_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_RATING"] = "hit",
    ["ITEM_MOD_HIT_MELEE_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_MELEE_RATING"] = "hit",
    ["ITEM_MOD_HIT_RANGED_RATING_SHORT"] = "hit",
    ["ITEM_MOD_HIT_RANGED_RATING"] = "hit",
    ["ITEM_MOD_HIT_SPELL_RATING_SHORT"] = "spell_hit",
    ["ITEM_MOD_HIT_SPELL_RATING"] = "spell_hit",
    ["ITEM_MOD_CRIT_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_RATING"] = "crit",
    ["ITEM_MOD_CRIT_MELEE_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_MELEE_RATING"] = "crit",
    ["ITEM_MOD_CRIT_RANGED_RATING_SHORT"] = "crit",
    ["ITEM_MOD_CRIT_RANGED_RATING"] = "crit",
    ["ITEM_MOD_CRIT_SPELL_RATING_SHORT"] = "spell_crit",
    ["ITEM_MOD_CRIT_SPELL_RATING"] = "spell_crit",
    -- Attack power / weapon
    ["ITEM_MOD_ATTACK_POWER_SHORT"] = "ap",
    ["ITEM_MOD_ATTACK_POWER"] = "ap",
    ["ITEM_MOD_MELEE_ATTACK_POWER_SHORT"] = "ap",
    ["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = "rap",
    ["ITEM_MOD_RANGED_ATTACK_POWER"] = "rap",
    ["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"] = "feral_ap",
    ["ITEM_MOD_FERAL_ATTACK_POWER"] = "feral_ap",
    ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = "dps",
    -- Tank / avoidance
    ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = "def",
    ["ITEM_MOD_DEFENSE_SKILL_RATING"] = "def",
    ["ITEM_MOD_DODGE_RATING_SHORT"] = "dodge",
    ["ITEM_MOD_DODGE_RATING"] = "dodge",
    ["ITEM_MOD_PARRY_RATING_SHORT"] = "parry",
    ["ITEM_MOD_PARRY_RATING"] = "parry",
    ["ITEM_MOD_BLOCK_RATING_SHORT"] = "block",
    ["ITEM_MOD_BLOCK_RATING"] = "block",
    ["ITEM_MOD_BLOCK_VALUE_SHORT"] = "blockval",
    ["ITEM_MOD_BLOCK_VALUE"] = "blockval",
    -- Regeneration
    ["ITEM_MOD_MANA_REGENERATION_SHORT"] = "mp5",
    ["ITEM_MOD_MANA_REGENERATION"] = "mp5",
    ["ITEM_MOD_POWER_REGEN0_SHORT"] = "mp5",
    ["ITEM_MOD_HEALTH_REGEN_SHORT"] = "health_regen",
    ["ITEM_MOD_HEALTH_REGENERATION_SHORT"] = "health_regen",
    ["ITEM_MOD_HEALTH_REGEN"] = "health_regen",
    ["ITEM_MOD_HEALTH_REGENERATION"] = "health_regen",
    -- Health / mana (uncommon on gear but returned by GetItemStats)
    ["ITEM_MOD_HEALTH_SHORT"] = "health",
    ["ITEM_MOD_HEALTH"] = "health",
    ["ITEM_MOD_MANA_SHORT"] = "mana",
    ["ITEM_MOD_MANA"] = "mana",
    -- TBC-adjacent ratings that may appear on later patches / edge items
    ["ITEM_MOD_RESILIENCE_RATING_SHORT"] = "resilience",
    ["ITEM_MOD_RESILIENCE_RATING"] = "resilience",
    ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = "expertise",
    ["ITEM_MOD_EXPERTISE_RATING"] = "expertise",
    ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = "armor_pen",
    ["ITEM_MOD_ARMOR_PENETRATION_RATING"] = "armor_pen",
    ["ITEM_MOD_SPELL_PENETRATION_SHORT"] = "spell_pen",
    ["ITEM_MOD_SPELL_PENETRATION"] = "spell_pen",
    ["ITEM_MOD_HASTE_RATING_SHORT"] = "haste",
    ["ITEM_MOD_HASTE_RATING"] = "haste",
    ["ITEM_MOD_HASTE_MELEE_RATING_SHORT"] = "haste",
    ["ITEM_MOD_HASTE_MELEE_RATING"] = "haste",
    ["ITEM_MOD_HASTE_RANGED_RATING_SHORT"] = "haste",
    ["ITEM_MOD_HASTE_RANGED_RATING"] = "haste",
    ["ITEM_MOD_HASTE_SPELL_RATING_SHORT"] = "spell_haste",
    ["ITEM_MOD_HASTE_SPELL_RATING"] = "spell_haste",
    -- Per-school spell damage (tooltip-only keys)
    ["ALTARMY_FIRE_SPELL"] = "fire_sp",
    ["ALTARMY_FROST_SPELL"] = "frost_sp",
    ["ALTARMY_ARCANE_SPELL"] = "arcane_sp",
    ["ALTARMY_SHADOW_SPELL"] = "shadow_sp",
    ["ALTARMY_NATURE_SPELL"] = "nature_sp",
    ["ALTARMY_HOLY_SPELL"] = "holy_sp",
}

-- English display labels for normalized stat keys (compare panel, debug).
IS.STAT_LABELS = {
    str = "Strength",
    agi = "Agility",
    sta = "Stamina",
    int = "Intellect",
    spi = "Spirit",
    armor = "Armor",
    bonus_armor = "Bonus Armor",
    holy_res = "Holy Resistance",
    fire_res = "Fire Resistance",
    nature_res = "Nature Resistance",
    frost_res = "Frost Resistance",
    shadow_res = "Shadow Resistance",
    arcane_res = "Arcane Resistance",
    sp = "Spell Damage",
    heal = "Healing",
    hit = "Hit Rating",
    crit = "Crit Rating",
    spell_hit = "Spell Hit Rating",
    spell_crit = "Spell Crit Rating",
    spell_haste = "Spell Haste Rating",
    fire_sp = "Fire Spell Damage",
    frost_sp = "Frost Spell Damage",
    arcane_sp = "Arcane Spell Damage",
    shadow_sp = "Shadow Spell Damage",
    nature_sp = "Nature Spell Damage",
    holy_sp = "Holy Spell Damage",
    ap = "Attack Power",
    rap = "Ranged AP",
    feral_ap = "Attack Power In Forms",
    melee_dps = "Melee DPS",
    ranged_dps = "Ranged DPS",
    def = "Defense",
    dodge = "Dodge",
    parry = "Parry",
    block = "Block",
    blockval = "Block Value",
    mp5 = "Mana Regen",
    health_regen = "Health Regen",
    health = "Health",
    mana = "Mana",
    resilience = "Resilience",
    expertise = "Expertise",
    armor_pen = "Armor Penetration",
    spell_pen = "Spell Penetration",
    haste = "Haste",
}

local PRIMARY_STAT_DEFS = {
    { apiKey = "ITEM_MOD_STRENGTH_SHORT", label = "Strength" },
    { apiKey = "ITEM_MOD_AGILITY_SHORT", label = "Agility" },
    { apiKey = "ITEM_MOD_STAMINA_SHORT", label = "Stamina" },
    { apiKey = "ITEM_MOD_INTELLECT_SHORT", label = "Intellect" },
    { apiKey = "ITEM_MOD_SPIRIT_SHORT", label = "Spirit" },
}

local EQUIP_STAT_PATTERNS = {
    { "^Equip: %+(%d+) Attack Power%.$", "ITEM_MOD_ATTACK_POWER_SHORT" },
    { "^Equip: Increases attack power by (%d+)%.$", "ITEM_MOD_ATTACK_POWER_SHORT" },
    { "^Equip: %+(%d+) Ranged Attack Power%.$", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
    { "^Equip: Increases ranged attack power by (%d+)%.$", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
    { "^%+(%d+) Hit Rating$", "ITEM_MOD_HIT_RATING_SHORT" },
    { "^%+(%d+) Critical Strike Rating$", "ITEM_MOD_CRIT_RATING_SHORT" },
    { "^%+(%d+) Spell Hit Rating$", "ITEM_MOD_HIT_SPELL_RATING_SHORT" },
    { "^%+(%d+) Spell Critical Strike Rating$", "ITEM_MOD_CRIT_SPELL_RATING_SHORT" },
    { "^%+(%d+) Spell Haste Rating$", "ITEM_MOD_HASTE_SPELL_RATING_SHORT" },
    { "^Equip: Increases damage done by Fire spells and effects by up to (%d+)%.$",
        "ALTARMY_FIRE_SPELL" },
    { "^Equip: Increases damage done by Frost spells and effects by up to (%d+)%.$",
        "ALTARMY_FROST_SPELL" },
    { "^Equip: Increases damage done by Arcane spells and effects by up to (%d+)%.$",
        "ALTARMY_ARCANE_SPELL" },
    { "^Equip: Increases damage done by Shadow spells and effects by up to (%d+)%.$",
        "ALTARMY_SHADOW_SPELL" },
    { "^Equip: Increases damage done by Nature spells and effects by up to (%d+)%.$",
        "ALTARMY_NATURE_SPELL" },
    { "^Equip: Increases damage done by Holy spells and effects by up to (%d+)%.$",
        "ALTARMY_HOLY_SPELL" },
    { "^%+(%d+) Defense Rating$", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
    { "^%+(%d+) Dodge Rating$", "ITEM_MOD_DODGE_RATING_SHORT" },
    { "^%+(%d+) Parry Rating$", "ITEM_MOD_PARRY_RATING_SHORT" },
    { "^Equip: Increases damage and healing done by magical spells and effects by up to (%d+)%.$",
        "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
    { "^%+(%d+) Healing Spells$", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
    { "^%+(%d+) Damage and Healing Spells$", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
    { "^Equip: Restores (%d+) mana per 5 sec%.$", "ITEM_MOD_MANA_REGENERATION_SHORT" },
    { "^(%d+%.?%d*) damage per second$", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" },
    { "^(%d+) Armor$", "RESISTANCE0_NAME" },
}

local TOOLTIP_ONLY_STAT_KEYS = {
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = true,
    ITEM_MOD_DAMAGE_PER_SECOND = true,
    ALTARMY_FIRE_SPELL = true,
    ALTARMY_FROST_SPELL = true,
    ALTARMY_ARCANE_SPELL = true,
    ALTARMY_SHADOW_SPELL = true,
    ALTARMY_NATURE_SPELL = true,
    ALTARMY_HOLY_SPELL = true,
}

local RANGED_WEAPON_SUBCLASSES = {
    Bow = true,
    Gun = true,
    Crossbow = true,
    Wand = true,
    Thrown = true,
}

local function isTooltipOnlyStatKey(apiKey)
    return TOOLTIP_ONLY_STAT_KEYS[apiKey] == true
end

local function resolveWeaponDpsKey(link)
    if not link or not GetItemInfo then return "melee_dps" end
    local _, _, _, _, _, _, subclass, _, equipSlot = GetItemInfo(link)
    if subclass and RANGED_WEAPON_SUBCLASSES[subclass] then
        return "ranged_dps"
    end
    if equipSlot == "INVTYPE_RANGED" or equipSlot == "INVTYPE_RANGEDRIGHT" then
        return "ranged_dps"
    end
    return "melee_dps"
end

local function mergeTooltipSupplement(apiRaw, tooltipRaw)
    local merged = {}
    if apiRaw then
        for k, v in pairs(apiRaw) do
            merged[k] = v
        end
    end
    local hasApi = apiRaw and next(apiRaw) ~= nil
    if not tooltipRaw then return merged end
    for k, v in pairs(tooltipRaw) do
        if isTooltipOnlyStatKey(k) or not hasApi then
            merged[k] = (merged[k] or 0) + (tonumber(v) or 0)
        end
    end
    return merged
end

local cache = {}
local pendingIds = {}
local onUpdatedCallback
local pendingFrame
local statScanTooltip
local tooltipPatterns

local function copyTable(t)
    local out = {}
    if not t then return out end
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

local function escapePattern(s)
    return (s:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1"))
end

local function buildTooltipPatterns()
    if tooltipPatterns then return tooltipPatterns end
    local patterns = {}
    for i = 1, #PRIMARY_STAT_DEFS do
        local def = PRIMARY_STAT_DEFS[i]
        local label = _G[def.apiKey] or def.label
        local pat = "^%+?(%d+) " .. escapePattern(label) .. "$"
        patterns[#patterns + 1] = { pattern = pat, apiKey = def.apiKey }
    end
    for i = 1, #EQUIP_STAT_PATTERNS do
        local row = EQUIP_STAT_PATTERNS[i]
        patterns[#patterns + 1] = { pattern = row[1], apiKey = row[2] }
    end
    tooltipPatterns = patterns
    return patterns
end

local function parseItemId(link)
    if not link then return nil end
    return tonumber(tostring(link):match("item:(%d+)"))
end

local function resolveGlobalStringLabel(name)
    local g = _G[name]
    if type(g) ~= "string" or g == "" or g == name then return nil end
    if g:find("%%") then
        if not name:match("_SHORT$") then
            return resolveGlobalStringLabel(name .. "_SHORT")
        end
        return nil
    end
    return g
end

function IS.GetDisplayLabel(key)
    if not key then return "?" end
    local shortKey = IS.STAT_ALIASES[key] or key
    if IS.STAT_LABELS[shortKey] then
        return IS.STAT_LABELS[shortKey]
    end
    local globalLabel = resolveGlobalStringLabel(key)
    if globalLabel then return globalLabel end
    if shortKey ~= key then
        for apiKey, mappedShort in pairs(IS.STAT_ALIASES) do
            if mappedShort == shortKey then
                globalLabel = resolveGlobalStringLabel(apiKey)
                if globalLabel then return globalLabel end
            end
        end
    end
    return key
end

local function normalizeRawStats(raw, link)
    local out = {}
    if not raw then return out end
    local dpsKey = resolveWeaponDpsKey(link)
    for statKey, value in pairs(raw) do
        local short = IS.STAT_ALIASES[statKey] or statKey
        if statKey == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
            or statKey == "ITEM_MOD_DAMAGE_PER_SECOND" then
            short = dpsKey
        end
        out[short] = (out[short] or 0) + (tonumber(value) or 0)
    end
    return out
end

local function stripColorCodes(text)
    text = text:gsub("|c[%x]+", "")
    text = text:gsub("|r", "")
    return text
end

local function normalizeTooltipLine(text)
    text = stripColorCodes(text or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local name, val = text:match("^([%w%s]+) %+(%d+)$")
    if name and val then
        text = "+" .. val .. " " .. name
    end
    return text
end

local function isSetBonusKillLine(text)
    return text:match(" %(%d+/%d+%)$") ~= nil
end

local function lineHasArmor(text)
    return text:find("Armor", 1, true) ~= nil and text:match("(%d+)") ~= nil
end

local function getStatScanTooltip()
    if statScanTooltip then
        if statScanTooltip.SetHyperlink and statScanTooltip.GetRegions then
            return statScanTooltip
        end
        statScanTooltip = nil
    end
    if not CreateFrame then return nil end
    statScanTooltip = CreateFrame(
        "GameTooltip",
        "AltArmyTBC_ItemStatsScanTooltip",
        UIParent,
        "GameTooltipTemplate")
    if not statScanTooltip or not statScanTooltip.SetHyperlink then
        statScanTooltip = nil
        return nil
    end
    if statScanTooltip.SetOwner then
        statScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return statScanTooltip
end

local function collectTooltipLines(tooltip)
    local lines = {}
    if not tooltip then return lines end
    if tooltip.GetRegions then
        for _, region in ipairs({ tooltip:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("FontString") then
                local text = region.GetText and region:GetText()
                if text and text ~= "" then
                    lines[#lines + 1] = text
                end
            end
        end
    end
    if #lines == 0 and tooltip.NumLines and tooltip.GetName then
        local tipName = tooltip:GetName()
        if tipName then
            for i = 1, tooltip:NumLines() do
                local line = _G[tipName .. "TextLeft" .. i]
                if line and line.GetText then
                    local text = line:GetText()
                    if text and text ~= "" then
                        lines[#lines + 1] = text
                    end
                end
            end
        end
    end
    return lines
end

local function parseLineToRaw(text, rawOut)
    local patterns = buildTooltipPatterns()
    for i = 1, #patterns do
        local row = patterns[i]
        local amount = text:match(row.pattern)
        if amount then
            local n = tonumber(amount) or tonumber((amount:gsub(",", ".", 1)))
            if n then
                rawOut[row.apiKey] = (rawOut[row.apiKey] or 0) + n
                return true
            end
        end
    end
    return false
end

local function parseTooltipToRaw(link)
    local tip = getStatScanTooltip()
    if not tip then return {}, {}, false end
    tip:ClearLines()
    tip:SetHyperlink(link)
    local rawLines = collectTooltipLines(tip)
    local strippedLines = {}
    local raw = {}
    local sawArmor = false
    for i = 1, #rawLines do
        local normalized = normalizeTooltipLine(rawLines[i])
        strippedLines[#strippedLines + 1] = normalized
        if isSetBonusKillLine(normalized) then
            break
        end
        if lineHasArmor(normalized) then
            sawArmor = true
        end
        parseLineToRaw(normalized, raw)
    end
    local incomplete = false
    if sawArmor and not next(raw) and #strippedLines > 0 then
        incomplete = true
    end
    return raw, strippedLines, incomplete
end

local function fetchFromApi(link)
    if not GetItemStats then return nil end
    local stats = GetItemStats(link)
    if type(stats) == "table" and next(stats) then
        return stats, "api"
    end
    local tableStats = {}
    local ok = GetItemStats(link, tableStats)
    if ok ~= false and next(tableStats) then
        return tableStats, "api"
    end
    return nil
end

local function ensurePendingFrame()
    if pendingFrame or not CreateFrame then return end
    pendingFrame = CreateFrame("Frame")
    if not pendingFrame.RegisterEvent then return end
    pendingFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    pendingFrame:SetScript("OnEvent", function(_, _, itemId)
        itemId = tonumber(itemId)
        if not itemId or not pendingIds[itemId] then return end
        pendingIds[itemId] = nil
        for link, entry in pairs(cache) do
            if entry.itemId == itemId then
                cache[link] = nil
            end
        end
        if onUpdatedCallback then
            onUpdatedCallback(itemId)
        end
    end)
end

local function queuePending(itemId)
    if not itemId then return end
    pendingIds[itemId] = true
    ensurePendingFrame()
end

local function storeCache(link, normalized, source, meta)
    meta = meta or {}
    cache[link] = {
        normalized = copyTable(normalized),
        source = source,
        tooltipLines = meta.tooltipLines,
        itemId = parseItemId(link),
        complete = source ~= "pending",
    }
end

function IS.ClearCache()
    cache = {}
    pendingIds = {}
end

function IS.SetOnUpdated(fn)
    onUpdatedCallback = fn
end

function IS.GetSource(link)
    if not link then return "none" end
    local entry = cache[link]
    if entry then return entry.source or "none" end
    IS.GetNormalized(link)
    entry = cache[link]
    return entry and entry.source or "none"
end

function IS.GetTooltipLines(link)
    if not link then return {} end
    local entry = cache[link]
    if entry and entry.tooltipLines then
        return copyTable(entry.tooltipLines)
    end
    IS.GetNormalized(link)
    entry = cache[link]
    return entry and copyTable(entry.tooltipLines or {}) or {}
end

local function fetchStats(link)
    if GetItemInfo then
        local name = GetItemInfo(link)
        if not name then
            queuePending(parseItemId(link))
            return {}, "pending", {}
        end
    end

    local apiRaw = fetchFromApi(link)
    local tooltipRaw, tooltipLines, incomplete = parseTooltipToRaw(link)
    local mergedRaw = mergeTooltipSupplement(apiRaw, tooltipRaw)

    if next(mergedRaw) then
        local source = apiRaw and "api" or "tooltip"
        if apiRaw and tooltipRaw and next(tooltipRaw) then
            for k in pairs(tooltipRaw) do
                if isTooltipOnlyStatKey(k) and mergedRaw[k] then
                    source = "api"
                    break
                end
            end
        end
        return normalizeRawStats(mergedRaw, link), source, { tooltipLines = tooltipLines }
    end
    if incomplete then
        queuePending(parseItemId(link))
        return {}, "pending", { tooltipLines = tooltipLines }
    end

    return {}, "none", { tooltipLines = tooltipLines }
end

function IS.GetNormalized(link)
    if not link then return {} end
    local entry = cache[link]
    if entry and entry.complete ~= false then
        return copyTable(entry.normalized)
    end
    local normalized, source, meta = fetchStats(link)
    storeCache(link, normalized, source, meta)
    return copyTable(normalized)
end

function IS.FormatNormalizedForDebug(stats)
    if not stats or not next(stats) then return "(none)" end
    local keys = {}
    for k in pairs(stats) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        parts[#parts + 1] = string.format("%s=%s", k, tostring(stats[k]))
    end
    return table.concat(parts, " ")
end
