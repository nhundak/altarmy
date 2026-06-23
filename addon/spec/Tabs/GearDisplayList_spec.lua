--[[
  Unit tests for Gear tab display list ordering (showSelfFirst + score sort).
  Mirrors the split/sort logic from TabGear.lua GetDisplayList.
  Run from project root: npm test
]]

describe("Gear display list showSelfFirst", function()
    local GetSortValue
    local CharKey

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Data/?.lua"
        require("CharKey")
        require("CharacterSort")
        GetSortValue = AltArmy.CharacterSort.GetSortValue
        CharKey = AltArmy.CharKey
    end)

    local function compareBySelectedScore(entryA, entryB, sortKey, descending)
        local va = GetSortValue(entryA, sortKey)
        local vb = GetSortValue(entryB, sortKey)
        if va ~= vb then
            if descending then return va > vb else return va < vb end
        end
        return (entryA.name or "") < (entryB.name or "")
    end

    --- Mirror TabGear GetDisplayList split/sort (no realm filter or item drop).
    local function buildDisplayList(visible, opts)
        opts = opts or {}
        local sortKey = opts.sortKey or "Time Played"
        local descending = opts.scoreSortDescending ~= false
        local showSelfFirst = opts.showSelfFirst ~= false
        local currentName = opts.currentName or "Me"
        local currentRealm = opts.currentRealm or "RealmA"
        local charSettings = opts.charSettings or {}
        local inputList = opts.inputList

        local function GetCharSetting(name, realm, key)
            local c = charSettings[CharKey(name, realm)]
            if not c then return false end
            return c[key] == true
        end

        local filtered = visible
        if inputList then
            filtered = {}
            for i = 1, #inputList do
                local e = inputList[i]
                local isSelf = (e.name == currentName and e.realm == currentRealm)
                local isHidden = GetCharSetting(e.name, e.realm, "hide")
                if not isHidden or (showSelfFirst and isSelf) then
                    filtered[#filtered + 1] = e
                end
            end
        end

        local pinned = {}
        local nonPinned = {}
        for i = 1, #filtered do
            local e = filtered[i]
            local isSelf = (e.name == currentName and e.realm == currentRealm)
            local isPinned = GetCharSetting(e.name, e.realm, "pin")
            if isPinned or (showSelfFirst and isSelf) then
                pinned[#pinned + 1] = e
            else
                nonPinned[#nonPinned + 1] = e
            end
        end

        table.sort(pinned, function(a, b)
            return compareBySelectedScore(a, b, sortKey, descending)
        end)
        table.sort(nonPinned, function(a, b)
            return compareBySelectedScore(a, b, sortKey, descending)
        end)

        local list = {}
        for i = 1, #pinned do list[#list + 1] = pinned[i] end
        for i = 1, #nonPinned do list[#list + 1] = nonPinned[i] end
        return list
    end

    local sampleChars = {
        { name = "Alice", realm = "RealmA", played = 100 },
        { name = "Me", realm = "RealmA", played = 50 },
        { name = "Bob", realm = "RealmA", played = 75 },
    }

    it("puts self in pinned group when showSelfFirst is enabled", function()
        local list = buildDisplayList(sampleChars, { showSelfFirst = true })
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Alice", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts pin-current-character with other pinned characters by selected score", function()
        local chars = {
            { name = "Alice", realm = "RealmA", played = 100 },
            { name = "Me", realm = "RealmA", played = 50 },
            { name = "Bob", realm = "RealmA", played = 75 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = true,
            charSettings = {
                ["RealmA\\Alice"] = { pin = true },
            },
        })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Me", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts self by selected score when showSelfFirst is disabled", function()
        local list = buildDisplayList(sampleChars, { showSelfFirst = false })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Bob", list[2].name)
        assert.are.equal("Me", list[3].name)
    end)

    it("respects pin when showSelfFirst is disabled for self", function()
        local list = buildDisplayList(sampleChars, {
            showSelfFirst = false,
            charSettings = {
                ["RealmA\\Me"] = { pin = true },
            },
        })
        assert.are.equal("Me", list[1].name)
        assert.are.equal("Alice", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts by selected score descending with name tie-break", function()
        local chars = {
            { name = "Bob", avgItemLevel = 100 },
            { name = "Alice", avgItemLevel = 120 },
            { name = "Zed", avgItemLevel = 120 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            sortKey = "Avg Item Level",
            scoreSortDescending = true,
        })
        assert.are.equal("Alice", list[1].name)
        assert.are.equal("Zed", list[2].name)
        assert.are.equal("Bob", list[3].name)
    end)

    it("sorts ascending when scoreSortDescending is false", function()
        local chars = {
            { name = "Bob", avgItemLevel = 100 },
            { name = "Alice", avgItemLevel = 120 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            sortKey = "Avg Item Level",
            scoreSortDescending = false,
        })
        assert.are.equal("Bob", list[1].name)
        assert.are.equal("Alice", list[2].name)
    end)

    it("shows hidden current character when pin current character is enabled", function()
        local chars = {
            { name = "Alice", realm = "RealmA", played = 100 },
            { name = "Me", realm = "RealmA", played = 50 },
            { name = "Bob", realm = "RealmA", played = 75 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = true,
            inputList = chars,
            charSettings = {
                ["RealmA\\Me"] = { hide = true },
            },
        })
        assert.are.equal("Me", list[1].name)
        assert.are.equal(3, #list)
    end)

    it("respects hide for current character when pin current character is disabled", function()
        local chars = {
            { name = "Me", realm = "RealmA", played = 50 },
            { name = "Alice", realm = "RealmA", played = 100 },
        }
        local list = buildDisplayList(chars, {
            showSelfFirst = false,
            inputList = chars,
            charSettings = {
                ["RealmA\\Me"] = { hide = true },
            },
        })
        assert.are.equal(1, #list)
        assert.are.equal("Alice", list[1].name)
    end)
end)

describe("Gear display list focus mode", function()
    local GU
    local IU
    local DS
    local CharKey

    local SLOT_ORDER = {
        16, 17, 18,
        1, 2, 3, 5,
        15,
        9, 10,
        6, 7, 8,
        11, 12, 13, 14,
        4, 19,
    }

    local function mockGetItemInfo(item)
        local id = tonumber(tostring(item):match("item:(%d+)"))
        local items = {
            [10] = { "Old Helm", nil, 2, 20, 20, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [11] = { "New Helm", nil, 3, 35, 35, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
            [12] = { "Ring", nil, 3, 40, 40, "Armor", "Miscellaneous", nil, "INVTYPE_FINGER" },
            [13] = { "Newer Helm", nil, 3, 32, 32, "Armor", "Cloth", nil, "INVTYPE_HEAD" },
        }
        local info = items[id]
        if not info then return end
        local link = "|cff|Hitem:" .. tostring(id) .. ":0|h[" .. info[1] .. "]|h|r"
        return info[1], link, info[3], info[4], info[5], info[6], info[7], nil, info[9]
    end

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        _G.AltArmyTBC_Data = {
            Characters = {
                RealmA = {
                    Upgrader = {
                        name = "Upgrader",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = { [1] = "|Hitem:10:0|h[Old Helm]|h" },
                    },
                    SmallUpgrader = {
                        name = "SmallUpgrader",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = { [1] = "|Hitem:13:0|h[Newer Helm]|h" },
                    },
                    Usable = {
                        name = "Usable",
                        classFile = "MAGE",
                        level = 60,
                        Inventory = { [1] = "|Hitem:11:0|h[New Helm]|h" },
                    },
                    WrongClass = {
                        name = "WrongClass",
                        classFile = "WARRIOR",
                        level = 60,
                        Inventory = {},
                    },
                },
            },
        }
        _G.GetItemInfo = mockGetItemInfo
        _G.GetItemStats = function() return {} end
        _G.CreateFrame = _G.CreateFrame or function()
            return { SetScript = function() end, RegisterEvent = function() end }
        end
        _G.UIParent = _G.UIParent or {}
        package.loaded["DataStore"] = nil
        package.loaded["ItemUsability"] = nil
        package.loaded["DataStoreTalents"] = nil
        package.loaded["GearUpgrade"] = nil
        require("DataStore")
        require("DataStoreEquipment")
        require("ItemUsability")
        require("DataStoreTalents")
        require("GearUpgrade")
        require("CharKey")
        DS = AltArmy.DataStore
        CharKey = AltArmy.CharKey
        DS.accountData = _G.AltArmyTBC_Data
        IU = AltArmy.ItemUsability
        GU = AltArmy.GearUpgrade
    end)

    --- Mirror TabGear focus sort.
    local function sortByFocusTier(list, itemLink, upgradeOpts)
        local slots = IU.GetInventorySlotsForItem(itemLink) or {}
        local upgradeMaxDelta
        for i = 1, #list do
            local charData = DS:GetCharacter(list[i].name, list[i].realm)
            for s = 1, #slots do
                local delta = GU.GetSlotCompareDelta(charData, itemLink, slots[s], upgradeOpts) or 0
                if delta > 0 and (not upgradeMaxDelta or delta > upgradeMaxDelta) then
                    upgradeMaxDelta = delta
                end
            end
        end
        local copy = {}
        for i = 1, #list do copy[i] = list[i] end
        table.sort(copy, function(a, b)
            local charA = DS:GetCharacter(a.name, a.realm)
            local charB = DS:GetCharacter(b.name, b.realm)
            local ta = GU.GetFocusTier(a, charA, itemLink, upgradeOpts, upgradeMaxDelta)
            local tb = GU.GetFocusTier(b, charB, itemLink, upgradeOpts, upgradeMaxDelta)
            if ta ~= tb then return ta < tb end
            local da = GU.GetFocusUpgradeDelta(a, charA, itemLink, upgradeOpts, upgradeMaxDelta) or 0
            local db = GU.GetFocusUpgradeDelta(b, charB, itemLink, upgradeOpts, upgradeMaxDelta) or 0
            if da ~= db then return da > db end
            return (a.name or "") < (b.name or "")
        end)
        return copy
    end

    --- Mirror TabGear IsDisplaySlotVisible (lines 267-272).
    local function isDisplaySlotVisible(displayIdx, itemLink)
        local slots = IU.GetInventorySlotsForItem(itemLink)
        if not slots or #slots == 0 then return true end
        local focused = {}
        for i = 1, #slots do focused[slots[i]] = true end
        local invSlot = SLOT_ORDER[displayIdx]
        return focused[invSlot] == true
    end

    --- Mirror TabGear GetFocusedInventorySlots.
    local function getFocusedInventorySlots(itemLink)
        local slots = IU.GetInventorySlotsForItem(itemLink)
        if not slots or #slots == 0 then return {} end
        return slots
    end

    --- Mirror TabGear PickBestCompareSelection (in-range upgrade/sidegrade only).
    local function pickBestCompareSelection(list, itemLink, upgradeOpts)
        if not list or #list == 0 or not itemLink then return nil, nil end
        local slots = getFocusedInventorySlots(itemLink)
        if #slots == 0 then return nil, nil end
        local upgradeMaxDelta
        for i = 1, #list do
            local charData = DS:GetCharacter(list[i].name, list[i].realm)
            for s = 1, #slots do
                local delta = GU.GetSlotCompareDelta(charData, itemLink, slots[s], upgradeOpts) or 0
                if delta > 0 and (not upgradeMaxDelta or delta > upgradeMaxDelta) then
                    upgradeMaxDelta = delta
                end
            end
        end
        local bestKey, bestSlot, bestDelta = nil, nil, 0
        for i = 1, #list do
            local e = list[i]
            local charData = DS:GetCharacter(e.name, e.realm)
            for s = 1, #slots do
                local invSlot = slots[s]
                local info = GU.ClassifyFocusSlot(e, charData, itemLink, invSlot, upgradeOpts, upgradeMaxDelta)
                if info
                    and (info.category == GU.FOCUS_CATEGORY.UPGRADE_IN_RANGE
                        or info.category == GU.FOCUS_CATEGORY.SIDEGRADE_IN_RANGE)
                    and info.delta > bestDelta then
                    bestDelta = info.delta
                    bestKey = CharKey(e.name, e.realm)
                    bestSlot = invSlot
                end
            end
        end
        if bestKey and bestSlot then
            return bestKey, bestSlot
        end
        return nil, nil
    end

    it("sorts columns by focus tier: upgrade, beyond-level upgrade, then neutral", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "LowLevel", realm = "RealmA", classFile = "MAGE", level = 10 },
            { name = "Usable", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal("Upgrader", sorted[1].name)
        assert.are.equal("LowLevel", sorted[2].name)
        assert.are.equal("Usable", sorted[3].name)
    end)

    it("sorts upgrade columns by biggest upgrade first", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "SmallUpgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal("Upgrader", sorted[1].name)
        assert.are.equal("SmallUpgrader", sorted[2].name)
        assert.are.equal(15, GU.GetFocusUpgradeDelta(sorted[1], DS:GetCharacter("Upgrader", "RealmA"), itemLink, {
            technique = "ilvl",
            levelsAhead = 0,
        }, 15))
        assert.are.equal(3, GU.GetFocusUpgradeDelta(sorted[2], DS:GetCharacter("SmallUpgrader", "RealmA"), itemLink, {
            technique = "ilvl",
            levelsAhead = 0,
        }, 15))
    end)

    it("auto-selects the best upgrade character when one exists", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "SmallUpgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Usable", realm = "RealmA", classFile = "MAGE", level = 60 },
            { name = "Upgrader", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local sorted = sortByFocusTier(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        local key, slot = pickBestCompareSelection(sorted, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.are.equal(CharKey("Upgrader", "RealmA"), key)
        assert.are.equal(1, slot)
    end)

    it("does not auto-select when no character has an upgrade or sidegrade", function()
        local itemLink = "|Hitem:11:0|h[New Helm]|h"
        local entries = {
            { name = "Usable", realm = "RealmA", classFile = "MAGE", level = 60 },
        }
        local key, slot = pickBestCompareSelection(entries, itemLink, { technique = "ilvl", levelsAhead = 0 })
        assert.is_nil(key)
        assert.is_nil(slot)
    end)

    it("filters display rows to focused item inventory slots", function()
        local headLink = "|Hitem:11:0|h[New Helm]|h"
        local ringLink = "|Hitem:12:0|h[Ring]|h"
        local headRowIdx
        local ringRowIdx
        for i = 1, #SLOT_ORDER do
            if SLOT_ORDER[i] == 1 then headRowIdx = i end
            if SLOT_ORDER[i] == 11 then ringRowIdx = i end
        end
        assert.is_true(isDisplaySlotVisible(headRowIdx, headLink))
        assert.is_false(isDisplaySlotVisible(ringRowIdx, headLink))
        assert.is_true(isDisplaySlotVisible(ringRowIdx, ringLink))
        assert.is_false(isDisplaySlotVisible(headRowIdx, ringLink))
    end)

    --- Mirror TabGear GetFirstFocusedColumnSlot: topmost visible compare row.
    local function getFirstFocusedColumnSlot(itemLink)
        local visible = {}
        for slot = 1, #SLOT_ORDER do
            if isDisplaySlotVisible(slot, itemLink) then
                visible[#visible + 1] = slot
            end
        end
        if #visible > 0 then
            return SLOT_ORDER[visible[1]]
        end
        local slots = IU.GetInventorySlotsForItem(itemLink)
        return slots[1]
    end

    it("picks the topmost visible slot for header compare selection", function()
        local ringLink = "|Hitem:12:0|h[Ring]|h"
        assert.are.equal(11, getFirstFocusedColumnSlot(ringLink))
        local headLink = "|Hitem:11:0|h[New Helm]|h"
        assert.are.equal(1, getFirstFocusedColumnSlot(headLink))
    end)
end)
