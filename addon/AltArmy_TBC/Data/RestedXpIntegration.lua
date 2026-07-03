-- AltArmy TBC — RestedXP (RXPGuides) integration helpers.
-- luacheck: globals C_AddOns IsAddOnLoaded RXPGuides RXPSettings RXPCSettings RXPData C_Timer
-- luacheck: globals LibStub UnitName GetRealmName

if not AltArmy then return end

AltArmy.RestedXpIntegration = AltArmy.RestedXpIntegration or {}
local RXI = AltArmy.RestedXpIntegration

local ACE_ADDON_NAME = "RXPGuides"
local RXP_ADDON_NAMES = { "RXPGuides_TBC", "RXPGuides" }
local RXP_LOGO_TEXTURE = "Textures/rxp_logo-64"
local PROMPT_RECHECK_DELAY = 0.5
local PROMPT_RECHECK_MAX_ATTEMPTS = 12

local promptRecheckAttempt = 0
local promptRecheckPending = false

local function isAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if IsAddOnLoaded then
        return IsAddOnLoaded(name)
    end
    return false
end

function RXI.GetLoadedAddonName()
    for i = 1, #RXP_ADDON_NAMES do
        if isAddOnLoaded(RXP_ADDON_NAMES[i]) then
            return RXP_ADDON_NAMES[i]
        end
    end
    return nil
end

function RXI.GetAceAddon()
    if LibStub then
        local aceAddon = LibStub("AceAddon-3.0", true)
        if aceAddon and aceAddon.GetAddon then
            local addon = aceAddon:GetAddon(ACE_ADDON_NAME, true)
            if addon then
                return addon
            end
        end
    end

    -- Unit-test fallback mimicking ace addon shape.
    local legacy = rawget(_G, "RXPGuides")
    if legacy and legacy.settings then
        return legacy
    end
    return nil
end

function RXI.GetAddon()
    return RXI.GetAceAddon()
end

function RXI.IsLoaded()
    if RXI.GetAceAddon() then
        return true
    end
    return RXI.GetLoadedAddonName() ~= nil
end

local function getRxpCharacterProfileKey()
    if not UnitName or not GetRealmName then return nil end
    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or not realm then return nil end
    return name .. " - " .. realm
end

local function resolveRxpcProfile()
    local charDb = rawget(_G, "RXPCSettings")
    if not charDb then return nil, nil end
    if charDb.profile then
        return charDb.profile, "RXPCSettings.profile"
    end
    if charDb.profiles and charDb.profileKeys then
        local charKey = getRxpCharacterProfileKey()
        if charKey then
            local profileName = charDb.profileKeys[charKey]
            if profileName and charDb.profiles[profileName] then
                return charDb.profiles[profileName], "RXPCSettings.profiles[" .. profileName .. "]"
            end
        end
    end
    return nil, nil
end

function RXI.GetProfile()
    local addon = RXI.GetAceAddon()
    if addon and addon.settings and addon.settings.profile then
        return addon.settings.profile, "ace.settings.profile"
    end

    local accountDb = rawget(_G, "RXPSettings")
    if accountDb and accountDb.profile then
        return accountDb.profile, "RXPSettings.profile"
    end

    return resolveRxpcProfile()
end

function RXI.AreSettingsReady()
    return RXI.GetProfile() ~= nil
end

local function readProfileFlag(profile, key)
    if not profile then return nil end
    local value = profile[key]
    if value == nil then
        -- RXP defaults unset recommendation toggles to enabled.
        return true
    end
    return value ~= false
end

function RXI.IsQuestRewardUpgradeRecommendationEnabled()
    local profile = RXI.GetProfile()
    if not profile then return nil end
    return readProfileFlag(profile, "enableQuestChoiceRecommendation")
end

function RXI.IsQuestRewardGoldRecommendationEnabled()
    local profile = RXI.GetProfile()
    if not profile then return nil end
    return readProfileFlag(profile, "enableQuestChoiceGoldRecommendation")
end

local QUEST_REWARD_PROFILE_KEYS = {
    "enableQuestChoiceRecommendation",
    "enableQuestChoiceGoldRecommendation",
}

local function applyQuestRewardFlagsToProfile(profile, enabled)
    if type(profile) ~= "table" then return end
    for i = 1, #QUEST_REWARD_PROFILE_KEYS do
        profile[QUEST_REWARD_PROFILE_KEYS[i]] = enabled == true
    end
end

function RXI.SetQuestRewardRecommendationsOnAllProfiles(enabled)
    local updated = false
    local rxpSettings = rawget(_G, "RXPSettings")
    if rxpSettings and type(rxpSettings.profiles) == "table" then
        for _, profile in pairs(rxpSettings.profiles) do
            applyQuestRewardFlagsToProfile(profile, enabled)
            updated = true
        end
    end
    local rxpData = rawget(_G, "RXPData")
    if rxpData and type(rxpData.defaultProfile) == "table" then
        applyQuestRewardFlagsToProfile(rxpData.defaultProfile.profile, enabled)
        updated = true
    end
    local activeProfile = RXI.GetProfile()
    if activeProfile then
        applyQuestRewardFlagsToProfile(activeProfile, enabled)
        updated = true
    end
    return updated
end

function RXI.SetQuestRewardUpgradeRecommendationEnabled(enabled)
    local profile = RXI.GetProfile()
    if not profile then return false end
    profile.enableQuestChoiceRecommendation = enabled == true
    return true
end

function RXI.SetQuestRewardGoldRecommendationEnabled(enabled)
    local profile = RXI.GetProfile()
    if not profile then return false end
    profile.enableQuestChoiceGoldRecommendation = enabled == true
    return true
end

function RXI.GetLogoTexturePath()
    local addonName = RXI.GetLoadedAddonName()
    if not addonName then return nil end
    return "Interface/AddOns/" .. addonName .. "/" .. RXP_LOGO_TEXTURE
end

function RXI.SchedulePromptRecheck()
    if promptRecheckPending or not RXI.IsLoaded() then return end
    if promptRecheckAttempt >= PROMPT_RECHECK_MAX_ATTEMPTS then
        return
    end
    promptRecheckPending = true
    promptRecheckAttempt = promptRecheckAttempt + 1
    if C_Timer and C_Timer.After then
        C_Timer.After(PROMPT_RECHECK_DELAY, function()
            promptRecheckPending = false
            local profile = RXI.GetProfile()
            if profile then
                promptRecheckAttempt = 0
            end
            local queue = AltArmy.OnboardingDialogQueue
            if queue and queue.RequestProcess then
                queue.RequestProcess()
            end
            if not profile and promptRecheckAttempt < PROMPT_RECHECK_MAX_ATTEMPTS then
                RXI.SchedulePromptRecheck()
            end
        end)
    else
        promptRecheckPending = false
    end
end

function RXI._ResetPromptRecheckForTests()
    promptRecheckAttempt = 0
    promptRecheckPending = false
end

local function onRxpAvailable()
    local queue = AltArmy.OnboardingDialogQueue
    if queue and queue.RequestProcess then
        queue.RequestProcess()
    end
    if not RXI.AreSettingsReady() then
        RXI.SchedulePromptRecheck()
    end
end

local rxpFrame = CreateFrame and CreateFrame("Frame")
if rxpFrame then
    rxpFrame:RegisterEvent("ADDON_LOADED")
    rxpFrame:RegisterEvent("PLAYER_LOGIN")
    rxpFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rxpFrame:SetScript("OnEvent", function(_, event, loadedName)
        if event == "ADDON_LOADED" then
            if loadedName ~= "RXPGuides" and loadedName ~= "RXPGuides_TBC" then return end
            onRxpAvailable()
        elseif event == "PLAYER_LOGIN" then
            if not RXI.IsLoaded() then return end
            onRxpAvailable()
        elseif event == "PLAYER_ENTERING_WORLD" then
            if not RXI.IsLoaded() then return end
            onRxpAvailable()
        end
    end)
end
