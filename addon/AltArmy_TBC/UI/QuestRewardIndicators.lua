-- AltArmy TBC — Quest reward upgrade/vendor overlays on turn-in and quest log screens.
-- luacheck: globals QuestInfoRewardsFrame QuestInfoFrame QuestInfo_GetRewardButton
-- luacheck: globals QuestLogDetailScrollFrame SelectQuestLogEntry GetQuestLogItemLink
-- luacheck: globals GetNumQuestLogChoices GetNumQuestLogRewards GetQuestItemLink
-- luacheck: globals GetNumQuestChoices GetNumQuestRewards GetItemInfo QUEST_COMPLETE

if not AltArmy then return end

AltArmy.QuestRewardIndicators = AltArmy.QuestRewardIndicators or {}
local QRI = AltArmy.QuestRewardIndicators

local GA = AltArmy.GearUpgradeAlerts
local GU = AltArmy.GearUpgrade

local VENDOR_ICON = "Interface/GossipFrame/VendorGossipIcon.blp"
local UPGRADE_BADGE_CLEAR_COLOR = { 0.2, 1, 0.2 }
local UPGRADE_BADGE_MINOR_COLOR = { 0.9, 0.78, 0.12 }
local UPGRADE_BADGE_FONT_OBJECT = "GameFontNormalSmall"
local UPGRADE_BADGE_FONT_SCALE = 2
local ICON_SIZE = 16
local ICON_OFFSET_X = -3
local ICON_OFFSET_Y = 3
local MINOR_UPGRADE_OFFSET_Y = -6

local turnInOverlays = {}
local questLogOverlays = {}
local hooksInstalled = false
local UPGRADE_HIT_SIZE = 22
local UPGRADE_TOOLTIP_TEXT = "Compare using Alt Army"

local function showUpgradeTooltip(owner)
    if not GameTooltip or not owner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(UPGRADE_TOOLTIP_TEXT, 1, 1, 1)
    GameTooltip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 4)
    GameTooltip:Show()
end

local function hideUpgradeTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function findEntryLink(entries, unifiedIndex)
    if not unifiedIndex then return nil end
    for i = 1, #entries do
        local entry = entries[i]
        if entry.unifiedIndex == unifiedIndex then
            return entry.link
        end
    end
    return nil
end

function QRI.OpenGearComparisonForLink(itemLink)
    if not itemLink or itemLink == "" then return false end
    if AltArmy.OpenGearTabFocused then
        AltArmy.OpenGearTabFocused(itemLink)
        return true
    end
    return false
end

function QRI.ApplyUpgradeBadgeStyle(badge, highlightKind)
    if not badge then return end
    if highlightKind == "minor" then
        badge:SetText("~")
        badge:SetTextColor(
            UPGRADE_BADGE_MINOR_COLOR[1],
            UPGRADE_BADGE_MINOR_COLOR[2],
            UPGRADE_BADGE_MINOR_COLOR[3],
            1)
    else
        badge:SetText("+")
        badge:SetTextColor(
            UPGRADE_BADGE_CLEAR_COLOR[1],
            UPGRADE_BADGE_CLEAR_COLOR[2],
            UPGRADE_BADGE_CLEAR_COLOR[3],
            1)
    end
end

local function extractItemId(itemLink)
    if not itemLink then return nil end
    local payload = itemLink:match("|H(item:[^|]+)|") or itemLink:match("^(item:[^|]+)")
    if not payload then return nil end
    return tonumber(payload:match("^item:(%d+)"))
end

local function readSellPrice(link)
    if not link or not GetItemInfo then return 0 end
    local sellPrice = select(11, GetItemInfo(link))
    return tonumber(sellPrice) or 0
end

local function applyUpgradeBadgeFont(fontString)
    if not fontString then return end
    fontString:SetFontObject(UPGRADE_BADGE_FONT_OBJECT)
    local font, size, flags = fontString:GetFont()
    if font and size then
        fontString:SetFont(font, size * UPGRADE_BADGE_FONT_SCALE, flags)
    end
end

local function ensureOverlays(surfaceKey, parentFrame)
    local overlays = surfaceKey == "turnin" and turnInOverlays or questLogOverlays
    if not overlays.upgrade then
        local btn = CreateFrame("Button", nil, parentFrame)
        btn:SetSize(UPGRADE_HIT_SIZE, UPGRADE_HIT_SIZE)
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetScript("OnClick", function(self)
            QRI.OpenGearComparisonForLink(self.itemLink)
        end)
        btn:SetScript("OnEnter", function(self)
            showUpgradeTooltip(self)
        end)
        btn:SetScript("OnLeave", hideUpgradeTooltip)
        local badge = btn:CreateFontString(nil, "OVERLAY", UPGRADE_BADGE_FONT_OBJECT)
        applyUpgradeBadgeFont(badge)
        badge:SetPoint("CENTER", btn, "CENTER", 0, 0)
        QRI.ApplyUpgradeBadgeStyle(badge, "clear")
        btn.upgradeBadge = badge
        btn:Hide()
        overlays.upgrade = btn
    end
    if not overlays.vendor then
        overlays.vendor = parentFrame:CreateTexture(nil, "OVERLAY")
        overlays.vendor:SetTexture(VENDOR_ICON)
        overlays.vendor:SetSize(ICON_SIZE, ICON_SIZE)
        overlays.vendor:Hide()
    end
    return overlays
end

local function hideOverlays(overlays)
    if not overlays then return end
    if overlays.upgrade then
        overlays.upgrade:Hide()
        hideUpgradeTooltip()
    end
    if overlays.vendor then overlays.vendor:Hide() end
end

local function collectRewardLinks(getNumChoices, getNumRewards, getItemLink)
    local entries = {}
    local numChoices = getNumChoices and getNumChoices() or 0
    local numRewards = getNumRewards and getNumRewards() or 0

    local function addEntry(kind, index, unifiedIndex)
        if not getItemLink then return end
        local link = getItemLink(kind, index)
        if not link or link == "" then return end
        entries[#entries + 1] = {
            kind = kind,
            index = index,
            unifiedIndex = unifiedIndex,
            link = link,
            itemId = extractItemId(link),
            sellPrice = readSellPrice(link),
        }
    end

    for i = 1, numChoices do
        addEntry("choice", i, i)
    end
    for i = 1, numRewards do
        addEntry("reward", i, numChoices + i)
    end
    return entries
end

function QRI.CollectTurnInRewardEntries()
    return collectRewardLinks(GetNumQuestChoices, GetNumQuestRewards, GetQuestItemLink)
end

function QRI.CollectQuestLogRewardEntries()
    return collectRewardLinks(GetNumQuestLogChoices, GetNumQuestLogRewards, GetQuestLogItemLink)
end

function QRI.EvaluateRewardIndicators(entries, opts)
    opts = opts or {}
    local bestUpgrade
    local bestVendor

    if opts.showQuestRewardUpgradeIndicator ~= false then
        for i = 1, #entries do
            local entry = entries[i]
            if entry.equippable and (entry.delta or 0) > 0 then
                if not bestUpgrade
                    or entry.delta > bestUpgrade.delta
                    or (entry.delta == bestUpgrade.delta
                        and (entry.itemId or 0) < (bestUpgrade.itemId or 0)) then
                    bestUpgrade = entry
                end
            end
        end
    end

    if opts.showQuestRewardVendorIndicator ~= false then
        for i = 1, #entries do
            local entry = entries[i]
            local sellPrice = entry.sellPrice or 0
            if sellPrice > 0 then
                if not bestVendor
                    or sellPrice > bestVendor.sellPrice
                    or (sellPrice == bestVendor.sellPrice
                        and (entry.itemId or 0) < (bestVendor.itemId or 0)) then
                    bestVendor = entry
                end
            end
        end
    end

    return {
        bestUpgradeUnifiedIndex = bestUpgrade and bestUpgrade.unifiedIndex or nil,
        bestUpgradeHighlightKind = bestUpgrade and bestUpgrade.highlightKind or nil,
        bestVendorUnifiedIndex = bestVendor and bestVendor.unifiedIndex or nil,
    }
end

function QRI.ShouldEvaluateForCurrentCharacter()
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCurrentCharacter then return false end
    local char = DS:GetCurrentCharacter()
    if not char then return false end
    local BA = AltArmy.BankAlt
    if BA and BA.Is then
        local realm = char.realm or (DS.GetCurrentPlayerRealm and DS:GetCurrentPlayerRealm()) or ""
        if BA.Is(char.name or "", realm) then return false end
    end
    return true
end

local function enrichEntriesForCurrentCharacter(entries, evalOpts, opts)
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCurrentCharacter then return entries end
    local char = DS:GetCurrentCharacter()
    if not char then return entries end
    opts = opts or (GU and GU.GetOptions and GU.GetOptions()) or {}

    for i = 1, #entries do
        local entry = entries[i]
        local equippable = GA and GA.IsQuestRewardEquippableForCharacter
            and GA.IsQuestRewardEquippableForCharacter(char, entry.link, evalOpts) or false
        entry.equippable = equippable
        entry.highlightKind = nil
        if equippable and GU and GU.GetCharacterUpgradeDelta then
            entry.delta = GU.GetCharacterUpgradeDelta(char, entry.link, evalOpts) or 0
            if entry.delta > 0 and GU.GetUpgradeHighlightKind then
                local upgradeMaxDelta
                if GU.ComputeUpgradeMaxDeltaForCurrentRealm then
                    upgradeMaxDelta = GU.ComputeUpgradeMaxDeltaForCurrentRealm(entry.link, evalOpts)
                end
                entry.highlightKind = GU.GetUpgradeHighlightKind(entry.delta, upgradeMaxDelta, opts)
            end
        else
            entry.delta = 0
        end
    end
    return entries
end

local function resolveTurnInRewardButton(unifiedIndex)
    if not unifiedIndex or unifiedIndex < 1 then return nil end
    if QuestInfo_GetRewardButton and QuestInfoFrame and QuestInfoFrame.rewardsFrame then
        return QuestInfo_GetRewardButton(QuestInfoFrame.rewardsFrame, unifiedIndex)
    end
    if QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons then
        return QuestInfoRewardsFrame.RewardButtons[unifiedIndex]
    end
    return nil
end

local function resolveQuestLogRewardButton(unifiedIndex)
    if not unifiedIndex or unifiedIndex < 1 then return nil end
    local frame = _G["QuestLogItem" .. tostring(unifiedIndex)]
    if frame then return frame end
    if QuestInfo_GetRewardButton and QuestInfoFrame and QuestInfoFrame.rewardsFrame then
        return QuestInfo_GetRewardButton(QuestInfoFrame.rewardsFrame, unifiedIndex)
    end
    return nil
end

local function showOverlayOnButton(overlay, button, point, itemLink, offsetY)
    if not overlay or not button or not button.IsShown or not button:IsShown() then
        if overlay then overlay:Hide() end
        return
    end
    if itemLink then
        overlay.itemLink = itemLink
    end
    overlay:ClearAllPoints()
    overlay:SetPoint(point, button, point, ICON_OFFSET_X, offsetY or ICON_OFFSET_Y)
    overlay:SetParent(button)
    overlay:Show()
end

local function applyIndicators(surfaceKey, parentFrame, resolveButton, collectEntries)
    if not parentFrame then return end
    if not QRI.ShouldEvaluateForCurrentCharacter() then
        hideOverlays(surfaceKey == "turnin" and turnInOverlays or questLogOverlays)
        return
    end

    local opts = GU and GU.GetOptions and GU.GetOptions() or {}
    local evalOpts = {
        technique = opts.technique,
        levelsAhead = opts.levelsAhead,
    }
    local entries = collectEntries()
    if #entries == 0 then
        hideOverlays(surfaceKey == "turnin" and turnInOverlays or questLogOverlays)
        return
    end

    enrichEntriesForCurrentCharacter(entries, evalOpts, opts)
    local result = QRI.EvaluateRewardIndicators(entries, opts)
    local overlays = ensureOverlays(surfaceKey, parentFrame)

    if result.bestUpgradeUnifiedIndex then
        if overlays.upgrade and overlays.upgrade.upgradeBadge then
            QRI.ApplyUpgradeBadgeStyle(
                overlays.upgrade.upgradeBadge,
                result.bestUpgradeHighlightKind)
        end
        local upgradeOffsetY = ICON_OFFSET_Y
        if result.bestUpgradeHighlightKind == "minor" then
            upgradeOffsetY = ICON_OFFSET_Y + MINOR_UPGRADE_OFFSET_Y
        end
        showOverlayOnButton(
            overlays.upgrade,
            resolveButton(result.bestUpgradeUnifiedIndex),
            "TOPRIGHT",
            findEntryLink(entries, result.bestUpgradeUnifiedIndex),
            upgradeOffsetY)
    else
        overlays.upgrade:Hide()
    end

    if result.bestVendorUnifiedIndex then
        showOverlayOnButton(
            overlays.vendor,
            resolveButton(result.bestVendorUnifiedIndex),
            "BOTTOMRIGHT")
    else
        overlays.vendor:Hide()
    end
end

function QRI.RefreshTurnInIndicators()
    applyIndicators("turnin", QuestInfoRewardsFrame, resolveTurnInRewardButton, QRI.CollectTurnInRewardEntries)
end

function QRI.RefreshQuestLogIndicators()
    applyIndicators(
        "questlog",
        QuestLogDetailScrollFrame,
        resolveQuestLogRewardButton,
        QRI.CollectQuestLogRewardEntries)
end

function QRI.Refresh()
    QRI.RefreshTurnInIndicators()
    QRI.RefreshQuestLogIndicators()
end

local function hideAllIndicators()
    hideOverlays(turnInOverlays)
    hideOverlays(questLogOverlays)
end

local function installHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    if QuestInfoRewardsFrame then
        QuestInfoRewardsFrame:HookScript("OnHide", hideAllIndicators)
    end
    if QuestLogDetailScrollFrame then
        QuestLogDetailScrollFrame:HookScript("OnHide", hideAllIndicators)
        QuestLogDetailScrollFrame:HookScript("OnShow", function()
            QRI.RefreshQuestLogIndicators()
        end)
    end
    if _G.hooksecurefunc and SelectQuestLogEntry then
        hooksecurefunc("SelectQuestLogEntry", function()
            hideOverlays(questLogOverlays)
            QRI.RefreshQuestLogIndicators()
        end)
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("QUEST_COMPLETE")
    frame:SetScript("OnEvent", function(_, event)
        if event ~= "QUEST_COMPLETE" then return end
        local ctimer = _G.C_Timer
        if ctimer and ctimer.After then
            ctimer.After(0, QRI.RefreshTurnInIndicators)
        else
            QRI.RefreshTurnInIndicators()
        end
    end)
end

installHooks()
