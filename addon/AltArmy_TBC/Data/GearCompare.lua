-- AltArmy TBC — Item comparison for Gear tab character selection.
-- luacheck: globals GetItemInfo GetItemStats

AltArmy = AltArmy or {}
AltArmy.GearCompare = AltArmy.GearCompare or {}

local GC = AltArmy.GearCompare
local GU = AltArmy.GearUpgrade
local ItemStats = AltArmy.ItemStats

local function getStatLabel(key)
    if ItemStats and ItemStats.GetDisplayLabel then
        return ItemStats.GetDisplayLabel(key)
    end
    return key
end

local function IU()
    return AltArmy.ItemUsability
end

local function getItemName(link)
    if not link or not GetItemInfo then return "?" end
    local name = GetItemInfo(link)
    return name or "?"
end

local function getRawStats(link)
    if ItemStats and ItemStats.GetNormalized then
        return ItemStats.GetNormalized(link)
    end
    if GU.GetNormalizedItemStats then
        return GU.GetNormalizedItemStats(link)
    end
    return {}
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

local function statWeightForKey(weights, key)
    if not weights then return 0 end
    local w = weights[key]
    if not w or w <= 0 then return 0 end
    return w
end

local function compareStatComparisonRows(a, b)
    local wa = a.weight or 0
    local wb = b.weight or 0
    local aImportant = wa > 0
    local bImportant = wb > 0
    if aImportant and bImportant then
        if wa ~= wb then return wa > wb end
        return (a.label or "") < (b.label or "")
    end
    if aImportant then return true end
    if bImportant then return false end
    return (a.label or "") < (b.label or "")
end

local function buildStatComparisonRows(newLink, oldLink, classFile, specKey)
    local weights = GU.GetWeights and GU.GetWeights(classFile, specKey) or {}
    local newStats = getRawStats(newLink)
    local oldStats = oldLink and getRawStats(oldLink) or {}
    local seen = {}
    for k in pairs(newStats) do seen[k] = true end
    for k in pairs(oldStats) do seen[k] = true end

    local rows = {}
    for key in pairs(seen) do
        local newVal = newStats[key] or 0
        local oldVal = oldStats[key] or 0
        if newVal ~= oldVal then
            local w = statWeightForKey(weights, key)
            rows[#rows + 1] = {
                label = getStatLabel(key),
                newValue = newVal,
                oldValue = oldVal,
                delta = newVal - oldVal,
                weight = w,
                unimportant = w <= 0,
                weightedDelta = (newVal - oldVal) * w,
            }
        end
    end
    table.sort(rows, compareStatComparisonRows)
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
            label = getStatLabel(key),
            newValue = newVal,
            oldValue = oldVal,
            delta = newVal - oldVal,
        }
    end
    return rows
end

local function weightedPercentValue(summary, upgradeMaxDelta)
    local delta = summary.delta or 0
    if upgradeMaxDelta and upgradeMaxDelta > 0 then
        return delta / upgradeMaxDelta * 100
    end
    local oldTotal = summary.oldTotal or 0
    if oldTotal > 0 then
        return delta / oldTotal * 100
    end
    if delta > 0 then return 100 end
    return 0
end

local function buildCustomComparison(newLink, oldLink, classFile, specKey, opts)
    opts = opts or {}
    local rows = buildStatComparisonRows(newLink, oldLink, classFile, specKey)
    local summary = buildSummary(newLink, oldLink, "custom", classFile, specKey)
    rows[#rows + 1] = {
        label = "Weighted sum",
        delta = summary.delta,
        hideWeight = true,
    }
    rows[#rows + 1] = {
        label = "Weighted percent",
        delta = weightedPercentValue(summary, opts.upgradeMaxDelta),
        hideWeight = true,
        formatAsPercent = true,
    }
    local sections = {
        {
            title = "Stat comparison",
            rows = rows,
        },
    }
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
    local classFile, specKey = GU.ResolveCompareContext(char, opts.entry)
    local DS = AltArmy.DataStore
    if not DS or not DS.GetInventoryItem then return nil, slots[1] end

    if opts.slot then
        local equipped = DS:GetInventoryItem(char, opts.slot)
        local eqLink = GU.ResolveItemLink(equipped)
        return eqLink, opts.slot
    end

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

function GC.BuildComparison(focusedLink, equippedLink, technique, charData, entry, opts)
    if not focusedLink then return nil end
    opts = opts or {}
    technique = GU.GetEffectiveTechnique(technique or "custom")
    local classFile, specKey = GU.ResolveCompareContext(charData, entry)
    local provider = GU.GetProvider(technique)
    local sections

    if technique == "custom" then
        sections = buildCustomComparison(focusedLink, equippedLink, classFile, specKey, opts)
    elseif technique == "ilvl" or technique == "gearscore" then
        sections = buildScoreOnlyComparison(focusedLink, equippedLink, classFile, specKey, technique)
    else
        sections = buildCustomComparison(focusedLink, equippedLink, classFile, specKey, opts)
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

local function formatDebugNumber(value)
    local n = tonumber(value) or 0
    if math.floor(n) == n then
        return tostring(n)
    end
    return string.format("%.1f", n)
end

local function charMatchesRealmFilter(realm, realmFilter, currentRealm)
    if realmFilter == "currentRealm" and currentRealm and realm ~= currentRealm then
        return false
    end
    return true
end

local function collectEquippableCharacters(itemLink, levelsAhead)
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter or not itemLink then return {} end
    local slots = IU() and IU().GetInventorySlotsForItem(itemLink) or {}
    if #slots == 0 then return {} end

    local realmFilter = "all"
    local GRF = AltArmy.GlobalRealmFilter
    if GRF and GRF.Get then realmFilter = GRF.Get() end
    local currentRealm = DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or ""

    local out = {}
    DS:ForEachCharacter(function(realm, charName, charData)
        if not charMatchesRealmFilter(realm, realmFilter, currentRealm) then
            return
        end
        local classFile = charData.classFile or ""
        local level = (DS.GetCharacterLevel and DS:GetCharacterLevel(charData))
            or tonumber(charData.level) or 0
        local equippable = IU() and IU().IsEquippableWithin(classFile, level, itemLink, levelsAhead)
        if not equippable then return end
        out[#out + 1] = {
            name = charData.name or charName,
            realm = realm,
            charData = charData,
        }
    end)
    table.sort(out, function(a, b)
        if a.realm ~= b.realm then return (a.realm or "") < (b.realm or "") end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

local function formatComparisonRow(row)
    if row.weightedDelta ~= nil then
        return string.format(
            "      %s: %s → %s (Δ%s, weighted Δ%s)",
            row.label or "?",
            formatDebugNumber(row.oldValue),
            formatDebugNumber(row.newValue),
            formatDebugNumber(row.delta),
            formatDebugNumber(row.weightedDelta))
    end
    return string.format(
        "      %s: %s → %s (Δ%s)",
        row.label or "?",
        formatDebugNumber(row.oldValue),
        formatDebugNumber(row.newValue),
        formatDebugNumber(row.delta))
end

--- Chat lines comparing one item across every gear technique (for debug logging).
function GC.BuildItemComparisonDebugReport(itemLink)
    local lines = {}
    if not itemLink or not GU then return lines end

    local opts = GU.GetOptions and GU.GetOptions() or {}
    local levelsAhead = tonumber(opts.levelsAhead)
    if levelsAhead == nil then levelsAhead = 5 end
    levelsAhead = math.max(0, math.floor(levelsAhead))

    lines[#lines + 1] = string.format("Item: %s", getItemName(itemLink))

    local characters = collectEquippableCharacters(itemLink, levelsAhead)
    if #characters == 0 then
        lines[#lines + 1] = "No equippable alts for this item."
    end

    local providers = GU.GetProviders and GU.GetProviders() or {}
    for i = 1, #providers do
        local provider = providers[i]
        lines[#lines + 1] = string.format("[%s]", provider.label or provider.id or "?")
        if provider.IsAvailable and not provider.IsAvailable() then
            lines[#lines + 1] = "  (not installed — skipped)"
        elseif #characters == 0 then
            lines[#lines + 1] = "  (no equippable alts)"
        else
            local technique = provider.id or "custom"
            for c = 1, #characters do
                local entry = characters[c]
                local charData = entry.charData
                local equippedLink = GC.GetEquippedCompareItem(charData, itemLink, {
                    technique = technique,
                    entry = entry,
                })
                local comparison = GC.BuildComparison(itemLink, equippedLink, technique, charData, entry)
                if comparison then
                    local summary = comparison.summary or {}
                    local isUpgrade = GU.EvaluateForCharacter(charData, itemLink, {
                        technique = technique,
                        levelsAhead = levelsAhead,
                    })
                    local tag = isUpgrade and "upgrade" or "not upgrade"
                    lines[#lines + 1] = string.format(
                        "  %s-%s: %s → %s | total %s → %s (Δ%s) [%s]",
                        entry.name or "?",
                        entry.realm or "?",
                        comparison.equippedName or "(empty)",
                        comparison.focusedName or "?",
                        formatDebugNumber(summary.oldTotal),
                        formatDebugNumber(summary.newTotal),
                        formatDebugNumber(summary.delta),
                        tag)
                    local sections = comparison.sections or {}
                    for s = 1, #sections do
                        local section = sections[s]
                        if section.title and section.title ~= "" then
                            lines[#lines + 1] = "    " .. section.title .. ":"
                        end
                        local rows = section.rows or {}
                        for r = 1, #rows do
                            lines[#lines + 1] = formatComparisonRow(rows[r])
                        end
                    end
                end
            end
        end
    end
    return lines
end

function GC.LogItemComparisonDebug(itemLink)
    local D = AltArmy.Debug
    if not D or not D.IsItemComparisonEnabled or not D.IsItemComparisonEnabled() then
        return
    end
    local lines = GC.BuildItemComparisonDebugReport(itemLink)
    if #lines == 0 then return end
    if D.LogItemComparison then
        D.LogItemComparison(lines)
    end
end
