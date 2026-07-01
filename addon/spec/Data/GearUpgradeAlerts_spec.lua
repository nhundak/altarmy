--[[
  Unit tests for GearUpgradeAlerts.lua.
  Run from project root: npm test
]]

describe("GearUpgradeAlerts", function()
    local GA
    local openedLink

    local function defaultGetItemInfo(item)
        local id = type(item) == "number" and item
            or tonumber(tostring(item):match("item:(%d+)"))
        if id == 11 then
            return "New Helm", "|Hitem:11:0|h[New Helm]|h"
        end
        return nil
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        openedLink = nil
        AltArmy.OpenGearTabFocused = function(itemLink)
            openedLink = itemLink
        end
        _G.GetItemInfo = defaultGetItemInfo
        _G.CreateFrame = _G.CreateFrame or function()
            return {
                RegisterEvent = function() end,
                SetScript = function() end,
                HookScript = function() end,
            }
        end
        _G.SetItemRef = function() end
        _G.UIParent = _G.UIParent or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        package.loaded["GearUpgradeAlerts"] = nil
        require("GearUpgradeAlerts")
        GA = AltArmy.GearUpgradeAlerts
    end)

    before_each(function()
        _G.GetItemInfo = defaultGetItemInfo
        openedLink = nil
    end)

    it("HandleSetItemRef opens gear tab for altarmy upgrade links", function()
        local ok = GA.HandleSetItemRef("altarmy:upgrade:11", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)
    end)

    it("HandleSetItemRef accepts mixed-case link types", function()
        local ok = GA.HandleSetItemRef("AltArmy:upgrade:11", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)
    end)

    it("HandleSetItemRef falls back to bare item id when item is uncached", function()
        local ok = GA.HandleSetItemRef("altarmy:upgrade:99999", "LeftButton")
        assert.is_true(ok)
        assert.are.equal("item:99999", openedLink)
    end)

    it("HandleSetItemRef preserves random suffix item payload", function()
        _G.GetItemInfo = function(item)
            if type(item) == "string" and item:find("item:99:") then
                return "Greaves of the Boar", item
            end
            if item == 99 then
                return "Greaves", "|Hitem:99:0|h[Greaves]|h"
            end
            return nil
        end
        local ok = GA.HandleSetItemRef(
            "altarmy:upgrade:item:99:0:0:0:0:0:55:12345:0",
            "LeftButton")
        assert.is_true(ok)
        assert.matches("item:99:0:0:0:0:0:55:12345", openedLink)
    end)

    it("HandleSetItemRef ignores non-upgrade links", function()
        openedLink = nil
        assert.is_false(GA.HandleSetItemRef("item:11", "LeftButton"))
        assert.is_nil(openedLink)
    end)

    it("SetItemRef wrapper intercepts altarmy links before inner handler", function()
        local innerCalled = false
        _G.SetItemRef = function()
            innerCalled = true
        end
        package.loaded["GearUpgradeAlerts"] = nil
        require("GearUpgradeAlerts")
        GA = AltArmy.GearUpgradeAlerts
        openedLink = nil
        SetItemRef("altarmy:upgrade:11", "View details", "LeftButton")
        assert.is_false(innerCalled)
        assert.are.equal("|Hitem:11:0|h[New Helm]|h", openedLink)

        SetItemRef("item:11", "item", "LeftButton")
        assert.is_true(innerCalled)
    end)

    describe("AnnounceLootUpgrade", function()
        local chatLines

        local function loadWithMocks(overrides)
            overrides = overrides or {}
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            local notifyCurrent = overrides.notifyCurrentCharacter
            if notifyCurrent == nil then notifyCurrent = true end
            local notifyOther = overrides.notifyOtherCharacters
            if notifyOther == nil then notifyOther = true end
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    return {
                        notifyCurrentCharacter = notifyCurrent,
                        notifyOtherCharacters = notifyOther,
                        technique = "custom",
                        levelsAhead = 5,
                    }
                end,
                GetEffectiveTechnique = function(technique)
                    return technique
                end,
                EvaluateForAllAlts = overrides.evaluateForAllAlts or function()
                    return {}
                end,
                EvaluateForCharacter = overrides.evaluateForCharacter or function()
                    return false
                end,
            }
            AltArmy.DataStore = {
                GetCurrentCharacter = overrides.getCurrentCharacter or function()
                    return { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
                end,
                GetCurrentPlayerRealm = function() return "TestRealm" end,
                GetCharacterLevel = function(_, char) return char and char.level or 0 end,
                IsCurrentCharacter = function(_, name)
                    return name == "MageAlt"
                end,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = overrides.isBindOnPickup or function() return false end,
            }
            AltArmy.ClassColor = {
                wrapName = function(name) return name end,
            }
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
        end

        it("includes the item link, character names, and view details link", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end,
            })
            local itemLink = "|Hitem:11:0|h[New Helm]|h"
            local ok = GA.AnnounceLootUpgrade(itemLink)
            assert.is_true(ok)
            assert.is_not_nil(chatLines[1]:find(itemLink, 1, true))
            assert.matches("is an upgrade for Bravo:", chatLines[1])
            assert.matches("%[View details%]", chatLines[1])
        end)

        it("lists every alt name when three or fewer match", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return {
                        { name = "Alpha", classFile = "MAGE" },
                        { name = "Bravo", classFile = "PRIEST" },
                        { name = "Charlie", classFile = "WARLOCK" },
                    }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for Alpha, Bravo, Charlie:", chatLines[1])
        end)

        it("summarizes four or more alts as two names plus others", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return {
                        { name = "Alpha", classFile = "MAGE" },
                        { name = "Bravo", classFile = "PRIEST" },
                        { name = "Charlie", classFile = "WARLOCK" },
                        { name = "Delta", classFile = "HUNTER" },
                        { name = "Echo", classFile = "ROGUE" },
                    }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for Alpha, Bravo, and 3 others:", chatLines[1])
        end)

        it("announces bind-on-pickup loot upgrades for the current character when enabled", function()
            loadWithMocks({
                isBindOnPickup = function() return true end,
                evaluateForCharacter = function() return true end,
            })
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_true(ok)
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("skips bind-on-pickup loot when current-character notifications are disabled", function()
            loadWithMocks({
                notifyCurrentCharacter = false,
                isBindOnPickup = function() return true end,
            })
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_false(ok)
            assert.are.equal(0, #chatLines)
        end)

        it("does not check other characters for bind-on-pickup loot", function()
            local evaluatedAllAlts = false
            loadWithMocks({
                isBindOnPickup = function() return true end,
                evaluateForCharacter = function() return true end,
                evaluateForAllAlts = function()
                    evaluatedAllAlts = true
                    return { { name = "Bravo", classFile = "PRIEST" } }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_false(evaluatedAllAlts)
        end)

        it("announces when only the current character matches and current notifications are enabled", function()
            loadWithMocks({
                notifyOtherCharacters = false,
                evaluateForCharacter = function() return true end,
            })
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_true(ok)
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("does not announce loot upgrades when other-character notifications are disabled and current does not match", function()
            loadWithMocks({
                notifyOtherCharacters = false,
                evaluateForCharacter = function() return false end,
            })
            AltArmy.GearUpgrade.EvaluateForAllAlts = function()
                return { { name = "Bravo", classFile = "PRIEST" } }
            end
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_false(ok)
            assert.are.equal(0, #chatLines)
        end)

        it("excludes the current character when only other-character notifications are enabled", function()
            loadWithMocks({
                notifyCurrentCharacter = false,
                evaluateForAllAlts = function()
                    return {
                        { name = "MageAlt", classFile = "MAGE" },
                        { name = "Bravo", classFile = "PRIEST" },
                    }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for Bravo:", chatLines[1])
            assert.is_nil(chatLines[1]:match("MageAlt"))
        end)

        it("includes the current character when both notification toggles are enabled", function()
            loadWithMocks({
                evaluateForAllAlts = function()
                    return {
                        { name = "MageAlt", classFile = "MAGE" },
                        { name = "Bravo", classFile = "PRIEST" },
                    }
                end,
            })
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for MageAlt, Bravo:", chatLines[1])
        end)
    end)

    describe("AnnounceLevelUpUpgrades", function()
        local chatLines
        local helmLink = "|Hitem:11:0|h[New Helm]|h"

        local function loadWithMocks(overrides)
            overrides = overrides or {}
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            _G.GetContainerNumSlots = overrides.getContainerNumSlots or function() return 0 end
            _G.GetContainerItemLink = overrides.getContainerItemLink
            AltArmy.DataStore = {
                GetCurrentCharacter = function()
                    return overrides.char or { classFile = "MAGE", name = "MageAlt" }
                end,
                IsCurrentCharacter = function(_, name)
                    return name == "MageAlt"
                end,
                ScanBags = function() end,
                IterateBagSlots = overrides.iterateBagSlots,
                IterateBankSlots = overrides.iterateBankSlots,
                GetNumMails = overrides.getNumMails or function() return 0 end,
                GetMailInfo = overrides.getMailInfo,
                BANK_CONTAINER = -1,
                MIN_BANK_BAG_ID = 5,
                MAX_BANK_BAG_ID = 11,
            }
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    local notifyCurrent = overrides.notifyCurrentCharacter
                    if notifyCurrent == nil then notifyCurrent = true end
                    local notifyOther = overrides.notifyOtherCharacters
                    if notifyOther == nil then notifyOther = true end
                    return {
                        notifyCurrentCharacter = notifyCurrent,
                        notifyOtherCharacters = notifyOther,
                        technique = "custom",
                        levelsAhead = 5,
                    }
                end,
                EvaluateForCharacter = overrides.evaluateForCharacter or function()
                    return true
                end,
                GetEffectiveTechnique = function(technique)
                    return technique
                end,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = function() return false end,
                NeedsProficiencyTraining = function() return false end,
                EffectiveRequiredLevel = overrides.effectiveRequiredLevel or function(_, link)
                    if link == helmLink then return 40 end
                    return 999
                end,
            }
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
        end

        it("skips level-up announcements for bank alts", function()
            require("CharKey")
            package.loaded["BankAlt"] = nil
            require("BankAlt")
            AltArmy.BankAlt.Set("MageAlt", "TestRealm", true)
            loadWithMocks({
                char = { classFile = "MAGE", name = "MageAlt", realm = "TestRealm" },
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
            })
            AltArmy.DataStore.GetCurrentPlayerRealm = function() return "TestRealm" end
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(0, #chatLines)
        end)

        it("announces equippable bag upgrades at the new level", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(1, #chatLines)
            assert.matches("Congratulations! You can now equip ", chatLines[1])
            assert.is_not_nil(chatLines[1]:find(helmLink, 1, true))
            assert.is_nil(chatLines[1]:match("%(bank%)"))
            assert.is_nil(chatLines[1]:match("%(mail%)"))
        end)

        it("appends bank reminder when the upgrade is in the bank", function()
            loadWithMocks({
                iterateBankSlots = function(_, _char, cb)
                    cb(-1, 1, 11, 1, helmLink)
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.matches("%(bank%)", chatLines[1])
        end)

        it("appends mailbox reminder when the upgrade is in mail", function()
            loadWithMocks({
                getNumMails = function() return 1 end,
                getMailInfo = function()
                    return nil, 1, helmLink
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.matches("%(mail%)", chatLines[1])
        end)

        it("skips items that are not upgrades", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
                evaluateForCharacter = function() return false end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(0, #chatLines)
        end)

        it("skips items whose required level does not match the new level", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
                effectiveRequiredLevel = function() return 41 end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(0, #chatLines)
        end)

        it("evaluates upgrades at the simulated new level", function()
            local seenLevel
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
                effectiveRequiredLevel = function() return 67 end,
                evaluateForCharacter = function(_, _, opts)
                    seenLevel = opts.level
                    return opts.level == 67
                end,
            })
            GA.AnnounceLevelUpUpgrades(67)
            assert.are.equal(67, seenLevel)
            assert.are.equal(1, #chatLines)
        end)

        it("SimulateLevelUp runs the level-up upgrade scan", function()
            loadWithMocks({
                iterateBagSlots = function(_, _char, cb)
                    cb(0, 1, 11, 1, helmLink)
                end,
                effectiveRequiredLevel = function(_, link)
                    if link == helmLink then return 61 end
                    return 999
                end,
            })
            local ok = GA.SimulateLevelUp(61)
            assert.is_true(ok)
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(helmLink, 1, true))
        end)

        it("SimulateLevelUp reports invalid level usage", function()
            loadWithMocks()
            local ok = GA.SimulateLevelUp("abc")
            assert.is_false(ok)
            assert.matches("Usage: /altarmy debug levelup", chatLines[1])
        end)

        it("does not announce level-up upgrades when current-character notifications are disabled", function()
            loadWithMocks({
                notifyCurrentCharacter = false,
                getContainerNumSlots = function() return 1 end,
                getContainerItemLink = function(_, slot)
                    if slot == 1 then return helmLink end
                end,
            })
            GA.AnnounceLevelUpUpgrades(40)
            assert.are.equal(0, #chatLines)
        end)

        it("SimulateLevelUp reports disabled current-character notifications", function()
            loadWithMocks({ notifyCurrentCharacter = false })
            local ok = GA.SimulateLevelUp(40)
            assert.is_false(ok)
            assert.matches("disabled in options", chatLines[1])
        end)
    end)

    describe("CollectQuestRewardLinks", function()
        it("collects reward and choice links without duplicates", function()
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
            _G.GetNumQuestRewards = function() return 1 end
            _G.GetNumQuestChoices = function() return 2 end
            _G.GetQuestItemLink = function(kind, index)
                if kind == "reward" and index == 1 then
                    return "|Hitem:11:0|h[Reward]|h"
                end
                if kind == "choice" and index == 1 then
                    return "|Hitem:22:0|h[Choice A]|h"
                end
                if kind == "choice" and index == 2 then
                    return "|Hitem:11:0|h[Reward]|h"
                end
            end
            local links = GA.CollectQuestRewardLinks()
            assert.are.equal(2, #links)
            assert.is_not_nil(links[1]:find("item:11", 1, true))
            assert.is_not_nil(links[2]:find("item:22", 1, true))
        end)

        it("returns empty list when quest APIs are missing", function()
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
            _G.GetNumQuestRewards = nil
            _G.GetNumQuestChoices = nil
            _G.GetQuestItemLink = nil
            assert.are.same({}, GA.CollectQuestRewardLinks())
        end)
    end)

    describe("AnnounceQuestRewardUpgrades", function()
        local chatLines
        local linkA = "|Hitem:11:0|h[Choice A]|h"
        local linkB = "|Hitem:22:0|h[Choice B]|h"

        local function loadWithMocks(overrides)
            overrides = overrides or {}
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            if not AltArmy.BankAlt then
                package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
                require("CharKey")
                package.loaded["BankAlt"] = nil
                require("BankAlt")
            end
            _G.AltArmyTBC_Options = _G.AltArmyTBC_Options or {}
            AltArmy.BankAlt.Set("MageAlt", "TestRealm", false)
            local notifyCurrent = overrides.notifyCurrentCharacter
            if notifyCurrent == nil then notifyCurrent = true end
            local evaluatedAllAlts = false
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    return {
                        notifyCurrentCharacter = notifyCurrent,
                        notifyOtherCharacters = overrides.notifyOtherCharacters ~= false,
                        technique = "custom",
                        levelsAhead = 5,
                        upgradeThresholdPercent = overrides.upgradeThresholdPercent or 10,
                    }
                end,
                GetEffectiveTechnique = function(technique)
                    return technique
                end,
                EvaluateForCharacter = overrides.evaluateForCharacter or function(_, link)
                    return link == linkA or link == linkB
                end,
                EvaluateForAllAlts = function()
                    evaluatedAllAlts = true
                    return {}
                end,
                GetCharacterUpgradeDelta = overrides.getCharacterUpgradeDelta or function(_, link)
                    if link == linkA then return 10 end
                    if link == linkB then return 50 end
                    return 0
                end,
                ComputeUpgradeMaxDeltaForCurrentRealm =
                    overrides.computeUpgradeMaxDeltaForCurrentRealm or function() return 100 end,
                GetUpgradeHighlightKind = overrides.getUpgradeHighlightKind or function(delta, maxDelta, opts)
                    local threshold = ((opts and opts.upgradeThresholdPercent) or 10) / 100
                    if not delta or delta <= 0 then return nil end
                    if not maxDelta or maxDelta <= 0 then return "clear" end
                    if delta >= maxDelta * threshold then return "clear" end
                    return "minor"
                end,
            }
            AltArmy.DataStore = {
                GetCurrentCharacter = function()
                    return { name = "MageAlt", realm = "TestRealm", classFile = "MAGE", level = 60 }
                end,
                GetCurrentPlayerRealm = function() return "TestRealm" end,
                GetCharacterLevel = function(_, char) return char and char.level or 0 end,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = function() return false end,
                GetInventorySlotsForItem = overrides.getInventorySlotsForItem or function() return { 1 } end,
                IsEquippableWithin = overrides.isEquippableWithin or function() return true, 0, nil end,
            }
            AltArmy.ClassColor = {
                wrapName = function(name) return name end,
            }
            _G.GetNumQuestRewards = overrides.getNumQuestRewards or function() return 0 end
            _G.GetNumQuestChoices = overrides.getNumQuestChoices or function() return 2 end
            _G.GetQuestItemLink = overrides.getQuestItemLink or function(_, index)
                if index == 1 then return linkA end
                if index == 2 then return linkB end
            end
            local mockTime = overrides.mockTime or 1000
            _G.GetTime = overrides.getTime or function() return mockTime end
            _G.GetTitleText = overrides.getTitleText or function() return "Test Quest" end
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
            return { evaluatedAllAlts = function() return evaluatedAllAlts end }
        end

        it("announces the best quest reward upgrade when multiple rewards match", function()
            loadWithMocks({
                getNumQuestRewards = function() return 1 end,
                getQuestItemLink = function(kind, index)
                    if kind == "reward" and index == 1 then
                        return "|Hitem:33:0|h[Reward]|h"
                    end
                    if kind == "choice" and index == 1 then return linkA end
                end,
                getNumQuestChoices = function() return 1 end,
                evaluateForCharacter = function() return true end,
                getCharacterUpgradeDelta = function(_, link)
                    if link:find("item:33", 1, true) then return 5 end
                    if link == linkA then return 10 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkA, 1, true))
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("does not announce when current-character notifications are disabled", function()
            loadWithMocks({ notifyCurrentCharacter = false })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(0, #chatLines)
        end)

        it("does not check other characters", function()
            local ctx = loadWithMocks({ notifyOtherCharacters = true })
            GA.AnnounceQuestRewardUpgrades()
            assert.is_false(ctx.evaluatedAllAlts())
        end)

        it("announces all clear quest reward upgrades with the best first", function()
            loadWithMocks()
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(2, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkB, 1, true))
            assert.matches("is the best upgrade for MageAlt:", chatLines[1])
            assert.is_not_nil(chatLines[2]:find(linkA, 1, true))
            assert.matches("is an upgrade for MageAlt:", chatLines[2])
        end)

        it("uses standard upgrade wording for a single clear quest reward", function()
            loadWithMocks({
                getNumQuestChoices = function() return 1 end,
                getQuestItemLink = function(_, index)
                    if index == 1 then return linkB end
                end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkB then return 50 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
            assert.is_nil(chatLines[1]:match("is the best upgrade"))
        end)

        it("announces a clear upgrade when the reward meets the realm-wide threshold", function()
            loadWithMocks({
                computeUpgradeMaxDeltaForCurrentRealm = function() return 100 end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkA then return 8 end
                    if link == linkB then return 15 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkB, 1, true))
            assert.matches("is an upgrade for MageAlt:", chatLines[1])
        end)

        it("announces a minor upgrade for the best positive reward below threshold", function()
            loadWithMocks({
                computeUpgradeMaxDeltaForCurrentRealm = function() return 100 end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkA then return 8 end
                    if link == linkB then return 5 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkA, 1, true))
            assert.matches("is a minor upgrade for MageAlt:", chatLines[1])
        end)

        it("announces when no equippable quest rewards are upgrades for the current character", function()
            loadWithMocks({
                evaluateForCharacter = function() return false end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkA then return -5 end
                    if link == linkB then return -2 end
                    return 0
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.matches("None of these rewards are an upgrade for MageAlt", chatLines[1])
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkA))
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkB))
        end)

        it("skips quest reward checks when no rewards are equippable", function()
            loadWithMocks({
                getInventorySlotsForItem = function() return {} end,
                isEquippableWithin = function() return false end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(0, #chatLines)
        end)

        it("only evaluates equippable quest rewards", function()
            loadWithMocks({
                getNumQuestChoices = function() return 2 end,
                evaluateForCharacter = function() return true end,
                getCharacterUpgradeDelta = function(_, link)
                    if link == linkA then return 100 end
                    if link == linkB then return 5 end
                    return 0
                end,
                getInventorySlotsForItem = function(link)
                    if link == linkB then return { 1 } end
                    return {}
                end,
                isEquippableWithin = function(_, _, link)
                    return link == linkB, 0, nil
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_not_nil(chatLines[1]:find(linkB, 1, true))
            assert.is_nil(chatLines[1]:find(linkA, 1, true))
        end)

        it("suppresses duplicate loot announcements for announced quest rewards", function()
            loadWithMocks({
                getNumQuestChoices = function() return 1 end,
                getQuestItemLink = function(_, index)
                    if index == 1 then return linkA end
                end,
                evaluateForCharacter = function(_, link)
                    return link == linkA
                end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(1, #chatLines)
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkA))
            local ok = GA.AnnounceLootUpgrade(linkA)
            assert.is_false(ok)
            assert.are.equal(1, #chatLines)
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkA))
        end)

        it("keeps suppressing loot until consumed, regardless of elapsed time", function()
            local mockTime = 1000
            loadWithMocks({
                getNumQuestChoices = function() return 1 end,
                getQuestItemLink = function(_, index)
                    if index == 1 then return linkA end
                end,
                getTime = function() return mockTime end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkA))
            -- A large time jump must not expire the flag: suppression no longer uses a TTL.
            mockTime = 100000
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkA))
            local ok = GA.AnnounceLootUpgrade(linkA)
            assert.is_false(ok)
            assert.are.equal(1, #chatLines)
            -- The flag is consumed by the suppressed loot, so a later drop announces again.
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkA))
        end)

        it("clears all suppressions when entering the world", function()
            loadWithMocks({
                getNumQuestChoices = function() return 2 end,
                notifyOtherCharacters = false,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkA))
            assert.is_true(GA.ShouldSuppressLootUpgrade(linkB))
            GA.ClearQuestLootUpgradeSuppression()
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkA))
            assert.is_false(GA.ShouldSuppressLootUpgrade(linkB))
            local ok = GA.AnnounceLootUpgrade(linkB)
            assert.is_true(ok)
            assert.are.equal(3, #chatLines)
        end)

        it("debounces rapid duplicate quest reward announcements", function()
            loadWithMocks()
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(2, #chatLines)
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(2, #chatLines)
        end)

        it("announces quest rewards again after debounce expires", function()
            local mockTime = 1000
            loadWithMocks({
                getTime = function() return mockTime end,
            })
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(2, #chatLines)
            mockTime = 1002
            GA.AnnounceQuestRewardUpgrades()
            assert.are.equal(4, #chatLines)
        end)
    end)

    describe("FormatQuestRewardMessages", function()
        it("formats minor, best, and no-upgrade quest messages", function()
            assert.matches("is a minor upgrade for Bravo:", GA.FormatQuestMinorUpgradeMessage(
                "|Hitem:11:0|h[New Helm]|h", "Bravo", "[View details]"))
            assert.matches("is the best upgrade for Bravo:", GA.FormatQuestBestUpgradeMessage(
                "|Hitem:11:0|h[New Helm]|h", "Bravo", "[View details]"))
            assert.are.equal(
                "None of these rewards are an upgrade for MageAlt",
                GA.FormatQuestNoUpgradeMessage("MageAlt"))
        end)

        it("FormatLootUpgradeMessage resets item link color before plain text", function()
            local coloredLink = "|cffa335ee|Hitem:11:0|h[Epic Helm]|h"
            local msg = GA.FormatLootUpgradeMessage(coloredLink, "MageAlt", "[View details]")
            assert.matches("|r is an upgrade for MageAlt:", msg)
        end)
    end)

    describe("FormatLevelUpEquipMessage", function()
        it("adds location reminders only for bank or mail", function()
            local link = "|Hitem:11:0|h[New Helm]|h"
            assert.are.equal(
                "Congratulations! You can now equip " .. link,
                GA.FormatLevelUpEquipMessage(link, { bag = true }))
            assert.are.equal(
                "Congratulations! You can now equip " .. link .. " (bank)",
                GA.FormatLevelUpEquipMessage(link, { bank = true }))
            assert.are.equal(
                "Congratulations! You can now equip " .. link,
                GA.FormatLevelUpEquipMessage(link, { bag = true, bank = true }))
            assert.are.equal(
                "Congratulations! You can now equip " .. link .. " (mail)",
                GA.FormatLevelUpEquipMessage(link, { mail = true }))
            assert.are.equal(
                "Congratulations! You can now equip " .. link .. " (mail)",
                GA.FormatLevelUpEquipMessage(link, { bank = true, mail = true }))
        end)
    end)
end)
