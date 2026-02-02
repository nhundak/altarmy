-- AltArmy TBC — Summary data layer: character list for the Summary tab.
-- Uses internal AltArmy.DataStore (SavedVariables); entry shape: name, realm, level, restXp, money, played, lastOnline.

AltArmy.SummaryData = AltArmy.SummaryData or {}

local MAX_LOGOUT_SENTINEL = 5000000000
local MAX_LEVEL = MAX_PLAYER_LEVEL or 70

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

--- Build rest XP display: rate is 0-100 (or 0-150). Return number for sorting; UI can format as "X%".
function AltArmy.SummaryData.FormatRestXp(rate)
    if rate == nil then return "" end
    return math.floor(rate + 0.5) .. "%"
end

-- Returns a list of character entries: { name, realm, level, restXp, money, played, lastOnline }
-- Raw values (copper, seconds, timestamp); formatting in UI.
function AltArmy.SummaryData.GetCharacterList()
    local list = {}
    local DS = AltArmy.DataStore
    if not DS or not DS.GetRealms or not DS.GetCharacters then
        if AltArmy.DebugLog then
            AltArmy.DebugLog("Character list: DataStore not ready")
        end
        return list
    end

    local currentRealm = GetRealmName and GetRealmName() or ""
    local currentName = (UnitName and UnitName("player")) or (GetUnitName and GetUnitName("player")) or ""

    for realm in pairs(DS:GetRealms()) do
        for charName, charData in pairs(DS:GetCharacters(realm)) do
            local name = DS:GetCharacterName(charData) or charName
            local level = DS:GetCharacterLevel(charData) or 0
            local money = DS:GetMoney(charData) or 0
            local played = DS:GetPlayTime(charData) or 0
            local lastLogout = DS:GetLastLogout(charData) or MAX_LOGOUT_SENTINEL
            local restRate = (DS.GetRestXPRate and DS:GetRestXPRate(charData)) or 0
            if level == MAX_LEVEL then
                restRate = 0
            end
            local classLoc, classFile = DS:GetCharacterClass(charData)
            local isCurrent = (name == currentName and realm == currentRealm)
            table.insert(list, {
                name = name,
                realm = realm or "",
                level = level,
                restXp = restRate,
                money = money,
                played = played,
                lastOnline = isCurrent and nil or lastLogout,
                class = classLoc or "",
                classFile = classFile or "",
            })
        end
    end

    if AltArmy.DebugLog then
        AltArmy.DebugLog("Character list loaded: " .. #list .. " character(s)")
    end
    return list
end
