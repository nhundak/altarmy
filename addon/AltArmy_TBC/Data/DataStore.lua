-- AltArmy TBC — Internal character data store.
-- Persists character data to SavedVariables (AltArmyTBC_Data), shared across all characters on the account.
-- TBC-compatible; no external DataStore dependency.

if not AltArmy then return end

AltArmy.DataStore = AltArmy.DataStore or {}

local DS = AltArmy.DataStore
local MAX_LEVEL = MAX_PLAYER_LEVEL or 70
local MAX_LOGOUT_SENTINEL = 5000000000

-- Ensure SavedVariables structure (runs at load; SV are already loaded)
AltArmyTBC_Data = AltArmyTBC_Data or {}
AltArmyTBC_Data.Characters = AltArmyTBC_Data.Characters or {}

AltArmy.DB = AltArmyTBC_Data

local function GetCurrentName()
    if UnitName then
        local name = UnitName("player")
        if name and name ~= "" then return name end
    end
    return GetUnitName and GetUnitName("player") or ""
end

local function GetCurrentRealm()
    return (GetRealmName and GetRealmName()) or ""
end

--- Get or create the current character's data table.
local function GetCurrentCharTable()
    local realm = GetCurrentRealm()
    local name = GetCurrentName()
    if not realm or not name or name == "" then return nil end
    if not AltArmyTBC_Data.Characters[realm] then
        AltArmyTBC_Data.Characters[realm] = {}
    end
    local char = AltArmyTBC_Data.Characters[realm][name]
    if not char then
        char = {}
        AltArmyTBC_Data.Characters[realm][name] = char
    end
    return char
end

--- Scan current character's basic info (name, realm, class, race, faction, level, money, XP, rest).
local function ScanCharacter()
    local char = GetCurrentCharTable()
    if not char then return end
    char.name = GetCurrentName()
    char.realm = GetCurrentRealm()
    char.level = (UnitLevel and UnitLevel("player")) or 0
    char.money = (GetMoney and GetMoney()) or 0
    char.lastUpdate = time()
    if UnitClass then
        local loc, eng = UnitClass("player")
        char.class = loc
        char.classFile = eng and eng:upper() or ""
    else
        char.class = ""
        char.classFile = ""
    end
    if UnitRace then
        char.race = UnitRace("player") or ""
    else
        char.race = ""
    end
    if UnitFactionGroup then
        char.faction = UnitFactionGroup("player") or ""
    else
        char.faction = ""
    end
    if GetMoney then
        char.money = GetMoney()
    end
    if UnitXP and UnitXPMax then
        char.xp = UnitXP("player") or 0
        char.xpMax = UnitXPMax("player") or 0
    else
        char.xp = 0
        char.xpMax = 0
    end
    if GetXPExhaustion then
        char.restXP = GetXPExhaustion() or 0
    else
        char.restXP = 0
    end
    if char.level == MAX_LEVEL then
        char.restXP = 0
    end
end

--- API: GetRealms() — returns { ["RealmName"] = true, ... }
function DS:GetRealms()
    local out = {}
    for realm in pairs(AltArmyTBC_Data.Characters) do
        out[realm] = true
    end
    return out
end

--- API: GetCharacters(realm) — returns { ["CharName"] = charData, ... }
function DS:GetCharacters(realm)
    if not realm then return {} end
    return AltArmyTBC_Data.Characters[realm] or {}
end

--- API: GetCharacter(name, realm) — returns charData table or nil
function DS:GetCharacter(name, realm)
    if not name or not realm then return nil end
    local realmTable = AltArmyTBC_Data.Characters[realm]
    return realmTable and realmTable[name] or nil
end

--- API: GetCurrentCharacter() — returns current character's data table
function DS:GetCurrentCharacter()
    return GetCurrentCharTable()
end

--- Per-character getters (take charData table)
function DS:GetCharacterName(char)
    return char and char.name or ""
end

function DS:GetCharacterLevel(char)
    return (char and char.level) or 0
end

function DS:GetMoney(char)
    return (char and char.money) or 0
end

function DS:GetPlayTime(char)
    return (char and char.played) or 0
end

function DS:GetLastLogout(char)
    return (char and char.lastLogout) or MAX_LOGOUT_SENTINEL
end

function DS:GetCharacterClass(char)
    if not char then return "", "" end
    return char.class or "", char.classFile or ""
end

function DS:GetCharacterFaction(char)
    return (char and char.faction) or ""
end

--- Stored rest XP rate as percentage (0–100). Simple: restXP / (xpMax * 1.5) * 100.
--- Use this for the raw saved value only; use GetRestXp for "rest now" (predicted).
function DS:GetStoredRestXp(char)
    if not char or char.level == MAX_LEVEL then return 0 end
    local xpMax = char.xpMax or 0
    local restXP = char.restXP or 0
    if xpMax <= 0 then return 0 end
    local maxRest = xpMax * 1.5
    return math.min(100, math.floor((restXP / maxRest) * 100 + 0.5))
end

--- Rest XP rate as percentage (0–100) *now*: predicted for alts, or use saved rate when no lastLogout.
--- Formula: 8 hours rested = 5% of current level; max rest = 150% of level (1.5 levels). Time since
--- last logout earns rest at that rate (assumes character is resting when offline). Adapted from
--- DataStore_Characters (Thaoky). For current character (no lastLogout), returns saved rate.
function DS:GetRestXp(char)
    if not char or char.level == MAX_LEVEL then return 0 end
    local xpMax = char.xpMax or 0
    local restXP = char.restXP or 0
    if xpMax <= 0 then return 0 end
    local maxRest = xpMax * 1.5
    local lastLogout = char.lastLogout or MAX_LOGOUT_SENTINEL
    if lastLogout >= MAX_LOGOUT_SENTINEL then
        return math.min(100, math.floor((restXP / maxRest) * 100 + 0.5))
    end
    local oneXPBubble = xpMax / 20
    local elapsed = time() - lastLogout
    local numXPBubbles = elapsed / 28800
    local xpEarnedResting = numXPBubbles * oneXPBubble
    if xpEarnedResting < 0 then xpEarnedResting = 0 end
    if (restXP + xpEarnedResting) > maxRest then
        xpEarnedResting = maxRest - restXP
    end
    local predictedRestXP = restXP + xpEarnedResting
    local rate = (predictedRestXP / maxRest) * 100
    return math.min(100, math.floor(rate + 0.5))
end

-- Event frame
local frame = CreateFrame("Frame", nil, UIParent)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("TIME_PLAYED_MSG")

local loginFired = false
frame:SetScript("OnEvent", function(_, event, addonName, a1)
    if event == "ADDON_LOADED" and addonName == "AltArmy_TBC" then
        AltArmyTBC_Data.Characters = AltArmyTBC_Data.Characters or {}
        GetCurrentCharTable()
        return
    end
    if event == "PLAYER_LOGIN" then
        if not loginFired and RequestTimePlayed then
            RequestTimePlayed()
            loginFired = true
        end
        return
    end
    if event == "PLAYER_ALIVE" or event == "PLAYER_ENTERING_WORLD" then
        ScanCharacter()
        return
    end
    if event == "PLAYER_LOGOUT" then
        local char = GetCurrentCharTable()
        if char then
            char.lastLogout = time()
            char.lastUpdate = time()
        end
        return
    end
    if event == "PLAYER_MONEY" then
        local char = GetCurrentCharTable()
        if char and GetMoney then
            char.money = GetMoney()
        end
        return
    end
    if event == "PLAYER_XP_UPDATE" then
        local char = GetCurrentCharTable()
        if char then
            if UnitXP and UnitXPMax then
                char.xp = UnitXP("player") or 0
                char.xpMax = UnitXPMax("player") or 0
            end
            if GetXPExhaustion then
                char.restXP = GetXPExhaustion() or 0
            end
            if char.level == MAX_LEVEL then
                char.restXP = 0
            end
        end
        return
    end
    if event == "PLAYER_LEVEL_UP" then
        local char = GetCurrentCharTable()
        if char and UnitLevel then
            char.level = UnitLevel("player")
            if char.level == MAX_LEVEL then
                char.restXP = 0
            end
        end
        return
    end
    if event == "TIME_PLAYED_MSG" then
        local char = GetCurrentCharTable()
        -- First event arg is total time played (seconds)
        if char and addonName and type(addonName) == "number" then
            char.played = addonName
        end
        return
    end
end)
frame:RegisterEvent("PLAYER_LOGIN")
