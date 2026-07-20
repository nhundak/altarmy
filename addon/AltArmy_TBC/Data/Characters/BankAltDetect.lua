-- AltArmy TBC — Bank alt detection (stagnation + wealth heuristics).
-- luacheck: globals C_Timer CreateFrame

if not AltArmy then return end

AltArmy.BankAltDetect = AltArmy.BankAltDetect or {}
local BD = AltArmy.BankAltDetect

local MAX_DETECT_LEVEL = 5
local WEALTH_COPPER = 200 * 10000
local ONE_HOUR = 3600

local function charKey(name, realm)
    return AltArmy.CharKey(name, realm)
end

function BD.NormalLevelTimeSeconds(level)
    level = math.floor(level or 0)
    if level < 1 then level = 1 end
    return (15 + 5 * (level - 1)) * 60
end

function BD.StagnationThresholdSeconds(level)
    return BD.NormalLevelTimeSeconds(level) * 4 + ONE_HOUR
end

function BD.IsEligibleLevel(level)
    level = math.floor(level or 0)
    return level >= 1 and level <= MAX_DETECT_LEVEL
end

function BD.IsWealthy(wealthCopper)
    return (wealthCopper or 0) >= WEALTH_COPPER
end

function BD.IsStagnant(level, timeAtLevelSeconds)
    return (timeAtLevelSeconds or 0) >= BD.StagnationThresholdSeconds(level)
end

function BD.GetTotalWealthCopper(char, DS)
    if not char or not DS then return 0 end
    local money = (DS.GetMoney and DS:GetMoney(char)) or char.money or 0
    local mail = (DS.GetMailMoneyTotal and DS:GetMailMoneyTotal(char)) or 0
    return money + mail
end

function BD.GetTimeAtCurrentLevelSeconds(char, DS, opts)
    opts = opts or {}
    if not char then return 0 end
    if type(char.playedThisLevel) == "number" and char.playedThisLevel >= 0 then
        return char.playedThisLevel
    end

    local level = math.floor(
        (DS and DS.GetCharacterLevel and DS:GetCharacterLevel(char)) or char.level or 1)
    local playedTotal
    if opts.isCurrent and DS and DS.GetDerivedPlayedTotal then
        playedTotal = DS:GetDerivedPlayedTotal()
    else
        playedTotal = (DS and DS.GetPlayTime and DS:GetPlayTime(char)) or char.played or 0
    end

    local milestones = char.levelHistory and char.levelHistory.milestones
    local milestone = milestones and milestones[level]
    if milestone and type(milestone.playedTotal) == "number" then
        local delta = playedTotal - milestone.playedTotal
        if delta < 0 then return playedTotal end
        return delta
    end

    return playedTotal
end

function BD.EnsureDismiss()
    _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
    AltArmyTBC_Options.bankAltPromptDismissed = AltArmyTBC_Options.bankAltPromptDismissed or {}
end

function BD.IsDismissed(name, realm)
    BD.EnsureDismiss()
    if not name or not realm then return false end
    return AltArmyTBC_Options.bankAltPromptDismissed[charKey(name, realm)] == true
end

function BD.Dismiss(name, realm, _kind)
    BD.EnsureDismiss()
    if not name or not realm then return end
    AltArmyTBC_Options.bankAltPromptDismissed[charKey(name, realm)] = true
end

local function formatDuration(seconds)
    seconds = math.floor(seconds or 0)
    if seconds < 60 then
        return string.format("%ds", seconds)
    end
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    if hours > 0 and mins > 0 then
        return string.format("%dh %dm", hours, mins)
    end
    if hours > 0 then
        return string.format("%dh", hours)
    end
    return string.format("%dm", mins)
end

local function formatGold(copper)
    copper = copper or 0
    local gold = math.floor(copper / 10000)
    return tostring(gold) .. "g"
end

function BD.BuildReasonLines(result)
    result = result or {}
    local lines = {}
    if result.level then
        lines[#lines + 1] = string.format(
            "Level %d · %s · %s at this level (threshold %s)",
            result.level,
            formatGold(result.wealthCopper),
            formatDuration(result.timeAtLevelSeconds),
            formatDuration(result.thresholdSeconds))
    end
    return lines
end

function BD.Evaluate(char, DS, opts)
    opts = opts or {}
    local result = {
        shouldPrompt = false,
        eligible = false,
        wealthy = false,
        stagnant = false,
        level = 0,
        wealthCopper = 0,
        timeAtLevelSeconds = 0,
        thresholdSeconds = 0,
        name = "",
        realm = "",
        reasonLines = {},
    }
    if not char or not DS then return result end

    local name = (DS.GetCharacterName and DS:GetCharacterName(char)) or char.name or ""
    local realm = char.realm or ""
    local level = math.floor((DS.GetCharacterLevel and DS:GetCharacterLevel(char)) or char.level or 0)

    result.name = name
    result.realm = realm
    result.level = level

    local BA = AltArmy.BankAlt
    if BA and BA.Is and BA.Is(name, realm) then
        return result
    end
    if not opts.skipDismiss and BD.IsDismissed(name, realm) then
        return result
    end
    if not BD.IsEligibleLevel(level) then
        return result
    end

    result.eligible = true
    result.wealthCopper = BD.GetTotalWealthCopper(char, DS)
    result.wealthy = BD.IsWealthy(result.wealthCopper)
    result.timeAtLevelSeconds = BD.GetTimeAtCurrentLevelSeconds(char, DS, opts)
    result.thresholdSeconds = BD.StagnationThresholdSeconds(level)
    result.stagnant = BD.IsStagnant(level, result.timeAtLevelSeconds)
    result.shouldPrompt = result.wealthy and result.stagnant
    result.reasonLines = BD.BuildReasonLines(result)

    return result
end

function BD.TryPromptForCurrentCharacter()
    local queue = AltArmy.OnboardingDialogQueue
    if queue and queue.RequestProcess then
        queue.RequestProcess()
    end
end

function BD.EvaluateCurrentCharacter()
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCurrentCharacter then return nil end
    local char = DS:GetCurrentCharacter()
    if not char then return nil end
    return BD.Evaluate(char, DS, { isCurrent = true, skipDismiss = true })
end

BD.EnsureDismiss()

local promptFrame = CreateFrame and CreateFrame("Frame")
if promptFrame then
    promptFrame:RegisterEvent("PLAYER_MONEY")
    promptFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    promptFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_MONEY" or event == "PLAYER_ENTERING_WORLD" then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, BD.TryPromptForCurrentCharacter)
            else
                BD.TryPromptForCurrentCharacter()
            end
        end
    end)
end
