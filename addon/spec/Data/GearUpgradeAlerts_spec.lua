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

        local function loadWithMocks(evaluateFn)
            chatLines = {}
            _G.DEFAULT_CHAT_FRAME = {
                AddMessage = function(_, line)
                    chatLines[#chatLines + 1] = line
                end,
            }
            AltArmy.GearUpgrade = {
                GetOptions = function()
                    return {
                        notifyCurrentCharacter = true,
                        notifyOtherCharacters = true,
                        technique = "custom",
                        levelsAhead = 5,
                    }
                end,
                GetEffectiveTechnique = function(technique)
                    return technique
                end,
                EvaluateForAllAlts = evaluateFn,
            }
            AltArmy.DataStore = {
                IsCurrentCharacter = function(_, name)
                    return name == "MageAlt"
                end,
            }
            AltArmy.ItemUsability = {
                IsBindOnPickup = function() return false end,
            }
            AltArmy.ClassColor = {
                wrapName = function(name) return name end,
            }
            package.loaded["GearUpgradeAlerts"] = nil
            require("GearUpgradeAlerts")
            GA = AltArmy.GearUpgradeAlerts
        end

        it("includes the item link, character names, and view details link", function()
            loadWithMocks(function()
                return { { name = "Bravo", classFile = "PRIEST" } }
            end)
            local itemLink = "|Hitem:11:0|h[New Helm]|h"
            local ok = GA.AnnounceLootUpgrade(itemLink)
            assert.is_true(ok)
            assert.is_not_nil(chatLines[1]:find(itemLink, 1, true))
            assert.matches("is an upgrade for Bravo:", chatLines[1])
            assert.matches("%[View details%]", chatLines[1])
        end)

        it("lists every alt name when three or fewer match", function()
            loadWithMocks(function()
                return {
                    { name = "Alpha", classFile = "MAGE" },
                    { name = "Bravo", classFile = "PRIEST" },
                    { name = "Charlie", classFile = "WARLOCK" },
                }
            end)
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for Alpha, Bravo, Charlie:", chatLines[1])
        end)

        it("summarizes four or more alts as two names plus others", function()
            loadWithMocks(function()
                return {
                    { name = "Alpha", classFile = "MAGE" },
                    { name = "Bravo", classFile = "PRIEST" },
                    { name = "Charlie", classFile = "WARLOCK" },
                    { name = "Delta", classFile = "HUNTER" },
                    { name = "Echo", classFile = "ROGUE" },
                }
            end)
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for Alpha, Bravo, and 3 others:", chatLines[1])
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

        it("does not announce loot upgrades when other-character notifications are disabled", function()
            loadWithMocks({
                notifyOtherCharacters = false,
            })
            AltArmy.GearUpgrade.EvaluateForAllAlts = function()
                return { { name = "Bravo", classFile = "PRIEST" } }
            end
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_false(ok)
            assert.are.equal(0, #chatLines)
        end)

        it("excludes the current character from loot upgrade announcements", function()
            loadWithMocks({})
            AltArmy.GearUpgrade.EvaluateForAllAlts = function()
                return {
                    { name = "MageAlt", classFile = "MAGE" },
                    { name = "Bravo", classFile = "PRIEST" },
                }
            end
            GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.matches("is an upgrade for Bravo:", chatLines[1])
            assert.is_nil(chatLines[1]:match("MageAlt"))
        end)

        it("skips loot announcements when only the current character matches", function()
            loadWithMocks({})
            AltArmy.GearUpgrade.EvaluateForAllAlts = function()
                return { { name = "MageAlt", classFile = "MAGE" } }
            end
            local ok = GA.AnnounceLootUpgrade("|Hitem:11:0|h[New Helm]|h")
            assert.is_false(ok)
            assert.are.equal(0, #chatLines)
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
