-- AltArmy TBC — Item stat extraction for gear compare/scoring.
-- Priority: Pawn API → GetItemStats → tooltip regex (Pawn-modeled).
-- luacheck: globals GetItemInfo GetItemStats PawnGetItemData UIParent CreateFrame

AltArmy = AltArmy or {}
AltArmy.ItemStats = AltArmy.ItemStats or {}

local IS = AltArmy.ItemStats

IS.STAT_ALIASES = {
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

local PAWN_STAT_TO_SHORT = {
    Strength = "str",
    Agility = "agi",
    Stamina = "sta",
    Intellect = "int",
    Spirit = "spi",
    SpellDamage = "sp",
    SpellPower = "sp",
    Healing = "heal",
    HitRating = "hit",
    CritRating = "crit",
    Ap = "ap",
    Rap = "rap",
    DefenseRating = "def",
    DodgeRating = "dodge",
    ParryRating = "parry",
    BlockRating = "block",
    BlockValue = "blockval",
    Mp5 = "mp5",
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
    { "^%+(%d+) Spell Hit Rating$", "ITEM_MOD_HIT_RATING_SHORT" },
    { "^%+(%d+) Spell Critical Strike Rating$", "ITEM_MOD_CRIT_RATING_SHORT" },
    { "^%+(%d+) Defense Rating$", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
    { "^%+(%d+) Dodge Rating$", "ITEM_MOD_DODGE_RATING_SHORT" },
    { "^%+(%d+) Parry Rating$", "ITEM_MOD_PARRY_RATING_SHORT" },
    { "^Equip: Increases damage and healing done by magical spells and effects by up to (%d+)%.$",
        "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
    { "^%+(%d+) Healing Spells$", "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
    { "^%+(%d+) Damage and Healing Spells$", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
    { "^Equip: Restores (%d+) mana per 5 sec%.$", "ITEM_MOD_MANA_REGENERATION_SHORT" },
}

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

local function normalizeRawStats(raw)
    local out = {}
    if not raw then return out end
    for statKey, value in pairs(raw) do
        local short = IS.STAT_ALIASES[statKey] or statKey
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

local function fetchFromPawn(link)
    if type(_G.PawnGetItemData) ~= "function" then return nil end
    local item = _G.PawnGetItemData(link)
    if not item or not item.Stats or not next(item.Stats) then return nil end
    local normalized = {}
    for pawnName, value in pairs(item.Stats) do
        local short = PAWN_STAT_TO_SHORT[pawnName]
        local n = tonumber(value)
        if short and n then
            normalized[short] = (normalized[short] or 0) + n
        end
    end
    if not next(normalized) then return nil end
    return normalized, "pawn", {}
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
    local pawnNorm, pawnSource, pawnMeta = fetchFromPawn(link)
    if pawnNorm then
        return pawnNorm, pawnSource, pawnMeta
    end

    if GetItemInfo then
        local name = GetItemInfo(link)
        if not name then
            queuePending(parseItemId(link))
            return {}, "pending", {}
        end
    end

    local apiRaw, apiSource = fetchFromApi(link)
    if apiRaw then
        return normalizeRawStats(apiRaw), apiSource, {}
    end

    local tooltipRaw, tooltipLines, incomplete = parseTooltipToRaw(link)
    if next(tooltipRaw) then
        return normalizeRawStats(tooltipRaw), "tooltip", { tooltipLines = tooltipLines }
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
