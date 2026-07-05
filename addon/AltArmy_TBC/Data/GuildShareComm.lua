-- AltArmy TBC — Guild data sharing: comm layer (AceComm/AceSerializer wiring).
-- Broadcasts a privacy-limited presence over the GUILD channel and pulls recipe lists
-- on demand. Sending is ALWAYS active (subject to the send-set below); receiving + UI
-- are gated behind the guildShare feature flag.
--
-- Send-set inversion (see GuildShareSettings):
--   flag OFF -> GetAllGuildedCharacters() (ignore the user's settings; lets the developer
--               collect data from flag-off guildmates)
--   flag ON  -> GetShareableCharacters() (opt-in, defaults to none)
--
-- Libs are acquired lazily inside Init() (called on login) so this file's position in the
-- .toc relative to the Ace3 libs does not matter.

if not AltArmy then return end

AltArmy.GuildShareComm = AltArmy.GuildShareComm or {}
local Comm = AltArmy.GuildShareComm

local PREFIX = "AltArmyGS"
local MSG_PRESENCE = "P"       -- initial presence broadcast
local MSG_PRESENCE_REPLY = "PR" -- whispered reply to a broadcast (no further reply)
local MSG_REQ_RECIPES = "RQ"   -- request recipe list for a character
local MSG_RECIPES = "RC"       -- recipe list reply

local BROADCAST_THROTTLE = 10          -- seconds between guild broadcasts
local STALE_MAX_AGE = 60 * 60 * 24 * 14 -- prune received data older than 14 days

local commObj            -- table embedded with AceComm-3.0 + AceSerializer-3.0
local initialized = false
local lastBroadcast = 0
local knownGuild        -- last observed guild name, to detect gkick/gquit/gjoin
local knownOnlineMembers = {} -- guildmate name -> true (excludes self); roster baseline
local rosterBaselinePending = true

-- *** Small helpers (some exposed for unit tests) ***

local function isReceiveEnabled()
    local D = AltArmy.Debug
    return D and D.IsGuildShareEnabled and D.IsGuildShareEnabled() == true
end

--- Verbose traffic logging (gated by the standalone guildShareVerbose debug flag).
local function log(msg)
    local D = AltArmy.Debug
    if D and D.LogGuildShare then
        D.LogGuildShare(msg)
    end
end

local function playerName()
    return (UnitName and UnitName("player")) or ""
end

local function currentRealm()
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS._CurrentRealm then return GSS._CurrentRealm() end
    return (GetRealmName and GetRealmName()) or ""
end

local function currentGuild()
    if GetGuildInfo then
        local g = GetGuildInfo("player")
        if g and g ~= "" then return g end
    end
    return nil
end

--- Strip any realm suffix an addon-message sender may carry ("Name-Realm" -> "Name").
local function normalizeSender(sender)
    if type(sender) ~= "string" then return sender end
    return sender:match("^[^%-]+") or sender
end
Comm._NormalizeSender = normalizeSender

--- True when the addon-message sender is this client (guild broadcasts echo back to self).
local function isLocalSender(sender)
    local mine = normalizeSender(playerName())
    if mine == "" then return false end
    return normalizeSender(sender) == mine
end
Comm._IsLocalSender = isLocalSender

--- Select the set of characters to broadcast, branching on the feature flag.
--- Exposed for unit testing the flag inversion.
function Comm._SelectShareChars(flagOn, guild, realm)
    local GSS = AltArmy.GuildShareSettings
    if not GSS then return {} end
    if flagOn then
        return GSS.GetShareableCharacters(guild, realm)
    end
    return GSS.GetAllGuildedCharacters(guild, realm)
end

--- Verbose log line when a broadcast would run but sending is blocked by user settings.
--- Only when the guildShare feature flag is ON (opt-in send path) and sharing is disabled.
--- Other empty-send cases (no guilded characters, all opted out, etc.) are silent.
function Comm._BroadcastSkippedLogMessage(flagOn, sharingEnabled)
    if flagOn and sharingEnabled == false then
        return "broadcast skipped: sharing disabled (enable in Options > General)"
    end
    return nil
end

--- True when `curr` contains an online guildmate who was not online in `prev`.
function Comm._HasNewlyOnlineGuildmate(prev, curr)
    if type(curr) ~= "table" then return false end
    prev = prev or {}
    for name in pairs(curr) do
        if not prev[name] then return true end
    end
    return false
end

--- Whether a GUILD_ROSTER_UPDATE should trigger a throttled broadcast.
function Comm._ShouldBroadcastOnRosterUpdate(prev, curr, baselinePending)
    if baselinePending then return false end
    return Comm._HasNewlyOnlineGuildmate(prev, curr)
end

--- True when the player's guild membership changed (nil and name are distinct states).
function Comm._GuildMembershipChanged(prevGuild, newGuild)
    return prevGuild ~= newGuild
end

local function guildRosterLooksUnloaded()
    if not (IsInGuild and IsInGuild()) then return false end
    if not GetNumGuildMembers then return false end
    return GetNumGuildMembers() == 0
end
Comm._GuildRosterLooksUnloaded = guildRosterLooksUnloaded

local function collectOnlineGuildMembers()
    local out = {}
    if not (IsInGuild and IsInGuild()) then return out end
    if not GetNumGuildMembers or not GetGuildRosterInfo then return out end
    local mine = normalizeSender(playerName())
    local n = GetNumGuildMembers()
    for i = 1, n do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if online and name then
            local short = normalizeSender(name)
            if short ~= "" and short ~= mine then
                out[short] = true
            end
        end
    end
    return out
end

local function resetRosterOnlineBaseline()
    knownOnlineMembers = {}
    rosterBaselinePending = true
end

local function handleGuildRosterUpdate()
    local curr = collectOnlineGuildMembers()
    if rosterBaselinePending then
        knownOnlineMembers = curr
        if guildRosterLooksUnloaded() then
            return
        end
        rosterBaselinePending = false
        return
    end
    if Comm._ShouldBroadcastOnRosterUpdate(knownOnlineMembers, curr, false) then
        Comm.Broadcast(false)
    end
    knownOnlineMembers = curr
end

local function handlePlayerGuildUpdate()
    local newGuild = currentGuild()
    if not Comm._GuildMembershipChanged(knownGuild, newGuild) then
        return
    end
    if knownGuild then
        local GSD = AltArmy.GuildShareData
        if GSD and GSD.PurgeGuild then
            pcall(function() GSD.PurgeGuild(knownGuild) end)
        end
        Comm.NotifyDataChanged()
    end
    knownGuild = newGuild
    resetRosterOnlineBaseline()
    Comm.Broadcast(true)
end
Comm._HandlePlayerGuildUpdate = handlePlayerGuildUpdate

-- *** Sending ***

local function serialize(msgType, payload)
    if not commObj then return nil end
    return commObj:Serialize(msgType, payload)
end

local function send(msgType, payload, distribution, target)
    local data = serialize(msgType, payload)
    if not data then return end
    log(string.format("SEND %s -> %s%s (%d bytes)",
        msgType, distribution, target and (":" .. target) or "", #data))
    pcall(function()
        commObj:SendCommMessage(PREFIX, data, distribution, target)
    end)
end

--- Build my presence payload for the given guild/realm (respecting the flag-branched set).
local function buildMyPresence(guild, realm)
    local P = AltArmy.GuildShareProtocol
    local GSS = AltArmy.GuildShareSettings
    if not P or not GSS then return nil end
    local chars = Comm._SelectShareChars(isReceiveEnabled(), guild, realm)
    if #chars == 0 then return nil end
    local mainName, displayName = GSS.ResolvePresenceMainAndDisplay(chars, realm)
    return P.BuildPresence(chars, mainName, displayName)
end

function Comm.Broadcast(force)
    if not commObj then return end
    if not (IsInGuild and IsInGuild()) then return end
    local nowTs = (GetTime and GetTime()) or 0
    if not force and (nowTs - lastBroadcast) < BROADCAST_THROTTLE then return end
    local flagOn = isReceiveEnabled()
    local GSS = AltArmy.GuildShareSettings
    local sharingEnabled = GSS and GSS.IsSharingEnabled and GSS.IsSharingEnabled()
    local guild = currentGuild()
    local realm = currentRealm()
    local presence = buildMyPresence(guild, realm)
    if not presence then
        local skipMsg = Comm._BroadcastSkippedLogMessage(flagOn, sharingEnabled)
        if skipMsg then
            log(skipMsg)
            lastBroadcast = nowTs
        end
        return
    end
    lastBroadcast = nowTs
    log(string.format("broadcasting presence: %d character(s) to guild '%s' (flag %s)",
        #presence.chars, tostring(guild), isReceiveEnabled() and "on/opt-in" or "off/all-guilded"))
    send(MSG_PRESENCE, presence, "GUILD")
end

-- *** Receiving (gated by the feature flag) ***

--- Notify dependents that guild data changed (search cache, guild tab).
function Comm.NotifyDataChanged()
    local SD = AltArmy.SearchData
    if SD and SD.NotifyRecipesChanged then
        pcall(SD.NotifyRecipesChanged)
    end
    if AltArmy.RefreshGuildTab then
        pcall(AltArmy.RefreshGuildTab)
    end
end

-- *** Debug: single-account test injection ***

--- Pick one of the player's own scanned characters that has professions, so the test
--- injection can seed realistic recipe data that resolves to real names in search.
--- Returns a char table (with .Professions) or nil.
function Comm._PickSampleProfChar(realm)
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCharacters then return nil end
    local chars = DS:GetCharacters(realm) or {}
    local best, bestCount
    for _, char in pairs(chars) do
        if type(char) == "table" and type(char.Professions) == "table" then
            local count = 0
            for _ in pairs(char.Professions) do count = count + 1 end
            if count > 0 and (not bestCount or count > bestCount) then
                best, bestCount = char, count
            end
        end
    end
    return best
end

--- DEBUG-ONLY (/altarmy debug guildshare test): inject a synthetic guildmate (a main + an
--- alt) straight into the receive/store path, so a single account can exercise the store +
--- Guild tab + search-merge without a second player online. Requires the feature flag ON
--- (that is the receive gate). Recipes are seeded from one of the player's own characters so
--- they resolve to real names in search; if none exist the guildmate simply has no recipes.
--- Returns true on success, or false + reason ("flag-off" / "unavailable" / "parse").
function Comm.InjectTestPresence()
    if not isReceiveEnabled() then
        log("test inject skipped: guildShare feature flag is OFF")
        return false, "flag-off"
    end
    local P = AltArmy.GuildShareProtocol
    local GSD = AltArmy.GuildShareData
    if not P or not GSD then
        log("test inject skipped: guild share modules unavailable")
        return false, "unavailable"
    end

    local realm = currentRealm()
    if realm == "" then realm = "TestRealm" end
    local guild = currentGuild() or "AltArmy Test Guild"

    local sample = Comm._PickSampleProfChar(realm)
    local summaries = sample and P.BuildProfessionSummaries(sample) or {}

    local presence = {
        v = P.VERSION,
        main = "AAtestmain",
        displayName = "AA Test Main",
        chars = {
            {
                name = "AAtestmain", realm = realm, classFile = "MAGE",
                faction = "Alliance", level = 70, profs = summaries,
            },
            {
                name = "AAtestalt", realm = realm, classFile = "WARRIOR",
                faction = "Alliance", level = 42, profs = {},
            },
        },
    }

    local parsed = P.ParsePresence(presence)
    if not parsed then
        log("test inject failed: presence did not parse")
        return false, "parse"
    end
    GSD.SaveReceived("AAtestmain", parsed, guild, realm)

    if sample then
        GSD.SaveRecipes(realm, P.BuildRecipes("AAtestmain", realm, sample))
    end

    Comm.NotifyDataChanged()
    log(string.format(
        "test inject: 2 synthetic guildmate(s) stored under guild '%s' (realm %s)%s",
        guild, realm, sample and " with sampled recipes" or " (no local recipes to sample)"))
    return true
end

--- After storing a peer's presence, request recipe lists for any professions we lack.
local function requestMissingRecipes(presence, sender, realm)
    local GSD = AltArmy.GuildShareData
    if not GSD then return end
    for _, c in ipairs(presence.chars or {}) do
        local needed = GSD.GetProfessionsNeedingRecipes(c.name, realm)
        if #needed > 0 then
            send(MSG_REQ_RECIPES, { name = c.name, realm = realm }, "WHISPER", sender)
        end
    end
end

--- Reply to a recipe request: only for characters we actually own and are sharing.
local function handleRecipeRequest(payload, sender)
    local P = AltArmy.GuildShareProtocol
    local DS = AltArmy.DataStore
    if not P or not DS or type(payload) ~= "table" then return end
    local guild = currentGuild()
    local realm = payload.realm or currentRealm()
    local chars = Comm._SelectShareChars(isReceiveEnabled(), guild, realm)
    local ownedAndShared
    for _, entry in ipairs(chars) do
        if entry.name == payload.name then
            ownedAndShared = entry.char
            break
        end
    end
    if not ownedAndShared then return end
    send(MSG_RECIPES, P.BuildRecipes(payload.name, realm, ownedAndShared), "WHISPER", sender)
end

local function handlePresence(payload, sender, isReply)
    local P = AltArmy.GuildShareProtocol
    local GSD = AltArmy.GuildShareData
    if not P or not GSD then return end
    local parsed = P.ParsePresence(payload)
    if not parsed then return end
    local guild = currentGuild()
    local realm = currentRealm()
    GSD.SaveReceived(sender, parsed, guild, realm)
    Comm.NotifyDataChanged()
    requestMissingRecipes(parsed, sender, realm)
    -- Announce/reply handshake: reply to an initial broadcast (not to a reply) so we don't loop.
    if not isReply and sender ~= playerName() then
        local mine = buildMyPresence(guild, realm)
        if mine then
            send(MSG_PRESENCE_REPLY, mine, "WHISPER", sender)
        end
    end
end

local function handleRecipes(payload)
    local P = AltArmy.GuildShareProtocol
    local GSD = AltArmy.GuildShareData
    if not P or not GSD then return end
    local parsed = P.ParseRecipes(payload)
    if not parsed then return end
    GSD.SaveRecipes(parsed.realm or currentRealm(), parsed)
    Comm.NotifyDataChanged()
end

--- Raw AceComm receive callback. All work is wrapped in pcall so a malformed message
--- can never surface an error, and inbound is ignored entirely when the flag is off.
function Comm._DispatchReceivedMessage(msgType, payload, rawSender)
    local sender = normalizeSender(rawSender)
    if isLocalSender(sender) then return end
    log(string.format("RECV %s from %s", msgType, tostring(sender)))
    if msgType == MSG_PRESENCE then
        handlePresence(payload, sender, false)
    elseif msgType == MSG_PRESENCE_REPLY then
        handlePresence(payload, sender, true)
    elseif msgType == MSG_REQ_RECIPES then
        handleRecipeRequest(payload, sender)
    elseif msgType == MSG_RECIPES then
        handleRecipes(payload)
    end
end

local function onCommReceived(_prefix, message, _distribution, rawSender)
    if not isReceiveEnabled() then return end
    if not commObj then return end
    pcall(function()
        local ok, msgType, payload = commObj:Deserialize(message)
        if not ok or type(msgType) ~= "string" then
            log(string.format("RECV (undecodable) from %s", tostring(rawSender)))
            return
        end
        Comm._DispatchReceivedMessage(msgType, payload, rawSender)
    end)
end

-- *** Initialization ***

function Comm.Init()
    if initialized then return end
    if not LibStub then return end
    local AceComm = LibStub:GetLibrary("AceComm-3.0", true)
    local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0", true)
    if not AceComm or not AceSerializer then return end
    commObj = {}
    AceComm:Embed(commObj)
    AceSerializer:Embed(commObj)
    commObj:RegisterComm(PREFIX, onCommReceived)
    initialized = true
    -- Prune very old received data (harmless when the flag is off / no data present).
    local GSD = AltArmy.GuildShareData
    if GSD and GSD.PurgeStale then
        pcall(function() GSD.PurgeStale(STALE_MAX_AGE) end)
    end
end

-- *** Events ***

local frame = CreateFrame and CreateFrame("Frame")
if frame then
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            Comm.Init()
            knownGuild = currentGuild()
            resetRosterOnlineBaseline()
            if IsInGuild and IsInGuild() then
                if GuildRoster then pcall(GuildRoster) end
                Comm.Broadcast(true)
            end
        elseif event == "GUILD_ROSTER_UPDATE" then
            handleGuildRosterUpdate()
        elseif event == "PLAYER_GUILD_UPDATE" then
            handlePlayerGuildUpdate()
        end
    end)
end
