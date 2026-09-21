-- AltArmy TBC — Internal character data store (core).
-- Persists character data to SavedVariables (AltArmyTBC_Data), shared across all characters on the account.
-- Domain modules (DataStoreCharacter, DataStoreContainers, etc.) attach scans and getters to AltArmy.DataStore.
-- TBC-compatible; no external DataStore dependency.
-- luacheck: globals C_EventUtils

if not AltArmy then return end

AltArmy.DataStore = AltArmy.DataStore or {}

local DS = AltArmy.DataStore

-- Existence-check, not version-check: GetMaxPlayerLevel() reflects whatever
-- cap the running client actually has (70 on TBC Classic, 60 on WoW Forever),
-- so this stays correct across clients without needing to detect which one
-- we're on. Falls back to TBC's 70 if the API isn't present.
DS.MAX_LEVEL = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 70

-- Version check, not existence check: unlike most of this file, there's no API
-- to defensively probe here — selecting which stat-weight data table to use
-- (see Data/Gear/PawnScalesForever.lua) genuinely requires knowing which client
-- is running. 16001 is WoW Forever's confirmed Interface number (see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md). Falls back to false (today's
-- TBC behavior) if GetBuildInfo isn't present.
DS.IsWowForever = (GetBuildInfo and select(4, GetBuildInfo()) == 16001) or false

local DATA_VERSIONS = {
    character = 1,
    guildMembership = 1,
    containers = 2,
    equipment = 1,
    gearScores = 1,
    professions = 1,
    reputations = 2,
    mail = 1,
    auctions = 1,
    currencies = 1,
    levelHistory = 1,
    talents = 2,
    legacyTalents = 1,
}

AltArmyTBC_Data = AltArmyTBC_Data or {}
AltArmyTBC_Data.Characters = AltArmyTBC_Data.Characters or {}
AltArmyTBC_Data.OrphanImports = AltArmyTBC_Data.OrphanImports or {}

-- SavedVariables are applied after this file can run; the global table may be replaced, so
-- re-point these in SyncAccountDataRoot (ADDON_LOADED + VARIABLES_LOADED) or writes (e.g.
-- RecipeReagents) can go to a stale table and not persist across /reload.
AltArmy.DB = AltArmyTBC_Data
DS.accountData = AltArmyTBC_Data

local function SyncAccountDataRoot()
    DS.accountData = AltArmyTBC_Data
    AltArmy.DB = AltArmyTBC_Data
end

local function GetCurrentName()
    if UnitName then
        local name = UnitName("player")
        if name and name ~= "" then return name end
    end
    return GetUnitName and GetUnitName("player") or ""
end

local function GetCurrentRealm()
    return (GetRealmName and GetRealmName()) or ""
end

local function GetCurrentCharTable()
    local realm = GetCurrentRealm()
    local name = GetCurrentName()
    if not realm or not name or name == "" then return nil end
    if not AltArmyTBC_Data.Characters[realm] then
        AltArmyTBC_Data.Characters[realm] = {}
    end
    local char = AltArmyTBC_Data.Characters[realm][name]
    if not char then
        char = {}
        AltArmyTBC_Data.Characters[realm][name] = char
    end
    return char
end

local function MigrateDataVersions(data)
    data = data or AltArmyTBC_Data
    for _, chars in pairs(data.Characters or {}) do
        for _, char in pairs(chars) do
            char.dataVersions = char.dataVersions or {}
            if char.name and not char.dataVersions.character then
                char.dataVersions.character = 1
            end
            if char.Containers and next(char.Containers) and not char.dataVersions.containers then
                char.dataVersions.containers = 1
            end
            if char.Inventory and next(char.Inventory) and not char.dataVersions.equipment then
                char.dataVersions.equipment = 1
            end
        end
    end
end

DS._GetCurrentCharTable = GetCurrentCharTable
DS._MigrateDataVersions = MigrateDataVersions
DS._DATA_VERSIONS = DATA_VERSIONS

function DS:GetRealms()
    local out = {}
    for realm in pairs(AltArmyTBC_Data.Characters) do
        out[realm] = true
    end
    return out
end

function DS:GetCharacters(realm)
    if not realm then return {} end
    return AltArmyTBC_Data.Characters[realm] or {}
end

function DS:GetCharacter(name, realm)
    if not name or not realm then return nil end
    local realmTable = AltArmyTBC_Data.Characters[realm]
    return realmTable and realmTable[name] or nil
end

function DS:GetCurrentCharacter()
    return GetCurrentCharTable()
end

function DS:GetCurrentPlayerName()
    return GetCurrentName()
end

function DS:GetCurrentPlayerRealm()
    return GetCurrentRealm()
end

function DS:GetCurrentPlayerIdentity()
    return GetCurrentName(), GetCurrentRealm()
end

function DS:IsCurrentCharacter(name, realm)
    if not name or not realm then return false end
    return name == GetCurrentName() and realm == GetCurrentRealm()
end

--- Iterate all stored characters. fn(realm, charName, charData) — return true to stop early.
function DS:ForEachCharacter(fn)
    if not fn then return end
    for realm in pairs(self:GetRealms()) do
        for charName, charData in pairs(self:GetCharacters(realm)) do
            if fn(realm, charName, charData) == true then
                return
            end
        end
    end
end

function DS:HasModuleData(char, moduleName)
    if not char or not moduleName then return false end
    local v = (char.dataVersions and char.dataVersions[moduleName]) or 0
    return v > 0
end

function DS:GetDataVersion(char, moduleName)
    if not char or not moduleName then return 0 end
    return (char.dataVersions and char.dataVersions[moduleName]) or 0
end

function DS:NeedsRescan(char, moduleName)
    if not char or not moduleName then return true end
    local current = DATA_VERSIONS[moduleName]
    if not current then return false end
    return (DS:GetDataVersion(char, moduleName) or 0) < current
end

function DS:GetAllDataVersions(char)
    if not char then return {} end
    local out = {}
    for k, v in pairs(char.dataVersions or {}) do
        out[k] = v
    end
    return out
end

function DS:DeleteCharacter(name, realm)
    if not name or not realm then return end
    local realmTable = AltArmyTBC_Data.Characters[realm]
    if not realmTable then return end
    realmTable[name] = nil
    if AltArmy.Characters and AltArmy.Characters.InvalidateView then
        AltArmy.Characters:InvalidateView()
    end
end

-- Event frame and dispatch
local frame = CreateFrame("Frame", nil, UIParent)

--- Registers an event only if the running client recognizes it (checked via
--- C_EventUtils.IsEventValid when available, per Thaoky/AddonFactory's
--- cross-flavor pattern), falling back to a pcall so an unrecognized event
--- can never hard-error RegisterEvent on any client, old or new.
local function SafeRegisterEvent(eventName)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(eventName) then
        return
    end
    pcall(frame.RegisterEvent, frame, eventName)
end

--- Patch 12.0+ clients (Forever included) can hand combat-log fields to addons as
--- Secret Values that error on any operation beyond store/pass. `canaccessvalue()`
--- (existence-checked) is the guard, matching DataStoreLevelHistory.lua's copy and
--- our DataStoreProfessions.lua fix.
local function canAccessSecretValue(value)
    if _G.canaccessvalue then
        return _G.canaccessvalue(value)
    end
    return true
end

SafeRegisterEvent("ADDON_LOADED")
SafeRegisterEvent("VARIABLES_LOADED")
SafeRegisterEvent("PLAYER_ALIVE")
SafeRegisterEvent("PLAYER_ENTERING_WORLD")
SafeRegisterEvent("PLAYER_GUILD_UPDATE")
SafeRegisterEvent("PLAYER_LOGOUT")
SafeRegisterEvent("PLAYER_MONEY")
SafeRegisterEvent("PLAYER_XP_UPDATE")
SafeRegisterEvent("PLAYER_LEVEL_UP")
SafeRegisterEvent("TIME_PLAYED_MSG")
SafeRegisterEvent("BAG_UPDATE")
SafeRegisterEvent("BANKFRAME_OPENED")
SafeRegisterEvent("BANKFRAME_CLOSED")
SafeRegisterEvent("PLAYERBANKSLOTS_CHANGED")
SafeRegisterEvent("PLAYER_EQUIPMENT_CHANGED")
SafeRegisterEvent("SKILL_LINES_CHANGED")
SafeRegisterEvent("TRADE_SKILL_SHOW")
SafeRegisterEvent("TRADE_SKILL_CLOSE")
-- Retail/Forever-shaped trigger for the C_TradeSkillUI recipe scan (see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Eighth"): on those clients TRADE_SKILL_SHOW alone
-- doesn't signal that recipe data is actually loaded, this event does. SafeRegisterEvent no-ops on
-- clients without it (TBC Classic included, where TRADE_SKILL_SHOW's own timer already covers it).
SafeRegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
SafeRegisterEvent("CRAFT_SHOW")
SafeRegisterEvent("CHAT_MSG_SKILL")
SafeRegisterEvent("CHAT_MSG_SYSTEM")
SafeRegisterEvent("NEW_RECIPE_LEARNED")
SafeRegisterEvent("UPDATE_FACTION")
SafeRegisterEvent("MAIL_SHOW")
SafeRegisterEvent("MAIL_INBOX_UPDATE")
SafeRegisterEvent("MAIL_CLOSED")
-- TBC Anniversary often does not fire MAIL_CLOSED; interaction-manager covers that client.
SafeRegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
SafeRegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
SafeRegisterEvent("AUCTION_HOUSE_SHOW")
SafeRegisterEvent("AUCTION_HOUSE_CLOSED")
SafeRegisterEvent("AUCTION_OWNED_LIST_UPDATE")
SafeRegisterEvent("AUCTION_BIDDER_LIST_UPDATE")
-- Retail/Forever-shaped C_AuctionHouse equivalents of the two legacy events above (see
-- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md); SafeRegisterEvent no-ops on clients without them.
SafeRegisterEvent("OWNED_AUCTIONS_UPDATED")
SafeRegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
SafeRegisterEvent("BIDS_UPDATED")
-- Forever's client is missing CombatLogGetCurrentEventInfo (confirmed via
-- /altarmy debug apicheck; see docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md), and the
-- OnEvent handler below is a no-op without it — registering anyway triggers a spurious
-- ADDON_ACTION_FORBIDDEN, so skip registration entirely when the API isn't there.
if CombatLogGetCurrentEventInfo then
    SafeRegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
SafeRegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
SafeRegisterEvent("UPDATE_INSTANCE_INFO")
SafeRegisterEvent("RAID_INSTANCE_WELCOME")

local isMailOpen = false
local isAuctionHouseOpen = false
local lastReputationScan = 0
local isBankOpen = false
local MAIL_INTERACTION_TYPE = (
    _G.Enum and _G.Enum.PlayerInteractionType and _G.Enum.PlayerInteractionType.MailInfo
) or 17

local function HookMailFrameVisibility()
    local mf = _G.MailFrame
    if not mf or mf.altArmyDataStoreMailHooked then
        return
    end
    mf.altArmyDataStoreMailHooked = true
    if mf.HookScript then
        mf:HookScript("OnShow", function()
            isMailOpen = true
        end)
        mf:HookScript("OnHide", function()
            isMailOpen = false
        end)
    end
end

HookMailFrameVisibility()

function DS:IsBankOpen()
    return isBankOpen
end

--- Called on PLAYER_GUILD_UPDATE to keep guild membership current without a relog.
--- WoW can fire this event twice for a single join/leave; skip when nothing changed.
function DS:HandlePlayerGuildUpdate()
    local char = GetCurrentCharTable()
    if not char then return end
    local prevGuild = char.guildName
    local liveGuild
    if GetGuildInfo then
        local g = GetGuildInfo("player")
        liveGuild = (g ~= "" and g) or nil
    end
    if liveGuild == prevGuild and DS.HasModuleData and DS:HasModuleData(char, "guildMembership") then
        return
    end
    if DS.ScanGuildMembership then
        DS:ScanGuildMembership()
    end
end

local REPUTATION_SCAN_THROTTLE = 3
local BAG_SCAN_DELAY = 3
--- Equipment links can be nil on PEW/ALIVE before item cache is ready (same class of bug as bags).
local EQUIPMENT_SCAN_DELAY = 3
local TRADE_SKILL_SCAN_DELAY = 0.5
--- Deferred reagent-only retry (Cooldowns RecipeReagents); avoids TRADE_SKILL_UPDATE loops.
local TRADE_SKILL_REAGENT_RETRY_DELAY = 1.25
local CRAFT_REAGENT_RETRY_DELAY = 1.25

local bagScanFrame = CreateFrame("Frame", nil, UIParent)
bagScanFrame:SetScript("OnUpdate", nil)
bagScanFrame.elapsed = 0

local equipmentScanFrame = CreateFrame("Frame", nil, UIParent)
equipmentScanFrame:SetScript("OnUpdate", nil)
equipmentScanFrame.elapsed = 0

-- Run professions + reputations again after delay (skill/faction data can load late)
local LATE_SCAN_DELAY = 2
local lateScanFrame = CreateFrame("Frame", nil, UIParent)
lateScanFrame:SetScript("OnUpdate", nil)
lateScanFrame.elapsed = 0

local tradeSkillScanFrame = CreateFrame("Frame", nil, UIParent)
tradeSkillScanFrame:SetScript("OnUpdate", nil)
tradeSkillScanFrame.elapsed = 0

local craftScanFrame = CreateFrame("Frame", nil, UIParent)
craftScanFrame:SetScript("OnUpdate", nil)
craftScanFrame.elapsed = 0

local tradeSkillReagentRetryFrame = CreateFrame("Frame", nil, UIParent)
tradeSkillReagentRetryFrame:SetScript("OnUpdate", nil)
tradeSkillReagentRetryFrame.elapsed = 0

local craftReagentRetryFrame = CreateFrame("Frame", nil, UIParent)
craftReagentRetryFrame:SetScript("OnUpdate", nil)
craftReagentRetryFrame.elapsed = 0

-- After a successful cast, the cooldown isn't always queryable on the same frame.
local cooldownAfterCastFrame = CreateFrame("Frame", nil, UIParent)
cooldownAfterCastFrame:SetScript("OnUpdate", nil)
cooldownAfterCastFrame.elapsed = 0
cooldownAfterCastFrame.pendingSpellId = nil

function DS:IsMailOpen()
    return isMailOpen == true
end

frame:SetScript("OnEvent", function(_, event, ...)
    local addonName, a1, a3 = ...
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not CombatLogGetCurrentEventInfo or not UnitGUID then return end
        local payload = { CombatLogGetCurrentEventInfo() }
        if DS.HandleCombatLogForLevelHistory then
            DS:HandleCombatLogForLevelHistory(payload)
        end
        local CD = AltArmy and AltArmy.CooldownData
        if not CD or not CD.RecordSuccessfulTransmuteCast then return end
        local subevent = payload[2]
        if not canAccessSecretValue(subevent) or subevent ~= "SPELL_CAST_SUCCESS" then return end
        local srcGUID = payload[4]
        local playerGUID = UnitGUID("player")
        if not playerGUID or srcGUID ~= playerGUID then return end
        local spellId = payload[12]
        if type(spellId) ~= "number" then return end
        local char = GetCurrentCharTable()
        if char then
            CD.RecordSuccessfulTransmuteCast(char, spellId)
            if CD.RecordSuccessfulSphereCast then
                CD.RecordSuccessfulSphereCast(char, spellId)
            end
            cooldownAfterCastFrame.pendingSpellId = spellId
            cooldownAfterCastFrame.elapsed = 0
            cooldownAfterCastFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= 0.10 then
                    f:SetScript("OnUpdate", nil)
                    local sid = f.pendingSpellId
                    f.pendingSpellId = nil
                    if sid and CD.IsTransmuteSpellId and CD.IsTransmuteSpellId(sid)
                        and DS.TryScanTransmuteCooldownsFromSpellApi
                    then
                        DS:TryScanTransmuteCooldownsFromSpellApi(sid)
                    elseif sid and CD.IsSphereSpellId and CD.IsSphereSpellId(sid)
                        and DS.TryScanSphereCooldownsFromSpellApi
                    then
                        DS:TryScanSphereCooldownsFromSpellApi(sid)
                    elseif sid and DS.TryScanTrackedCooldownFromSpellApi then
                        DS:TryScanTrackedCooldownFromSpellApi(sid)
                    end
                end
            end)
        end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = addonName
        local spellId = a3
        if unit ~= "player" then return end
        if type(spellId) ~= "number" then return end
        local CD = AltArmy and AltArmy.CooldownData
        if not CD or not CD.IsTrackedSpellId then return end
        if not CD.IsTrackedSpellId(spellId) then return end

        cooldownAfterCastFrame.pendingSpellId = spellId
        cooldownAfterCastFrame.elapsed = 0
        cooldownAfterCastFrame:SetScript("OnUpdate", function(f, elapsed)
            f.elapsed = f.elapsed + elapsed
            if f.elapsed >= 0.10 then
                f:SetScript("OnUpdate", nil)
                local sid = f.pendingSpellId
                f.pendingSpellId = nil
                if sid and CD.IsTransmuteSpellId and CD.IsTransmuteSpellId(sid)
                    and DS.TryScanTransmuteCooldownsFromSpellApi
                then
                    DS:TryScanTransmuteCooldownsFromSpellApi(sid)
                elseif sid and CD.IsSphereSpellId and CD.IsSphereSpellId(sid)
                    and DS.TryScanSphereCooldownsFromSpellApi
                then
                    DS:TryScanSphereCooldownsFromSpellApi(sid)
                elseif sid and DS.TryScanTrackedCooldownFromSpellApi then
                    DS:TryScanTrackedCooldownFromSpellApi(sid)
                end
            end
        end)
        return
    end
    if event == "VARIABLES_LOADED" then
        SyncAccountDataRoot()
        return
    end
    if event == "ADDON_LOADED" then
        if addonName == "AltArmy_TBC" then
            SyncAccountDataRoot()
            AltArmyTBC_Data.Characters = AltArmyTBC_Data.Characters or {}
            AltArmyTBC_Data.OrphanImports = AltArmyTBC_Data.OrphanImports or {}
            AltArmyTBC_Data.RecipeReagents = AltArmyTBC_Data.RecipeReagents or {}
            GetCurrentCharTable()
            MigrateDataVersions()
            if DS.MigratePhantomLevelHistoryImports then
                DS:MigratePhantomLevelHistoryImports()
            end
        end
        return
    end
    if event == "PLAYER_ALIVE" or event == "PLAYER_ENTERING_WORLD" then
        if DS.MigrateRecipePrimaryIds then
            DS:MigrateRecipePrimaryIds()
        end
        if DS.ScanCharacter then DS:ScanCharacter() end
        if DS.RequestTimePlayedSilently then
            DS:RequestTimePlayedSilently()
        elseif RequestTimePlayed then
            RequestTimePlayed()
        end
        local char = GetCurrentCharTable()
        if char then
            if DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
                DS:ScanProfessionLinks()
            end
            if DS.HasReputationApi and DS.HasReputationApi() and DS.ScanReputations then
                DS:ScanReputations()
            end
            -- Delayed run: skill/faction data can load after login; rescan so we get it without opening panels
            lateScanFrame.elapsed = 0
            lateScanFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= LATE_SCAN_DELAY then
                    f:SetScript("OnUpdate", nil)
                    local c = GetCurrentCharTable()
                    if c then
                        if DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
                            DS:ScanProfessionLinks()
                        end
                        if DS.HasReputationApi and DS.HasReputationApi() and DS.ScanReputations then
                            DS:ScanReputations()
                        end
                    end
                end
            end)
            -- Equipment: delay only — early PEW links are often all nil and would wipe Inventory
            equipmentScanFrame.elapsed = 0
            equipmentScanFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= EQUIPMENT_SCAN_DELAY then
                    f:SetScript("OnUpdate", nil)
                    if DS.ScanEquipment then DS:ScanEquipment() end
                end
            end)
            -- Bags: run once now (if ready) and again after delay to catch late-loaded data
            if DS.ScanBags then DS:ScanBags() end
            if DS.TryScanTrackedCooldownsFromActionBars then
                DS:TryScanTrackedCooldownsFromActionBars()
            end
            bagScanFrame.elapsed = 0
            bagScanFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= BAG_SCAN_DELAY then
                    f:SetScript("OnUpdate", nil)
                    if DS.ScanBags then DS:ScanBags() end
                    if DS.TryScanTrackedCooldownsFromActionBars then
                        DS:TryScanTrackedCooldownsFromActionBars()
                    end
                end
            end)
            if DS.RunLevelHistoryBackfill then
                DS:RunLevelHistoryBackfill()
            end
            if DS.RequestLockoutInfoDelayed then
                DS:RequestLockoutInfoDelayed()
            end
        end
        return
    end
    if event == "UPDATE_INSTANCE_INFO" then
        if DS.ScanSavedInstances then
            DS:ScanSavedInstances()
        end
        return
    end
    if event == "RAID_INSTANCE_WELCOME" then
        if DS.RequestLockoutInfo then
            DS:RequestLockoutInfo()
        end
        return
    end
    if event == "SKILL_LINES_CHANGED" then
        local char = GetCurrentCharTable()
        if char and DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
            DS:ScanProfessionLinks()
        end
        return
    end
    if event == "TRADE_SKILL_SHOW" then
        if DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
            DS:ScanProfessionLinks()
        end
        tradeSkillScanFrame.elapsed = 0
        tradeSkillScanFrame:SetScript("OnUpdate", function(f, elapsed)
            f.elapsed = f.elapsed + elapsed
            if f.elapsed >= TRADE_SKILL_SCAN_DELAY then
                f:SetScript("OnUpdate", nil)
                if DS.HasTradeSkillRecipesApi and DS.HasTradeSkillRecipesApi() and DS.RunDeferredRecipeScan then
                    DS:RunDeferredRecipeScan()
                end
            end
        end)
        tradeSkillReagentRetryFrame.elapsed = 0
        tradeSkillReagentRetryFrame:SetScript("OnUpdate", function(f, elapsed)
            f.elapsed = f.elapsed + elapsed
            if f.elapsed >= TRADE_SKILL_REAGENT_RETRY_DELAY then
                f:SetScript("OnUpdate", nil)
                -- Legacy-only: reagent capture still has no C_TradeSkillUI fallback (deferred, see
                -- docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md, "Eighth").
                if GetNumTradeSkills and DS.CaptureAllTradeSkillReagentsOnly then
                    DS:CaptureAllTradeSkillReagentsOnly()
                end
            end
        end)
        return
    end
    if event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        -- Retail/Forever-shaped: fires once recipe data for the currently-viewed profession is
        -- actually loaded, unlike TRADE_SKILL_SHOW which fires on window-open regardless. No-op on
        -- TBC Classic (this event won't fire there; TRADE_SKILL_SHOW's own timer already covers it).
        if DS.HasTradeSkillRecipesApi and DS.HasTradeSkillRecipesApi() and DS.RunDeferredRecipeScan then
            DS:RunDeferredRecipeScan()
        end
        return
    end
    if event == "TRADE_SKILL_CLOSE" then
        return
    end
    if event == "CRAFT_SHOW" then
        if GetCraftSkillLine and DS.ScanCraftRecipes then
            craftScanFrame.elapsed = 0
            craftScanFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= TRADE_SKILL_SCAN_DELAY then
                    f:SetScript("OnUpdate", nil)
                    if GetCraftSkillLine and DS.ScanCraftRecipes then
                        DS:ScanCraftRecipes()
                    end
                end
            end)
            craftReagentRetryFrame.elapsed = 0
            craftReagentRetryFrame:SetScript("OnUpdate", function(f, elapsed)
                f.elapsed = f.elapsed + elapsed
                if f.elapsed >= CRAFT_REAGENT_RETRY_DELAY then
                    f:SetScript("OnUpdate", nil)
                    if GetNumCrafts and DS.CaptureAllCraftReagentsOnly then
                        DS:CaptureAllCraftReagentsOnly()
                    end
                end
            end)
        end
        return
    end
    if event == "NEW_RECIPE_LEARNED" then
        if DS.OnNewRecipeLearned then
            DS:OnNewRecipeLearned(tonumber((...)))
        end
        return
    end
    if event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        if DS.OnProfessionLearnSystemMessage then
            DS:OnProfessionLearnSystemMessage(msg)
        end
        return
    end
    if event == "CHAT_MSG_SKILL" then
        local char = GetCurrentCharTable()
        if char and DS.HasProfessionsListApi and DS.HasProfessionsListApi() and DS.ScanProfessionLinks then
            DS:ScanProfessionLinks()
        end
        return
    end
    if event == "UPDATE_FACTION" then
        local now = time()
        if now - lastReputationScan >= REPUTATION_SCAN_THROTTLE then
            lastReputationScan = now
            local char = GetCurrentCharTable()
            if char and DS.HasReputationApi and DS.HasReputationApi() and DS.ScanReputations then
                DS:ScanReputations()
            end
        end
        return
    end
    if event == "MAIL_SHOW" then
        isMailOpen = true
        HookMailFrameVisibility()
        return
    end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if interactionType == MAIL_INTERACTION_TYPE then
            isMailOpen = true
            HookMailFrameVisibility()
        end
        return
    end
    if event == "MAIL_INBOX_UPDATE" then
        local char = GetCurrentCharTable()
        if char and GetInboxNumItems and DS.ScanMailbox then
            DS:ScanMailbox()
        end
        return
    end
    if event == "MAIL_CLOSED" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            local interactionType = ...
            if interactionType ~= MAIL_INTERACTION_TYPE then
                return
            end
        end
        isMailOpen = false
        local char = GetCurrentCharTable()
        if char and GetInboxNumItems and DS.ScanMailbox then
            DS:ScanMailbox()
        end
        return
    end
    if event == "AUCTION_HOUSE_SHOW" then
        isAuctionHouseOpen = true
        local char = GetCurrentCharTable()
        if char and DS.HasOwnedAuctionsApi and DS.HasOwnedAuctionsApi() and DS.ScanAuctions then
            DS:ScanAuctions()
        end
        if char and DS.HasBidAuctionsApi and DS.HasBidAuctionsApi() and DS.ScanBids then
            DS:ScanBids()
        end
        return
    end
    if event == "AUCTION_HOUSE_CLOSED" then
        isAuctionHouseOpen = false
        return
    end
    if event == "AUCTION_OWNED_LIST_UPDATE" or event == "OWNED_AUCTIONS_UPDATED"
        or event == "AUCTION_HOUSE_AUCTION_CREATED" then
        if isAuctionHouseOpen and DS.HasOwnedAuctionsApi and DS.HasOwnedAuctionsApi() and DS.ScanAuctions then
            local char = GetCurrentCharTable()
            if char then DS:ScanAuctions() end
        end
        return
    end
    if event == "AUCTION_BIDDER_LIST_UPDATE" or event == "BIDS_UPDATED" then
        if isAuctionHouseOpen and DS.HasBidAuctionsApi and DS.HasBidAuctionsApi() and DS.ScanBids then
            local char = GetCurrentCharTable()
            if char then DS:ScanBids() end
        end
        return
    end
    if event == "BAG_UPDATE" then
        local char = GetCurrentCharTable()
        if not char then return end
        if isMailOpen and GetInboxNumItems and DS.ScanMailbox then
            DS:ScanMailbox()
        end
        local bagID = a1
        local numBagSlots = DS.NUM_BAG_SLOTS or 4
        local bankContainer = DS.BANK_CONTAINER or -1
        local keyringContainer = DS.KEYRING_CONTAINER or -2
        local minBankBagId = DS.MIN_BANK_BAG_ID or 5
        local maxBankBagId = DS.MAX_BANK_BAG_ID or 11
        if type(bagID) == "number" then
            if bagID >= 0 and bagID <= numBagSlots then
                if DS.ScanContainer then DS:ScanContainer(char, bagID) end
                if DS.ScanBags then DS:ScanBags() end
            elseif bagID == keyringContainer then
                if DS.ScanContainer then DS:ScanContainer(char, bagID) end
                if DS.ScanBags then DS:ScanBags() end
            elseif isBankOpen and (bagID == bankContainer or (bagID >= minBankBagId and bagID <= maxBankBagId)) then
                if DS.ScanContainer then DS:ScanContainer(char, bagID) end
                if DS.ScanBank then DS:ScanBank() end
            end
        else
            if DS.ScanBags then DS:ScanBags() end
            if isBankOpen and DS.ScanBank then DS:ScanBank() end
        end
        return
    end
    if event == "BANKFRAME_OPENED" then
        isBankOpen = true
        local char = GetCurrentCharTable()
        if char and DS.ScanBank then DS:ScanBank() end
        return
    end
    if event == "BANKFRAME_CLOSED" then
        isBankOpen = false
        return
    end
    if event == "PLAYERBANKSLOTS_CHANGED" then
        if isBankOpen and DS.ScanBank then
            local char = GetCurrentCharTable()
            if char then DS:ScanBank() end
        end
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        local char = GetCurrentCharTable()
        if char and DS.ScanEquipment then DS:ScanEquipment() end
        return
    end
    if event == "PLAYER_LOGOUT" then
        local char = GetCurrentCharTable()
        if char then
            char.lastLogout = time()
            char.lastUpdate = time()
        end
        return
    end
    if event == "PLAYER_GUILD_UPDATE" then
        if DS.HandlePlayerGuildUpdate then DS:HandlePlayerGuildUpdate() end
        return
    end
    if event == "PLAYER_MONEY" then
        local char = GetCurrentCharTable()
        if char and GetMoney then
            char.money = GetMoney()
        end
        return
    end
    if event == "PLAYER_XP_UPDATE" then
        local char = GetCurrentCharTable()
        if char then
            if UnitLevel then
                char.level = UnitLevel("player") or char.level
            end
            if UnitXP and UnitXPMax then
                char.xp = UnitXP("player") or 0
                char.xpMax = UnitXPMax("player") or 0
            end
            if GetXPExhaustion then
                char.restXP = GetXPExhaustion() or 0
            end
            if char.level == DS.MAX_LEVEL then
                char.restXP = 0
            end
        end
        return
    end
    if event == "PLAYER_LEVEL_UP" then
        local newLevel = addonName
        local char = GetCurrentCharTable()
        if char and UnitLevel then
            char.level = UnitLevel("player") or newLevel
            if char.level == DS.MAX_LEVEL then
                char.restXP = 0
            end
        end
        if DS.BeginPendingLevelUp then
            DS:BeginPendingLevelUp(newLevel or (char and char.level))
        end
        local Comm = AltArmy and AltArmy.GuildShareComm
        if Comm and Comm.ScheduleBroadcast then
            Comm.ScheduleBroadcast()
        end
        return
    end
    if event == "TIME_PLAYED_MSG" then
        local totalTimePlayed, timePlayedThisLevel = addonName, a1
        local char = GetCurrentCharTable()
        if char and totalTimePlayed and type(totalTimePlayed) == "number" then
            char.played = totalTimePlayed
            if type(timePlayedThisLevel) == "number" then
                char.playedThisLevel = timePlayedThisLevel
            end
            if DS.OnTimePlayedMessage then
                DS:OnTimePlayedMessage(totalTimePlayed, timePlayedThisLevel)
            end
            if AltArmy.BankAltDetect and AltArmy.BankAltDetect.TryPromptForCurrentCharacter then
                AltArmy.BankAltDetect.TryPromptForCurrentCharacter()
            end
        end
        return
    end
end)
