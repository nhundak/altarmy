-- AltArmy TBC — Gear upgrade chat alerts (loot + level-up).
-- luacheck: globals DEFAULT_CHAT_FRAME GetItemInfo IsUsableItem UnitName
-- luacheck: globals GetContainerItemLink GetContainerNumSlots SetItemRef ChatFrame_OnHyperlinkClick

if not AltArmy then return end

AltArmy.GearUpgradeAlerts = AltArmy.GearUpgradeAlerts or {}
local GA = AltArmy.GearUpgradeAlerts

local ALTARMY_GOLD = "|cfffecc00"
local IU = AltArmy.ItemUsability
local GU = AltArmy.GearUpgrade
local GC = AltArmy.GearCompare
local CC = AltArmy.ClassColor

local function postChat(line)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and chat.AddMessage and line and line ~= "" then
        chat:AddMessage(line)
    end
end

local function classColorName(name, classFile)
    if CC and CC.wrapName then
        return CC.wrapName(name, classFile)
    end
    return name or "?"
end

local function formatUpgradeNameList(matches)
    if not matches or #matches == 0 then return "" end
    local names = {}
    for i = 1, #matches do
        local m = matches[i]
        names[#names + 1] = classColorName(m.name, m.classFile)
    end
    if #names <= 3 then
        return table.concat(names, ", ")
    end
    local others = #names - 2
    return names[1] .. ", " .. names[2] .. ", and " .. tostring(others) .. " others"
end

local UPGRADE_LINK_PREFIX = "altarmy:upgrade:"

local function extractItemPayload(itemLink)
    if not itemLink then return nil end
    return itemLink:match("|H(item:[^|]+)|") or itemLink:match("^(item:[^|]+)")
end

local function payloadToUsableLink(payload)
    if not payload or payload == "" then return nil end
    if GetItemInfo then
        local _, link = GetItemInfo(payload)
        if link and link ~= "" then
            return link
        end
        local wrapped = "|H" .. payload .. "|h"
        local _, wrappedLink = GetItemInfo(wrapped)
        if wrappedLink and wrappedLink ~= "" then
            return wrappedLink
        end
    end
    return "|H" .. payload .. "|h[item]|h"
end

local function formatUpgradeLink(itemLink)
    local payload = extractItemPayload(itemLink)
    if not payload then return itemLink end
    return "|cfffecc00|H" .. UPGRADE_LINK_PREFIX .. payload .. "|h[View details]|h|r"
end

function GA.FormatLootUpgradeMessage(itemLink, nameList, actionLink)
    return (itemLink or "?") .. " is an upgrade for " .. nameList .. ": " .. actionLink
end

local function resolveItemLinkForUpgrade(itemId)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    if GetItemInfo then
        local _, cached = GetItemInfo(itemId)
        if cached and cached ~= "" then
            return cached
        end
    end
    return "item:" .. tostring(itemId)
end

local function parseUpgradeLink(link)
    if not link then return nil end
    local prefixLower = UPGRADE_LINK_PREFIX:lower()
    local lower = link:lower()
    if lower:sub(1, #prefixLower) ~= prefixLower then return nil end
    local payload = link:sub(#prefixLower + 1)
    if payload:match("^item:") then
        return payloadToUsableLink(payload)
    end
    local itemId = tonumber(payload)
    if itemId then
        return resolveItemLinkForUpgrade(itemId)
    end
    return nil
end

local function optionsEnabled()
    if not GU or not GU.GetOptions then return false end
    local opts = GU.GetOptions()
    return opts.enabled ~= false
end

local function extractItemLink(msg)
    if not msg then return nil end
    return msg:match("(|c.-|Hitem:.-|h[^|]*|h)")
        or msg:match("(|Hitem:.-|h[^|]*|h)")
        or msg:match("(item:%d+)")
end

local function isSelfLootMessage(msg)
    if not msg then return false end
    return msg:find("^You receive loot:") ~= nil
        or msg:find("^You receive item:") ~= nil
        or msg:find("^You create:") ~= nil
end

local function maybeLogItemComparison(itemLink)
    if GC and GC.LogItemComparisonDebug then
        GC.LogItemComparisonDebug(itemLink)
    end
end

function GA.AnnounceLootUpgrade(itemLink)
    if not optionsEnabled() or not itemLink or not GU or not GU.EvaluateForAllAlts then
        return false, "disabled"
    end
    if IU and IU.IsBindOnPickup and IU.IsBindOnPickup(itemLink) then return false, "bop" end
    local opts = GU.GetOptions()
    local matches = GU.EvaluateForAllAlts(itemLink, {
        technique = opts.technique,
        levelsAhead = opts.levelsAhead,
    })
    if not matches or #matches == 0 then return false, "no_matches" end

    local nameList = formatUpgradeNameList(matches)
    local actionLink = formatUpgradeLink(itemLink)
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local techniqueNote = ""
    if technique ~= (opts.technique or "custom") then
        techniqueNote = " (using built-in comparison; selected addon not installed)"
    end
    postChat(ALTARMY_GOLD .. "AltArmy|r "
        .. GA.FormatLootUpgradeMessage(itemLink, nameList, actionLink) .. techniqueNote)
    pcall(function()
        if PlaySound then PlaySound("TellMessage", "Master") end
    end)
    return true
end

--- Debug: run the same upgrade check as self-loot (CHAT_MSG_LOOT).
function GA.SimulateSelfLoot(rawInput)
    local link = extractItemLink(rawInput)
    if not link and rawInput and rawInput:find("item:") then
        link = rawInput:match("^%s*(.-)%s*$")
    end
    if not link or link == "" then
        postChat(ALTARMY_GOLD .. "AltArmy|r debug: could not parse item link. "
            .. "Usage: /altarmy debug item {shift-click item}")
        return false
    end
    maybeLogItemComparison(link)
    local ok, reason = GA.AnnounceLootUpgrade(link)
    if ok then return true end
    if reason == "disabled" then
        postChat(ALTARMY_GOLD .. "AltArmy|r debug: gear upgrade notifications are disabled in options.")
    elseif reason == "bop" then
        postChat(ALTARMY_GOLD .. "AltArmy|r debug: skipped (bind-on-pickup or quest item).")
    elseif reason == "no_matches" then
        postChat(ALTARMY_GOLD .. "AltArmy|r debug: no alt upgrade matches for this item.")
    end
    return false
end

--- Debug: run the same upgrade check as PLAYER_LEVEL_UP.
function GA.SimulateLevelUp(rawLevel)
    local newLevel = tonumber(rawLevel)
    if not newLevel or newLevel < 1 then
        postChat(ALTARMY_GOLD .. "AltArmy|r debug: invalid level. "
            .. "Usage: /altarmy debug levelup {level}")
        return false
    end
    if not optionsEnabled() then
        postChat(ALTARMY_GOLD .. "AltArmy|r debug: gear upgrade notifications are disabled in options.")
        return false
    end
    GA.AnnounceLevelUpUpgrades(newLevel)
    return true
end

local function resolveOwnedLink(itemId, storedLink)
    if storedLink and storedLink:find("item:") then
        return storedLink
    end
    if itemId and GetItemInfo then
        local _, link = GetItemInfo(itemId)
        if link then return link end
    end
    if itemId then
        return "item:" .. tostring(itemId)
    end
    return nil
end

local function trainingSkillName(link)
    if not link or not GetItemInfo or not IU then return "the required skill" end
    local _, _, _, _, _, itemClass, subclass = GetItemInfo(link)
    return IU.GetProficiencySkillName(itemClass, subclass)
end

function GA.FormatLevelUpEquipMessage(link, locations)
    locations = locations or {}
    local msg = "Congratulations! You can now equip " .. (link or "?")
    if locations.mail then
        msg = msg .. " (mail)"
    elseif locations.bank and not locations.bag then
        msg = msg .. " (bank)"
    end
    return msg
end

local function noteLevelUpCandidate(candidates, candidateOrder, link, location)
    if not candidates[link] then
        candidates[link] = { link = link, bag = false, bank = false, mail = false }
        candidateOrder[#candidateOrder + 1] = link
    end
    if location == "bag" then
        candidates[link].bag = true
    elseif location == "bank" then
        candidates[link].bank = true
    elseif location == "mail" then
        candidates[link].mail = true
    end
end

local function considerLevelUpCandidate(candidates, candidateOrder, link, location, classFile, newLevel)
    if not link then return end
    if IU and IU.IsBindOnPickup and IU.IsBindOnPickup(link) then return end
    local eff = IU and IU.EffectiveRequiredLevel(classFile, link) or 999
    if eff ~= newLevel then return end
    noteLevelUpCandidate(candidates, candidateOrder, link, location)
end

function GA.AnnounceLevelUpUpgrades(newLevel)
    if not optionsEnabled() or not newLevel or not GU then return end
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCurrentCharacter then return end
    local char = DS:GetCurrentCharacter()
    if not char then return end
    if DS.ScanBags then DS:ScanBags() end

    local opts = GU.GetOptions()
    local classFile = char.classFile or ""
    local candidates = {}
    local candidateOrder = {}

    local function considerSavedContainerSlot(itemId, link, location)
        considerLevelUpCandidate(
            candidates, candidateOrder,
            resolveOwnedLink(itemId, link), location, classFile, newLevel)
    end

    if DS.IterateBagSlots then
        DS:IterateBagSlots(char, function(_, _, itemId, _, link)
            considerSavedContainerSlot(itemId, link, "bag")
        end)
    elseif GetContainerNumSlots and GetContainerItemLink then
        for bag = 0, 4 do
            local slots = GetContainerNumSlots(bag) or 0
            for slot = 1, slots do
                considerLevelUpCandidate(
                    candidates, candidateOrder,
                    GetContainerItemLink(bag, slot), "bag", classFile, newLevel)
            end
        end
    end

    if DS.IterateBankSlots then
        DS:IterateBankSlots(char, function(_, _, itemId, _, link)
            considerSavedContainerSlot(itemId, link, "bank")
        end)
    end

    local numMails = DS.GetNumMails and DS:GetNumMails(char) or 0
    for i = 1, numMails do
        if DS.GetMailInfo then
            local _, _, link = DS:GetMailInfo(char, i)
            considerLevelUpCandidate(
                candidates, candidateOrder, link, "mail", classFile, newLevel)
        end
    end

    for i = 1, #candidateOrder do
        local candidate = candidates[candidateOrder[i]]
        local link = candidate.link
        if GU.EvaluateForCharacter(char, link, {
            technique = opts.technique,
            levelsAhead = 0,
            level = newLevel,
        }) then
            postChat(ALTARMY_GOLD .. "AltArmy|r "
                .. GA.FormatLevelUpEquipMessage(link, candidate))
            if IU and IU.NeedsProficiencyTraining(classFile, newLevel, link, char) then
                postChat(ALTARMY_GOLD .. "AltArmy|r Note that you must train "
                    .. trainingSkillName(link) .. " before you can equip this.")
            end
        end
    end
end

function GA.HandleSetItemRef(link, button)
    if button and button ~= "LeftButton" then return false end
    local itemLink = parseUpgradeLink(link)
    if not itemLink then return false end
    if AltArmy.OpenGearTabFocused then
        AltArmy.OpenGearTabFocused(itemLink)
        return true
    end
    return false
end

local wrappedSetItemRef
local wrappedChatFrame_OnHyperlinkClick

--- Intercept custom links before Blizzard/NovaInstanceTracker call SetHyperlink on them.
local function installUpgradeLinkInterceptors()
    if SetItemRef then
        local inner = SetItemRef
        if inner ~= wrappedSetItemRef then
            local function wrapper(link, text, button, chatFrame)
                if GA.HandleSetItemRef(link, button) then
                    return
                end
                return inner(link, text, button, chatFrame)
            end
            wrappedSetItemRef = wrapper
            SetItemRef = wrapper
        end
    end

    if ChatFrame_OnHyperlinkClick then
        local inner = ChatFrame_OnHyperlinkClick
        if inner ~= wrappedChatFrame_OnHyperlinkClick then
            local function wrapper(self, link, text, button)
                if GA.HandleSetItemRef(link, button) then
                    return
                end
                return inner(self, link, text, button)
            end
            wrappedChatFrame_OnHyperlinkClick = wrapper
            ChatFrame_OnHyperlinkClick = wrapper
        end
    end
end

local alertFrame = CreateFrame("Frame", "AltArmyTBC_GearUpgradeAlertFrame", UIParent)
alertFrame:RegisterEvent("CHAT_MSG_LOOT")
alertFrame:RegisterEvent("PLAYER_LEVEL_UP")
alertFrame:RegisterEvent("ADDON_LOADED")
alertFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        installUpgradeLinkInterceptors()
    elseif event == "CHAT_MSG_LOOT" then
        local msg = arg1
        if not isSelfLootMessage(msg) then return end
        local link = extractItemLink(msg)
        if link then
            maybeLogItemComparison(link)
            GA.AnnounceLootUpgrade(link)
        end
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = tonumber(arg1) or (UnitLevel and UnitLevel("player"))
        GA.AnnounceLevelUpUpgrades(newLevel)
    end
end)

installUpgradeLinkInterceptors()
