-- AltArmy TBC — DataStore module: character (name, level, class, money, XP, rest).
-- Requires DataStore.lua (core) loaded first.

if not AltArmy or not AltArmy.DataStore then return end

local DS = AltArmy.DataStore
local GetCurrentCharTable = DS._GetCurrentCharTable
local DATA_VERSIONS = DS._DATA_VERSIONS

local MAX_LEVEL = DS.MAX_LEVEL
local MAX_LOGOUT_SENTINEL = 5000000000

function DS:ScanCharacter(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    char.name = DS:GetCurrentPlayerName()
    char.realm = DS:GetCurrentPlayerRealm()
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
        local raceLoc, raceEng = UnitRace("player")
        char.race = raceLoc or ""
        char.raceFile = raceEng and raceEng:upper() or ""
    else
        char.race = ""
        char.raceFile = ""
    end
    if UnitSex then
        char.sex = UnitSex("player") or 2
    else
        char.sex = 2
    end
    if UnitFactionGroup then
        char.faction = UnitFactionGroup("player") or ""
    else
        char.faction = ""
    end
    -- Guild membership (needed by guild data sharing; nil = not in a guild).
    DS:ScanGuildMembership()
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
    char.dataVersions = char.dataVersions or {}
    char.dataVersions.character = DATA_VERSIONS.character
    if DS.ClaimOrphanLevelHistory then
        DS:ClaimOrphanLevelHistory(char.name, char.realm, char)
    end
end

--- Refresh stored guild membership for the current character (join/leave/promote).
function DS:ScanGuildMembership(_self)
    local char = GetCurrentCharTable()
    if not char then return end
    char.dataVersions = char.dataVersions or {}
    if GetGuildInfo then
        local guildName = GetGuildInfo("player")
        char.guildName = (guildName ~= "" and guildName) or nil
        char.dataVersions.guildMembership = DATA_VERSIONS.guildMembership
    end
    if AltArmy.UpdateGuildTabVisibility then
        AltArmy.UpdateGuildTabVisibility()
    end
end

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
    if not char then return 0 end
    if DS.GetDerivedPlayedTotal then
        local current = GetCurrentCharTable()
        if current and char == current then
            return DS:GetDerivedPlayedTotal()
        end
    end
    return char.played or 0
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

--- Guild name for a character, or nil when the character is not in a guild.
function DS:GetCharacterGuild(char)
    return char and char.guildName or nil
end

function DS:GetStoredRestXp(char)
    if not char or char.level == MAX_LEVEL then return 0 end
    local xpMax = char.xpMax or 0
    local restXP = char.restXP or 0
    if xpMax <= 0 then return 0 end
    local maxRest = xpMax * 1.5
    return math.min(100, (restXP / maxRest) * 100)
end

function DS:GetRestXp(char)
    if not char or char.level == MAX_LEVEL then return 0 end
    local xpMax = char.xpMax or 0
    local restXP = char.restXP or 0
    if xpMax <= 0 then return 0 end
    local maxRest = xpMax * 1.5
    local lastLogout = char.lastLogout or MAX_LOGOUT_SENTINEL
    if lastLogout >= MAX_LOGOUT_SENTINEL then
        return math.min(100, (restXP / maxRest) * 100)
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
    return math.min(100, rate)
end
