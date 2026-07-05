-- AltArmy TBC — Guild data sharing: guild-chat main-name insertion.
-- Annotates guild chat messages from an alt with the poster's self-declared main, so you can
-- tell who is behind an unfamiliar alt name. Pure Transform is unit-tested; the CHAT_MSG_GUILD
-- filter is installed once and gated at call time by the feature flag + the user's setting.

if not AltArmy then return end

AltArmy.GuildChatMainName = AltArmy.GuildChatMainName or {}
local GCM = AltArmy.GuildChatMainName

--- Pure annotation. getMain(sender) -> main name (or nil). Appends the main in gray parentheses
--- when the sender is a known alt of a different main; otherwise returns the message unchanged.
function GCM.Transform(sender, message, getMain)
    if not sender or not getMain then return message end
    local main = getMain(sender)
    if not main or main == "" or main == sender then
        return message
    end
    return (message or "") .. " |cff808080(" .. main .. ")|r"
end

--- Strip any realm suffix ("Name-Realm" -> "Name") for main lookups.
local function stripRealm(name)
    if type(name) ~= "string" then return name end
    return name:match("^[^%-]+") or name
end

--- Returns a modified message when annotation applies, or nil to leave it untouched.
--- Gated here (rather than by install/uninstall) so toggling takes effect immediately.
function GCM.FilterMessage(message, author)
    local D = AltArmy.Debug
    if not (D and D.IsGuildShareEnabled and D.IsGuildShareEnabled()) then return nil end
    local GSS = AltArmy.GuildShareSettings
    if not (GSS and GSS.IsChatInsertionEnabled and GSS.IsChatInsertionEnabled()) then return nil end
    local GSD = AltArmy.GuildShareData
    if not GSD or not GSD.GetMainOf then return nil end
    local result = GCM.Transform(author, message, function(s)
        return GSD.GetMainOf(stripRealm(s))
    end)
    if result ~= message then
        return result
    end
    return nil
end

-- Install the guild chat filter once. It no-ops unless the feature flag + user setting are on.
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", function(_, _, msg, author, ...)
        local newMsg = GCM.FilterMessage(msg, author)
        if newMsg then
            return false, newMsg, author, ...
        end
        return false
    end)
end
