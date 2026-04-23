-- AltArmy TBC — Summary data layer: character list for the Summary tab.
-- Summary list entries (SavedVariables / DataStore): name, realm, level, restXp, isMaxLevel,
-- money, played, lastOnline.
-- luacheck: globals GetSpellInfo

AltArmy.SummaryData = AltArmy.SummaryData or {}

local MAX_LOGOUT_SENTINEL = 5000000000
local MAX_LEVEL = (AltArmy.DataStore and AltArmy.DataStore.MAX_LEVEL) or 70

-- Formatting helpers (raw values in entry; format in UI or here for display)

-- Coin icon texture escape sequences (game's gold/silver/copper icons); size 12 to match small font
local COIN_ICON_SIZE = 12
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:" .. COIN_ICON_SIZE .. ":" .. COIN_ICON_SIZE .. "|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:" .. COIN_ICON_SIZE .. ":" .. COIN_ICON_SIZE .. "|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:" .. COIN_ICON_SIZE .. ":" .. COIN_ICON_SIZE .. "|t"

--- Copper to amount + gold/silver/copper icons. Skips leading zeros; shows zeros once a significant digit appears.
function AltArmy.SummaryData.GetMoneyString(copper)
    copper = copper or 0
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRem = copper % 100
    local parts = {}
    if gold > 0 then
        table.insert(parts, gold .. GOLD_ICON)
        table.insert(parts, silver .. SILVER_ICON)
        table.insert(parts, copperRem .. COPPER_ICON)
    elseif silver > 0 then
        table.insert(parts, silver .. SILVER_ICON)
        table.insert(parts, copperRem .. COPPER_ICON)
    else
        table.insert(parts, copperRem .. COPPER_ICON)
    end
    return table.concat(parts, " ")
end

--- Seconds to readable string (e.g. "2d 3h"). Uses SecondsToTime if available.
function AltArmy.SummaryData.GetTimeString(seconds)
    seconds = seconds or 0
    if SecondsToTime then
        return SecondsToTime(seconds)
    end
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local parts = {}
    if d > 0 then table.insert(parts, d .. "d") end
    if h > 0 then table.insert(parts, h .. "h") end
    if m > 0 or #parts == 0 then table.insert(parts, m .. "m") end
    return table.concat(parts, " ")
end

--- Last online: timestamp (number), nil = current/Online, MAX_LOGOUT_SENTINEL = unknown.
--- isCurrent: true if this is the logged-in character. Never shows seconds (days/hours/minutes only).
function AltArmy.SummaryData.FormatLastOnline(lastLogout, isCurrent)
    if isCurrent then
        return "Online"
    end
    if not lastLogout or lastLogout >= MAX_LOGOUT_SENTINEL then
        return "Unknown"
    end
    local ago = time() - lastLogout
    if ago < 60 then
        return "Just now"
    end
    local d = math.floor(ago / 86400)
    local h = math.floor((ago % 86400) / 3600)
    local m = math.floor((ago % 3600) / 60)
    if d > 0 then return d .. "d ago" end
    if h > 0 then return h .. "h ago" end
    return m .. "m ago"
end

--- Build rest XP display: rate is 0-100 (or 0-150). Round to nearest 0.1, show one decimal (e.g. "50.3%").
function AltArmy.SummaryData.FormatRestXp(rate)
    if rate == nil then return "" end
    local rounded = math.floor(rate * 10 + 0.5) / 10
    return string.format("%.1f%%", rounded)
end

-- Returns a list of character entries: { name, realm, level, restXp, isMaxLevel, money, played, lastOnline }
-- Raw values (copper, seconds, timestamp); formatting in UI.
function AltArmy.SummaryData.GetCharacterList()
    local list = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.GetRealms or not DS.GetCharacters then
        return list
    end

    local currentRealm = GetRealmName and GetRealmName() or ""
    local currentName = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""

    for realm in pairs(DS:GetRealms()) do
        for charName, charData in pairs(DS:GetCharacters(realm)) do
            local name = DS:GetCharacterName(charData) or charName
            local isCurrent = (name == currentName and realm == currentRealm)
            local level = DS:GetCharacterLevel(charData) or 0
            -- Fractional level (level + xp progress) for display with one decimal, rounded down
            local xp = isCurrent and (UnitXP and UnitXP("player")) or charData.xp
            local xpMax = isCurrent and (UnitXPMax and UnitXPMax("player")) or charData.xpMax
            if xp and xpMax and xpMax > 0 then
                level = level + xp / xpMax
            end
            local money = DS:GetMoney(charData) or 0
            if DS.GetMailMoneyTotal then
                money = money + (DS:GetMailMoneyTotal(charData) or 0)
            end
            local played = DS:GetPlayTime(charData) or 0
            local lastLogout = DS:GetLastLogout(charData) or MAX_LOGOUT_SENTINEL
            local classLoc, classFile = DS:GetCharacterClass(charData)
            local isMaxLevel = math.floor(level) == MAX_LEVEL
            local restRate
            if isMaxLevel then
                restRate = 0
            elseif isCurrent and UnitXPMax and GetXPExhaustion then
                local playerXpMax = UnitXPMax("player") or 0
                local restXP = GetXPExhaustion() or 0
                if playerXpMax <= 0 then
                    restRate = 0
                else
                    local maxRest = playerXpMax * 1.5
                    restRate = math.min(100, (restXP / maxRest) * 100)
                end
            else
                restRate = (DS.GetRestXp and DS:GetRestXp(charData)) or 0
            end
            local bagSlots = (DS.GetNumBagSlots and DS:GetNumBagSlots(charData)) or 0
            local bagFree = (DS.GetNumFreeBagSlots and DS:GetNumFreeBagSlots(charData)) or 0
            local equipmentCount = 0
            if charData.Inventory then
                for _ in pairs(charData.Inventory) do
                    equipmentCount = equipmentCount + 1
                end
            end
            local avgItemLevel = (DS.GetAverageItemLevel and DS:GetAverageItemLevel(charData)) or 0
            table.insert(list, {
                name = name,
                realm = realm or "",
                level = level,
                restXp = restRate,
                isMaxLevel = isMaxLevel,
                money = money,
                played = played,
                lastOnline = isCurrent and nil or lastLogout,
                class = classLoc or "",
                classFile = classFile or "",
                bagSlots = bagSlots,
                bagFree = bagFree,
                equipmentCount = equipmentCount,
                avgItemLevel = avgItemLevel,
            })
        end
    end
    return list
end

-- Module name -> instruction when that module's data has not been gathered
-- (mail, auctions excluded: do not warn for mailbox or auction house)
local MODULE_INSTRUCTIONS = {
    containers = "* Open your bags or visit a bank",
    equipment = "* Log in with this character",
    professions = "* Open your Skills window (P)",
    reputations = "* Open your Reputation panel",
    currencies = "* Open your bags or visit a bank",
}

-- Professions we do not warn about (gathering/secondary; no "Open your X window")
local PROFESSIONS_NO_WARNING = {
    Fishing = true,
    Riding = true,
    Herbalism = true,
    Mining = true,
    Skinning = true,
}

local function charHasLegacyReputationScalars(char)
    if not char or not char.Reputations then return false end
    for _, v in pairs(char.Reputations) do
        if type(v) == "number" then return true end
    end
    return false
end

-- Profession spell IDs (TBC) — localized skill names from GetSpellInfo match DataStore Professions keys.
local SPELL_ID_ALCHEMY = 2259
local SPELL_ID_TAILORING = 3908
local COOLDOWN_SPEC_SCAN_MIN_LEVEL = 60
local COOLDOWN_SPEC_SCAN_MIN_PROF_RANK = 350

--- True after DataStoreProfessions:ScanCooldownSpecializations has written boolean flags (even if all false).
local function hasPersistedCooldownSpecializations(char)
    local cs = char and char.cooldownSpecs
    if type(cs) ~= "table" then
        return false
    end
    return rawget(cs, "masterTransmutation") ~= nil
end

local function tailoringOrAlchemyAtLeastRank(char, minRank)
    local gsi = _G.GetSpellInfo
    if type(gsi) ~= "function" or not char or not char.Professions then
        return false
    end
    local profs = char.Professions
    local alchName = gsi(SPELL_ID_ALCHEMY)
    local tailorName = gsi(SPELL_ID_TAILORING)
    local alchR = (alchName and profs[alchName] and profs[alchName].rank) or 0
    local tailR = (tailorName and profs[tailorName] and profs[tailorName].rank) or 0
    return alchR >= minRank or tailR >= minRank
end

--- High-level toons with tailoring or alchemy may be missing cooldown specialization flags until login scan runs.
local function needsCooldownSpecializationScan(char, DS)
    if hasPersistedCooldownSpecializations(char) then
        return false
    end
    local level = 0
    if DS and DS.GetCharacterLevel then
        level = tonumber(DS:GetCharacterLevel(char)) or 0
    elseif char and char.level then
        level = tonumber(char.level) or 0
    end
    if math.floor(level) < COOLDOWN_SPEC_SCAN_MIN_LEVEL then
        return false
    end
    return tailoringOrAlchemyAtLeastRank(char, COOLDOWN_SPEC_SCAN_MIN_PROF_RANK)
end

--- Returns whether a character is missing any gathered data and a list of instructions for the tooltip.
--- @param name string Character name
--- @param realm string Realm name
--- @return table { hasMissing = boolean, instructions = string[] }
function AltArmy.SummaryData.GetMissingDataInfo(name, realm)
    local out = { hasMissing = false, instructions = {} }
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCharacter then return out end
    local char = DS:GetCharacter(name, realm)
    if not char then return out end

    local currentName = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""
    local currentRealm = GetRealmName and GetRealmName() or ""
    local isCurrent = (name == currentName and realm == currentRealm)
    local addedLoginInstruction = false

    for moduleName, instruction in pairs(MODULE_INSTRUCTIONS) do
        if not (DS.HasModuleData and DS:HasModuleData(char, moduleName)) then
            if isCurrent then
                table.insert(out.instructions, instruction)
            elseif not addedLoginInstruction then
                table.insert(out.instructions, "* Log in with this character")
                addedLoginInstruction = true
            end
        end
    end

    -- Reputation: stale data version and/or legacy scalar storage (pre-v2 snapshot rows)
    if DS.HasModuleData and DS:HasModuleData(char, "reputations") then
        local staleVersion = DS.NeedsRescan and DS:NeedsRescan(char, "reputations")
        local legacyScalars = charHasLegacyReputationScalars(char)
        if staleVersion or legacyScalars then
            if isCurrent then
                table.insert(out.instructions, "* /reload or log in again to refresh reputation data")
            elseif not addedLoginInstruction then
                table.insert(out.instructions, "* Log in with this character")
            end
        end
    end

    -- Per-profession: if we have profession data but a skill has no recipes, add "Open your X window"
    -- (skip Fishing, Riding, Herbalism, Mining, Skinning)
    if DS.HasModuleData and DS:HasModuleData(char, "professions") and DS.GetProfessions and DS.GetNumRecipes then
        local professions = DS:GetProfessions(char)
        for profName, prof in pairs(professions or {}) do
            if not PROFESSIONS_NO_WARNING[profName] then
                local rank = (prof and prof.rank) or 0
                if rank > 0 and DS:GetNumRecipes(char, profName) == 0 then
                    table.insert(out.instructions, "* Open your " .. profName .. " window")
                end
            end
        end
    end

    -- Cooldown specialization passives (Master of Transmutation, Spellfire, etc.): filled on login scan.
    if needsCooldownSpecializationScan(char, DS) then
        local loginMsg = "* Log in with this character"
        local dup = false
        for _, line in ipairs(out.instructions) do
            if line == loginMsg then
                dup = true
                break
            end
        end
        if not dup then
            table.insert(out.instructions, loginMsg)
        end
    end

    out.hasMissing = #out.instructions > 0
    return out
end

--- Title (with |c-colored name) and instruction lines for the Summary warning tooltip. nil if nothing missing.
--- @param name string
--- @param realm string
--- @param classFile string|nil
--- @return string|nil title, table|nil instructions
function AltArmy.SummaryData.GetMissingDataTooltip(name, realm, classFile)
    local info = AltArmy.SummaryData.GetMissingDataInfo(name, realm)
    if not info or not info.hasMissing then return nil, nil end
    local r, g, b = 1, 0.82, 0
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        r, g, b = c.r, c.g, c.b
    end
    local hex = string.format("|cFF%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    local n = name or ""
    local titlePrefix = "Some data for " .. hex .. n .. "|r"
    local title = titlePrefix .. " has not been gathered yet."
    return title, info.instructions
end

--- Same GameTooltip presentation as the Summary warning column (white title, gold instructions).
--- @return boolean true if a tooltip was shown
function AltArmy.SummaryData.PresentMissingDataTooltip(owner, anchor, name, realm, classFile)
    if not owner or not GameTooltip then return false end
    local title, lines = AltArmy.SummaryData.GetMissingDataTooltip(name, realm, classFile)
    if not title or not lines then return false end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title, 1, 1, 1, true)
    for _, line in ipairs(lines) do
        GameTooltip:AddLine(line, 1, 0.82, 0, true)
    end
    GameTooltip:Show()
    return true
end
