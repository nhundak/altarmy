-- AltArmy TBC — Mail expiry login alerts (chat).
-- Warns when any character's soonest mail return is within WARN_DAYS.
-- Uses DataStoreMail.GetSoonestMailDaysLeft. Chat lines are prefixed with gold "Alt Army".

if not AltArmy then return end

AltArmy.MailAlerts = AltArmy.MailAlerts or {}
local MA = AltArmy.MailAlerts

local WARN_DAYS = 5
local LOGIN_DELAY = 5
local ALTARMY_GOLD = "|cfffecc00"

local CC = AltArmy.ClassColor

local alertFrame = CreateFrame("Frame", "AltArmyTBC_MailAlertFrame", UIParent)

local function postChat(line)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage and line and line ~= "" then
        chat:AddMessage(line)
    end
end

local function classColorWrap(text, classFile)
    if CC and CC.wrapName then
        return CC.wrapName(text, classFile)
    end
    return text or "?"
end

--- Human-readable remaining duration from fractional days.
--- @param daysLeft number|nil
--- @return string
function MA.FormatDuration(daysLeft)
    if not daysLeft or daysLeft <= 0 then
        return "less than an hour"
    end
    local days = math.floor(daysLeft)
    local hours = math.floor((daysLeft - days) * 24 + 1e-9)
    if days >= 2 then
        if hours > 0 then
            return string.format("%d days %d hours", days, hours)
        end
        return string.format("%d days", days)
    end
    if days == 1 then
        if hours > 0 then
            return string.format("1 day %d hours", hours)
        end
        return "1 day"
    end
    local totalMinutes = math.floor(daysLeft * 24 * 60 + 1e-9)
    local h = math.floor(totalMinutes / 60)
    local m = totalMinutes % 60
    if h >= 2 then
        if m > 0 then
            return string.format("%d hours %d minutes", h, m)
        end
        return string.format("%d hours", h)
    end
    if h == 1 then
        if m > 0 then
            return string.format("1 hour %d minutes", m)
        end
        return "1 hour"
    end
    if m <= 1 then
        return "less than a minute"
    end
    return string.format("%d minutes", m)
end

--- Body text (no Alt Army prefix): "{Name} has mail which will be returned in {duration}".
--- @param name string|nil
--- @param classFile string|nil
--- @param daysLeft number|nil
--- @return string
function MA.FormatMessage(name, classFile, daysLeft)
    local namePart = classColorWrap(name, classFile)
    local duration = MA.FormatDuration(daysLeft)
    return string.format("%s has mail which will be returned in %s", namePart, duration)
end

--- Collect characters whose soonest mail expires within thresholdDays.
--- @param DS table AltArmy.DataStore
--- @param now number|nil unix time
--- @param thresholdDays number|nil default WARN_DAYS
--- @return table[] { name, realm, classFile, daysLeft }
function MA.CollectWarnings(DS, now, thresholdDays)
    local results = {}
    if not DS or not DS.ForEachCharacter or not DS.GetSoonestMailDaysLeft then
        return results
    end
    now = now or (time and time() or 0)
    thresholdDays = thresholdDays or WARN_DAYS
    DS:ForEachCharacter(function(realm, charName, char)
        local daysLeft = DS:GetSoonestMailDaysLeft(char, now)
        if daysLeft ~= nil and daysLeft <= thresholdDays then
            results[#results + 1] = {
                name = (char and char.name) or charName,
                realm = realm,
                classFile = char and char.classFile or nil,
                daysLeft = daysLeft,
            }
        end
    end)
    table.sort(results, function(a, b)
        if a.daysLeft ~= b.daysLeft then
            return a.daysLeft < b.daysLeft
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return (a.realm or "") < (b.realm or "")
    end)
    return results
end

--- Post one chat line per warning.
--- @param warnings table[] from CollectWarnings / manual rows
function MA.AnnounceWarnings(warnings)
    if not warnings or #warnings == 0 then return end
    for i = 1, #warnings do
        local w = warnings[i]
        local body = MA.FormatMessage(w.name, w.classFile, w.daysLeft)
        postChat(ALTARMY_GOLD .. "Alt Army|r " .. body)
    end
end

function MA.RunLoginCheck()
    local DS = AltArmy.DataStore
    if not DS then return end
    local now = time and time() or 0
    local warnings = MA.CollectWarnings(DS, now, WARN_DAYS)
    MA.AnnounceWarnings(warnings)
end

--- Debug: announce soonest mail return for a character regardless of threshold.
--- @param characterName string
--- @return boolean true if a mail warning was posted
function MA.DebugAnnounceForCharacter(characterName)
    local DS = AltArmy.DataStore
    local name = characterName and tostring(characterName):match("^%s*(.-)%s*$") or ""
    if name == "" then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: Usage: /altarmy debug mail {character name}")
        return false
    end
    if not DS or not DS.ForEachCharacter or not DS.GetSoonestMailDaysLeft then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: mail data is unavailable.")
        return false
    end
    local wanted = string.lower(name)
    local matches = {}
    DS:ForEachCharacter(function(realm, charName, char)
        local display = (char and char.name) or charName
        if string.lower(display) == wanted or string.lower(charName) == wanted then
            matches[#matches + 1] = {
                name = display,
                realm = realm,
                classFile = char and char.classFile or nil,
                char = char,
            }
        end
    end)
    if #matches == 0 then
        postChat(ALTARMY_GOLD .. "Alt Army|r debug: character \"" .. name .. "\" not found.")
        return false
    end
    local now = time and time() or 0
    local announced = false
    for i = 1, #matches do
        local m = matches[i]
        local daysLeft = DS:GetSoonestMailDaysLeft(m.char, now)
        if daysLeft == nil then
            postChat(ALTARMY_GOLD .. "Alt Army|r debug: " .. classColorWrap(m.name, m.classFile)
                .. " has no mail.")
        else
            MA.AnnounceWarnings({
                {
                    name = m.name,
                    realm = m.realm,
                    classFile = m.classFile,
                    daysLeft = daysLeft,
                },
            })
            announced = true
        end
    end
    return announced
end

alertFrame:RegisterEvent("PLAYER_LOGIN")
alertFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        alertFrame.loginSweepPending = true
        alertFrame.loginElapsed = 0
    end
end)

alertFrame:SetScript("OnUpdate", function(f, dt)
    if not f.loginSweepPending then return end
    f.loginElapsed = (f.loginElapsed or 0) + dt
    if f.loginElapsed >= LOGIN_DELAY then
        f.loginSweepPending = false
        MA.RunLoginCheck()
    end
end)
