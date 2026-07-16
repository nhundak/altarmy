-- AltArmy TBC — Guild data sharing: comm layer (AceComm/AceSerializer wiring).
-- luacheck: globals C_Timer
-- Broadcasts a privacy-limited presence over the GUILD channel and pulls recipe lists
-- on demand. Sending is ALWAYS active (subject to the send-set below); receiving + UI
-- are gated behind the guildShare feature flag, except that inbound RQ (recipe requests)
-- are always processed: flag-off clients always reply with RC; flag-on clients reply only
-- when guild sharing is enabled in Options.
-- ScheduleBroadcast is a trailing-edge debounce (timer resets on each call). Options/
-- onboarding use 5s; profession/recipe scans use PROFESSION_BROADCAST_DEBOUNCE_SEC so
-- long craft casts (e.g. 8s bandages) do not each complete the quiet window mid-session.
-- Login/reload and guild join/leave Broadcast immediately. Login/reload presence carries
-- login=true so peers whisper a PR reply even when data is already stored.
--
-- Send-set inversion (see GuildShareSettings):
--   flag OFF -> GetAllGuildedCharacters() (ignore the user's settings; lets the developer
--               collect data from flag-off guildmates). Empty set => no send.
--   flag ON  -> GetShareableCharacters() (opt-in, defaults to none). Empty set => still
--               send an empty presence so peers clear previously received characters.
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

local MSG_LABELS = {
    [MSG_PRESENCE] = "presence",
    [MSG_PRESENCE_REPLY] = "presence reply",
    [MSG_REQ_RECIPES] = "recipe request",
    [MSG_RECIPES] = "recipes",
}

--- Human-readable log label for a wire message type, e.g. "P (presence)".
local function formatMsgType(msgType)
    local label = MSG_LABELS[msgType]
    if label then
        return string.format("%s (%s)", msgType, label)
    end
    return tostring(msgType)
end
Comm._FormatMsgType = formatMsgType

local UNDECODABLE_HEAD_LEN = 48

--- Safe short preview of a raw AceComm payload for chat debug logs.
local function messageHead(message)
    if type(message) ~= "string" then
        return string.format("<%s>", type(message))
    end
    local head = message:sub(1, UNDECODABLE_HEAD_LEN)
    head = head:gsub("[%c]", ".")
    if #message > UNDECODABLE_HEAD_LEN then
        head = head .. "..."
    end
    return head
end

--- Verbose log line when AceSerializer cannot decode an inbound guild-share message.
function Comm._FormatUndecodableRecvLog(prefix, message, distribution, rawSender, deserializeOk, firstValue)
    local bytes = (type(message) == "string") and #message or 0
    local reason
    if not deserializeOk then
        reason = tostring(firstValue)
    else
        reason = "msgType=" .. type(firstValue)
    end
    return string.format(
        "recv (undecodable) from %s prefix=%s dist=%s bytes=%d reason=%s head=%s",
        tostring(rawSender),
        tostring(prefix),
        tostring(distribution),
        bytes,
        reason,
        messageHead(message)
    )
end

local BROADCAST_THROTTLE = 10          -- seconds between guild broadcasts
-- Debounce window for Options/onboarding settings changes (coalesce rapid toggles).
Comm.SETTINGS_BROADCAST_DEBOUNCE_SEC = 5
-- Longer than typical craft cast times so skill-ups during a crafting session coalesce.
Comm.PROFESSION_BROADCAST_DEBOUNCE_SEC = 30
-- Prune received data older than 60 days (14+ day data stays but is flagged in the Guild tab).
Comm.STALE_MAX_AGE = 60 * 60 * 24 * 60
local STALE_MAX_AGE = Comm.STALE_MAX_AGE

local commObj            -- table embedded with AceComm-3.0 + AceSerializer-3.0
local initialized = false
local lastBroadcast = 0
local settingsBroadcastGeneration = 0
local knownGuild        -- last observed guild name, to detect gkick/gquit/gjoin

-- *** Small helpers (some exposed for unit tests) ***

local function isReceiveEnabled()
    local D = AltArmy.Debug
    return D and D.IsGuildShareEnabled and D.IsGuildShareEnabled() == true
end

--- True when an inbound message type may be processed (RQ is always allowed).
local function isInboundAllowed(msgType)
    if msgType == MSG_REQ_RECIPES then return true end
    return isReceiveEnabled()
end
Comm._IsInboundAllowed = isInboundAllowed

--- True when this client should send RC in response to an inbound RQ.
function Comm._ShouldRespondToRecipeRequest()
    if not isReceiveEnabled() then
        return true
    end
    local GSS = AltArmy.GuildShareSettings
    return GSS and GSS.IsSharingEnabled and GSS.IsSharingEnabled() == true
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

--- Legacy helper: sharing-disabled no longer skips the wire send (an empty presence is
--- broadcast instead so peers can clear). Kept for tests / call sites; always returns nil.
function Comm._BroadcastSkippedLogMessage(_flagOn, _sharingEnabled)
    return nil
end

--- Build a presence payload for the selected share set.
--- Flag ON + empty set => empty presence (opt-out clear). Flag OFF + empty => nil (no send).
function Comm._PresenceForShareChars(flagOn, chars, mainName, displayName)
    local P = AltArmy.GuildShareProtocol
    if not P or type(P.BuildPresence) ~= "function" then return nil end
    chars = chars or {}
    if #chars == 0 then
        if flagOn then
            return P.BuildPresence({}, nil, nil)
        end
        return nil
    end
    return P.BuildPresence(chars, mainName, displayName)
end

--- True when the player's guild membership changed (nil and name are distinct states).
function Comm._GuildMembershipChanged(prevGuild, newGuild)
    return prevGuild ~= newGuild
end

--- Whether PLAYER_ENTERING_WORLD should broadcast (login/reload only; not zone transitions).
function Comm._ShouldBroadcastOnEnteringWorld(isInitialLogin, isReloadingUi)
    return isInitialLogin == true or isReloadingUi == true
end

--- Stamp or clear the login announce flag on a presence payload.
function Comm._WithLoginAnnounce(presence, isLoginAnnounce)
    if not presence then return nil end
    if isLoginAnnounce then
        presence.login = true
    else
        presence.login = nil
    end
    return presence
end

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

--- True when a guildmate (normalized short name) is online in the roster.
function Comm.IsGuildMemberOnline(name)
    name = normalizeSender(name)
    if name == "" then return false end
    return collectOnlineGuildMembers()[name] == true
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
    Comm.Broadcast(true)
end
Comm._HandlePlayerGuildUpdate = handlePlayerGuildUpdate

-- *** Sending ***

local function serialize(msgType, payload)
    if not commObj then return nil end
    return commObj:Serialize(msgType, payload)
end

local function send(msgType, payload, distribution, target)
    -- Unit-test hook: capture outbound messages without AceComm.
    if Comm._TestHookSend then
        Comm._TestHookSend(msgType, payload, distribution, target)
        return
    end
    local data = serialize(msgType, payload)
    if not data then return end
    log(string.format("SEND %s -> %s%s (%d bytes)",
        formatMsgType(msgType), distribution, target and (":" .. target) or "", #data))
    pcall(function()
        commObj:SendCommMessage(PREFIX, data, distribution, target)
    end)
end

--- On-demand recipe pull for one character; whispers `sender` when they are online and recipes are missing.
--- Returns true when a request was sent.
function Comm.RequestRecipesForCharacter(name, realm, sender)
    if not name or not sender or sender == "" then return false end
    sender = normalizeSender(sender)
    if not Comm.IsGuildMemberOnline(sender) then return false end
    local GSD = AltArmy.GuildShareData
    if not GSD or not GSD.GetProfessionsNeedingRecipes then return false end
    local needed = GSD.GetProfessionsNeedingRecipes(name, realm)
    if #needed == 0 then return false end
    send(MSG_REQ_RECIPES, { name = name, realm = realm }, "WHISPER", sender)
    if GSD.MarkRecipesRequested then
        GSD.MarkRecipesRequested(name, realm, needed)
    end
    return true
end

--- Build my presence payload for the given guild/realm (respecting the flag-branched set).
local function buildMyPresence(guild, realm)
    local GSS = AltArmy.GuildShareSettings
    if not GSS then return nil end
    local flagOn = isReceiveEnabled()
    local chars = Comm._SelectShareChars(flagOn, guild, realm)
    local mainName, displayName
    if #chars > 0 and GSS.ResolvePresenceMainAndDisplay then
        mainName, displayName = GSS.ResolvePresenceMainAndDisplay(chars, realm)
    end
    return Comm._PresenceForShareChars(flagOn, chars, mainName, displayName)
end

--- Broadcast presence to the guild. When isLoginAnnounce is true, peers whisper a PR
--- reply even if they already have our data (covers newcomers who missed prior sends).
function Comm.Broadcast(force, isLoginAnnounce)
    if not Comm._TestHookSend and not commObj then return end
    if not (IsInGuild and IsInGuild()) then return end
    local nowTs = (GetTime and GetTime()) or 0
    if not force and (nowTs - lastBroadcast) < BROADCAST_THROTTLE then return end
    local guild = currentGuild()
    local realm = currentRealm()
    local presence = Comm._WithLoginAnnounce(buildMyPresence(guild, realm), isLoginAnnounce)
    if not presence then
        return
    end
    lastBroadcast = nowTs
    log(string.format("broadcasting presence: %d character(s) to guild '%s' (flag %s%s)",
        #presence.chars, tostring(guild), isReceiveEnabled() and "on/opt-in" or "off/all-guilded",
        isLoginAnnounce and ", login announce" or ""))
    send(MSG_PRESENCE, presence, "GUILD")
end

--- Cancel a pending settings-driven presence broadcast.
function Comm.CancelScheduledBroadcast()
    settingsBroadcastGeneration = settingsBroadcastGeneration + 1
end

--- Schedule a forced presence broadcast after a quiet period (trailing-edge debounce).
--- Repeated calls reset the timer. delaySec defaults to SETTINGS_BROADCAST_DEBOUNCE_SEC;
--- pass PROFESSION_BROADCAST_DEBOUNCE_SEC for skill/recipe scans.
function Comm.ScheduleBroadcast(delaySec)
    Comm.CancelScheduledBroadcast()
    local generation = settingsBroadcastGeneration
    local delay = delaySec or Comm.SETTINGS_BROADCAST_DEBOUNCE_SEC
    local ctimer = _G.C_Timer
    if ctimer and ctimer.After then
        ctimer.After(delay, function()
            if generation ~= settingsBroadcastGeneration then return end
            Comm.Broadcast(true)
        end)
    else
        Comm.Broadcast(true)
    end
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
    for _, c in ipairs(presence.chars or {}) do
        Comm.RequestRecipesForCharacter(c.name, realm, sender)
    end
end

--- Reply to a recipe request: only for characters we actually own and are sharing.
local function handleRecipeRequest(payload, sender)
    local P = AltArmy.GuildShareProtocol
    local DS = AltArmy.DataStore
    if not P or not DS or type(payload) ~= "table" then return end
    if not Comm._ShouldRespondToRecipeRequest() then return end
    local guild = currentGuild()
    local realm = payload.realm or currentRealm()
    local flagOn = isReceiveEnabled()
    local chars = Comm._SelectShareChars(flagOn, guild, realm)
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

local function whisperPresenceReply(sender, guild, realm)
    local mine = buildMyPresence(guild, realm)
    if mine then
        send(MSG_PRESENCE_REPLY, mine, "WHISPER", sender)
    end
end

local function handlePresence(payload, sender, isReply)
    local P = AltArmy.GuildShareProtocol
    local GSD = AltArmy.GuildShareData
    if not P or not GSD then return end
    local parsed = P.ParsePresence(payload)
    if not parsed then return end
    local guild = currentGuild()
    local realm = currentRealm()
    local isLoginAnnounce = parsed.login == true
    local unchanged = GSD.PresenceMatchesStored
        and GSD.PresenceMatchesStored(sender, parsed, realm)
    if unchanged then
        -- Login announces still get a whispered PR so the newcomer receives our presence
        -- even though their data is already stored (they missed our last guild broadcast).
        if not isReply and isLoginAnnounce then
            whisperPresenceReply(sender, guild, realm)
        end
        return
    end
    GSD.SaveReceived(sender, parsed, guild, realm)
    Comm.NotifyDataChanged()
    requestMissingRecipes(parsed, sender, realm)
    -- Announce/reply handshake: reply to an initial broadcast (not to a reply) so we don't loop.
    if not isReply and sender ~= playerName() then
        whisperPresenceReply(sender, guild, realm)
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
--- can never surface an error. Inbound is ignored when the flag is off, except RQ
--- which send-only clients still answer with RC.
function Comm._DispatchReceivedMessage(msgType, payload, rawSender)
    local sender = normalizeSender(rawSender)
    if isLocalSender(sender) then return end
    log(string.format("RECV %s from %s", formatMsgType(msgType), tostring(sender)))
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

local function onCommReceived(prefix, message, distribution, rawSender)
    if not commObj then return end
    pcall(function()
        local ok, msgType, payload = commObj:Deserialize(message)
        if not ok or type(msgType) ~= "string" then
            log(Comm._FormatUndecodableRecvLog(prefix, message, distribution, rawSender, ok, msgType))
            return
        end
        if not isInboundAllowed(msgType) then return end
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
    frame:RegisterEvent("PLAYER_GUILD_UPDATE")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGIN" then
            Comm.Init()
            knownGuild = currentGuild()
        elseif event == "PLAYER_ENTERING_WORLD" then
            local isInitialLogin, isReloadingUi = ...
            Comm.Init()
            knownGuild = currentGuild()
            if Comm._ShouldBroadcastOnEnteringWorld(isInitialLogin, isReloadingUi)
                and IsInGuild and IsInGuild() then
                if GuildRoster then pcall(GuildRoster) end
                Comm.Broadcast(true, true)
            end
        elseif event == "PLAYER_GUILD_UPDATE" then
            handlePlayerGuildUpdate()
        end
    end)
end
