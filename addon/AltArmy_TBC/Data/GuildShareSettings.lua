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

-- *** Main selection + display name (per realm) ***

function GSS.GetMain(realm)
    return ensure().mains[realm or currentRealm()]
end

function GSS.SetMain(realm, name)
    ensure().mains[realm or currentRealm()] = name
end

GSS.DISPLAY_NAME_MAX_LENGTH = 20

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
