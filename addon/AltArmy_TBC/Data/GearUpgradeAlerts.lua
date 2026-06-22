-- AltArmy TBC — Gear upgrade chat alerts (loot + level-up).
-- luacheck: globals DEFAULT_CHAT_FRAME GetItemInfo IsUsableItem UnitName
-- luacheck: globals GetContainerItemLink GetContainerNumSlots hooksecurefunc SetItemRef

if not AltArmy then return end

AltArmy.GearUpgradeAlerts = AltArmy.GearUpgradeAlerts or {}
local GA = AltArmy.GearUpgradeAlerts

local ALTARMY_GOLD = "|cfffecc00"
local IU = AltArmy.ItemUsability
local GU = AltArmy.GearUpgrade
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

local function formatUpgradeLink(itemLink)
    local itemId = tonumber(itemLink and itemLink:match("item:(%d+)"))
    if not itemId then return itemLink end
    local label = "View in AltArmy"
    if GetItemInfo then
        local name = GetItemInfo(itemLink)
        if name and name ~= "" then
            label = "View upgrade: " .. name
        end
    end
    return "|Haltarmy:upgrade:" .. tostring(itemId) .. "|h[" .. label .. "]|h"
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

    local names = {}
    for i = 1, #matches do
        local m = matches[i]
        names[#names + 1] = classColorName(m.name, m.classFile)
    end
    local nameList = table.concat(names, ", ")
    local actionLink = formatUpgradeLink(itemLink)
    local technique = GU.GetEffectiveTechnique(opts.technique or "custom")
    local techniqueNote = ""
    if technique ~= (opts.technique or "custom") then
        techniqueNote = " (using built-in comparison; selected addon not installed)"
    end
    postChat(ALTARMY_GOLD .. "AltArmy|r Upgrade for " .. nameList .. ": " .. (itemLink or "?")
        .. " " .. actionLink .. techniqueNote)
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

local function needsTraining(link)
    if not link or not IsUsableItem then return false end
    local usable = IsUsableItem(link)
    return usable == false
end

local function trainingSkillName(link)
    if not link or not GetItemInfo or not IU then return "the required skill" end
    local _, _, _, _, _, itemClass, subclass = GetItemInfo(link)
    return IU.GetProficiencySkillName(itemClass, subclass)
end

function GA.AnnounceLevelUpUpgrades(newLevel)
    if not optionsEnabled() or not newLevel or not GU then return end
    local DS = AltArmy.DataStore
    if not DS or not DS.GetCurrentCharacter then return end
    local char = DS:GetCurrentCharacter()
    if not char then return end
    if DS.ScanBags then DS:ScanBags() end
    if DS.ScanBank then DS:ScanBank() end

    local opts = GU.GetOptions()
    local classFile = char.classFile or ""
    local seen = {}
    local candidates = {}

    local function consider(link)
        if not link or seen[link] then return end
        if IU and IU.IsBindOnPickup and IU.IsBindOnPickup(link) then return end
        local eff = IU and IU.EffectiveRequiredLevel(classFile, link) or 999
        if eff ~= newLevel then return end
        seen[link] = true
        candidates[#candidates + 1] = link
    end

    if GetContainerNumSlots and GetContainerItemLink then
        for bag = 0, 4 do
            local slots = GetContainerNumSlots(bag) or 0
            for slot = 1, slots do
                consider(GetContainerItemLink(bag, slot))
            end
        end
    end

    if DS.IterateContainerSlots then
        DS:IterateContainerSlots(char, function(_, _, itemId, _, link)
            consider(resolveOwnedLink(itemId, link))
        end)
    end

    local numMails = DS.GetNumMails and DS:GetNumMails(char) or 0
    for i = 1, numMails do
        if DS.GetMailInfo then
            local _, _, link = DS:GetMailInfo(char, i)
            consider(link)
        end
    end

    for i = 1, #candidates do
        local link = candidates[i]
        if GU.EvaluateForCharacter(char, link, {
            technique = opts.technique,
            levelsAhead = 0,
        }) then
            postChat(ALTARMY_GOLD .. "AltArmy|r Congratulations! You can now use "
                .. (link or "?") .. ", which appears to be an upgrade for you.")
            if needsTraining(link) then
                postChat(ALTARMY_GOLD .. "AltArmy|r Note that you must train "
                    .. trainingSkillName(link) .. " before you can equip this.")
            end
        end
    end
end

function GA.HandleSetItemRef(link, button)
    if button and button ~= "LeftButton" then return false end
    if not link then return false end
    local itemId = link:match("^altarmy:upgrade:(%d+)$")
    if not itemId then return false end
    if GetItemInfo then
        local _, itemLink = GetItemInfo(tonumber(itemId))
        if itemLink and AltArmy.OpenGearTabFocused then
            AltArmy.OpenGearTabFocused(itemLink)
            return true
        end
    end
    return false
end

local alertFrame = CreateFrame("Frame", "AltArmyTBC_GearUpgradeAlertFrame", UIParent)
alertFrame:RegisterEvent("CHAT_MSG_LOOT")
alertFrame:RegisterEvent("PLAYER_LEVEL_UP")
alertFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "CHAT_MSG_LOOT" then
        local msg = arg1
        if not isSelfLootMessage(msg) then return end
        local link = extractItemLink(msg)
        if link then
            GA.AnnounceLootUpgrade(link)
        end
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = tonumber(arg1) or (UnitLevel and UnitLevel("player"))
        GA.AnnounceLevelUpUpgrades(newLevel)
    end
end)

if hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link, _, button)
        GA.HandleSetItemRef(link, button)
    end)
end
