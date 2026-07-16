-- AltArmy TBC — Guild data sharing: guild-chat main-name insertion.
-- Annotates chat messages from an alt with the poster's self-declared main, so you can
-- tell who is behind an unfamiliar alt name. Also annotates guildmate online/offline
-- system messages the same way. Pure Transform is unit-tested; chat filters are installed
-- once and gated at call time by the feature flag, sharing opt-in, and chat settings.

if not AltArmy then return end

AltArmy.GuildChatMainName = AltArmy.GuildChatMainName or {}
local GCM = AltArmy.GuildChatMainName

GCM.CHANNEL_EVENTS = {
    say = { "CHAT_MSG_SAY" },
    yell = { "CHAT_MSG_YELL" },
    emote = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" },
    guild = { "CHAT_MSG_GUILD" },
    party = { "CHAT_MSG_PARTY" },
    raid = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" },
    -- Modern Classic uses INSTANCE_CHAT; older TBC builds used BATTLEGROUND.
    battleground = {
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER",
    },
    whisper = { "CHAT_MSG_WHISPER" },
}

local ONLINE_FALLBACK = "|Hplayer:%s|h[%s]|h has come online."
local OFFLINE_FALLBACK = "%s has gone offline."

--- Pure annotation. getMain(sender) -> main name (or nil). getMainClass(sender, main) -> classFile
--- (optional). Prefixes the main in class color when the sender is a known alt of a different main;
--- otherwise returns the message unchanged. colorByClass=false skips color escapes entirely.
function GCM.FormatMainPrefix(main, classFile, colorByClass)
    if colorByClass == false then
        return "[" .. (main or "") .. "] "
    end
    local CC = AltArmy.ClassColor
    local namePart = (CC and CC.formatName) and CC.formatName(main, classFile) or main
    return "[" .. namePart .. "] "
end

--- Strip any realm suffix ("Name-Realm" -> "Name") for main lookups.
local function stripRealm(name)
    if type(name) ~= "string" then return name end
    return name:match("^[^%-]+") or name
end

--- Annotate when sender is an alt of `getMain(sender)`. Optional `getLabel(sender, main)`
--- supplies the bracket text (override → preferred → main); defaults to main.
--- Optional `colorByClass` (default true) controls class-color escapes on the bracket label.
function GCM.Transform(sender, message, getMain, getMainClass, getLabel, colorByClass)
    if not sender or not getMain then return message end
    local senderKey = stripRealm(sender)
    local main = getMain(sender)
    if not main or main == "" or main == senderKey then
        return message
    end
    local label = (getLabel and getLabel(sender, main)) or main
    if not label or label == "" then
        label = main
    end
    local useColor = colorByClass ~= false
    local classFile = (useColor and getMainClass) and getMainClass(sender, main) or nil
    return GCM.FormatMainPrefix(label, classFile, useColor) .. (message or "")
end

--- Turn a printf-style global string into a Lua pattern with (.+) captures for each %s.
local function formatToPattern(fmt)
    local escaped = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

local function onlinePattern()
    return formatToPattern(_G.ERR_FRIEND_ONLINE_SS or ONLINE_FALLBACK)
end

local function offlinePattern()
    return formatToPattern(_G.ERR_FRIEND_OFFLINE_S or OFFLINE_FALLBACK)
end

--- Parse an online/offline system message. Returns name, "online"|"offline", or nil.
function GCM.ParseOnlineOffline(message)
    if type(message) ~= "string" then return nil end
    local name1 = message:match(onlinePattern())
    if name1 then
        return stripRealm(name1), "online"
    end
    local name = message:match(offlinePattern())
    if name then
        return stripRealm(name), "offline"
    end
    return nil
end

--- Resolve label + class for an alt sender. Returns label, classFile, or nil if no annotation.
local function resolveAnnotation(sender, getMain, getMainClass, getLabel, colorByClass)
    if not sender or not getMain then return nil end
    local senderKey = stripRealm(sender)
    local main = getMain(sender)
    if not main or main == "" or main == senderKey then
        return nil
    end
    local label = (getLabel and getLabel(sender, main)) or main
    if not label or label == "" then
        label = main
    end
    local useColor = colorByClass ~= false
    local classFile = (useColor and getMainClass) and getMainClass(sender, main) or nil
    return label, classFile, useColor
end

--- Insert class-colored main after the character name in an online/offline system message.
function GCM.TransformOnlineOffline(message, getMain, getMainClass, getLabel, colorByClass)
    local name, kind = GCM.ParseOnlineOffline(message)
    if not name then return message end
    local label, classFile, useColor = resolveAnnotation(
        name, getMain, getMainClass, getLabel, colorByClass)
    if not label then return message end
    local prefix = GCM.FormatMainPrefix(label, classFile, useColor)
    if kind == "online" then
        -- "|Hplayer:Name|h[Name]|h has come online." → insert after the closing |h
        local linkEnd = message:find("|h ", 1, true)
        if not linkEnd then return message end
        -- linkEnd points at start of "|h "; keep "|h" then insert " [Main] " before the rest
        local before = message:sub(1, linkEnd + 1) -- includes "|h"
        local after = message:sub(linkEnd + 3) -- after "|h "
        return before .. " " .. prefix .. after
    end
    -- offline: "Name has gone offline." → "Name [Main] has gone offline."
    local rest = message:match("^[^%s]+%s+(.+)$")
    if not rest then return message end
    return name .. " " .. prefix .. rest
end

--- Shared GuildShareData resolvers used by both chat and system-message filters.
local function buildResolvers(author)
    local GSD = AltArmy.GuildShareData
    local GSS = AltArmy.GuildShareSettings
    if not GSD or not GSD.GetMainOf then return nil end
    local senderName = stripRealm(author)
    local senderEntry = GSD.FindCharacter and GSD.FindCharacter(senderName) or nil
    return function(s)
        return GSD.GetMainOf(stripRealm(s))
    end, function(_, main)
        local mainEntry = GSD.FindCharacter and GSD.FindCharacter(main, senderEntry and senderEntry.realm)
        return mainEntry and mainEntry.classFile or nil
    end, function(_, main)
        local realm = senderEntry and senderEntry.realm
        local override = GSS and GSS.GetGroupOverrideName and GSS.GetGroupOverrideName(main, realm) or nil
        if override and override ~= "" then
            return override
        end
        local mainEntry = GSD.FindCharacter and GSD.FindCharacter(main, realm) or nil
        if mainEntry and mainEntry.displayName and mainEntry.displayName ~= "" then
            return mainEntry.displayName
        end
        return main
    end
end

local function chatInsertionAllowed()
    local D = AltArmy.Debug
    if not (D and D.IsGuildShareEnabled and D.IsGuildShareEnabled()) then return false end
    local GSS = AltArmy.GuildShareSettings
    -- Opt-out of guild sharing also disables chat main-name insertion.
    if not (GSS and GSS.IsSharingEnabled and GSS.IsSharingEnabled()) then return false end
    if not (GSS.IsChatInsertionEnabled and GSS.IsChatInsertionEnabled()) then return false end
    return true
end

local function chatInsertionClassColorEnabled()
    local GSS = AltArmy.GuildShareSettings
    if GSS and GSS.IsChatInsertionClassColorEnabled then
        return GSS.IsChatInsertionClassColorEnabled()
    end
    return true
end

--- Returns a modified message when annotation applies, or nil to leave it untouched.
--- Gated here (rather than by install/uninstall) so toggling takes effect immediately.
function GCM.FilterMessage(message, author, channelKey)
    if not chatInsertionAllowed() then return nil end
    local GSS = AltArmy.GuildShareSettings
    if channelKey and GSS.IsChatInsertionChannelEnabled
        and not GSS.IsChatInsertionChannelEnabled(channelKey) then
        return nil
    end
    local getMain, getMainClass, getLabel = buildResolvers(author)
    if not getMain then return nil end
    local result = GCM.Transform(
        author, message, getMain, getMainClass, getLabel, chatInsertionClassColorEnabled())
    if result ~= message then
        return result
    end
    return nil
end

--- Annotate online/offline system messages when chat insertion is enabled.
function GCM.FilterSystemMessage(message)
    if not chatInsertionAllowed() then return nil end
    local name = GCM.ParseOnlineOffline(message)
    if not name then return nil end
    local getMain, getMainClass, getLabel = buildResolvers(name)
    if not getMain then return nil end
    local result = GCM.TransformOnlineOffline(
        message, getMain, getMainClass, getLabel, chatInsertionClassColorEnabled())
    if result ~= message then
        return result
    end
    return nil
end

local function installChatFilter(channelKey, eventName)
    if not ChatFrame_AddMessageEventFilter then return end
    ChatFrame_AddMessageEventFilter(eventName, function(_, _, msg, author, ...)
        local newMsg = GCM.FilterMessage(msg, author, channelKey)
        if newMsg then
            return false, newMsg, author, ...
        end
        return false
    end)
end

for channelKey, events in pairs(GCM.CHANNEL_EVENTS) do
    for _, eventName in ipairs(events) do
        installChatFilter(channelKey, eventName)
    end
end

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg, ...)
        local newMsg = GCM.FilterSystemMessage(msg)
        if newMsg then
            return false, newMsg, ...
        end
        return false
    end)
end
