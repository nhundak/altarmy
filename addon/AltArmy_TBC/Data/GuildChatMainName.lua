-- AltArmy TBC — Guild data sharing: guild-chat main-name insertion.
-- Annotates chat messages from an alt with the poster's self-declared main, so you can
-- tell who is behind an unfamiliar alt name. Pure Transform is unit-tested; chat filters
-- are installed once and gated at call time by the feature flag + the user's settings.

if not AltArmy then return end

AltArmy.GuildChatMainName = AltArmy.GuildChatMainName or {}
local GCM = AltArmy.GuildChatMainName

GCM.CHANNEL_EVENTS = {
    guild = { "CHAT_MSG_GUILD" },
    party = { "CHAT_MSG_PARTY" },
    raid = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" },
    whisper = { "CHAT_MSG_WHISPER" },
}

--- Pure annotation. getMain(sender) -> main name (or nil). getMainClass(sender, main) -> classFile
--- (optional). Prefixes the main in class color when the sender is a known alt of a different main;
--- otherwise returns the message unchanged.
function GCM.FormatMainPrefix(main, classFile)
    local CC = AltArmy.ClassColor
    local namePart = (CC and CC.formatName) and CC.formatName(main, classFile) or main
    return "[" .. namePart .. "] "
end

--- Strip any realm suffix ("Name-Realm" -> "Name") for main lookups.
local function stripRealm(name)
    if type(name) ~= "string" then return name end
    return name:match("^[^%-]+") or name
end

function GCM.Transform(sender, message, getMain, getMainClass)
    if not sender or not getMain then return message end
    local senderKey = stripRealm(sender)
    local main = getMain(sender)
    if not main or main == "" or main == senderKey then
        return message
    end
    local classFile = getMainClass and getMainClass(sender, main) or nil
    return GCM.FormatMainPrefix(main, classFile) .. (message or "")
end

--- Returns a modified message when annotation applies, or nil to leave it untouched.
--- Gated here (rather than by install/uninstall) so toggling takes effect immediately.
function GCM.FilterMessage(message, author, channelKey)
    local D = AltArmy.Debug
    if not (D and D.IsGuildShareEnabled and D.IsGuildShareEnabled()) then return nil end
    local GSS = AltArmy.GuildShareSettings
    if not (GSS and GSS.IsChatInsertionEnabled and GSS.IsChatInsertionEnabled()) then return nil end
    if channelKey and GSS.IsChatInsertionChannelEnabled
        and not GSS.IsChatInsertionChannelEnabled(channelKey) then
        return nil
    end
    local GSD = AltArmy.GuildShareData
    if not GSD or not GSD.GetMainOf then return nil end
    local senderName = stripRealm(author)
    local senderEntry = GSD.FindCharacter and GSD.FindCharacter(senderName) or nil
    local result = GCM.Transform(author, message, function(s)
        return GSD.GetMainOf(stripRealm(s))
    end, function(_, main)
        local mainEntry = GSD.FindCharacter and GSD.FindCharacter(main, senderEntry and senderEntry.realm)
        return mainEntry and mainEntry.classFile or nil
    end)
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
