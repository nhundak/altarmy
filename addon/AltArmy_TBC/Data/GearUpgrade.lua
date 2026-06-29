-- AltArmy TBC — Gear upgrade comparison engine.
-- Requires DataStore, ItemUsability, DataStoreTalents, ItemStats, GearScore (optional).
-- luacheck: globals GetItemInfo GetItemStats

AltArmy = AltArmy or {}
AltArmy.GearUpgrade = AltArmy.GearUpgrade or {}

local GU = AltArmy.GearUpgrade
local DT = AltArmy.DataStoreTalents
local CC = AltArmy.ClassColor

local function IS()
    return AltArmy.ItemStats
end

local function IU()
    return AltArmy.ItemUsability
end

local DEFAULT_LEVELS_AHEAD = 5
local DEFAULT_UPGRADE_THRESHOLD_PERCENT = 10

local scoreMemo = {}
local storedItemMemo = {}
local bagRoleMemo = {}
local slotDeltaMemo = {}
local weaponConfigMemo = {}

function GU.ResetFocusPass()
    scoreMemo = {}
    storedItemMemo = {}
    bagRoleMemo = {}
    slotDeltaMemo = {}
    weaponConfigMemo = {}
end

local function charKeyFromChar(char, entry)
    local name = (entry and entry.name) or (char and char.name) or ""
    local realm = (entry and entry.realm) or (char and char.realm) or ""
    return name .. "-" .. realm
end

local function storedItemsFingerprint(char)
    local parts = {}
    local containers = char and char.Containers
    if containers then
        for bagID, bag in pairs(containers) do
            local links = bag and bag.links
            if links then
                for slot, link in pairs(links) do
                    parts[#parts + 1] = tostring(bagID) .. ":" .. tostring(slot)
                        .. "=" .. tostring(link)
                end
            end
        end
    end
    if char and char.Mails then
        for i, mail in ipairs(char.Mails) do
            parts[#parts + 1] = "mail:" .. tostring(i) .. "="
                .. tostring(mail and (mail.link or mail.itemID))
        end
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function scoreMemoKey(link, technique, classFile, specKey)
    return tostring(link) .. "\0" .. tostring(technique)
        .. "\0" .. tostring(classFile) .. "\0" .. tostring(specKey)
end

local function resolveLevelsAhead(value)
    local n = tonumber(value)
    if n == nil then return DEFAULT_LEVELS_AHEAD end
    return math.max(0, math.floor(n))
end

function GU.ResolveUpgradeThresholdPercent(value)
    local n = tonumber(value)
    if n == nil then return DEFAULT_UPGRADE_THRESHOLD_PERCENT end
    return math.max(0, math.min(100, n))
end

function GU.GetUpgradeThresholdRatio(opts)
    opts = opts or {}
    local pct = opts.upgradeThresholdPercent
    if pct == nil and GU.GetOptions then
        pct = GU.GetOptions().upgradeThresholdPercent
    end
    return GU.ResolveUpgradeThresholdPercent(pct) / 100
end

--- Weighted percent change for compare panel and focus verdict (matches GearCompare).
function GU.GetWeightedChangePercent(delta, oldTotal, upgradeMaxDelta)
    delta = tonumber(delta) or 0
    if upgradeMaxDelta and upgradeMaxDelta > 0 then
        return delta / upgradeMaxDelta * 100
    end
    oldTotal = tonumber(oldTotal) or 0
    if oldTotal > 0 then
        return delta / oldTotal * 100
    end
    if delta > 0 then return 100 end
    return 0
end

local WEIGHTED_CHANGE_COLOR_GREEN = { 0.2, 1, 0.2 }
local WEIGHTED_CHANGE_COLOR_RED = { 1, 0.4, 0.3 }
local WEIGHTED_CHANGE_COLOR_YELLOW = { 1, 0.82, 0 }

local function lerpChannel(from, to, t)
    return from + (to - from) * t
end

local function colorComponents(color)
    return color[1], color[2], color[3]
end

--- Compare-panel weighted row color from change percent and upgrade threshold.
function GU.GetWeightedChangeColor(percent, opts)
    percent = tonumber(percent) or 0
    opts = opts or {}
    local threshold = GU.ResolveUpgradeThresholdPercent(opts.upgradeThresholdPercent)
    if threshold <= 0 then
        if percent > 0 then return colorComponents(WEIGHTED_CHANGE_COLOR_GREEN) end
        if percent < 0 then return colorComponents(WEIGHTED_CHANGE_COLOR_RED) end
        return colorComponents(WEIGHTED_CHANGE_COLOR_YELLOW)
    end

    if percent >= threshold then
        return colorComponents(WEIGHTED_CHANGE_COLOR_GREEN)
    end
    if percent <= -threshold then
        return colorComponents(WEIGHTED_CHANGE_COLOR_RED)
    end
    if percent == 0 then
        return colorComponents(WEIGHTED_CHANGE_COLOR_YELLOW)
    end

    if percent > 0 then
        local t = percent / threshold
        return lerpChannel(WEIGHTED_CHANGE_COLOR_YELLOW[1], WEIGHTED_CHANGE_COLOR_GREEN[1], t),
            lerpChannel(WEIGHTED_CHANGE_COLOR_YELLOW[2], WEIGHTED_CHANGE_COLOR_GREEN[2], t),
            lerpChannel(WEIGHTED_CHANGE_COLOR_YELLOW[3], WEIGHTED_CHANGE_COLOR_GREEN[3], t)
    end

    local t = (percent + threshold) / threshold
    return lerpChannel(WEIGHTED_CHANGE_COLOR_RED[1], WEIGHTED_CHANGE_COLOR_YELLOW[1], t),
        lerpChannel(WEIGHTED_CHANGE_COLOR_RED[2], WEIGHTED_CHANGE_COLOR_YELLOW[2], t),
        lerpChannel(WEIGHTED_CHANGE_COLOR_RED[3], WEIGHTED_CHANGE_COLOR_YELLOW[3], t)
end

local function buildWeightsFromPawnScales()
    local out = {}
    local PS = AltArmy.PawnScales
    local raw = PS and PS.RAW
    if not raw then return out end
    for classFile, bySpec in pairs(raw) do
        out[classFile] = {}
        for specKey, pawnValues in pairs(bySpec) do
            out[classFile][specKey] = GU.PawnScaleToWeights(pawnValues)
        end
    end
    return out
end

-- TBC stat weights per class/spec (weebly EJ/MaxDPS-derived, via PawnScale translator).
local WEIGHTS = buildWeightsFromPawnScales()

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
    if requested == "pawn" or requested == "sgj" then
        return "custom"
    end
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

local function normalizeClassFile(classFile)
    return (classFile or ""):upper()
end

local function normalizeItemStats(link)
    local itemStats = IS()
    if itemStats and itemStats.GetNormalized then
        return itemStats.GetNormalized(link) or {}
    end
    return {}
end

local function normalizeItemStatsRef(link)
    local itemStats = IS()
    if itemStats and itemStats.GetNormalizedRef then
        return itemStats.GetNormalizedRef(link) or {}
    end
    return normalizeItemStats(link)
end

function GU.GetNormalizedItemStats(link)
    return normalizeItemStats(link)
end

local function resolveCompareClassFile(char, entry)
    if entry and entry.classFile and entry.classFile ~= "" then
        return normalizeClassFile(entry.classFile)
    end
    if char and char.classFile and char.classFile ~= "" then
        return normalizeClassFile(char.classFile)
    end
    return ""
end

--- Custom gear compare uses leveling spec unless talent data picks a primary spec.
local function resolveGearCompareSpecKey(char, classFile)
    classFile = normalizeClassFile(classFile)
    if DT and DT.ResolveSpecKey and char then
        local specKey, known = DT.ResolveSpecKey(char)
        if known and specKey and specKey ~= "unknown" then
            return specKey
        end
    end
    if DT and DT.GetLevelingSpecKey then
        return DT.GetLevelingSpecKey(classFile)
    end
    return "unknown"
end

local function resolveCompareContext(char, entry)
    local classFile = resolveCompareClassFile(char, entry)
    local specKey = resolveGearCompareSpecKey(char, classFile)
    return classFile, specKey
end

function GU.ResolveCompareContext(char, entry)
    return resolveCompareContext(char, entry)
end

function GU.FormatSpecDisplayName(specKey)
    if not specKey or specKey == "" or specKey == "unknown" then
        return "Unknown"
    end
    return specKey:sub(1, 1):upper() .. specKey:sub(2)
end

local function formatCompareCharName(charName, classFile)
    if CC and CC.formatName then
        return CC.formatName(charName, classFile)
    end
    return charName or "?"
end

function GU.FormatCompareSpecWarningText(charName, assumedSpec, classFile)
    return string.format(
        "%s's spec is unknown. Assuming %s",
        formatCompareCharName(charName, classFile),
        assumedSpec or "Unknown")
end

function GU.FormatCompareUnpickedSpecWarningText(charName, assumedSpec, classFile)
    return string.format(
        "%s hasn't picked a spec yet. Assuming %s",
        formatCompareCharName(charName, classFile),
        assumedSpec or "Unknown")
end

local TALENT_SPEC_MIN_LEVEL = 10

local function getCompareCharacterLevel(entry, charData)
    local level = tonumber(entry and entry.level) or tonumber(charData and charData.level)
    return level or 0
end

local function charHasPickedSpec(charData)
    if not DT or not DT.ResolveSpecKey then return false end
    local _, known = DT.ResolveSpecKey(charData)
    return known == true
end

local function charNeedsUnpickedSpecWarning(charData, entry)
    if not DT or not DT.HasTalentData or not DT.HasTalentData(charData) then
        return false
    end
    if getCompareCharacterLevel(entry, charData) < TALENT_SPEC_MIN_LEVEL then
        return true
    end
    local primary = charData.talents and charData.talents.primary
    return not primary or primary <= 0
end

--- Compare-panel warning when spec is unknown (missing scan vs not picked yet).
function GU.GetCompareSpecWarning(entry, charData)
    if not entry or not charData then return nil end
    if charHasPickedSpec(charData) then return nil end

    local _, specKey = resolveCompareContext(charData, entry)
    local assumedSpec = GU.FormatSpecDisplayName(specKey)
    local charName = entry.name or "?"
    local warningBase = {
        charName = charName,
        realm = entry.realm or "",
        classFile = entry.classFile or charData.classFile,
        assumedSpec = assumedSpec,
    }

    local missingData = false
    if DT and DT.HasTalentData and not DT.HasTalentData(charData) then
        local SD = AltArmy.SummaryData
        if SD and SD.GetTalentSpecMissingInfo then
            local info = SD.GetTalentSpecMissingInfo(entry.name, entry.realm)
            missingData = info and info.hasMissing
        else
            missingData = true
        end
    end

    if missingData then
        return {
            kind = "missing_spec",
            text = GU.FormatCompareSpecWarningText(charName, assumedSpec, warningBase.classFile),
            charName = warningBase.charName,
            realm = warningBase.realm,
            classFile = warningBase.classFile,
            assumedSpec = assumedSpec,
        }
    end

    if charNeedsUnpickedSpecWarning(charData, entry) then
        return {
            kind = "unpicked_spec",
            text = GU.FormatCompareUnpickedSpecWarningText(charName, assumedSpec, warningBase.classFile),
            charName = warningBase.charName,
            realm = warningBase.realm,
            classFile = warningBase.classFile,
            assumedSpec = assumedSpec,
        }
    end

    return nil
end

local function getSpecKey(char)
    if DT and DT.ResolveSpecKey then
        return select(1, DT.ResolveSpecKey(char)) or "unknown"
    end
    return "unknown"
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
    if not link then return 0 end
    local weights = getWeights(classFile, specKey)
    if not weights then return 0 end
    local stats = normalizeItemStatsRef(link)
    local total = 0
    for short, value in pairs(stats) do
        local w = weights[short]
        if w then
            total = total + value * w
        end
    end
    return total
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
    local key = scoreMemoKey(link, technique, classFile, specKey)
    local cached = scoreMemo[key]
    if cached ~= nil then return cached end
    local score
    if technique == "ilvl" then
        score = getItemLevel(link)
    elseif technique == "custom" then
        score = GU.ScoreItemCustom(link, classFile, specKey)
    elseif technique == "gearscore" then
        score = scoreItemGearScore(link) or getItemLevel(link)
    else
        score = GU.ScoreItemCustom(link, classFile, specKey)
    end
    scoreMemo[key] = score
    return score
end

function GU.ResolveItemLink(item)
    return resolveItemLink(item)
end

function GU.ScoreItem(link, technique, classFile, specKey)
    return scoreItem(link, technique, classFile, specKey)
end

--- Per-stat weighted score breakdown for debug dumps.
function GU.BuildScoreBreakdown(link, technique, classFile, specKey)
    if not link then return nil end
    technique = GU.GetEffectiveTechnique(technique or "custom")
    local weights = getWeights(classFile, specKey)
    local stats = normalizeItemStats(link)
    local contributions = {}
    local weightedSum = 0
    for key, value in pairs(stats) do
        local statValue = tonumber(value) or 0
        local weight = weights and tonumber(weights[key]) or 0
        local contribution = statValue * weight
        weightedSum = weightedSum + contribution
        contributions[#contributions + 1] = {
            key = key,
            statValue = statValue,
            weight = weight,
            contribution = contribution,
        }
    end
    table.sort(contributions, function(a, b)
        return (a.key or "") < (b.key or "")
    end)
    return {
        technique = technique,
        total = scoreItem(link, technique, classFile, specKey),
        weightedSum = weightedSum,
        contributions = contributions,
    }
end

function GU.CompareItems(newLink, oldLink, technique, classFile, specKey)
    local newScore = scoreItem(newLink, technique, classFile, specKey)
    local oldScore = oldLink and scoreItem(oldLink, technique, classFile, specKey) or 0
    if not oldLink then
        return newScore > 0
    end
    return newScore > oldScore
end

--- Signed score delta for focused item vs equipped item in one slot.
function GU.GetSlotCompareDelta(char, itemLink, invSlot, opts, entry)
    opts = opts or {}
    if not char or not itemLink or not invSlot then return 0 end
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local DS = AltArmy.DataStore
    local equipped = DS and DS.GetInventoryItem and DS:GetInventoryItem(char, invSlot)
    local eqLink = resolveItemLink(equipped)
    local memoKey = charKeyFromChar(char, entry) .. "\0" .. tostring(invSlot)
        .. "\0" .. tostring(itemLink) .. "\0" .. technique
        .. "\0" .. tostring(eqLink or "")
    local cached = slotDeltaMemo[memoKey]
    if cached ~= nil then return cached end
    if not DS or not DS.GetInventoryItem then return 0 end
    local classFile, specKey = resolveCompareContext(char, entry)
    local newScore = scoreItem(itemLink, technique, classFile, specKey)
    local delta
    if not eqLink then
        delta = newScore > 0 and newScore or 0
    else
        delta = newScore - scoreItem(eqLink, technique, classFile, specKey)
    end
    slotDeltaMemo[memoKey] = delta
    return delta
end

local MAIN_HAND_SLOT = 16
local OFF_HAND_SLOT = 17

local function getEquippedLink(char, invSlot)
    local DS = AltArmy.DataStore
    if not DS or not DS.GetInventoryItem then return nil end
    return resolveItemLink(DS:GetInventoryItem(char, invSlot))
end

local function scoreForLink(link, technique, classFile, specKey)
    if not link then return 0 end
    return scoreItem(link, technique, classFile, specKey)
end

--- True for weapons that occupy the main-hand + off-hand loadout pair.
function GU.IsWeaponPairItem(itemLink)
    local iu = IU()
    if not iu or not iu.GetWeaponRole then return false end
    local role = iu.GetWeaponRole(itemLink)
    return role == "twohand" or role == "onehand" or role == "offhand"
end

--- Weighted score of equipped main-hand plus off-hand (empty slots count as 0).
function GU.GetEquippedLoadoutValue(char, technique, classFile, specKey)
    local mh = getEquippedLink(char, MAIN_HAND_SLOT)
    local oh = getEquippedLink(char, OFF_HAND_SLOT)
    return scoreForLink(mh, technique, classFile, specKey)
        + scoreForLink(oh, technique, classFile, specKey)
end

--- Best usable bag/bank item matching a weapon role for this character.
function GU.FindBestBagItemForRole(char, role, opts, entry)
    opts = opts or {}
    if not char or not role then return nil, 0 end
    local iu = IU()
    if not iu or not iu.GetWeaponRole then return nil, 0 end
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local classFile, specKey = resolveCompareContext(char, entry)
    local level = tonumber(entry and entry.level) or tonumber(char.level) or 0
    local levelsAhead = resolveLevelsAhead(opts.levelsAhead)
    local memoKey = charKeyFromChar(char, entry) .. "\0" .. tostring(role)
        .. "\0" .. technique .. "\0" .. classFile .. "\0" .. specKey
        .. "\0" .. tostring(level) .. "\0" .. tostring(levelsAhead)
        .. "\0" .. storedItemsFingerprint(char)
    local cached = bagRoleMemo[memoKey]
    if cached then
        return cached.link, cached.score
    end
    local containers = char.Containers
    if not containers then return nil, 0 end

    local bestLink
    local bestScore = 0
    for _, bag in pairs(containers) do
        local links = bag and bag.links
        if links then
            for _, link in pairs(links) do
                if link and iu.GetWeaponRole(link) == role then
                    if not iu.CanNeverUseItem(classFile, link) then
                        local equippable = iu.IsEquippableWithin(
                            classFile, level, link, levelsAhead)
                        if equippable then
                            local itemScore = scoreItem(link, technique, classFile, specKey)
                            if itemScore > bestScore then
                                bestScore = itemScore
                                bestLink = link
                            end
                        end
                    end
                end
            end
        end
    end
    bagRoleMemo[memoKey] = { link = bestLink, score = bestScore }
    return bestLink, bestScore
end

local function otherWeaponSlot(slot)
    if slot == MAIN_HAND_SLOT then return OFF_HAND_SLOT end
    return MAIN_HAND_SLOT
end

local function isSingleHandSelectedRole(role)
    return role == "onehand" or role == "offhand"
end

local function scoreLoadoutLinks(mhLink, ohLink, technique, classFile, specKey)
    return scoreForLink(mhLink, technique, classFile, specKey)
        + scoreForLink(ohLink, technique, classFile, specKey)
end

local function loadoutLinksFromSlots(mhLink, ohLink)
    local links = {}
    if mhLink then links[#links + 1] = mhLink end
    if ohLink then links[#links + 1] = ohLink end
    return links
end

local function canEquipLinkInWeaponSlot(link, targetSlot, classFile, specKey)
    local iu = IU()
    if not iu or not link or not targetSlot then return false end
    local slots = iu.GetInventorySlotsForItem(link) or {}
    for i = 1, #slots do
        if slots[i] == targetSlot then return true end
    end
    if targetSlot == OFF_HAND_SLOT and iu.CanClassDualWield(classFile, specKey) then
        local role = iu.GetWeaponRole(link)
        if role == "onehand" and GetItemInfo then
            local equipLoc = select(9, GetItemInfo(link))
            if equipLoc and equipLoc ~= "INVTYPE_WEAPONMAINHAND" then
                return true
            end
        end
    end
    return false
end

local function considerStoredLinkForSlot(
    link, targetSlot, classFile, specKey, level, levelsAhead, technique, bestLink, bestScore)
    if not canEquipLinkInWeaponSlot(link, targetSlot, classFile, specKey) then
        return bestLink, bestScore
    end
    local iu = IU()
    if not iu or iu.CanNeverUseItem(classFile, link) then
        return bestLink, bestScore
    end
    if not iu.IsEquippableWithin(classFile, level, link, levelsAhead) then
        return bestLink, bestScore
    end
    local itemScore = scoreItem(link, technique, classFile, specKey)
    if itemScore > bestScore then
        return link, itemScore
    end
    return bestLink, bestScore
end

--- Best bags/bank/mail item equippable in a weapon slot for this character.
function GU.FindBestStoredItemForSlot(char, targetSlot, opts, entry)
    opts = opts or {}
    if not char or not targetSlot then return nil, 0 end
    local iu = IU()
    if not iu then return nil, 0 end
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local classFile, specKey = resolveCompareContext(char, entry)
    local level = tonumber(entry and entry.level) or tonumber(char.level) or 0
    local levelsAhead = resolveLevelsAhead(opts.levelsAhead)
    local memoKey = charKeyFromChar(char, entry) .. "\0" .. tostring(targetSlot)
        .. "\0" .. technique .. "\0" .. classFile .. "\0" .. specKey
        .. "\0" .. tostring(level) .. "\0" .. tostring(levelsAhead)
        .. "\0" .. storedItemsFingerprint(char)
    local cached = storedItemMemo[memoKey]
    if cached then
        return cached.link, cached.score
    end

    local bestLink
    local bestScore = 0
    local containers = char.Containers
    if containers then
        for _, bag in pairs(containers) do
            local links = bag and bag.links
            if links then
                for _, link in pairs(links) do
                    bestLink, bestScore = considerStoredLinkForSlot(
                        link, targetSlot, classFile, specKey, level, levelsAhead,
                        technique, bestLink, bestScore)
                end
            end
        end
    end

    local DS = AltArmy.DataStore
    if DS and DS.IterateMailItemLinks then
        DS:IterateMailItemLinks(char, function(link)
            bestLink, bestScore = considerStoredLinkForSlot(
                link, targetSlot, classFile, specKey, level, levelsAhead,
                technique, bestLink, bestScore)
            return false
        end)
    end
    storedItemMemo[memoKey] = { link = bestLink, score = bestScore }
    return bestLink, bestScore
end

local function makeDeducedEntry(link, side, slot, fillRole)
    return {
        link = link,
        side = side,
        slot = slot,
        fillRole = fillRole,
    }
end

local function fillRoleForSlot(slot)
    if slot == MAIN_HAND_SLOT then return "mainhand" end
    return "offhand"
end

local function finalizeSelectionCompare(
    candidateMH, candidateOH, equippedMH, equippedOH,
    mode, deducedLinks, technique, classFile, specKey)
    local candidateValue = scoreLoadoutLinks(candidateMH, candidateOH, technique, classFile, specKey)
    local equippedValue = scoreLoadoutLinks(equippedMH, equippedOH, technique, classFile, specKey)
    return {
        candidateLinks = loadoutLinksFromSlots(candidateMH, candidateOH),
        equippedLinks = loadoutLinksFromSlots(equippedMH, equippedOH),
        candidateMH = candidateMH,
        candidateOH = candidateOH,
        equippedMH = equippedMH,
        equippedOH = equippedOH,
        candidateValue = candidateValue,
        equippedValue = equippedValue,
        delta = candidateValue - equippedValue,
        deducedLinks = deducedLinks or {},
        mode = mode,
    }
end

local function buildOnehandFocusCompare(
    char, focusedLink, selectedSlot, selectedLink, selectedRole, opts, entry,
    technique, classFile, specKey)
    local deducedLinks = {}
    if selectedRole == "twohand" then
        local deduced = select(1, GU.FindBestStoredItemForSlot(
            char, OFF_HAND_SLOT, opts, entry))
        if deduced then
            deducedLinks[#deducedLinks + 1] = makeDeducedEntry(
                deduced, "candidate", OFF_HAND_SLOT, "offhand")
            return finalizeSelectionCompare(
                focusedLink, deduced, selectedLink, nil,
                "paired_candidate", deducedLinks, technique, classFile, specKey)
        end
        return finalizeSelectionCompare(
            focusedLink, nil, selectedLink, nil,
            "one_v_one", deducedLinks, technique, classFile, specKey)
    end
    if isSingleHandSelectedRole(selectedRole) then
        local candidateMH, candidateOH, equippedMH, equippedOH
        if selectedSlot == MAIN_HAND_SLOT then
            candidateMH, equippedMH = focusedLink, selectedLink
        else
            candidateOH, equippedOH = focusedLink, selectedLink
        end
        return finalizeSelectionCompare(
            candidateMH, candidateOH, equippedMH, equippedOH,
            "one_v_one", deducedLinks, technique, classFile, specKey)
    end
    local candidateMH, candidateOH
    if selectedSlot == MAIN_HAND_SLOT then
        candidateMH = focusedLink
    else
        candidateOH = focusedLink
    end
    return finalizeSelectionCompare(
        candidateMH, candidateOH, nil, nil,
        "one_v_one", deducedLinks, technique, classFile, specKey)
end

local function buildTwohandFocusCompare(
    char, focusedLink, selectedSlot, selectedLink, selectedRole, opts, entry,
    technique, classFile, specKey)
    local deducedLinks = {}
    if selectedRole == "twohand" then
        return finalizeSelectionCompare(
            focusedLink, nil, selectedLink, nil,
            "one_v_one", deducedLinks, technique, classFile, specKey)
    end
    if not selectedLink then
        local otherSlot = otherWeaponSlot(selectedSlot)
        local otherLink = getEquippedLink(char, otherSlot)
        local deduced = select(1, GU.FindBestStoredItemForSlot(
            char, selectedSlot, opts, entry))
        local equippedMH, equippedOH
        if selectedSlot == MAIN_HAND_SLOT then
            equippedMH = deduced
            equippedOH = otherLink
        else
            equippedMH = otherLink
            equippedOH = deduced
        end
        if deduced then
            deducedLinks[#deducedLinks + 1] = makeDeducedEntry(
                deduced, "equipped", selectedSlot, fillRoleForSlot(selectedSlot))
        end
        return finalizeSelectionCompare(
            focusedLink, nil, equippedMH, equippedOH,
            "empty_2h", deducedLinks, technique, classFile, specKey)
    end
    if isSingleHandSelectedRole(selectedRole) then
        local otherSlot = otherWeaponSlot(selectedSlot)
        local otherLink = getEquippedLink(char, otherSlot)
        local equippedMH, equippedOH
        if selectedSlot == MAIN_HAND_SLOT then
            equippedMH = selectedLink
            if otherLink then
                equippedOH = otherLink
            else
                local deduced = select(1, GU.FindBestStoredItemForSlot(
                    char, OFF_HAND_SLOT, opts, entry))
                equippedOH = deduced
                if deduced then
                    deducedLinks[#deducedLinks + 1] = makeDeducedEntry(
                        deduced, "equipped", OFF_HAND_SLOT, "offhand")
                end
            end
        else
            equippedOH = selectedLink
            if otherLink then
                equippedMH = otherLink
            else
                local deduced = select(1, GU.FindBestStoredItemForSlot(
                    char, MAIN_HAND_SLOT, opts, entry))
                equippedMH = deduced
                if deduced then
                    deducedLinks[#deducedLinks + 1] = makeDeducedEntry(
                        deduced, "equipped", MAIN_HAND_SLOT, "mainhand")
                end
            end
        end
        local mode = #deducedLinks > 0 and "paired_equipped" or "one_v_one"
        return finalizeSelectionCompare(
            focusedLink, nil, equippedMH, equippedOH,
            mode, deducedLinks, technique, classFile, specKey)
    end
    return finalizeSelectionCompare(
        focusedLink, nil, nil, nil,
        "one_v_one", deducedLinks, technique, classFile, specKey)
end

local function buildOffhandFocusCompare(
    char, focusedLink, selectedSlot, selectedLink, selectedRole, opts, entry,
    technique, classFile, specKey)
    local deducedLinks = {}
    if selectedRole == "twohand" then
        local deduced = select(1, GU.FindBestStoredItemForSlot(
            char, MAIN_HAND_SLOT, opts, entry))
        if deduced then
            deducedLinks[#deducedLinks + 1] = makeDeducedEntry(
                deduced, "candidate", MAIN_HAND_SLOT, "mainhand")
            return finalizeSelectionCompare(
                deduced, focusedLink, selectedLink, nil,
                "paired_candidate", deducedLinks, technique, classFile, specKey)
        end
        return finalizeSelectionCompare(
            nil, focusedLink, selectedLink, nil,
            "one_v_one", deducedLinks, technique, classFile, specKey)
    end
    if isSingleHandSelectedRole(selectedRole) then
        local candidateMH = nil
        local candidateOH = focusedLink
        local equippedMH, equippedOH
        if selectedSlot == MAIN_HAND_SLOT then
            equippedMH = selectedLink
        else
            equippedOH = selectedLink
        end
        return finalizeSelectionCompare(
            candidateMH, candidateOH, equippedMH, equippedOH,
            "one_v_one", deducedLinks, technique, classFile, specKey)
    end
    return finalizeSelectionCompare(
        nil, focusedLink, nil, nil,
        "one_v_one", deducedLinks, technique, classFile, specKey)
end

--- Selection-driven weapon loadout compare for one focused item and grid slot.
function GU.BuildSelectionLoadoutCompare(char, focusedLink, selectedSlot, opts, entry)
    opts = opts or {}
    if not char or not focusedLink or not selectedSlot then return nil end
    local iu = IU()
    if not iu or not iu.GetWeaponRole then return nil end
    local focusRole = iu.GetWeaponRole(focusedLink)
    if not focusRole or focusRole == "ranged" then return nil end

    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local classFile, specKey = resolveCompareContext(char, entry)
    local selectedLink = getEquippedLink(char, selectedSlot)
    local selectedRole = selectedLink and iu.GetWeaponRole(selectedLink) or nil

    if focusRole == "twohand" then
        return buildTwohandFocusCompare(
            char, focusedLink, selectedSlot, selectedLink, selectedRole,
            opts, entry, technique, classFile, specKey)
    end
    if focusRole == "offhand" then
        return buildOffhandFocusCompare(
            char, focusedLink, selectedSlot, selectedLink, selectedRole,
            opts, entry, technique, classFile, specKey)
    end
    return buildOnehandFocusCompare(
        char, focusedLink, selectedSlot, selectedLink, selectedRole,
        opts, entry, technique, classFile, specKey)
end

local function selectionInfoFromCompare(result, compareSlot)
    if not result then return nil end
    local offHandLink = result.candidateOH
    local mainHandLink = result.candidateMH
    for i = 1, #(result.deducedLinks or {}) do
        local deduced = result.deducedLinks[i]
        if deduced.side == "candidate" then
            if deduced.slot == OFF_HAND_SLOT then
                offHandLink = deduced.link
            elseif deduced.slot == MAIN_HAND_SLOT then
                mainHandLink = deduced.link
            end
        end
    end
    return {
        config = result.mode,
        targetSlot = compareSlot,
        currentValue = result.equippedValue,
        candidateValue = result.candidateValue,
        offHandLink = offHandLink,
        mainHandLink = mainHandLink,
        selection = result,
    }
end

local function resolveWeaponCompareSlot(opts)
    return opts and (opts.compareSlot or opts.slot) or nil
end

local function bestSelectionCompareAcrossSlots(char, focusedLink, opts, entry)
    local bestResult
    local bestDelta
    local bestSlot
    for _, slot in ipairs({ MAIN_HAND_SLOT, OFF_HAND_SLOT }) do
        local slotOpts = {}
        for k, v in pairs(opts or {}) do
            slotOpts[k] = v
        end
        slotOpts.compareSlot = slot
        local result = GU.BuildSelectionLoadoutCompare(char, focusedLink, slot, slotOpts, entry)
        if result and (not bestDelta or (result.delta or 0) > bestDelta) then
            bestDelta = result.delta
            bestResult = result
            bestSlot = slot
        end
    end
    if bestResult then
        bestResult.compareSlot = bestSlot
    end
    return bestResult
end

--- Loadout-aware weapon delta vs equipped configuration for a selected grid slot.
function GU.GetWeaponConfigDelta(char, itemLink, opts, entry)
    opts = opts or {}
    if not char or not itemLink then return 0, nil end
    local iu = IU()
    if not iu or not iu.GetWeaponRole then return 0, nil end
    local itemRole = iu.GetWeaponRole(itemLink)
    if not itemRole or itemRole == "ranged" then return 0, nil end

    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local compareSlot = resolveWeaponCompareSlot(opts)
    local mh = getEquippedLink(char, MAIN_HAND_SLOT)
    local oh = getEquippedLink(char, OFF_HAND_SLOT)
    local memoKey = charKeyFromChar(char, entry) .. "\0" .. tostring(itemLink)
        .. "\0" .. technique .. "\0" .. tostring(compareSlot or "auto")
        .. "\0" .. tostring(mh or "") .. "\0" .. tostring(oh or "")
        .. "\0" .. storedItemsFingerprint(char)
    local cached = weaponConfigMemo[memoKey]
    if cached then
        return cached.delta, cached.info
    end

    local result
    if compareSlot then
        result = GU.BuildSelectionLoadoutCompare(char, itemLink, compareSlot, opts, entry)
    else
        result = bestSelectionCompareAcrossSlots(char, itemLink, opts, entry)
        compareSlot = result and result.compareSlot
    end
    if not result then return 0, nil end
    local delta = result.delta or 0
    local info = selectionInfoFromCompare(result, compareSlot)
    weaponConfigMemo[memoKey] = { delta = delta, info = info }
    return delta, info
end

--- Item links for each side of a weapon loadout stat/compare breakdown.
function GU.GetWeaponLoadoutCompareLinks(char, focusedLink, opts, entry)
    if not char or not focusedLink or not GU.IsWeaponPairItem(focusedLink) then
        return nil
    end
    local compareSlot = resolveWeaponCompareSlot(opts)
    if not compareSlot then return nil end
    local result = GU.BuildSelectionLoadoutCompare(char, focusedLink, compareSlot, opts, entry)
    if not result then return nil end
    return {
        candidateLinks = result.candidateLinks,
        equippedLinks = result.equippedLinks,
        selection = result,
    }
end

local function linksReferToSameItem(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local idA = tonumber(a:match("item:(%d+)"))
    local idB = tonumber(b:match("item:(%d+)"))
    return idA and idB and idA == idB
end

local function weaponLoadoutStorageLocation(bagID)
    local DS = AltArmy.DataStore
    bagID = tonumber(bagID)
    if not bagID then return "bag" end
    local bankContainer = (DS and DS.BANK_CONTAINER) or -1
    local minBank = (DS and DS.MIN_BANK_BAG_ID) or 5
    local maxBank = (DS and DS.MAX_BANK_BAG_ID) or 11
    if bagID == bankContainer or (bagID >= minBank and bagID <= maxBank) then
        return "bank"
    end
    return "bag"
end

--- True when link is equipped in main-hand or off-hand.
function GU.IsWeaponLoadoutItemEquipped(char, link)
    if not char or not link then return false end
    for _, slot in ipairs({ MAIN_HAND_SLOT, OFF_HAND_SLOT }) do
        if linksReferToSameItem(getEquippedLink(char, slot), link) then
            return true
        end
    end
    return false
end

--- Bag/bank location for a stored item link (nil if not in last container scan).
function GU.FindWeaponLoadoutItemStorage(char, link)
    if not char or not link then return nil end
    local targetId = tonumber(link:match("item:(%d+)"))
    local DS = AltArmy.DataStore

    if DS and DS.IterateContainerSlots then
        local found
        DS:IterateContainerSlots(char, function(bagID, slot, itemID, _count, bagLink)
            if linksReferToSameItem(bagLink, link)
                or (targetId and itemID == targetId) then
                found = {
                    location = weaponLoadoutStorageLocation(bagID),
                    bagID = tonumber(bagID),
                    slot = slot,
                }
                return true
            end
            return false
        end)
        if found then return found end
    end

    local containers = char.Containers
    if not containers then return nil end
    for bagID, bag in pairs(containers) do
        local links = bag and bag.links
        if links then
            for slot, bagLink in pairs(links) do
                if linksReferToSameItem(bagLink, link) then
                    return {
                        location = weaponLoadoutStorageLocation(bagID),
                        bagID = tonumber(bagID),
                        slot = slot,
                    }
                end
            end
        end
    end
    return nil
end

--- Tooltip text for a non-equipped loadout item inferred from bags/bank/mail.
function GU.FormatDeducedWeaponLoadoutHint(link, char)
    if not link then return nil end
    local itemName = "This item"
    if GetItemInfo then
        local name = GetItemInfo(link)
        if name and name ~= "" then
            itemName = name
        end
    end
    local charName = formatCompareCharName(char and char.name, char and char.classFile)
    return string.format(
        "%s is the best item we could find among %s's items, to improve the comparison against a 2-hander",
        itemName,
        charName)
end

local function deducedLoadoutHintForLink(link, focusedLink, char)
    if linksReferToSameItem(link, focusedLink) then return nil end
    if GU.IsWeaponLoadoutItemEquipped(char, link) then return nil end
    return GU.FormatDeducedWeaponLoadoutHint(link, char)
end

--- Item links for compare header when a weapon loadout spans multiple slots.
--- Returns nil when only one item per side (no extra icons needed).
function GU.BuildWeaponLoadoutHeaderLinks(focusedLink, char, opts, entry)
    if not focusedLink or not char or not GU.IsWeaponPairItem(focusedLink) then
        return nil
    end
    local compareSlot = resolveWeaponCompareSlot(opts)
    if not compareSlot then return nil end
    local result = GU.BuildSelectionLoadoutCompare(char, focusedLink, compareSlot, opts, entry)
    if not result then return nil end

    local focusedLinks = result.candidateLinks or {}
    local equippedLinks = result.equippedLinks or {}
    if #focusedLinks <= 1 and #equippedLinks <= 1 then
        return nil
    end

    local focusedHints = {}
    local equippedHints = {}
    for i = 1, #focusedLinks do
        local link = focusedLinks[i]
        if linksReferToSameItem(link, focusedLink) then
            focusedHints[i] = nil
        else
            for _, deduced in ipairs(result.deducedLinks or {}) do
                if deduced.side == "candidate" and linksReferToSameItem(deduced.link, link) then
                    focusedHints[i] = deducedLoadoutHintForLink(
                        link, focusedLink, char)
                    break
                end
            end
        end
    end
    for i = 1, #equippedLinks do
        local link = equippedLinks[i]
        local hint
        for _, deduced in ipairs(result.deducedLinks or {}) do
            if deduced.side == "equipped" and linksReferToSameItem(deduced.link, link) then
                hint = deducedLoadoutHintForLink(link, focusedLink, char)
                break
            end
        end
        equippedHints[i] = hint
    end
    return {
        focusedLinks = focusedLinks,
        equippedLinks = equippedLinks,
        focusedHints = focusedHints,
        equippedHints = equippedHints,
    }
end

local function focusOptsForSlot(opts, invSlot)
    local compareOpts = {}
    for k, v in pairs(opts or {}) do
        compareOpts[k] = v
    end
    compareOpts.compareSlot = invSlot
    return compareOpts
end

--- Signed focus delta for one slot (loadout-aware for weapon pairs).
function GU.GetFocusSlotDelta(charData, itemLink, invSlot, opts, entry)
    opts = opts or {}
    if not charData or not itemLink or not invSlot then return 0 end
    if GU.IsWeaponPairItem(itemLink) then
        local delta = GU.GetWeaponConfigDelta(
            charData, itemLink, focusOptsForSlot(opts, invSlot), entry)
        return delta or 0
    end
    return GU.GetSlotCompareDelta(charData, itemLink, invSlot, opts, entry)
end

local function upgradeDeltaInSlots(char, newLink, technique, slots, entry)
    local DS = AltArmy.DataStore
    if not DS or not DS.GetInventoryItem then return 0 end
    if GU.IsWeaponPairItem(newLink) then
        local bestDelta = 0
        for _, slot in ipairs({ MAIN_HAND_SLOT, OFF_HAND_SLOT }) do
            local delta = GU.GetWeaponConfigDelta(
                char, newLink, { technique = technique, compareSlot = slot }, entry) or 0
            if delta > bestDelta then
                bestDelta = delta
            end
        end
        return bestDelta
    end
    local classFile, specKey = resolveCompareContext(char, entry)
    local newScore = scoreItem(newLink, technique, classFile, specKey)

    local bestDelta = 0
    local hasEquipped = false
    local opts = { technique = technique }
    for i = 1, #slots do
        local slot = slots[i]
        local equipped = DS:GetInventoryItem(char, slot)
        if resolveItemLink(equipped) then
            hasEquipped = true
            local delta = GU.GetSlotCompareDelta(char, newLink, slot, opts, entry)
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

--- Upgrade delta for one inventory slot (focused item vs equipped item in that slot).
function GU.GetSlotUpgradeDelta(char, itemLink, invSlot, opts, entry)
    opts = opts or {}
    if not char or not itemLink or not invSlot then return 0 end
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    return upgradeDeltaInSlots(char, itemLink, technique, { invSlot }, entry)
end

GU.FOCUS_CATEGORY = {
    NEVER = 1,
    UPGRADE_IN_RANGE = 2,
    UPGRADE_BEYOND = 3,
    SIDEGRADE_IN_RANGE = 4,
    SIDEGRADE_BEYOND = 5,
    DOWNGRADE = 6,
}

local FOCUS_CATEGORY_SORT_TIER = {
    [GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE] = 1,
    [GU.FOCUS_CATEGORY.UPGRADE_BEYOND] = 2,
    [GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE] = 3,
    [GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND] = 4,
    [GU.FOCUS_CATEGORY.NEVER] = 5,
    [GU.FOCUS_CATEGORY.DOWNGRADE] = 6,
}

local FOCUS_CATEGORY_DIMMED = {
    [GU.FOCUS_CATEGORY.NEVER] = true,
    [GU.FOCUS_CATEGORY.UPGRADE_BEYOND] = true,
    [GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND] = true,
    [GU.FOCUS_CATEGORY.DOWNGRADE] = true,
}

local FOCUS_CATEGORY_BADGE = {
    [GU.FOCUS_CATEGORY.NEVER] = "unusable",
    [GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE] = "upgrade",
    [GU.FOCUS_CATEGORY.UPGRADE_BEYOND] = "upgradeFuture",
    [GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE] = "sidegrade",
    [GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND] = "sidegradeFuture",
    [GU.FOCUS_CATEGORY.DOWNGRADE] = "unusable",
}

local FOCUS_VERDICT = {
    [GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE] = { label = "Upgrade", r = 0.2, g = 1, b = 0.2 },
    [GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE] = { label = "Sidegrade", r = 0.9, g = 0.78, b = 0.12 },
    [GU.FOCUS_CATEGORY.UPGRADE_BEYOND] = { label = "Eventual upgrade", r = 1, g = 1, b = 1 },
    [GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND] = { label = "Eventual sidegrade", r = 1, g = 1, b = 1 },
    [GU.FOCUS_CATEGORY.DOWNGRADE] = { label = "Downgrade", r = 1, g = 0.45, b = 0.2 },
    [GU.FOCUS_CATEGORY.NEVER] = { label = "Unusable", r = 1, g = 0.45, b = 0.2 },
}

local function focusSortTierForCategory(category)
    if not category then return 5 end
    return FOCUS_CATEGORY_SORT_TIER[category] or 5
end

--- clear (+) vs minor (~) among positive upgrade deltas.
function GU.GetUpgradeHighlightKind(delta, maxDelta, opts)
    if not delta or delta <= 0 then return nil end
    if not maxDelta or maxDelta <= 0 then return "clear" end
    local ratio = GU.GetUpgradeThresholdRatio(opts)
    if delta >= maxDelta * ratio then return "clear" end
    return "minor"
end

--- Inventory slot used for focus verdict/badges (the selected grid cell).
function GU.ResolveFocusCompareSlot(_charData, _itemLink, invSlot, _opts, _entry)
    return invSlot
end

--- Classify one inventory slot for focus-mode badges and sorting.
function GU.ClassifyFocusSlot(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta)
    opts = opts or {}
    if not entry or not itemLink or not invSlot then return nil end
    local iu = IU()
    if not iu then return nil end
    local classFile = entry.classFile or (charData and charData.classFile) or ""
    if iu.CanNeverUseItem(classFile, itemLink) then
        return {
            category = GU.FOCUS_CATEGORY.NEVER,
            badge = FOCUS_CATEGORY_BADGE[GU.FOCUS_CATEGORY.NEVER],
            delta = 0,
            dimmed = true,
        }
    end

    local level = entry.level or (charData and charData.level) or 0
    local levelsAhead = resolveLevelsAhead(opts.levelsAhead)
    local inRange, _, reason = iu.IsEquippableWithin(classFile, level, itemLink, levelsAhead)

    local rawDelta
    local loadoutOldScore
    if GU.IsWeaponPairItem(itemLink) then
        local slotOpts = focusOptsForSlot(opts, invSlot)
        local configDelta, configInfo = GU.GetWeaponConfigDelta(
            charData, itemLink, slotOpts, entry)
        rawDelta = configDelta or 0
        loadoutOldScore = configInfo and configInfo.currentValue or 0
    else
        rawDelta = GU.GetSlotCompareDelta(charData, itemLink, invSlot, opts, entry)
    end

    if not inRange and reason ~= "level" then
        return {
            category = GU.FOCUS_CATEGORY.NEVER,
            badge = FOCUS_CATEGORY_BADGE[GU.FOCUS_CATEGORY.NEVER],
            delta = 0,
            dimmed = true,
        }
    end

    if rawDelta < 0 then
        local oldScore = loadoutOldScore or 0
        if not loadoutOldScore then
            local DS = AltArmy.DataStore
            if DS and DS.GetInventoryItem then
                local equipped = DS:GetInventoryItem(charData, invSlot)
                local eqLink = resolveItemLink(equipped)
                if eqLink then
                    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
                    local compareClass, specKey = resolveCompareContext(charData, entry)
                    oldScore = scoreItem(eqLink, technique, compareClass, specKey) or 0
                end
            end
        end
        local weightedPercent = GU.GetWeightedChangePercent(rawDelta, oldScore, upgradeMaxDelta)
        local threshold = GU.GetUpgradeThresholdRatio(opts) * 100
        if weightedPercent > -threshold then
            local category = inRange and GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE
                or GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND
            return {
                category = category,
                badge = FOCUS_CATEGORY_BADGE[category],
                delta = rawDelta,
                dimmed = FOCUS_CATEGORY_DIMMED[category] == true,
            }
        end
        return {
            category = GU.FOCUS_CATEGORY.DOWNGRADE,
            badge = FOCUS_CATEGORY_BADGE[GU.FOCUS_CATEGORY.DOWNGRADE],
            delta = rawDelta,
            dimmed = true,
        }
    end

    if rawDelta > 0 then
        local kind = GU.GetUpgradeHighlightKind(rawDelta, upgradeMaxDelta, opts)
        local category
        if kind == "clear" then
            category = inRange and GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE
                or GU.FOCUS_CATEGORY.UPGRADE_BEYOND
        elseif kind == "minor" then
            category = inRange and GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE
                or GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND
        end
        if category then
            return {
                category = category,
                badge = FOCUS_CATEGORY_BADGE[category],
                delta = rawDelta,
                dimmed = FOCUS_CATEGORY_DIMMED[category] == true,
            }
        end
    end

    if rawDelta == 0 then
        if not inRange and reason == "level" then
            return {
                category = GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND,
                badge = FOCUS_CATEGORY_BADGE[GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND],
                delta = 0,
                dimmed = true,
            }
        end
        if inRange then
            return {
                category = GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE,
                badge = FOCUS_CATEGORY_BADGE[GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE],
                delta = 0,
                dimmed = false,
            }
        end
    end

    return nil
end

--- Summarize a character across one or more inventory slots (rings/trinkets use best upgrade).
function GU.SummarizeFocusCharacter(entry, charData, itemLink, slots, opts, upgradeMaxDelta)
    slots = slots or {}
    local bestPositive
    local bestSidegrade
    local hasNever = false
    local worstDowngrade = 0

    for i = 1, #slots do
        local info = GU.ClassifyFocusSlot(
            entry, charData, itemLink, slots[i], opts, upgradeMaxDelta)
        if info then
            if info.category == GU.FOCUS_CATEGORY.NEVER then
                hasNever = true
            elseif info.category == GU.FOCUS_CATEGORY.DOWNGRADE then
                if info.delta < worstDowngrade then
                    worstDowngrade = info.delta
                end
            elseif info.delta and info.delta > 0
                and (not bestPositive or info.delta > bestPositive.delta) then
                bestPositive = info
            elseif info.category == GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE
                or info.category == GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND then
                if not bestSidegrade
                    or focusSortTierForCategory(info.category)
                        < focusSortTierForCategory(bestSidegrade.category) then
                    bestSidegrade = info
                end
            end
        end
    end

    if bestPositive then
        return {
            sortTier = focusSortTierForCategory(bestPositive.category),
            category = bestPositive.category,
            sortDelta = bestPositive.delta,
            dimmed = bestPositive.dimmed,
        }
    end
    if bestSidegrade then
        return {
            sortTier = focusSortTierForCategory(bestSidegrade.category),
            category = bestSidegrade.category,
            sortDelta = 0,
            dimmed = bestSidegrade.dimmed,
        }
    end
    if hasNever then
        return {
            sortTier = 5,
            category = GU.FOCUS_CATEGORY.NEVER,
            sortDelta = 0,
            dimmed = true,
        }
    end
    if worstDowngrade < 0 then
        return {
            sortTier = 5,
            category = GU.FOCUS_CATEGORY.DOWNGRADE,
            sortDelta = math.abs(worstDowngrade),
            dimmed = true,
        }
    end
    return {
        sortTier = 5,
        category = nil,
        sortDelta = 0,
        dimmed = false,
    }
end

function GU.GetFocusInventorySlots(itemLink)
    local iu = IU()
    if not iu or not iu.GetInventorySlotsForItem or not itemLink then return {} end
    return iu.GetInventorySlotsForItem(itemLink) or {}
end

function GU.SummarizeFocusEntry(entry, charData, itemLink, opts, upgradeMaxDelta)
    local slots = GU.GetFocusInventorySlots(itemLink)
    return GU.SummarizeFocusCharacter(entry, charData, itemLink, slots, opts, upgradeMaxDelta)
end

--- Per-cell badge in focus mode.
function GU.GetFocusCellBadgeKind(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta)
    local info = GU.ClassifyFocusSlot(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta)
    return info and info.badge or nil
end

--- Compare-panel verdict for one selected slot; nil when no classification.
function GU.GetFocusVerdictForSlot(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta)
    invSlot = GU.ResolveFocusCompareSlot(charData, itemLink, invSlot, opts, entry)
    if not invSlot then return nil end
    local info = GU.ClassifyFocusSlot(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta)
    if not info or not info.category then return nil end
    local verdict = FOCUS_VERDICT[info.category]
    if not verdict then return nil end
    return {
        label = verdict.label,
        r = verdict.r,
        g = verdict.g,
        b = verdict.b,
    }
end

local FOCUS_CATEGORY_DEBUG = {
    [GU.FOCUS_CATEGORY.NEVER] = "NEVER",
    [GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE] = "UPGRADE_IN_RANGE",
    [GU.FOCUS_CATEGORY.UPGRADE_BEYOND] = "UPGRADE_BEYOND",
    [GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE] = "SIDEGRADE_IN_RANGE",
    [GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND] = "SIDEGRADE_BEYOND",
    [GU.FOCUS_CATEGORY.DOWNGRADE] = "DOWNGRADE",
}

local function focusDebugItemLabel(itemOrLink)
    if itemOrLink == nil then return "(none)" end
    if type(itemOrLink) == "number" then
        local name = GetItemInfo and select(1, GetItemInfo(itemOrLink))
        return string.format("itemID %s (%s)", tostring(itemOrLink), name or "?")
    end
    if type(itemOrLink) == "string" then
        local name = GetItemInfo and select(1, GetItemInfo(itemOrLink))
        if name and name ~= "" then return name end
        local bracket = itemOrLink:match("%[(.-)%]")
        if bracket then return bracket end
        return itemOrLink
    end
    return tostring(itemOrLink)
end

local function focusDebugCategoryName(category)
    if category == nil then return "(nil)" end
    return FOCUS_CATEGORY_DEBUG[category] or tostring(category)
end

--- Diagnostic lines for focus-mode compare selection (verdict / badge path).
function GU.BuildFocusSlotDebugLines(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta, debugCtx)
    debugCtx = debugCtx or {}
    opts = opts or {}
    local lines = {}
    lines[#lines + 1] = "--- Focus compare selection ---"

    local charName = entry and entry.name or "?"
    local realm = entry and entry.realm or "?"
    lines[#lines + 1] = string.format(
        "  Character: %s @ %s (slot %s)",
        tostring(charName),
        tostring(realm),
        tostring(invSlot or "?"))

    if not entry or not itemLink or not invSlot then
        lines[#lines + 1] = "  Missing entry, focused item, or inventory slot."
        return lines
    end

    local classFile, specKey = resolveCompareContext(charData, entry)
    local level = entry.level or (charData and charData.level) or 0
    lines[#lines + 1] = string.format(
        "  Class/level/spec: %s / %s / %s",
        tostring(classFile),
        tostring(level),
        tostring(specKey))

    lines[#lines + 1] = string.format("  Focused item: %s", focusDebugItemLabel(itemLink))

    local DS = AltArmy.DataStore
    local equippedRaw
    if DS and DS.GetInventoryItem and charData then
        equippedRaw = DS:GetInventoryItem(charData, invSlot)
    end
    local eqLink = GU.ResolveItemLink(equippedRaw)
    lines[#lines + 1] = string.format(
        "  Equipped: %s (raw: %s)",
        focusDebugItemLabel(eqLink),
        focusDebugItemLabel(equippedRaw))

    local focusTechnique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local sessionTechnique = debugCtx.sessionTechnique
        and GU.GetEffectiveTechnique(debugCtx.sessionTechnique)
        or nil
    lines[#lines + 1] = string.format("  Verdict/grid technique: %s", tostring(focusTechnique))
    if sessionTechnique and sessionTechnique ~= focusTechnique then
        lines[#lines + 1] = string.format(
            "  Compare panel technique: %s  (MISMATCH — stats use panel, verdict uses grid)",
            tostring(sessionTechnique))
    elseif sessionTechnique then
        lines[#lines + 1] = string.format("  Compare panel technique: %s", tostring(sessionTechnique))
    end

    lines[#lines + 1] = string.format("  levelsAhead: %s", tostring(resolveLevelsAhead(opts.levelsAhead)))
    lines[#lines + 1] = string.format("  upgradeMaxDelta: %s", tostring(upgradeMaxDelta))

    local iu = IU()
    if iu then
        local never = iu.CanNeverUseItem(classFile, itemLink)
        lines[#lines + 1] = string.format("  CanNeverUseItem: %s", tostring(never))
        local levelsAhead = resolveLevelsAhead(opts.levelsAhead)
        local inRange, _, reason = iu.IsEquippableWithin(classFile, level, itemLink, levelsAhead)
        lines[#lines + 1] = string.format(
            "  IsEquippableWithin: inRange=%s reason=%s",
            tostring(inRange),
            tostring(reason or "(none)"))
    end

    if GU.IsWeaponPairItem(itemLink) then
        local slotOpts = focusOptsForSlot(opts, invSlot)
        local loadoutDelta, configInfo = GU.GetWeaponConfigDelta(charData, itemLink, slotOpts, entry)
        if configInfo then
            lines[#lines + 1] = string.format("  Selection compare mode: %s", tostring(configInfo.config))
            lines[#lines + 1] = string.format(
                "  Selection values: equipped=%s candidate=%s delta=%s compareSlot=%s",
                tostring(configInfo.currentValue),
                tostring(configInfo.candidateValue),
                tostring(loadoutDelta),
                tostring(configInfo.targetSlot))
            local selection = configInfo.selection
            if selection then
                for _, deduced in ipairs(selection.deducedLinks or {}) do
                    lines[#lines + 1] = string.format(
                        "  Deduced %s: %s (slot %s)",
                        tostring(deduced.side),
                        focusDebugItemLabel(deduced.link),
                        tostring(deduced.slot))
                end
            end
        end
    end

    local newScoreFocus = GU.ScoreItem(itemLink, focusTechnique, classFile, specKey)
    local oldScoreFocus = eqLink and GU.ScoreItem(eqLink, focusTechnique, classFile, specKey) or 0
    local rawDelta = GU.GetFocusSlotDelta(charData, itemLink, invSlot, opts, entry)
    local slotDelta = GU.GetSlotCompareDelta(charData, itemLink, invSlot, opts, entry)
    lines[#lines + 1] = string.format(
        "  Grid scores: new=%s old=%s delta=%s (slot-only=%s)",
        tostring(newScoreFocus),
        tostring(oldScoreFocus),
        tostring(rawDelta),
        tostring(slotDelta))

    local itemStats = IS()
    if itemStats then
        local focusStats = GU.GetNormalizedItemStats(itemLink)
        lines[#lines + 1] = string.format(
            "  Focused statSource: %s  parsed: %s",
            tostring(itemStats.GetSource and itemStats.GetSource(itemLink) or "?"),
            itemStats.FormatNormalizedForDebug
                and itemStats.FormatNormalizedForDebug(focusStats) or "?")
        if eqLink then
            local eqStats = GU.GetNormalizedItemStats(eqLink)
            lines[#lines + 1] = string.format(
                "  Equipped statSource: %s  parsed: %s",
                tostring(itemStats.GetSource and itemStats.GetSource(eqLink) or "?"),
                itemStats.FormatNormalizedForDebug
                    and itemStats.FormatNormalizedForDebug(eqStats) or "?")
        end
        local focusSource = itemStats.GetSource and itemStats.GetSource(itemLink) or ""
        if focusSource == "tooltip" or focusSource == "none" or focusSource == "pending" then
            local tipLines = itemStats.GetTooltipLines and itemStats.GetTooltipLines(itemLink) or {}
            local maxLines = math.min(#tipLines, 6)
            for i = 1, maxLines do
                lines[#lines + 1] = string.format("  tooltip[%d]: %s", i, tostring(tipLines[i]))
            end
        end
    end

    if sessionTechnique and sessionTechnique ~= focusTechnique then
        local newScoreSession = GU.ScoreItem(itemLink, sessionTechnique, classFile, specKey)
        local oldScoreSession = eqLink and GU.ScoreItem(eqLink, sessionTechnique, classFile, specKey) or 0
        local sessionOpts = { technique = debugCtx.sessionTechnique }
        local sessionDelta = GU.GetSlotCompareDelta(charData, itemLink, invSlot, sessionOpts, entry)
        lines[#lines + 1] = string.format(
            "  Panel scores: new=%s old=%s delta=%s",
            tostring(newScoreSession),
            tostring(oldScoreSession),
            tostring(sessionDelta))
    end

    if rawDelta > 0 then
        local kind = GU.GetUpgradeHighlightKind(rawDelta, upgradeMaxDelta, opts)
        lines[#lines + 1] = string.format("  Upgrade highlight kind: %s", tostring(kind or "(nil)"))
    end

    local info = GU.ClassifyFocusSlot(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta)
    if info then
        lines[#lines + 1] = string.format(
            "  ClassifyFocusSlot: category=%s badge=%s delta=%s dimmed=%s",
            focusDebugCategoryName(info.category),
            tostring(info.badge or "(nil)"),
            tostring(info.delta),
            tostring(info.dimmed))
    else
        lines[#lines + 1] = "  ClassifyFocusSlot: (nil) — no category; verdict hidden"
        if rawDelta == 0 then
            lines[#lines + 1] = "  Hint: grid delta is 0 after compare scoring."
        end
    end

    local verdict = GU.GetFocusVerdictForSlot(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta)
    if verdict then
        lines[#lines + 1] = string.format("  Verdict: %s", tostring(verdict.label))
    else
        lines[#lines + 1] = "  Verdict: (hidden)"
    end

    if debugCtx.equippedCompareLink and debugCtx.equippedCompareLink ~= eqLink then
        lines[#lines + 1] = string.format(
            "  Panel equipped link: %s (differs from grid slot inventory)",
            focusDebugItemLabel(debugCtx.equippedCompareLink))
    end

    return lines
end

function GU.LogFocusSlotDebug(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta, debugCtx)
    local D = AltArmy.Debug
    if not D or not D.IsItemComparisonEnabled or not D.IsItemComparisonEnabled() then
        return
    end
    local lines = GU.BuildFocusSlotDebugLines(
        entry, charData, itemLink, invSlot, opts, upgradeMaxDelta, debugCtx)
    if #lines > 0 and D.LogItemComparison then
        D.LogItemComparison(lines)
    end
    local itemStats = IS()
    if itemStats and itemStats.LogStatParseDebug then
        itemStats.LogStatParseDebug(itemLink)
        local eqLink = debugCtx and debugCtx.equippedCompareLink
        if eqLink then
            itemStats.LogStatParseDebug(eqLink)
        end
    end
end

function GU.GetFocusColumnDimmed(entry, charData, itemLink, opts, upgradeMaxDelta)
    local summary = GU.SummarizeFocusEntry(entry, charData, itemLink, opts, upgradeMaxDelta)
    return summary.dimmed == true
end

--- Upgrade magnitude for one slot in focus mode (positive upgrade delta only).
function GU.GetFocusUpgradeDeltaForSlot(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta)
    local info = GU.ClassifyFocusSlot(entry, charData, itemLink, invSlot, opts, upgradeMaxDelta)
    if not info or not info.delta or info.delta <= 0 then return 0 end
    if info.category == GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE
        or info.category == GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE
        or info.category == GU.FOCUS_CATEGORY.UPGRADE_BEYOND
        or info.category == GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND then
        return info.delta
    end
    return 0
end

--- True when any character has upgrade, eventual upgrade, or in-range sidegrade.
function GU.HasAnyFocusUpgradeOrEventual(list, itemLink, opts)
    if not list or not itemLink or #list == 0 then return false end
    local slots = GU.GetFocusInventorySlots(itemLink)
    if #slots == 0 then return false end
    opts = opts or {}
    local DS = AltArmy.DataStore
    local upgradeMaxDelta
    for i = 1, #list do
        local e = list[i]
        local charData = DS and DS.GetCharacter and DS:GetCharacter(e.name, e.realm)
        if GU.IsWeaponPairItem(itemLink) then
            for _, slot in ipairs({ MAIN_HAND_SLOT, OFF_HAND_SLOT }) do
                local slotOpts = focusOptsForSlot(opts, slot)
                local delta = GU.GetWeaponConfigDelta(charData, itemLink, slotOpts, e) or 0
                if delta > 0 and (not upgradeMaxDelta or delta > upgradeMaxDelta) then
                    upgradeMaxDelta = delta
                end
            end
        else
            for s = 1, #slots do
                local delta = GU.GetSlotCompareDelta(charData, itemLink, slots[s], opts, e) or 0
                if delta > 0 and (not upgradeMaxDelta or delta > upgradeMaxDelta) then
                    upgradeMaxDelta = delta
                end
            end
        end
    end
    local compareCategories = {
        [GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE] = true,
        [GU.FOCUS_CATEGORY.UPGRADE_BEYOND] = true,
        [GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE] = true,
    }
    for i = 1, #list do
        local e = list[i]
        local charData = DS and DS.GetCharacter and DS:GetCharacter(e.name, e.realm)
        for s = 1, #slots do
            local info = GU.ClassifyFocusSlot(
                e, charData, itemLink, slots[s], opts, upgradeMaxDelta)
            if info and compareCategories[info.category] then
                return true
            end
        end
    end
    return false
end

local function charMatchesRealm(_char, realm, _name, realmFilter, currentRealm)
    if realmFilter == "currentRealm" and currentRealm and realm ~= currentRealm then
        return false
    end
    return true
end

--- Max positive slot delta across entries (gear tab focus comparison).
function GU.ComputeUpgradeMaxDeltaForEntries(entries, itemLink, opts)
    if not entries or not itemLink then return nil end
    local slots = GU.GetFocusInventorySlots(itemLink)
    if #slots == 0 then return nil end
    opts = opts or {}
    local DS = AltArmy.DataStore
    local upgradeMaxDelta
    for i = 1, #entries do
        local e = entries[i]
        local charData = e.charData
            or (DS and DS.GetCharacter and DS:GetCharacter(e.name, e.realm))
        if GU.IsWeaponPairItem(itemLink) then
            for _, slot in ipairs({ MAIN_HAND_SLOT, OFF_HAND_SLOT }) do
                local slotOpts = focusOptsForSlot(opts, slot)
                local delta = GU.GetWeaponConfigDelta(charData, itemLink, slotOpts, e) or 0
                if delta > 0 and (not upgradeMaxDelta or delta > upgradeMaxDelta) then
                    upgradeMaxDelta = delta
                end
            end
        else
            for s = 1, #slots do
                local delta = GU.GetSlotCompareDelta(charData, itemLink, slots[s], opts, e) or 0
                if delta > 0 and (not upgradeMaxDelta or delta > upgradeMaxDelta) then
                    upgradeMaxDelta = delta
                end
            end
        end
    end
    return upgradeMaxDelta
end

--- True when any slot is classified as UPGRADE_IN_RANGE (gear tab green upgrade badge).
function GU.HasFocusUpgradeInRange(entry, charData, itemLink, opts, upgradeMaxDelta)
    local slots = GU.GetFocusInventorySlots(itemLink)
    if #slots == 0 then return false end
    for i = 1, #slots do
        local info = GU.ClassifyFocusSlot(entry, charData, itemLink, slots[i], opts, upgradeMaxDelta)
        if info and info.category == GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE then
            return true
        end
    end
    return false
end

function GU.EvaluateForAllAlts(itemLink, opts)
    opts = opts or {}
    local DS = AltArmy.DataStore
    if not DS or not DS.ForEachCharacter or not itemLink then return {} end
    local slots = GU.GetFocusInventorySlots(itemLink)
    if #slots == 0 then return {} end

    -- Loot upgrade alerts only compare alts on the current realm (ignore GlobalRealmFilter).
    local realmFilter = "currentRealm"
    local currentRealm = DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm() or ""

    local entries = {}
    DS:ForEachCharacter(function(realm, charName, charData)
        if not charMatchesRealm(charData, realm, charName, realmFilter, currentRealm) then
            return
        end
        local BA = AltArmy.BankAlt
        if BA and BA.Is and BA.Is(charData.name or charName, realm) then
            return
        end
        local classFile = charData.classFile or ""
        local level = (DS.GetCharacterLevel and DS:GetCharacterLevel(charData))
            or tonumber(charData.level) or 0
        entries[#entries + 1] = {
            name = charData.name or charName,
            realm = realm,
            classFile = classFile,
            level = level,
            charData = charData,
        }
    end)

    local upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForEntries(entries, itemLink, opts)
    local matches = {}
    for i = 1, #entries do
        local e = entries[i]
        if GU.HasFocusUpgradeInRange(e, e.charData, itemLink, opts, upgradeMaxDelta) then
            local equippableNow = e.level >= (IU().EffectiveRequiredLevel(e.classFile, itemLink) or 999)
            matches[#matches + 1] = {
                name = e.name,
                realm = e.realm,
                classFile = e.classFile,
                level = e.level,
                charData = e.charData,
                isUpgrade = true,
                equippableNow = equippableNow,
            }
        end
    end
    if #matches > 1 and GU.CompareFocusEntries then
        table.sort(matches, function(a, b)
            return GU.CompareFocusEntries(
                a, b, a.charData, b.charData, itemLink, opts, upgradeMaxDelta)
        end)
    end
    return matches
end

--- Evaluate upgrade for a single character (level-up scan, focus mode).
--- opts.level — evaluate as if the character were this level (level-up notifications).
function GU.EvaluateForCharacter(char, itemLink, opts)
    opts = opts or {}
    if not char or not itemLink then return false end
    local slots = GU.GetFocusInventorySlots(itemLink)
    if #slots == 0 then return false end
    local DS = AltArmy.DataStore
    local level = opts.level
    if level == nil then
        level = (DS and DS.GetCharacterLevel and DS:GetCharacterLevel(char))
            or tonumber(char.level) or 0
    else
        level = math.floor(tonumber(level) or 0)
    end
    local entry = {
        name = char.name,
        realm = char.realm,
        classFile = char.classFile or "",
        level = level,
    }
    local entries = { {
        name = entry.name,
        realm = entry.realm,
        classFile = entry.classFile,
        level = entry.level,
        charData = char,
    } }
    local upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForEntries(entries, itemLink, opts)
    return GU.HasFocusUpgradeInRange(entry, char, itemLink, opts, upgradeMaxDelta)
end

--- Raw upgrade magnitude for one character (technique-specific score delta).
function GU.GetCharacterUpgradeDelta(char, itemLink, opts, entry)
    opts = opts or {}
    if not char or not itemLink then return 0 end
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local slots = IU() and IU().GetInventorySlotsForItem(itemLink) or {}
    if #slots == 0 then return 0 end
    return upgradeDeltaInSlots(char, itemLink, technique, slots, entry)
end

--- Upgrade magnitude for focus-mode sort (best positive delta across item slots).
function GU.GetFocusUpgradeDelta(entry, charData, itemLink, opts, upgradeMaxDelta)
    local summary = GU.SummarizeFocusEntry(entry, charData, itemLink, opts, upgradeMaxDelta)
    return summary.sortDelta or 0
end

local FOCUS_COMPARE_SORT_TIER = {
    [GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE] = 1,
    [GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE] = 2,
    [GU.FOCUS_CATEGORY.UPGRADE_BEYOND] = 3,
    [GU.FOCUS_CATEGORY.SIDEGRADE_BEYOND] = 4,
    [GU.FOCUS_CATEGORY.DOWNGRADE] = 5,
    [GU.FOCUS_CATEGORY.NEVER] = 6,
}

local function focusCompareSortTierForCategory(category)
    if not category then return 6 end
    return FOCUS_COMPARE_SORT_TIER[category] or 6
end

--- Display-list sort tier: upgrade, sidegrade, eventual upgrade, eventual sidegrade, downgrade, unusable.
function GU.GetFocusCompareSortTier(entry, charData, itemLink, opts, upgradeMaxDelta)
    local summary = GU.SummarizeFocusEntry(entry, charData, itemLink, opts, upgradeMaxDelta)
    return focusCompareSortTierForCategory(summary and summary.category)
end

function GU.IsMaxLevelCharacter(entry, charData)
    local DS = AltArmy.DataStore
    local maxLevel = (DS and DS.MAX_LEVEL) or 70
    local level = entry and entry.level or (charData and charData.level) or 0
    if DS and DS.GetCharacterLevel and charData then
        level = DS:GetCharacterLevel(charData) or level
    end
    return math.floor(tonumber(level) or 0) >= maxLevel
end

function GU.GetLevelsUntilEquippable(entry, charData, itemLink)
    local iu = IU()
    if not iu or not itemLink then return 999 end
    local classFile = entry and entry.classFile or (charData and charData.classFile) or ""
    local level = entry and entry.level or (charData and charData.level) or 0
    local DS = AltArmy.DataStore
    if DS and DS.GetCharacterLevel and charData then
        level = DS:GetCharacterLevel(charData) or level
    end
    local effective = iu.EffectiveRequiredLevel(classFile, itemLink) or 999
    if effective >= 999 then return 999 end
    level = math.floor(tonumber(level) or 0)
    if level >= effective then return 0 end
    return effective - level
end

--- Upgrade size as a percent of the best positive delta in the comparison grid.
function GU.GetFocusUpgradePercent(entry, charData, itemLink, opts, upgradeMaxDelta)
    local delta = GU.GetFocusUpgradeDelta(entry, charData, itemLink, opts, upgradeMaxDelta) or 0
    if delta <= 0 or not upgradeMaxDelta or upgradeMaxDelta <= 0 then return 0 end
    return delta / upgradeMaxDelta * 100
end

--- True when entry a should appear before entry b in the focus comparison column list.
function GU.CompareFocusEntries(a, b, charA, charB, itemLink, opts, upgradeMaxDelta)
    local ta = GU.GetFocusCompareSortTier(a, charA, itemLink, opts, upgradeMaxDelta)
    local tb = GU.GetFocusCompareSortTier(b, charB, itemLink, opts, upgradeMaxDelta)
    if ta ~= tb then return ta < tb end

    local maxA = GU.IsMaxLevelCharacter(a, charA)
    local maxB = GU.IsMaxLevelCharacter(b, charB)
    if maxA ~= maxB then return not maxA end

    local pa = GU.GetFocusUpgradePercent(a, charA, itemLink, opts, upgradeMaxDelta)
    local pb = GU.GetFocusUpgradePercent(b, charB, itemLink, opts, upgradeMaxDelta)
    if pa ~= pb then return pa > pb end

    local la = GU.GetLevelsUntilEquippable(a, charA, itemLink)
    local lb = GU.GetLevelsUntilEquippable(b, charB, itemLink)
    if la ~= lb then return la < lb end

    return (a.name or "") < (b.name or "")
end

--- Sort tier for focus-mode column sort (1=best … 5=never/downgrade/neutral).
function GU.GetFocusTier(entry, charData, itemLink, opts, upgradeMaxDelta)
    local summary = GU.SummarizeFocusEntry(entry, charData, itemLink, opts, upgradeMaxDelta)
    return summary.sortTier or 5
end

function GU.EnsureGearUpgradeOptions()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    local root = _G.AltArmyTBC_Options
    root.gearUpgrades = root.gearUpgrades or {}
    local gu = root.gearUpgrades
    if gu.notifyCurrentCharacter == nil and gu.notifyOtherCharacters == nil then
        local legacy = gu.enabled
        if legacy == nil then legacy = true end
        gu.notifyCurrentCharacter = legacy
        gu.notifyOtherCharacters = legacy
    end
    if gu.notifyCurrentCharacter == nil then gu.notifyCurrentCharacter = true end
    if gu.notifyOtherCharacters == nil then gu.notifyOtherCharacters = true end
    gu.technique = "custom"
    gu.levelsAhead = resolveLevelsAhead(gu.levelsAhead)
    gu.upgradeThresholdPercent = GU.ResolveUpgradeThresholdPercent(gu.upgradeThresholdPercent)
    return gu
end

function GU.GetOptions()
    return GU.EnsureGearUpgradeOptions()
end
