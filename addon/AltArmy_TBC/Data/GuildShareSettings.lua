-- AltArmy TBC — Guild data sharing: the user's own sharing preferences (send-side privacy).
-- Backed by AltArmyTBC_SharingSettings. Sharing defaults to OFF (opt-in).
--
-- Two send-set resolvers are exposed for the comm layer:
--   GetShareableCharacters(guild, realm) — opt-in set, used when the feature flag is ON.
--   GetAllGuildedCharacters(guild, realm) — default set (ignores settings), used when the flag is OFF.
-- The flag branch itself lives in GuildShareComm; this module has no dependency on Debug.

if not AltArmy then return end

AltArmy.GuildShareSettings = AltArmy.GuildShareSettings or {}
local GSS = AltArmy.GuildShareSettings

local function ensure()
    _G.AltArmyTBC_SharingSettings = _G.AltArmyTBC_SharingSettings or {}
    local s = _G.AltArmyTBC_SharingSettings
    if s.enabled == nil then s.enabled = false end
    if s.chatInsertion == nil then s.chatInsertion = true end
    s.mains = s.mains or {}
    s.displayNames = s.displayNames or {}
    s.optOut = s.optOut or {}
    s.nonGuildedOptIn = s.nonGuildedOptIn or {}
    s.onboardingCompleted = s.onboardingCompleted or {}
    s.groupUiPrefs = s.groupUiPrefs or {}
    s.chatInsertionChannels = s.chatInsertionChannels or {}
    local channels = s.chatInsertionChannels
    if channels.guild == nil then channels.guild = true end
    if channels.party == nil then channels.party = true end
    if channels.raid == nil then channels.raid = true end
    if channels.whisper == nil then channels.whisper = true end
    return s
end
GSS._Ensure = ensure

local function currentRealm()
    local DS = AltArmy.DataStore
    if DS and DS.GetCurrentPlayerRealm then
        local r = DS:GetCurrentPlayerRealm()
        if r and r ~= "" then return r end
    end
    return (GetRealmName and GetRealmName()) or ""
end
GSS._CurrentRealm = currentRealm

local function currentGuild()
    if GetGuildInfo then
        local g = GetGuildInfo("player")
        if g and g ~= "" then return g end
    end
    return nil
end
GSS._CurrentGuild = currentGuild

--- Characters on a realm as a name->charData map (canonical account store).
local function charactersOnRealm(realm)
    local DS = AltArmy.DataStore
    if DS and DS.GetCharacters then
        return DS:GetCharacters(realm) or {}
    end
    local data = _G.AltArmyTBC_Data
    return (data and data.Characters and data.Characters[realm]) or {}
end

-- *** Master enable ***

function GSS.IsSharingEnabled()
    return ensure().enabled == true
end

function GSS.SetSharingEnabled(on)
    ensure().enabled = on == true
end

-- *** Chat insertion (Phase 6) ***

function GSS.IsChatInsertionEnabled()
    return ensure().chatInsertion == true
end

function GSS.SetChatInsertionEnabled(on)
    ensure().chatInsertion = on == true
end

GSS.CHAT_INSERTION_CHANNEL_ORDER = { "guild", "party", "raid", "whisper" }
GSS.CHAT_INSERTION_CHANNEL_LABELS = {
    guild = "Guild",
    party = "Party",
    raid = "Raid",
    whisper = "Whisper",
}

function GSS.GetChatInsertionChannels()
    local s = ensure()
    return s.chatInsertionChannels
end

function GSS.IsChatInsertionChannelEnabled(key)
    local channels = GSS.GetChatInsertionChannels()
    return channels[key] ~= false
end

function GSS.SetChatInsertionChannelEnabled(key, on)
    ensure().chatInsertionChannels[key] = on ~= false
end

--- Comma-separated enabled labels with chat colors. Returns "None" when nothing is enabled.
function GSS.FormatChatInsertionChannelColoredLabel(key, labelMap)
    labelMap = labelMap or GSS.CHAT_INSERTION_CHANNEL_LABELS
    local label = labelMap[key] or key
    local color = GSS.CHAT_INSERTION_CHANNEL_COLORS and GSS.CHAT_INSERTION_CHANNEL_COLORS[key]
    local CC = AltArmy.ClassColor
    if color and CC and CC.formatHex then
        return CC.formatHex(color[1], color[2], color[3], label)
    end
    return label
end

function GSS.FormatChatInsertionChannelSummary(keys, labelMap, filter)
    filter = filter or {}
    local selected = {}
    for _, key in ipairs(keys) do
        if filter[key] ~= false then
            selected[#selected + 1] = GSS.FormatChatInsertionChannelColoredLabel(key, labelMap)
        end
    end
    if #selected == 0 then
        return "None"
    end
    return table.concat(selected, ", ")
end

GSS.CHAT_INSERTION_CHANNEL_COLORS = {
    guild = { 0.063, 0.816, 0.063 },
    party = { 0.651, 0.816, 1.0 },
    raid = { 1.0, 0.498, 0.0 },
    whisper = { 1.0, 0.502, 1.0 },
}

--- Pick the top-ranked character as main when none is saved yet.
function GSS.EnsureDefaultMainIfMissing(realm)
    realm = realm or currentRealm()
    local existing = GSS.GetMain(realm)
    if existing then return existing end
    local GSO = AltArmy.GuildShareOnboarding
    local DS = AltArmy.DataStore
    if not GSO or not GSO.BuildRealmCharEntries or not DS or not DS.GetCharacters then
        return nil
    end
    local entries = GSO.BuildRealmCharEntries(DS:GetCharacters(realm) or {})
    local top = entries[1]
    if not top or not top.id then return nil end
    GSS.SetMain(realm, top.id)
    if not GSS.GetDisplayName(realm) then
        GSS.SetDisplayName(realm, top.id)
    end
    return top.id
end

-- *** Main selection + display name (per realm) ***

function GSS.GetMain(realm)
    return ensure().mains[realm or currentRealm()]
end

function GSS.SetMain(realm, name)
    ensure().mains[realm or currentRealm()] = name
end

GSS.DISPLAY_NAME_MAX_LENGTH = 20

--- Whether changing main should also update the preferred/display name.
--- Sync when the preferred name is empty, or still matches the old main
--- (case-insensitive). Keep a custom preferred name otherwise.
function GSS.ShouldSyncDisplayNameWithMain(oldMain, oldDisplayName)
    if type(oldDisplayName) ~= "string" or oldDisplayName == "" then
        return true
    end
    if type(oldMain) ~= "string" or oldMain == "" then
        return false
    end
    return oldMain:lower() == oldDisplayName:lower()
end

--- Trim a display name to the allowed length, or nil when empty/absent.
function GSS.NormalizeDisplayName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if #name > GSS.DISPLAY_NAME_MAX_LENGTH then
        return name:sub(1, GSS.DISPLAY_NAME_MAX_LENGTH)
    end
    return name
end

function GSS.GetDisplayName(realm)
    return GSS.NormalizeDisplayName(ensure().displayNames[realm or currentRealm()])
end

function GSS.SetDisplayName(realm, name)
    ensure().displayNames[realm or currentRealm()] = GSS.NormalizeDisplayName(name)
end

-- *** Per-group local UI prefs (Guild tab pin / override name) ***

local function groupUiEntry(main, realm, create)
    if type(main) ~= "string" or main == "" then return nil end
    realm = realm or currentRealm()
    local byRealm = ensure().groupUiPrefs[realm]
    if not byRealm then
        if not create then return nil end
        byRealm = {}
        ensure().groupUiPrefs[realm] = byRealm
    end
    local entry = byRealm[main]
    if not entry then
        if not create then return nil end
        entry = {}
        byRealm[main] = entry
    end
    return entry
end

function GSS.IsGroupPinned(main, realm)
    local entry = groupUiEntry(main, realm, false)
    return entry ~= nil and entry.pin == true
end

function GSS.SetGroupPinned(main, realm, pinned)
    if type(main) ~= "string" or main == "" then return end
    realm = realm or currentRealm()
    if pinned then
        local entry = groupUiEntry(main, realm, true)
        entry.pin = true
    else
        local entry = groupUiEntry(main, realm, false)
        if not entry then return end
        entry.pin = nil
        if not entry.overrideName then
            ensure().groupUiPrefs[realm][main] = nil
        end
    end
end

function GSS.GetGroupOverrideName(main, realm)
    local entry = groupUiEntry(main, realm, false)
    if not entry then return nil end
    return GSS.NormalizeDisplayName(entry.overrideName)
end

function GSS.SetGroupOverrideName(main, realm, name)
    if type(main) ~= "string" or main == "" then return end
    realm = realm or currentRealm()
    local normalized = GSS.NormalizeDisplayName(name)
    if normalized then
        local entry = groupUiEntry(main, realm, true)
        entry.overrideName = normalized
    else
        local entry = groupUiEntry(main, realm, false)
        if not entry then return end
        entry.overrideName = nil
        if not entry.pin then
            ensure().groupUiPrefs[realm][main] = nil
        end
    end
end

function GSS.ClearGroupUiPrefs(main, realm)
    if type(main) ~= "string" or main == "" then return end
    realm = realm or currentRealm()
    local byRealm = ensure().groupUiPrefs[realm]
    if byRealm then
        byRealm[main] = nil
    end
end

--- Main + display name for a presence broadcast.
--- Only an explicitly saved main is sent (receivers guess when nil so grouping still works).
--- Display falls back to the saved main name when the player has not set a preferred name.
--- `chars` is unused; kept for call-site compatibility.
function GSS.ResolvePresenceMainAndDisplay(_chars, realm)
    realm = realm or currentRealm()
    local mainName = GSS.GetMain(realm)
    local displayName = GSS.GetDisplayName(realm)
    if not displayName and mainName then
        displayName = mainName
    end
    return mainName, displayName
end

-- *** Onboarding completion (per realm) ***

function GSS.IsOnboardingCompleted(realm)
    return ensure().onboardingCompleted[realm or currentRealm()] == true
end

function GSS.SetOnboardingCompleted(realm, done)
    ensure().onboardingCompleted[realm or currentRealm()] = done == true
end

-- *** Per-character opt-out (guilded characters) ***

function GSS.IsCharacterOptedOut(name, realm)
    local byRealm = ensure().optOut[realm or currentRealm()]
    return byRealm ~= nil and byRealm[name] == true
end

function GSS.SetCharacterOptedOut(name, realm, optedOut)
    realm = realm or currentRealm()
    local s = ensure()
    s.optOut[realm] = s.optOut[realm] or {}
    s.optOut[realm][name] = optedOut and true or nil
end

-- *** Non-guilded opt-in (character -> guild to share it with) ***

function GSS.GetNonGuildedOptInGuild(name, realm)
    local byRealm = ensure().nonGuildedOptIn[realm or currentRealm()]
    return byRealm and byRealm[name] or nil
end

function GSS.IsNonGuildedOptedIn(name, realm)
    return GSS.GetNonGuildedOptInGuild(name, realm) ~= nil
end

function GSS.SetNonGuildedOptIn(name, realm, guild)
    realm = realm or currentRealm()
    local s = ensure()
    s.nonGuildedOptIn[realm] = s.nonGuildedOptIn[realm] or {}
    s.nonGuildedOptIn[realm][name] = guild
end

-- *** Per-character share mode (tri-state UI) ***

GSS.CHARACTER_SHARE_MODE_LABELS = {
    share = "Always share",
    dont_share = "Never share",
}

function GSS.GetCharacterShareModeDefaultLabel()
    if GSS.IsSharingEnabled() then
        return "Use global setting (share)"
    end
    return "Use global setting (don't share)"
end

function GSS.GetCharacterShareModeEntries()
    local labels = GSS.CHARACTER_SHARE_MODE_LABELS
    return {
        { id = "default", label = GSS.GetCharacterShareModeDefaultLabel() },
        { id = "share", label = labels.share },
        { id = "dont_share", label = labels.dont_share },
    }
end

function GSS.GetCharacterShareMode(name, realm)
    if GSS.IsCharacterOptedOut(name, realm) then
        return "dont_share"
    end
    if GSS.IsNonGuildedOptedIn(name, realm) then
        return "share"
    end
    return "default"
end

function GSS.SetCharacterShareMode(name, realm, mode)
    realm = realm or currentRealm()
    if mode == "share" then
        GSS.SetCharacterOptedOut(name, realm, false)
        local guild = currentGuild()
        if guild then
            GSS.SetNonGuildedOptIn(name, realm, guild)
        end
    elseif mode == "dont_share" then
        GSS.SetCharacterOptedOut(name, realm, true)
        GSS.SetNonGuildedOptIn(name, realm, nil)
    else
        GSS.SetCharacterOptedOut(name, realm, false)
        GSS.SetNonGuildedOptIn(name, realm, nil)
    end
end

-- *** Send-set resolvers ***

local function makeEntry(name, realm, char)
    return { name = name, realm = realm, char = char }
end

--- Default set (used when the feature flag is OFF): every one of my characters in `guild`
--- on `realm`, ignoring the user's sharing settings entirely.
function GSS.GetAllGuildedCharacters(guild, realm)
    guild = guild or currentGuild()
    realm = realm or currentRealm()
    local out = {}
    if not guild then return out end
    for name, char in pairs(charactersOnRealm(realm)) do
        if char and char.guildName == guild then
            out[#out + 1] = makeEntry(name, realm, char)
        end
    end
    return out
end

--- Opt-in set (used when the feature flag is ON): empty unless sharing is enabled; then
--- guilded characters that are not opted out, plus non-guilded characters opted in to `guild`.
function GSS.GetShareableCharacters(guild, realm)
    guild = guild or currentGuild()
    realm = realm or currentRealm()
    local out = {}
    if not guild or not GSS.IsSharingEnabled() then return out end
    for name, char in pairs(charactersOnRealm(realm)) do
        if char then
            if char.guildName == guild then
                if not GSS.IsCharacterOptedOut(name, realm) then
                    out[#out + 1] = makeEntry(name, realm, char)
                end
            elseif char.guildName == nil and GSS.GetNonGuildedOptInGuild(name, realm) == guild then
                out[#out + 1] = makeEntry(name, realm, char)
            end
        end
    end
    return out
end
